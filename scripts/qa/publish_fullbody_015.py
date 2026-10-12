"""Publish read-only whole-body .15 evidence without running a preview.

Copies immutable evidence into the review directory and its visible-life mirror.
Resource coverage, offline motion, native stills and native performance remain
separate statements. Missing/stale evidence is never promoted to acceptance.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import math
from pathlib import Path
import re
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
STUDY = ROOT / "docs/body-life/vascular-art-study"
BASE = STUDY / "fullbody-015"
PUBLIC = ROOT / "docs/body-life/previews/visible-life/vascular-art-study"
REVIEW = BASE / "review"
NAMES = {"brain": "脑", "heart": "心脏", "lung_r": "右肺", "lung_l": "左肺",
         "liver": "肝脏", "stomach": "胃", "pancreas": "胰腺", "kidney_r": "右肾",
         "kidney_l": "左肾", "small_intestine": "小肠", "large_intestine": "大肠", "bladder": "膀胱"}
RUNTIME_LAYERS = ("surfaceTiles", "organs", "deepTiles", "junctions", "foregroundPatches")
NORMAL_ENTRY_SHA256 = "091adca6a72ebf428d7a63cf51752668bf2d7edb51e9506f889a606521ce1595"
DEFERRED_VISUAL_REGIONS = frozenset(("heart", "lung_r", "lung_l"))
SCOPED_DETAIL_VIEWS = frozenset(name + "-z0.15" for name in (
    "head-entry", "brain-entry-right", "brain-entry-left", "hand-right", "hand-left", "neck-upper",
    "elbow-right", "elbow-left", "forearm-right", "forearm-left",
    "wrist-right", "wrist-left", "fingers-right", "fingers-left",
    "knee-right", "knee-left", "shin-right", "shin-left", "calf-right", "calf-left",
    "ankle-right", "ankle-left", "heel-right", "heel-left"))
DEFERRED_NATIVE_VIEWS = frozenset(("heart-z0.15", "lung_r-z0.15", "lung_l-z0.15", "coronary-entry-z0.15"))
HARNESS_HOOK_PATTERN = rb"^ require\('qa\.FullBodyMapNative(?:Views|Movement|Performance)'\)\.start\(game,R(?:,H)?,\{outputDir='qa/organ-atlas-native/[a-zA-Z0-9/-]+'(?:,camera=\{x=[0-9.]+,y=[0-9.]+\})?\}\)\r?\n"


def read(path: Path):
    return json.loads(path.read_text(encoding="utf8"))


def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve(value: str, directory: Path = BASE):
    path = Path(value)
    if path.is_absolute():
        return path
    if value.startswith(("scripts/", "assets/", "docs/")):
        return ROOT / path
    return directory / path


def input_hashes(record):
    return record.get("inputHashes", record.get("inputs", record.get("hashes", {})))


def verified_entry_snapshot(record, expected, current, directory):
    """Prove each capture's own temporary entry differs only by one QA hook."""
    snapshot = record.get("temporaryEntrySnapshot", {})
    if not isinstance(snapshot, dict) or snapshot.get("sha256") != expected:
        return None
    if snapshot.get("normalEntrySha256") != NORMAL_ENTRY_SHA256 or not snapshot.get("path"):
        return None
    path = resolve(snapshot["path"], directory)
    if (path.name != "temporary-entry.lua" or path.parent.resolve() != directory.resolve() or
            not path.is_file() or sha(path) != expected):
        return None
    captured = path.read_bytes()
    matches = list(re.finditer(HARNESS_HOOK_PATTERN, captured, re.MULTILINE))
    if len(matches) != 1:
        return None
    match = matches[0]
    normal = captured[:match.start()] + captured[match.end():]
    if hashlib.sha256(normal).hexdigest() != NORMAL_ENTRY_SHA256:
        return None
    runtime = (ROOT / "scripts/main.lua").read_bytes()
    if hashlib.sha256(runtime).hexdigest() != current:
        return None
    live_hooks = list(re.finditer(HARNESS_HOOK_PATTERN, runtime, re.MULTILINE))
    if len(live_hooks) == 1:
        live = live_hooks[0]
        runtime_normal = runtime[:live.start()] + runtime[live.end():]
    elif not live_hooks:
        runtime_normal = runtime
    else:
        return None
    if runtime_normal != normal:
        return None
    return {"file": "scripts/main.lua", "snapshotPath": str(path),
            "capturedSha256": expected, "normalEntrySha256": NORMAL_ENTRY_SHA256,
            "currentSha256": current, "capturedHook": match.group().decode().strip(),
            "currentMode": "temporary-QA-hook-changed" if live_hooks else "production-hook-removed",
            "byteReconstructionVerified": True}


def verified_harness_transition(expected, current):
    """Accept only a recorded, byte-proved change to the temporary QA hook."""
    path = REVIEW / "harness-transitions.json"
    if not path.is_file():
        return None
    for item in read(path).get("transitions", []):
        if item.get("capturedSha256") != expected or item.get("file") != "scripts/main.lua":
            continue
        baseline = Path(item["baselinePath"])
        if not baseline.is_absolute():
            baseline = ROOT / baseline
        if not baseline.is_file() or sha(baseline) != item["baselineSha256"]:
            continue
        original = baseline.read_bytes()
        hook = item.get("capturedHook", "").encode()
        anchor = item.get("insertionAnchor", "").encode()
        if original.count(anchor) != 1:
            continue
        captured = original.replace(anchor, anchor + hook, 1)
        if hashlib.sha256(captured).hexdigest() != expected:
            continue
        runtime = (ROOT / "scripts/main.lua").read_bytes()
        matches = list(re.finditer(HARNESS_HOOK_PATTERN, runtime, re.MULTILINE))
        if not matches and runtime == original:
            return {**item, "currentSha256": current, "currentMode": "production-hook-removed"}
        if len(matches) == 1 and runtime[:matches[0].start()] + runtime[matches[0].end():] == original:
            return {**item, "currentSha256": current, "currentMode": "temporary-QA-hook-changed",
                    "currentHook": matches[0].group().decode().strip()}
    return None


def verified_documentation_transition(name, expected, current):
    path = REVIEW / "documentation-transitions.json"
    if not path.is_file():
        return None
    for item in read(path).get("transitions", []):
        if (item.get("file"), item.get("capturedSha256"), item.get("currentSha256")) != (name, expected, current):
            continue
        required = item.get("requiredRuntimeInputs", {})
        if required and all(resolve(p).is_file() and sha(resolve(p)) == d for p, d in required.items()):
            return item
    return None


def hash_status(record, directory=BASE):
    expected = input_hashes(record)
    if not isinstance(expected, dict) or not expected:
        return {"verified": False, "checked": 0, "changed": [], "reason": "报告未记录输入哈希"}
    checked, changed, transitions, documentation = 0, [], [], []
    for name, digest in expected.items():
        if not isinstance(digest, str) or not re.fullmatch("[0-9a-f]{64}", digest):
            continue
        path = resolve(name, directory)
        checked += 1
        current = sha(path) if path.is_file() else None
        if name == "scripts/main.lua" and "temporaryEntrySnapshot" in record:
            transition = verified_entry_snapshot(record, digest, current, directory)
            if transition:
                transitions.append(transition)
            else:
                changed.append(name + " (capture QA snapshot invalid)")
            continue
        if current != digest:
            transition = verified_harness_transition(digest, current) if name == "scripts/main.lua" else None
            if transition:
                transitions.append(transition)
                continue
            transition = verified_documentation_transition(name, digest, current)
            if transition:
                documentation.append(transition)
                continue
            restored = record.get("mainRestoredSha256") if name == "scripts/main.lua" else None
            if not restored or current != restored:
                changed.append(name)
    reason = "输入哈希一致" if checked and not changed else "输入已变化或文件缺失"
    if checked and not changed and transitions:
        reason = "渲染/素材输入一致；main 仅临时 QA hook 切换，已逐字还原校验"
    return {"verified": checked > 0 and not changed, "checked": checked, "changed": changed,
            "temporaryHarnessFiles": transitions, "documentationOnlyChanges": documentation, "reason": reason}


def runtime_override_status(record=None, directory=BASE):
    """Reject incomplete or malformed independent resource bindings."""
    try:
        return _runtime_override_status(record, directory)
    except (OSError, ValueError, TypeError, KeyError, AttributeError, IndexError):
        return {"verified": False, "required": True, "overrides": [],
                "failures": ["override binding malformed or unreadable"],
                "reason": "独立心脏运行替换记录格式不完整或文件无法读取"}


def _runtime_override_status(record=None, directory=BASE):
    """Verify the separately owned heart image that occupies the existing slot."""
    art_source = (ROOT / "scripts/war/FullBodyMapArt.lua").read_text(encoding="utf8")
    active = "HeartVisual.replace" in art_source
    if record is None:
        path = BASE / "qa/runtime-resource-overrides.json"
        metadata = {"path": str(path), "sha256": sha(path)} if path.is_file() else {}
        capture_hashes = None
    else:
        metadata = record.get("resourceOverrides", {})
        capture_hashes = input_hashes(record)
    if not active and not metadata:
        return {"verified": True, "required": False, "overrides": [], "reason": "无独立运行素材替换"}
    failures = []
    path = resolve(metadata.get("path", "__missing__"), directory)
    if not active:
        failures.append("declared override is not registered by runtime")
    if not path.is_file() or sha(path) != metadata.get("sha256"):
        return {"verified": False, "required": active, "overrides": [],
                "failures": ["override record missing or changed"], "reason": "独立心脏运行替换记录缺失或哈希不符"}
    raw = read(path)
    manifest = read(BASE / "bake/manifest.json")
    if raw.get("schema") != "fullbody-runtime-resource-overrides/v1" or raw.get("scope") != "DEFERRED_EXTERNAL_SCOPE":
        failures.append("override schema or external scope invalid")
    if raw.get("manifestSha256") != sha(BASE / "bake/manifest.json"):
        failures.append("override baseline manifest changed")
    overrides = raw.get("overrides", [])
    if len(overrides) != 1 or overrides[0].get("id") != "heart" or overrides[0].get("runtimeLayer") != "organs":
        return {"verified": False, "required": active, "overrides": [],
                "failures": ["override must replace only the unique existing heart slot"],
                "reason": "运行替换不是唯一既有心脏规格"}
    item = overrides[0]
    baseline, replacement, module = (item.get(key, {}) for key in ("baseline", "replacement", "module"))
    for binding in (baseline, replacement):
        pixels = binding.get("pixelSize", [])
        if len(pixels) != 2 or any(type(value) is not int or value <= 0 for value in pixels):
            failures.append("bitmap dimensions must be two positive integer pixels")
    specs = [spec for layer in RUNTIME_LAYERS for spec in manifest.get("runtimeSpec", {}).get(layer, [])]
    hearts = [spec for spec in manifest.get("runtimeSpec", {}).get("organs", []) if spec.get("id") == "heart"]
    assets = [asset for asset in manifest.get("assets", []) if asset.get("id") == "heart"]
    if len(hearts) != 1 or len(assets) != 1 or sum(spec.get("id") == "heart" for spec in specs) != 1:
        return {"verified": False, "required": active, "overrides": [],
                "failures": ["baseline heart slot missing or repeated"], "reason": "冻结清单心脏规格不唯一"}
    original, asset = hearts[0], assets[0]
    if (any(baseline.get(key) != original.get(key) for key in ("resource", "sourceBox", "pixelSize")) or
            baseline.get("sha256") != asset.get("sha256") or
            baseline.get("sourceBox") != replacement.get("sourceBox") or
            replacement.get("sourceBox") != [468, 326, 568, 467]):
        failures.append("replacement registration differs from fixed heart source frame")
    original_path = ROOT / "assets" / original["resource"]
    try:
        if sha(original_path) != baseline.get("sha256") or list(Image.open(original_path).size) != baseline.get("pixelSize"):
            failures.append("baseline heart bitmap missing or changed")
    except (OSError, ValueError):
        failures.append("baseline heart bitmap missing or changed")
    replacement_path = resolve(replacement.get("path", "__missing__"), directory)
    resource_path = ROOT / "assets" / replacement.get("resource", "__missing__")
    if (replacement_path.resolve() != resource_path.resolve() or
            not resource_path.resolve().is_relative_to((ROOT / "assets").resolve()) or
            replacement.get("path") != "assets/" + replacement.get("resource", "__missing__")):
        failures.append("replacement path differs from actual registered resource")
    try:
        with Image.open(replacement_path) as bitmap:
            size = list(bitmap.size)
            if (bitmap.format != "PNG" or sha(replacement_path) != replacement.get("sha256") or
                    size != replacement.get("pixelSize")):
                failures.append("replacement PNG hash or image dimensions changed")
    except (OSError, ValueError):
        size = None
        failures.append("replacement bitmap missing or invalid")
    module_path = resolve(module.get("path", "__missing__"), directory)
    if module_path.resolve() != (ROOT / "scripts/war/HeartVisualData.lua").resolve() or not module_path.is_file():
        failures.append("heart registration module missing or different")
    else:
        text = module_path.read_text(encoding="utf8")
        resource_match = re.search(r"\bresource\s*=\s*['\"]([^'\"]+)['\"]", text)
        box_match = re.search(r"\bsourceBox\s*=\s*\{([^}]+)\}", text)
        size_match = re.search(r"\bpixelSize\s*=\s*\{([^}]+)\}", text)
        try:
            parsed_box = [float(x.strip()) for x in box_match[1].split(",")] if box_match else None
            parsed_size = [int(x.strip()) for x in size_match[1].split(",")] if size_match else None
        except ValueError:
            parsed_box = parsed_size = None
        if (sha(module_path) != module.get("sha256") or not resource_match or
                resource_match[1] != replacement.get("resource") or parsed_box != replacement.get("sourceBox") or
                parsed_size != replacement.get("pixelSize")):
            failures.append("actual HeartVisualData registration differs from record")
    hashes = input_hashes(raw)
    dependencies = [str(p.relative_to(ROOT)) for p in sorted((ROOT / "scripts/war").glob("Heart*.lua"))]
    dependencies.append(str(replacement_path.relative_to(ROOT)) if replacement_path.is_relative_to(ROOT) else str(replacement_path))
    for name in dependencies:
        source = resolve(name)
        actual = sha(source) if source.is_file() else None
        if not actual or hashes.get(name) != actual or (capture_hashes is not None and capture_hashes.get(name) != actual):
            failures.append("heart module or actual bitmap input hash missing or changed")
    if hashes.get(module.get("path")) != module.get("sha256"):
        failures.append("registration module input hash missing")
    effective = ["assets/" + (replacement["resource"] if spec.get("id") == "heart" else spec["resource"]) for spec in specs]
    quiet_source = (ROOT / "scripts/war/FullBodyMapArtData.lua").read_text(encoding="utf8")
    quiet = re.search(r'\["quietBase"\]=\{\["id"\]="[^"]+",\["resource"\]="([^"]+)"', quiet_source)
    quiet_bytes = 0
    if quiet:
        try:
            w, h = Image.open(ROOT / "assets" / quiet[1]).size
            quiet_bytes = w*h*4
        except (OSError, ValueError):
            failures.append("quiet bitmap missing while computing actual dimensions")
    else:
        failures.append("quiet runtime registration missing")
    baseline_bytes = sum(spec["pixelSize"][0]*spec["pixelSize"][1]*4 for spec in specs) + quiet_bytes
    effective_bytes = (baseline_bytes - original["pixelSize"][0]*original["pixelSize"][1]*4 + size[0]*size[1]*4) if size else None
    if (raw.get("effectiveRuntimeResourcesWithoutQuietBase") != effective or
            raw.get("baselineDecodedRGBABytesPerContext") != baseline_bytes or
            raw.get("effectiveDecodedRGBABytesPerContext") != effective_bytes):
        failures.append("actual loaded resources or decoded dimension estimate differs")
    if record is not None and (record.get("effectiveRuntimeResourcesWithoutQuietBase") != effective or
                               record.get("effectiveDecodedRGBABytesPerContext") != effective_bytes):
        failures.append("capture lacks actual override resource or decoded dimension binding")
    return {"verified": not failures, "required": active, "overrides": overrides,
            "recordPath": str(path), "recordSha256": sha(path), "failures": sorted(set(failures)),
            "effectiveRuntimeResourcesWithoutQuietBase": effective,
            "baselineDecodedRGBABytesPerContext": baseline_bytes,
            "effectiveDecodedRGBABytesPerContext": effective_bytes,
            "reason": "唯一心脏规格实际替换的源、PNG、尺寸与固定 sourceBox 已绑定；心肺美术仍属外部待合并" if not failures else "独立心脏运行替换未完整绑定"}


def native_hash_status(record, directory=BASE):
    """Bind native evidence to the manifest and every loaded bitmap, including quiet."""
    state = hash_status(record, directory)
    manifest_path = BASE / "bake/manifest.json"
    manifest = read(manifest_path)
    hashes = input_hashes(record)
    explicit = record.get("manifestSha256", hashes.get(str(manifest_path.relative_to(ROOT))))
    changed = list(state.get("changed", []))
    if explicit != sha(manifest_path):
        changed.append("bake/manifest.json (capture manifest)")
    expected = {a["path"]: a["sha256"] for a in manifest.get("assets", [])}
    override = runtime_override_status(record, directory)
    if not override["verified"]:
        changed.append("runtime heart resource override (missing or inconsistent binding)")
    elif override.get("required"):
        item = override["overrides"][0]
        expected.pop("assets/" + item["baseline"]["resource"], None)
        expected[item["replacement"]["path"]] = item["replacement"]["sha256"]
        for source in (ROOT / "scripts/war").glob("*.lua"):
            name = str(source.relative_to(ROOT))
            if hashes.get(name) != sha(source):
                changed.append(name + " (shared runtime source binding missing or changed)")
    data_path = ROOT / "scripts/war/FullBodyMapArtData.lua"
    data_source = data_path.read_text(encoding="utf8")
    quiet = re.search(r'\["quietBase"\]=\{\["id"\]="[^"]+",\["resource"\]="([^"]+)".*?\["sha256"\]="([0-9a-f]{64})"\}', data_source)
    if quiet:
        expected["assets/" + quiet[1]] = quiet[2]
    else:
        changed.append("quietBase (runtime specification missing)")
    for path, digest in expected.items():
        if hashes.get(path) != digest:
            changed.append(path + " (capture bitmap hash missing or different)")
    for path in ("scripts/war/FullBodyMapArt.lua", "scripts/war/FullBodyMapArtData.lua"):
        if path not in hashes:
            changed.append(path + " (capture runtime hash missing)")
    verified = state.get("verified", False) and not changed
    return {**state, "verified": verified, "changed": sorted(set(changed)),
            "runtimeBitmapHashes": len(expected),
            "resourceOverride": override,
            "reason": state["reason"] + "；manifest 与全部运行位图哈希一致" if verified else "运行输入、manifest 或位图版本未完整绑定"}


def native_batch_status(system, driver, directory):
    """Require the declared complete view batch before accepting its visual review."""
    captures = system.get("captures", [])
    phases = driver.get("phases", [])
    failures = []
    totals = {p.get("phase", p).get("total") for p in captures}
    expected = next(iter(totals)) if len(totals) == 1 else None
    if type(expected) is not int or expected < 1:
        failures.append("capture total missing or inconsistent")
        expected = 0
    if system.get("complete") is not True or driver.get("completed") is not True:
        failures.append("capture or driver not complete")
    if system.get("errors") or driver.get("errors"):
        failures.append("capture or driver errors")
    if len(captures) != expected or len(phases) != expected:
        failures.append("declared views missing")
    indices = [p.get("phase", p).get("index") for p in captures]
    if set(indices) != set(range(1, expected + 1)) or len(set(indices)) != len(indices):
        failures.append("capture indices missing or repeated")
    by_index = {p.get("index"): p for p in phases}
    if len(by_index) != len(phases):
        failures.append("driver indices repeated")
    verified_pngs = 0
    for item in captures:
        phase = item.get("phase", item)
        recorded = by_index.get(phase.get("index"), {})
        if any(phase.get(key) != recorded.get(key) for key in ("runId", "label", "camera", "zoom", "modal")):
            failures.append("capture phase differs from driver")
        if phase.get("runId") != driver.get("runId"):
            failures.append("capture run differs from driver")
        if not all(phase.get(key) is True for key in ("worldReady", "uiReady", "snapshotUnchanged", "visibilityUnchanged")):
            failures.append("capture readiness or frozen-state evidence missing")
        image_path = resolve(item.get("path", item.get("file", "__missing__")), directory)
        if image_path.is_file() and sha(image_path) == item.get("sha256"):
            verified_pngs += 1
        else:
            failures.append("capture PNG missing or changed")
    return {"verified": expected > 0 and not failures, "expectedViews": expected,
            "verifiedPngs": verified_pngs, "failures": sorted(set(failures))}


def scoped_visual_status(review, reviewed_all):
    """Keep the explicit non-cardiopulmonary scope and its detail evidence honest."""
    scope = review.get("reviewScope", {})
    rows = review.get("captures", [])
    failures = []
    if not reviewed_all:
        failures.append("current complete batch not independently reviewed")
    if (review.get("status") != "PASS_SCOPED" or scope.get("scopedVisualAccepted") is not True or
            review.get("overallVisualAccepted") is not False):
        failures.append("scoped acceptance declaration missing")
    if set(scope.get("excludedRegions", [])) != DEFERRED_VISUAL_REGIONS or not scope.get("description"):
        failures.append("heart and both lung scope not explicit")
    if scope.get("coverageComplete") is not True or scope.get("pendingRequiredViews"):
        failures.append("required visual coverage incomplete")
    by_label = {row.get("label"): row for row in rows}
    if len(by_label) != len(rows):
        failures.append("review labels repeated")
    for label in SCOPED_DETAIL_VIEWS:
        row = by_label.get(label, {})
        if (row.get("status") != "PASS" or row.get("zoom") != .15 or row.get("modal") is not False or
                row.get("independentlyViewed") is not True):
            failures.append("required head or limb detail evidence missing")
    for row in rows:
        label, status = row.get("label"), row.get("status")
        expected = ("DEFERRED_EXTERNAL_SCOPE" if label in DEFERRED_NATIVE_VIEWS else
                    "LOCATION_ONLY" if label in ("whole-body", "map-popup") else "PASS")
        if status != expected or row.get("independentlyViewed") is not True:
            failures.append("visual finding unresolved or outside declared scope")
    if review.get("blockingFindings") or review.get("pendingFindings"):
        failures.append("visual findings remain open")
    return {"verified": not failures, "failures": sorted(set(failures)),
            "requiredDetailViews": sorted(SCOPED_DETAIL_VIEWS)}


def menu_hash_status(review):
    """Bind the normal-menu image to its own capture inputs and production entry."""
    state = hash_status(review)
    record_path = resolve(review.get("recordPath", "__missing__"))
    if not record_path.is_file() or sha(record_path) != review.get("recordSha256"):
        return {**state, "verified": False, "reason": "菜单截图记录未绑定"}
    record = read(record_path)
    image_path = resolve(record.get("path", "__missing__"), record_path.parent)
    if (not image_path.is_file() or sha(image_path) != record.get("sha256") or
            record.get("sha256") != review.get("sha256") or
            image_path.resolve() != resolve(review.get("imagePath", "__missing__")).resolve()):
        return {**state, "verified": False, "reason": "菜单原始 PNG 与复核图片未绑定"}
    inputs_path = resolve(record.get("inputsPath", "__missing__"), record_path.parent)
    if not inputs_path.is_file() or sha(inputs_path) != record.get("inputsSha256"):
        return {**state, "verified": False, "reason": "菜单截图缺少本批完整输入绑定"}
    inputs = read(inputs_path)
    binding = native_hash_status(inputs, inputs_path.parent)
    normal = (record.get("mainSha256") == NORMAL_ENTRY_SHA256 and
              input_hashes(inputs).get("scripts/main.lua") == NORMAL_ENTRY_SHA256)
    verified = state["verified"] and binding["verified"] and normal
    return {**binding, "verified": verified,
            "reason": binding["reason"] + "；生产菜单入口已绑定" if verified else "菜单复核、生产入口或完整素材输入未绑定"}


def terminal_capture_status(case, captures, directory, system=None):
    """Require the final PNG to contain verified goals and match the driver's acknowledgement."""
    final = captures[-1] if captures else {}
    phase = final.get("phase", {})
    ack = case.get("terminalScreenshot", {})
    marker = bool(phase.get("terminal") and phase.get("terminalReady") and
                  phase.get("terminalRenderedFrames", 0) >= 2 and phase.get("driverArrivalVerified") and
                  phase.get("recording") and phase.get("stage") == "record" and phase.get("complete"))
    expected_path = resolve(final.get("path", "__missing__"), directory)
    acknowledged = bool(marker and ack.get("terminal") is True and
                        ack.get("stateRunId") == phase.get("stateRunId") == case.get("stateRunId") and
                        ack.get("index") == phase.get("index") == case.get("index") and
                        ack.get("pngSha256") == final.get("sha256") and ack.get("pngPath") and
                        resolve(ack["pngPath"], directory).resolve() == expected_path.resolve() and
                        expected_path.is_file() and sha(expected_path) == ack.get("pngSha256"))
    armed_mirror = True
    if ack.get("schema") == "fullbody-native-terminal-capture-ack/v2" or directory.name == "native-movement-005":
        system = system or {}
        armed = case.get("captureReady", {})
        mirror = final.get("runtimeMirror", {})
        current_path = Path(system.get("sourceCurrentPath", "__missing__"))
        mirror_path = Path(mirror.get("path", "__missing__"))
        batch = directory.name.removeprefix("native-movement-")
        runtime_path = f'qa/organ-atlas-native/fullbody-movement-{batch}/terminal-case-{case.get("index")}.png'
        manifest_sha = sha(BASE / "bake/manifest.json")
        armed_mirror = bool(
            ack.get("schema") == "fullbody-native-terminal-capture-ack/v2" and
            armed.get("schema") == "fullbody-native-capture-ready/v1" and
            armed.get("stateRunId") == armed.get("runId") == case.get("stateRunId") and
            armed.get("index") == case.get("index") and armed.get("id") == case.get("id") and
            re.fullmatch("[0-9a-f]{32}", str(armed.get("nonce", ""))) and
            ack.get("captureNonce") == armed.get("nonce") and
            type(system.get("ownerPid")) is int and system["ownerPid"] > 0 and
            ack.get("ownerPid") == armed.get("ownerPid") == armed.get("statusPID") == system["ownerPid"] and
            type(system.get("window", {}).get("id")) is int and system["window"]["id"] > 0 and
            ack.get("windowId") == system.get("window", {}).get("id") and
            ack.get("manifestSha256") == armed.get("manifestSha256") == armed.get("desiredManifestSha256") == manifest_sha and
            current_path.is_absolute() and mirror_path.is_absolute() and
            armed.get("sourceCurrentParent") == armed.get("currentParent") == str(current_path.parent.resolve()) and
            tuple(current_path.parts[-4:]) == ("qa", "organ-atlas-native", "fullbody-movement-" + batch, "current.json") and
            mirror_path.parent.resolve() == current_path.parent.resolve() and
            mirror_path.name == f'terminal-case-{case.get("index")}.png' and
            ack.get("pngRuntimePath") == mirror.get("runtimePath") == runtime_path and
            ack.get("runtimeMirrorSha256") == mirror.get("sha256") == final.get("sha256") and
            expected_path.is_file() and mirror_path.is_file() and sha(mirror_path) == final.get("sha256") and
            ack.get("runtimeMirrorBytes") == mirror.get("bytes") == mirror_path.stat().st_size == expected_path.stat().st_size and
            final.get("terminalAcknowledgement") == ack)
    goals_match = phase.get("goals") == case.get("commands") and bool(case.get("commands"))
    return {"terminalMarkerVerified": marker, "terminalScreenshotAcknowledged": acknowledged,
            "captureArmingAndRuntimeMirrorVerified": armed_mirror,
            "terminalGoalsMatchAcceptedCommands": goals_match,
            "verified": marker and acknowledged and armed_mirror and goals_match}


def performance_record_status(item, actual):
    try:
        return _performance_record_status(item, actual)
    except (ValueError, TypeError, KeyError, AttributeError, IndexError):
        return {"verified": False, "failures": ["timing samples or summary malformed"], "recomputed": {}}


def _performance_record_status(item, actual):
    """Recompute the two off/on P95 groups from the original frame samples."""
    phases = actual.get("phases", [])
    failures = []
    if (actual.get("schema") != "fullbody-native-timing/v1" or actual.get("completed") is not True or
            actual.get("simulationUnchanged", actual.get("simUnchanged")) is not True or
            actual.get("reason") != "complete" or actual.get("error") or actual.get("errors") or
            actual.get("zoom") != .15 or actual.get("dpr") != 2 or
            actual.get("samplesPerPhase") != 180 or actual.get("warmupPerPhase") != 60):
        failures.append("timing capture incomplete or required paused measurement differs")
    if len(phases) != 4 or [p.get("enabled") for p in phases] != [False, True, True, False]:
        failures.append("four paired off/on phases missing")
    for phase in phases:
        for field in ("frameMs", "renderCpuMs"):
            samples = phase.get(field, [])
            if (len(samples) != 180 or any(type(v) not in (int, float) or not math.isfinite(v) or
                                          v < 0 or (field == "frameMs" and v == 0) for v in samples)):
                failures.append("original frame or render CPU samples missing or invalid")
    if (item.get("camera") != actual.get("camera") or item.get("dpr") != actual.get("dpr") or
            item.get("resources") != actual.get("resources") or item.get("samplesPerGroup") != 360):
        failures.append("timing summary camera, resources or sample count differs")
    resources = actual.get("resources", {})
    if resources.get("contexts") != 2 or type(resources.get("images")) is not int or resources.get("images", 0) < 1:
        failures.append("both loaded runtime contexts missing")
    recomputed = {}
    if not failures:
        percentile = lambda rows: sorted(rows)[math.ceil(len(rows)*.95)-1]
        groups = {enabled: {field: percentile([v for p in phases if p["enabled"] is enabled for v in p[field]])
                            for field in ("frameMs", "renderCpuMs")} for enabled in (False, True)}
        for field, suffix in (("frameMs", "FrameP95Ms"), ("renderCpuMs", "RenderCpuP95Ms")):
            off, on = groups[False][field], groups[True][field]
            recomputed["off" + suffix], recomputed["on" + suffix] = off, on
            recomputed["frameP95IncrementMs" if field == "frameMs" else "renderCpuP95IncrementMs"] = on-off
        for key, value in recomputed.items():
            recorded = item.get(key)
            if (type(recorded) not in (int, float) or not math.isfinite(recorded) or
                    not math.isclose(recorded, value, rel_tol=1e-12, abs_tol=1e-9)):
                failures.append("timing summary P95 differs from original samples")
    return {"verified": not failures, "failures": sorted(set(failures)), "recomputed": recomputed}


def compact_ring(ring):
    # Empty Lua arrays are sometimes exported as {}. Normalize only that
    # documented empty shape; malformed nonempty geometry must stop publishing.
    outer, holes = ring.get("outer", []), ring.get("holes", [])
    if holes == {} or holes is None:
        holes = []
    if not isinstance(outer, list) or not isinstance(holes, list):
        raise ValueError("Collision ring outer/holes must contain coordinate arrays")
    for polygon in [outer, *holes]:
        if not isinstance(polygon, list) or any(not isinstance(point, list) or len(point) != 2 or
                                              not all(isinstance(x, (int, float)) and math.isfinite(x) for x in point)
                                              for point in polygon):
            raise ValueError("Collision ring point must be a finite [x,y] coordinate")
    return {"outer": outer, "holes": holes}


def webp_frame_durations(path):
    data, durations, offset = path.read_bytes(), [], 12
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return durations
    while offset + 8 <= len(data):
        kind = data[offset:offset+4]
        size = int.from_bytes(data[offset+4:offset+8], "little")
        body = data[offset+8:offset+8+size]
        if kind == b"ANMF" and len(body) >= 16:
            durations.append(int.from_bytes(body[12:15], "little"))
        offset += 8+size+(size % 2)
    return durations


class Publisher:
    def __init__(self):
        self.evidence = []
        self.staged = {}

    def stage(self, path: Path, category="evidence", expected=None):
        if not path.is_file():
            return None
        content = path.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        if expected and expected != digest:
            return None
        size = None
        if path.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp", ".gif"):
            try:
                size = list(Image.open(io.BytesIO(content)).size)
            except (OSError, ValueError):
                return None
        key = (str(path), digest)
        if key in self.staged:
            return self.staged[key]
        stem = re.sub(r"[^a-zA-Z0-9_.-]", "_", path.stem)[:70]
        relative = Path(category) / (stem + "-" + digest[:12] + path.suffix)
        target = REVIEW / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.is_file() or sha(target) != digest:
            target.write_bytes(content)
        row = {"url": "fullbody-015/review/" + relative.as_posix(), "sha256": digest,
               "sourcePath": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)}
        if size:
            row["pixelSize"] = size
        self.staged[key] = row
        self.evidence.append(row)
        return row

    def report(self, path):
        if not path.is_file():
            return {"status": "UNDETERMINED", "present": False, "hashState": {"verified": False}}
        record = read(path)
        row = self.stage(path, "reports")
        return {"status": record.get("status", "RECORDED"), "present": True, "record": row,
                "hashState": hash_status(record, path.parent),
                "total": record.get("total"), "passed": record.get("passed"),
                "nativeEvidence": record.get("nativeEvidence", False), "raw": record}

    def native(self):
        rows, records = [], []
        for path in sorted(BASE.glob("native-*/system-views.json")):
            if "performance" in path.parent.name:
                continue
            system = read(path)
            input_path = path.parent / "inputs.json"
            inputs = read(input_path) if input_path.is_file() else {}
            driver_path = path.parent / "driver-report.json"
            driver = read(driver_path) if driver_path.is_file() else {}
            state = native_hash_status(inputs, path.parent)
            batch = native_batch_status(system, driver, path.parent)
            binding = state["verified"]
            records.append({"directory": path.parent.name, "record": self.stage(path, "reports"),
                            "inputs": self.stage(input_path, "reports"), "current": binding, "hashState": state,
                            "complete": system.get("complete", driver.get("completed", False)), "errors": system.get("errors", []),
                            "batchState": batch,
                            "captureStatus": inputs.get("status", "RECORDED"), "driver": self.stage(driver_path, "reports")})
            for item in system.get("captures", []):
                image_path = resolve(item.get("path", item.get("file", "")), path.parent)
                if not image_path.is_file():
                    continue
                if sha(image_path) != item.get("sha256"):
                    continue
                phase = item.get("phase", item)
                pic = self.stage(image_path, "native")
                if not pic:
                    continue
                bounds = system.get("window", {}).get("bounds", {})
                logical_width = phase.get("logicalWidth", phase.get("width", bounds.get("Width")))
                dpr = phase.get("dpr", system.get("dpr", driver.get("dpr")))
                if dpr and not logical_width:
                    logical_width = pic["pixelSize"][0] / dpr
                if logical_width and not dpr:
                    dpr = pic["pixelSize"][0] / logical_width
                label = phase.get("label", image_path.stem)
                rows.append({**pic, "kind": "native", "label": label, "displayLabel": human_view_label(label),
                             "coverageNote": hand_coverage_note(label), "organId": phase.get("organId"),
                             "region": region_for(label, phase.get("organId")), "zoom": phase.get("zoom"),
                             "zoomLabel": "弹窗全身 fit（世界镜头 " + str(phase.get("zoom")) + "）" if "popup" in str(label) else str(phase.get("zoom")),
                             "logicalWidth": logical_width, "dpr": dpr, "phase": phase,
                             "current": binding, "captureDirectory": path.parent.name,
                             "captureStatus": inputs.get("status", "RECORDED")})
        return rows, records

    def offline(self):
        rows, moves, records = [], [], []
        for path in sorted(BASE.glob("**/*report.json")):
            if any(p.startswith("native-") for p in path.parts) or "review" in path.relative_to(BASE).parts:
                continue
            if not any(word in str(path.relative_to(BASE)) for word in ("render", "offline")):
                continue
            record = read(path)
            frames = record.get("frames", record.get("render", {}).get("frames", []))
            animations = record.get("animations", record.get("render", {}).get("animations", []))
            if not frames and not animations:
                continue
            state = hash_status(record, path.parent)
            explicit = record.get("manifestSha256")
            if explicit and explicit != sha(BASE / "bake/manifest.json"):
                state = {**state, "verified": False, "reason": "素材manifest已变化"}
            records.append({"record": self.stage(path, "reports"), "status": record.get("status"), "hashState": state})
            for item in frames:
                filename = item.get("file", item.get("path", ""))
                image_path = resolve(filename, BASE if filename.startswith("qa/") else path.parent)
                if not image_path.is_file() or (item.get("sha256") and sha(image_path) != item["sha256"]):
                    continue
                pic = self.stage(image_path, "offline")
                if not pic:
                    continue
                label = item.get("name", item.get("label", image_path.stem))
                size = item.get("size", item.get("logicalSize", []))
                logical_width = item.get("logicalWidth", size[0] if size else None)
                if not logical_width and item.get("dpr"):
                    logical_width = pic["pixelSize"][0] / item["dpr"]
                rows.append({**pic, "kind": "offline", "label": label, "displayLabel": human_view_label(label),
                             "coverageNote": hand_coverage_note(label), "organId": item.get("organId"),
                             "region": region_for(label, item.get("organId")), "zoom": item.get("zoom", .15),
                             "logicalWidth": logical_width, "dpr": item.get("dpr"), "current": state["verified"]})
            for item in animations:
                filename = item.get("file", item.get("path", ""))
                image_path = resolve(filename, BASE if filename.startswith("qa/") else path.parent)
                if image_path.is_file() and (not item.get("sha256") or sha(image_path) == item["sha256"]):
                    pic = self.stage(image_path, "movement")
                    if not pic:
                        continue
                    moves.append({**pic, "kind": "offline", "current": state["verified"],
                                  "label": item.get("label", item.get("organId", image_path.stem)),
                                  "seconds": item.get("seconds", item.get("duration")), "fps": item.get("fps"),
                                  "timeCompression": item.get("timeCompression"), "logicalWidth": item.get("logicalWidth"), "dpr": item.get("dpr")})
        return rows, moves, records

    def native_movement(self):
        moves, records = [], []
        for path in sorted(BASE.glob("native-movement-*/system-movement.json")):
            system = read(path)
            inputs_path, driver_path = path.parent / "inputs.json", path.parent / "driver-report.json"
            inputs = read(inputs_path) if inputs_path.is_file() else {}
            driver = read(driver_path) if driver_path.is_file() else {}
            binding = native_hash_status(inputs, path.parent)
            evidence = {"directory": path.parent.name, "record": self.stage(path, "reports"),
                        "driver": self.stage(driver_path, "reports"), "inputs": self.stage(inputs_path, "reports"),
                        "hashState": binding, "current": binding["verified"], "cases": []}
            bounds = system.get("window", {}).get("bounds", {})
            for coverage in system.get("caseCoverage", []):
                case = next((c for c in driver.get("cases", []) if c.get("id") == coverage.get("id")), {})
                captures = [c for c in system.get("captures", []) if c.get("phase", {}).get("id") == coverage.get("id")]
                frames, invalid = [], []
                last_time = -1
                for capture in captures:
                    pic = self.stage(resolve(capture["path"], path.parent), "native-movement", capture.get("sha256"))
                    phase = capture.get("phase", {})
                    stamp = capture.get("captureStartedUnix", 0)
                    valid = (pic and phase.get("recording") and phase.get("stage") == "record" and
                             phase.get("worldReady") and phase.get("uiReady") and
                             phase.get("stateRunId") == coverage.get("stateRunId") == case.get("stateRunId") and
                             phase.get("zoom") == .15 and stamp > last_time)
                    if not valid:
                        invalid.append(capture.get("path"))
                    if pic:
                        frames.append({**pic, "phase": phase, "captureStartedUnix": stamp})
                    last_time = stamp
                span = captures[-1]["captureStartedUnix"]-captures[0]["captureStartedUnix"] if len(captures) > 1 else 0
                arrivals = case.get("arrivals", [])
                arrived = bool(arrivals) and all(a.get("distanceWorld", 99) <= .075 and a.get("laneMatches") and a.get("organMatches") for a in arrivals)
                last_positions = {p.get("id"): p for p in captures[-1].get("phase", {}).get("positions", [])} if captures else {}
                last_capture_goals = []
                for command in case.get("commands", []):
                    actor, goal = last_positions.get(command.get("id")), command.get("resolved")
                    if actor and goal:
                        distance = math.hypot(actor["x"]-goal["x"], actor["y"]-goal["y"])
                        last_capture_goals.append({"id": command.get("id"), "distanceWorld": distance,
                                                   "laneMatches": actor.get("lane") == goal.get("lane"),
                                                   "capturedAtAcceptedGoal": distance <= .075 and actor.get("lane") == goal.get("lane")})
                captured_arrivals = bool(last_capture_goals) and len(last_capture_goals) == len(case.get("commands", [])) and all(g["capturedAtAcceptedGoal"] for g in last_capture_goals)
                terminal = terminal_capture_status(case, captures, path.parent, system)
                moved = bool(case.get("movedDistanceWorld")) and all(d > 0 for d in case["movedDistanceWorld"])
                accepted = bool(case.get("commands")) and all(c.get("accepted") and c.get("resolved") for c in case["commands"])
                recorded = bool(system.get("completed") and driver.get("completed") and case.get("completed") and
                                not invalid and len(frames) == coverage.get("frames") and span >= 15 and
                                case.get("recordingUsesNormalMainLoop") and driver.get("speed") == 1 and
                                system.get("timeCompression") == 1 and arrived and moved and accepted)
                index = case.get("index", 0)
                animation_path = path.parent / f"case-{index:02d}.webp"
                animation = self.stage(animation_path, "movement")
                if animation:
                    image = Image.open(animation_path)
                    animation_frames = getattr(image, "n_frames", 1)
                    durations = webp_frame_durations(animation_path)
                else:
                    animation_frames = 0
                    durations = []
                expected_durations = [max(1, round((captures[n+1]["captureStartedUnix"]-c["captureStartedUnix"])*1000))
                                      if n+1 < len(captures) else 750 for n, c in enumerate(captures)]
                timing_matches = len(durations) == len(captures) and all(abs(a-b) <= 2 for a, b in zip(durations, expected_durations))
                recorded = recorded and animation_frames == len(frames) and timing_matches
                arrival_recorded = recorded and captured_arrivals and terminal["verified"]
                review = {"id": coverage.get("id"), "frames": frames, "captureSpanSeconds": span,
                          "verifiedRecordedCase": arrival_recorded, "legacyRecordedCase": recorded,
                          "terminalCapture": terminal,
                          "invalidFrames": invalid, "arrived": arrived,
                          "movedDistanceWorld": case.get("movedDistanceWorld"), "commands": case.get("commands"),
                          "stateRunId": case.get("stateRunId"), "animationFrames": animation_frames,
                          "animationDurationSeconds": sum(durations)/1000, "replayTimingMatchesCapture": timing_matches}
                review.update({"driverArrivalVerified": arrived, "lastCaptureGoalChecks": last_capture_goals,
                               "lastCaptureShowsAllArrivals": captured_arrivals})
                evidence["cases"].append(review)
                if animation:
                    labels = {1: "胃壁出口 · 重型细胞", 2: "胸部主干 · 侦察细胞", 3: "胃入口 · 双向会车", 4: "胰腺入口 · 重型细胞"}
                    moves.append({**animation, "kind": "native", "label": labels.get(index, coverage.get("id")),
                                  "seconds": round(span, 3), "timeCompression": 1,
                                  "current": binding["verified"] and arrival_recorded, "recorded": recorded,
                                  "captureDirectory": path.parent.name, "logicalWidth": bounds.get("Width"),
                                  "frames": len(frames), "review": review,
                                  "limits": "原生正常 1×；按约一秒间隔的真实窗口截图播放，非 60 FPS 录像。" +
                                  (" 终点截图已入镜并获同一运行的驱动确认。" if arrival_recorded else
                                   " 最后截图已拍到终点，但未完整记录终点握手。" if captured_arrivals else
                                   " 最后截图尚未拍到全部到达；稍后的正常主循环 driver 记录验证终点，不将动图末帧写成到达。")})
            records.append(evidence)
        return moves, records

    def performance(self):
        summary = self.report(BASE / "qa/native-performance-summary.json")
        raw = summary.get("raw", {})
        records, binding_states = [], []
        input_records = {Path(item["path"]).parent: item for item in raw.get("inputEvidence", [])}
        views = raw.get("views", [])
        cameras = {(item.get("camera", {}).get("x"), item.get("camera", {}).get("y")) for item in views}
        valid = (len(views) == 2 and len(input_records) == len(raw.get("inputEvidence", [])) == 2 and
                 len({item["path"] for item in views}) == 2 and cameras == {(1036, 1492), (1056, 1210)})
        for item in raw.get("views", []):
            path = resolve(item["path"])
            report = self.stage(path, "reports", item.get("sha256"))
            input_item = input_records.get(Path(item["path"]).parent)
            input_path = resolve(input_item["path"]) if input_item else path.parent / "inputs.json"
            input_art = self.stage(input_path, "reports", input_item.get("sha256") if input_item else None)
            state = native_hash_status(read(input_path), input_path.parent) if input_art else {"verified": False, "reason": "缺少运行输入"}
            actual = read(path) if report else {}
            measurement = performance_record_status(item, actual)
            completed = bool(report and report["sha256"] == item.get("sha256") and input_item and input_art and
                             input_art["sha256"] == input_item.get("sha256") and measurement["verified"])
            if state["verified"] and actual.get("resources", {}).get("images") != state["runtimeBitmapHashes"]*2:
                state = {**state, "verified": False,
                         "changed": state.get("changed", []) + ["current runtime images not loaded in both contexts"],
                         "reason": "完整帧测量未在双 context 加载本次实际全部位图"}
            valid = valid and completed
            binding_states.append(state)
            records.append({**item, "report": report, "inputs": input_art, "hashState": state,
                            "measurementState": measurement, "recorded": completed})
        current = (valid and all(s["verified"] for s in binding_states) and
                   raw.get("schema") == "fullbody-native-performance-summary/v1" and
                   raw.get("manifestSha256") == sha(BASE / "bake/manifest.json"))
        summary["hashState"] = {"verified": current, "checked": sum(s.get("checked", 0) for s in binding_states),
                                "changed": sorted(set(n for s in binding_states for n in s.get("changed", []))),
                                "reason": "两视角各自运行输入、原始帧样本与重算 P95 一致" if current else
                                          "历史原生测量；输入已变化或缺失" if valid else "两视角原生测量未完整采样或汇总不一致"}
        target_met = (raw.get("targetAddedFrameP95Ms") == 2 and valid and
                      all(record["measurementState"]["recomputed"]["frameP95IncrementMs"] <= 2 for record in records))
        summary.update({"views": records, "recorded": valid,
                        "confirmed": bool(current and raw.get("nativeEvidence") is True and
                                          raw.get("incrementTargetMet") is True and target_met)})
        return summary


HAND_COVERAGE_NOTE = "手部冻结循环覆盖掌内与指根末梢；本轮未验证指尖全覆盖。"


def human_view_label(label):
    name = str(label)
    normalized = name.replace("_", "-")
    for prefix, display in (("fingers-right", "右手掌内／指根末梢"),
                            ("fingers-left", "左手掌内／指根末梢"),
                            ("hand-right", "右手掌循环"), ("hand-left", "左手掌循环")):
        if normalized == prefix or normalized.startswith(prefix + "-"):
            return display
    return name


def hand_coverage_note(label):
    return HAND_COVERAGE_NOTE if region_for(label) in ("hand_r", "hand_l") else ""


def region_for(label, organ=None):
    if any(word in str(label).lower() for word in ("whole", "popup", "overview")):
        return "whole"
    if organ in NAMES:
        return organ
    text = str(label).lower().replace("-", "_")
    for region, patterns in (("head", ("head_entry", "brain_entry")), ("neck", ("neck_",)),
                             ("hand_r", ("hand_right", "wrist_right", "fingers_right")),
                             ("hand_l", ("hand_left", "wrist_left", "fingers_left"))):
        if any(pattern in text for pattern in patterns):
            return region
    for oid in sorted(NAMES, key=len, reverse=True):
        if oid in text:
            return oid
    for region, patterns in [("arm_r", ["arm_r", "right_arm", "arm_right", "elbow_right"]), ("arm_l", ["arm_l", "left_arm", "arm_left", "elbow_left"]),
                             ("leg_r", ["leg_r", "right_leg", "leg_right", "foot_right", "knee_right", "shin_right", "calf_right", "ankle_right", "heel_right"]),
                             ("leg_l", ["leg_l", "left_leg", "leg_left", "foot_left", "knee_left", "shin_left", "calf_left", "ankle_left", "heel_left"]),
                             ("whole", ["whole", "popup", "overview"]), ("main", ["arch", "aorta", "portal", "mesenteric", "pelvis", "trunk", "main"])]:
        if any(p in text for p in patterns):
            return region
    return "main"


HTML = r'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>全身地图 · 0.15</title>
<style>*{box-sizing:border-box}body{margin:0;background:#eee8e1;color:#5d4446;font:15px/1.65 system-ui,-apple-system,sans-serif}header,main{max-width:1440px;margin:auto;padding:24px}h1{font-size:28px;line-height:1.3;margin:8px 0 12px}h2{font-size:20px;margin:0 0 14px}h3{font-size:16px;margin:0 0 8px}p{margin:8px 0}a{color:#835e6c}nav,.controls,.links{display:flex;gap:14px;align-items:center;flex-wrap:wrap}nav{margin:18px 0}.badge{display:inline-block;padding:4px 11px;background:#e7d8d0;border-radius:16px;font-size:12px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-top:22px}.stats>div,.panel{background:#fbf5ee;border:1px solid #d9c7bc;border-radius:12px;padding:18px}.stats strong{font-size:23px;display:block}.stats span,small,figcaption{font-size:12px;color:#856e6d}.layout{display:grid;grid-template-columns:264px minmax(0,1fr);gap:20px}.locator{position:sticky;top:16px;height:max-content}.locator svg{display:block;width:100%;height:auto;background:#fffdf9;border-radius:8px}.locator circle{cursor:pointer}.locator circle:focus{outline:none;stroke-width:8}.location-note{font-size:12px;color:#846f6c}section.panel{margin-bottom:20px;min-width:0}button,select{font:inherit;color:inherit;border:1px solid #c8b0a9;background:#f8eee4;border-radius:7px;padding:8px 10px;max-width:100%}button{cursor:pointer}label{font-size:13px}.controls{margin:12px 0 16px}.viewer{position:relative;overflow:auto;background:#ded6cd;border:1px solid #cbb8ae;border-radius:9px;max-height:800px;min-height:280px}.viewer img{display:block;max-width:none;width:var(--logical-width);height:auto}.viewer.fit img{width:100%;max-width:100%}.empty{padding:70px 24px;text-align:center;color:#846d67}.note{padding:12px 15px;background:#eadfd4;border-radius:8px;font-size:13px}.cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}.card{min-width:0;padding:12px;background:#f3e9df;border-radius:9px}.card img{display:block;width:100%;height:220px;object-fit:contain;background:#e7ddd3;border-radius:6px}figure{margin:0}.compare{display:grid;grid-template-columns:1fr 1fr;gap:14px}.compare img{display:block;width:100%;height:360px;object-fit:contain;background:#e9dfd4;border-radius:8px}table{width:100%;border-collapse:collapse;font-size:13px}td,th{padding:10px 12px;border-bottom:1px solid #e1d1c5;text-align:left;vertical-align:top}th{background:#f0e4d8}code{font-size:11px;overflow-wrap:anywhere}details{margin:12px 0}summary{cursor:pointer}.scroll{overflow:auto}.pathref svg{display:block;width:100%;max-height:640px;background:#f3e9df;border-radius:8px}.movement img{display:block;max-width:none;width:var(--logical-width,1024px)}footer{padding:10px 0 25px;color:#886f6a;font-size:12px}.status-pass{color:#6f6c58}.status-pending{color:#946b58}@media(max-width:900px){.layout{grid-template-columns:1fr}.locator{position:static;display:grid;grid-template-columns:150px 1fr;gap:16px}.locator svg{width:150px}.cards{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:560px){header,main{padding:16px}.stats{grid-template-columns:1fr 1fr}.cards,.compare{grid-template-columns:1fr}h1{font-size:24px}.compare img{height:280px}.controls{gap:10px}.locator{grid-template-columns:125px 1fr}.locator svg{width:125px}td,th{padding:8px}}</style></head>
<body><header><span class="badge">12 器官 · 定稿全身路线 · 独立可玩地图</span><h1>全身地图 · 0.15</h1><p>主干、分支、器官入口与十二个器官沿同一张人体主图对齐。血管采用 GPT 平面组织材质；脑部与四肢沿用定稿位置，食物、气道和尿路保持独立。</p><p class="note" id="top-review"></p><p class="note" id="scope-note" hidden></p><nav><a href="#scene">真正倍率视口</a><a href="#movement">原生 1× 移动</a><a href="#materials">器官与接头</a><a href="#reference">路线与碰撞参考</a><a href="#evidence">验收证据</a></nav><div class="stats"><div><strong id="organ-count"></strong><span>当前器官图像规格 · 外部替换另列</span></div><div><strong id="edge-count"></strong><span>当前清单覆盖血管</span></div><div><strong id="native-count"></strong><span>绑定当前版本的原生静帧</span></div><div><strong id="perf-state"></strong><span>原生完整帧时 · 独立验收</span></div></div></header>
<main><div class="layout"><aside class="panel locator"><svg id="locator" viewBox="0 0 1024 1536" aria-label="全身器官定位缩略图"></svg><div><h3>全身定位</h3><p class="location-note">点击器官圆点或从镜头列表选择。此缩略只用于定位；战场视口默认保留逻辑像素。</p><p class="location-note" id="locator-selected"></p><label><input id="locator-routes" type="checkbox">显示定稿路线</label><p class="location-note">新增入口为全身地图模式。原有战役、沙盒及存档的路线继续沿用各自版本。</p></div></aside><div>
<section class="panel" id="scene"><h2>真正倍率视口</h2><div class="note" id="native-note"></div><div class="controls"><label>区域 <select id="region"></select></label><label>证据 <select id="source"><option value="native">原生游戏窗口</option><option value="offline">真实 Lua 离线绘制</option></select></label><label>截图批次 <select id="capture"></select></label><label>视角 <select id="view"></select></label><label><input type="checkbox" id="fit">缩小到页面宽度</label></div><h3 id="view-title"></h3><div class="viewer" id="viewer"><div class="empty" id="empty"></div><img id="scene-image" alt="全身地图在真实倍率下的记录" hidden></div><p id="caption"></p><p><small>图片 SHA-256：<code id="scene-hash"></code></small></p><p><small>默认 1 个游戏逻辑像素对应 1 个页面 CSS 像素。窄页面可横向滚动；“缩小到页面宽度”只改变展示大小。zoom=0.15 时，主图的 1 像素对应 9.6 个游戏逻辑像素。全身远景与地图弹窗会单独标出倍率。</small></p></section>
<section class="panel" id="movement"><h2>原生 1× 移动与会车</h2><p id="motion-summary"></p><div class="controls"><select id="movement-view"></select><label>实际窗口帧 <select id="movement-frame"></select></label><button id="movement-play">播放记录</button><button id="movement-stop">停止</button><label><input id="movement-fit" type="checkbox">缩小到页面宽度</label></div><div class="viewer movement" id="movement-wrap"><div class="empty" id="movement-empty"></div><img id="movement-image" alt="生产移动逻辑记录" hidden></div><p id="movement-caption"></p><p><small>当前记录 SHA-256：<code id="movement-hash"></code></small></p><p><small>原生记录按真实截取间隔播放。静帧序列约 1 FPS，可观察移动与连接，完整帧时单独测量；离线缩时记录明确标出，不用来推定原生速度。</small></p></section>
<section class="panel" id="materials"><h2>器官与接头</h2><p>下列为最终裁剪素材，缩略用于看轮廓和风格；实际显示尺寸以视口证据为准。</p><div class="cards" id="organ-cards"></div><h3 style="margin-top:24px">GPT 接头原料与最终区域</h3><div class="controls"><label>接头 <select id="junction"></select></label></div><div class="compare"><figure><img id="junction-raw" alt="GPT接头原始输出"><figcaption>GPT 原始输出。背景仅定位参考。</figcaption></figure><figure><svg id="junction-final" role="img" aria-label="冻结坐标下的最终裁剪资源组装" style="width:100%;height:360px;background:#e9dfd4;border-radius:8px"></svg><figcaption id="junction-final-caption"></figcaption></figure></div><p id="junction-note"></p><details><summary>本次 GPT 完整管道材质</summary><div class="cards" id="pipe-material-cards"></div><img id="strip" alt="红色、蓝紫与粉色的平面血管材质" style="width:100%;height:auto"></details></section>
<section class="panel pathref" id="reference"><h2>路线与碰撞参考</h2><div class="controls"><label><input id="ref-routes" type="checkbox" checked>定稿血管</label><label><input id="ref-walls" type="checkbox">真实墙面 / 不可通行区</label><label><input id="ref-gates" type="checkbox" checked>固定组织入口</label></div><svg id="reference-svg" viewBox="0 0 1024 1536" aria-label="全身冻结路线和器官碰撞参考"></svg><p><small>这是独立坐标参考图。红／蓝紫／粉线为供给、回流、局部循环；入口圆点来自明确的组织 gate。投影交叉不创建连接。视觉贴图不决定碰撞；背景和色块也不自动成为可通行区域。</small></p></section>

<section class="panel" id="evidence"><h2>验收证据</h2><div class="scroll"><table><thead><tr><th>项目</th><th>本次真实记录</th><th>版本绑定 / 来源</th></tr></thead><tbody id="checks"></tbody></table></div><h3 style="margin-top:22px">独立视觉复核</h3><p id="review-summary"></p><div class="links" id="report-links"></div><details><summary>素材版本与实际限制</summary><p>当前素材 manifest SHA-256：<code id="manifest-hash"></code></p><p id="resource-limit"></p><ul><li>资源文件已覆盖或正确加载，不能证明原生接缝、单位可见和性能通过。</li><li>单张原生截图不能证明十五秒连续动画、持续移动或所有缩放连续性。</li><li>世界绘制 CPU P95 只反映提交耗时，不能替代整帧与 GPU 表现。</li></ul><p>发布时间：<span id="updated"></span>。原始报告和图片保留完整哈希。</p></details></section><footer>全身交付范围：十二个器官、定稿全身血管和独立可玩地图入口。此页按当前证据如实更新，不将胃部试样或旧版测量冒充全身验收。</footer></div></div></main>
<script>const DATA=__DATA__;const $=id=>document.getElementById(id),url=r=>r?.url+'?v='+r.sha256.slice(0,12);const ns='http://www.w3.org/2000/svg';function svg(tag,attrs){const n=document.createElementNS(ns,tag);for(const[k,v]of Object.entries(attrs))n.setAttribute(k,v);return n;}function lines(target){for(const r of DATA.routes)for(const pts of r.segments){target.append(svg('polyline',{points:pts.map(p=>p.join(',')).join(' '),fill:'none',stroke:r.system==='vein'?'#7776a5':r.system==='capillary'?'#b67b8b':'#b96b70','stroke-width':Math.max(1.8,r.width),'stroke-linecap':'round','stroke-linejoin':'round',opacity:.88}));}}function imageSvg(target){target.append(svg('image',{href:url(DATA.reference),x:0,y:0,width:1024,height:1536}));}
const extra=[['whole','全身定位 / 地图弹窗'],['main','主干与接头'],['head','头部入口'],['neck','颈部'],['arm_r','右臂'],['arm_l','左臂'],['hand_r','右手'],['hand_l','左手'],['leg_r','右腿'],['leg_l','左腿']];for(const[id,name]of [...DATA.organs.map(o=>[o.id,o.name]),...extra]){const n=document.createElement('option');n.value=id;n.textContent=name;$('region').append(n);}imageSvg($('locator'));const miniRoutes=svg('g',{});lines(miniRoutes);miniRoutes.style.display='none';$('locator').append(miniRoutes);for(const o of DATA.organs){const[x0,y0,x1,y1]=o.sourceBox,n=svg('circle',{cx:(x0+x1)/2,cy:(y0+y1)/2,r:13,fill:'#fcf6edd9',stroke:'#966773','stroke-width':3,tabindex:0,role:'button','aria-label':'选择'+o.name});const title=svg('title',{});title.textContent=o.name;n.append(title);const pick=()=>{$('region').value=o.id;selectViews();$('scene').scrollIntoView({block:'start',behavior:'smooth'});};n.onclick=pick;n.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')pick();};$('locator').append(n);}$('locator-routes').onchange=e=>miniRoutes.style.display=e.target.checked?'':'none';
for(const batch of DATA.nativeRecords){const option=document.createElement('option');option.value=batch.directory;option.textContent=batch.directory+' · '+(batch.current?'输入仍匹配':'历史版本')+' · '+(batch.batchState?.verified?'完整':'未完成')+' '+(batch.batchState?.verifiedPngs||0)+'/'+(batch.batchState?.expectedViews||'?')+(batch.captureStatus==='FIRST_COMPOSITION_LOCATE_ISSUES'?' · 首版待修':'');$('capture').append(option);}if(DATA.nativeRecords.length){$('capture').value=(DATA.nativeRecords.filter(r=>r.current).at(-1)||DATA.nativeRecords.at(-1)).directory;}function currentViews(){return DATA.views.filter(r=>r.kind===$('source').value&&r.region===$('region').value&&(r.kind==='native'?r.captureDirectory===$('capture').value:r.current));}function selectViews(){const previous=$('view').value;$('view').replaceChildren();for(const r of currentViews()){const n=document.createElement('option');n.value=r.sha256;n.textContent=(r.displayLabel||r.label)+' · '+(r.zoomLabel||'zoom='+r.zoom);$('view').append(n);}if(currentViews().some(r=>r.sha256===previous))$('view').value=previous;else if(currentViews().some(r=>r.zoom===.15))$('view').value=currentViews().find(r=>r.zoom===.15).sha256;drawView();}function drawView(){const r=currentViews().find(r=>r.sha256===$('view').value);$('locator-selected').textContent='当前：'+$('region').selectedOptions[0].textContent;$('viewer').classList.toggle('fit',$('fit').checked);if(!r){$('scene-image').hidden=true;$('scene-image').removeAttribute('src');$('scene-hash').textContent='缺少本次图片';$('empty').hidden=false;$('empty').textContent='当前区域尚无绑定本次素材版本的'+($('source').value==='native'?'原生窗口':'真实 Lua 离线')+'记录。';$('view-title').textContent=$('region').selectedOptions[0].textContent;$('caption').textContent='缺少证据：未确认。可在下方查看最终裁剪素材和冻结坐标。';return;}$('empty').hidden=true;$('scene-image').hidden=false;$('scene-image').src=url(r);$('scene-hash').textContent=r.sha256;$('viewer').style.setProperty('--logical-width',(r.logicalWidth||r.pixelSize[0])+'px');$('view-title').textContent=(r.displayLabel||r.label)+' · '+(r.zoomLabel||'zoom='+r.zoom);$('caption').textContent=(r.kind==='native'?'原生游戏窗口，含实际 HUD。'+(r.current?' 输入与当前版本匹配。':' 历史版本：输入已变化，仅用于问题对照。')+(r.captureStatus==='FIRST_COMPOSITION_LOCATE_ISSUES'?' 首版整合待修，不能作为视觉通过证据。':''):'真实 Lua 渲染接口的离线输出。')+(r.logicalWidth?' 按记录的逻辑宽度 '+r.logicalWidth+' px 显示，DPR '+(r.dpr||'未记录')+'。':' 报告未记录逻辑宽度／DPR，保留原始物理像素，不能推定逻辑尺寸。')+($('fit').checked?' 当前缩小到页面宽度。':' 当前保留像素大小，可滚动查看。')+(r.visualReviewStatus?' 本视图复核：'+r.visualReviewStatus+'。'+(r.visualReviewNote||''):'')+(r.coverageNote?' '+r.coverageNote:'');}for(const id of ['region','source','capture'])$(id).onchange=selectViews;$('view').onchange=drawView;$('fit').onchange=drawView;if(!DATA.views.some(r=>r.kind==='native'&&r.current)&&DATA.views.some(r=>r.kind==='offline'&&r.current))$('source').value='offline';const initial=new URLSearchParams(location.search).get('region');if([...$('region').options].some(o=>o.value===initial))$('region').value=initial;selectViews();
$('organ-count').textContent=DATA.coverage.validOrgans+' / 12';$('edge-count').textContent=DATA.coverage.coveredEdges+' / 202';$('native-count').textContent=DATA.views.filter(r=>r.kind==='native'&&r.current).length;$('perf-state').textContent=DATA.performance.confirmed?'当前已记录':DATA.performance.recorded?'历史已记录':'未确认';$('native-note').textContent=DATA.views.some(r=>r.kind==='native'&&r.current)?'已记录原生静帧。首版仅用于定位问题，后续批次按各自哈希复核；截图数量本身不代表通过。':'当前版本原生窗口证据仍待采集。历史截图可用于问题对照；当前素材和离线记录只能用于各自范围的检查。';
for(const o of DATA.organs){const f=document.createElement('figure');f.className='card';const h=document.createElement('h3');h.textContent=o.name;f.append(h);if(o.art){const i=document.createElement('img');i.src=url(o.art);i.alt=o.name+'：最终冻结轮廓裁剪素材';i.loading='lazy';f.append(i);}const p=document.createElement('figcaption');p.textContent='固定主图坐标 ['+o.sourceBox.join(', ')+']'+(o.artSource==='external-runtime-override'?' · 当前实际加载外部替换 PNG，SHA-256 '+(o.art?.sha256||'未完整绑定'):'')+(o.artSource==='unverified-runtime-override'?' · 当前独立替换尚未完整绑定':'')+(DATA.visualReview.reviewScope?.excludedRegions?.includes(o.id)?' · 本轮美术由另一对话负责，验收待合并':'');f.append(p);const b=document.createElement('button');b.textContent='查看 0.15 视口';b.onclick=()=>{$('region').value=o.id;selectViews();$('scene').scrollIntoView({block:'start',behavior:'smooth'});};f.append(b);$('organ-cards').append(f);}for(const j of DATA.junctions){const n=document.createElement('option');n.value=j.id;n.textContent=j.name;$('junction').append(n);}function junction(){const j=DATA.junctions.find(r=>r.id===$('junction').value);if(!j)return;if(j.raw)$('junction-raw').src=url(j.raw);else $('junction-raw').removeAttribute('src');const final=$('junction-final');final.replaceChildren();const[x0,y0,x1,y1]=j.sourceBox;final.setAttribute('viewBox',[x0,y0,x1-x0,y1-y0].join(' '));for(const a of DATA.compositionAssets){const[ax0,ay0,ax1,ay1]=a.sourceBox;if(ax1<=x0||ax0>=x1||ay1<=y0||ay0>=y1)continue;const i=svg('image',{href:url(a.art),x:ax0,y:ay0,width:ax1-ax0,height:ay1-ay0});if(a.coreBox){const[cx0,cy0,cx1,cy1]=a.coreBox,clip=svg('clipPath',{id:'junction-clip-'+a.id,clipPathUnits:'userSpaceOnUse'});clip.append(svg('rect',{x:cx0,y:cy0,width:cx1-cx0,height:cy1-cy0}));final.append(clip);i.setAttribute('clip-path','url(#junction-clip-'+a.id+')');}final.append(i);}$('junction-final-caption').textContent='裁剪资源按固定坐标组装的对照；实际效果见原生窗口。'+(DATA.coverage.externalOverrideOrganCount?' 心脏有独立动态形变，以原生窗口为准。':'');$('junction-note').textContent='涉及 '+j.edgeIds.length+' 条既有路线；'+j.status+'。奶油色保护通路不当作血管连接。原料 SHA-256：'+(j.raw?.sha256||'未确认')+(j.final?'；前景补片 SHA-256：'+j.final.sha256:'');}$('junction').onchange=junction;junction();if(DATA.strip)$('strip').src=url(DATA.strip);else $('strip').hidden=true;for(const material of DATA.pipeMaterials||[]){const figure=document.createElement('figure');figure.className='card';const name=document.createElement('h3');name.textContent=material.name;figure.append(name);const image=document.createElement('img');image.src=url(material.art);image.alt=material.name+'完整管壁与管腔原料';figure.append(image);const caption=document.createElement('figcaption');caption.textContent='本次清单原始输出 · SHA-256 '+material.art.sha256;figure.append(caption);$('pipe-material-cards').append(figure);}
imageSvg($('reference-svg'));const routeLayer=svg('g',{});lines(routeLayer);$('reference-svg').append(routeLayer);const wallLayer=svg('g',{});for(const o of DATA.organs)for(const ring of o.walls){let d='M '+ring.outer.map(p=>p.join(' ')).join(' L ')+' Z';for(const h of (Array.isArray(ring.holes)?ring.holes:[]))d+=' M '+h.map(p=>p.join(' ')).join(' L ')+' Z';wallLayer.append(svg('path',{d,fill:'#946e728c','fill-rule':'evenodd',stroke:'#72505b','stroke-width':.6}));}wallLayer.style.display='none';$('reference-svg').append(wallLayer);const gateLayer=svg('g',{});for(const g of DATA.gates){gateLayer.append(svg('line',{x1:g.pipe[0],y1:g.pipe[1],x2:g.tissue[0],y2:g.tissue[1],stroke:'#faf5eb','stroke-width':3}));const n=svg('circle',{cx:g.pipe[0],cy:g.pipe[1],r:2.7,fill:'#f8eccf',stroke:'#8a6170','stroke-width':1});const title=svg('title',{});title.textContent=g.id;n.append(title);gateLayer.append(n);}$('reference-svg').append(gateLayer);$('ref-routes').onchange=e=>routeLayer.style.display=e.target.checked?'':'none';$('ref-walls').onchange=e=>wallLayer.style.display=e.target.checked?'':'none';$('ref-gates').onchange=e=>gateLayer.style.display=e.target.checked?'':'none';
const motion=DATA.checks.find(r=>r.id==='nativeMotion');$('motion-summary').textContent=motion.detail;const moves=DATA.movements.filter(r=>r.kind==='native'?r.recorded:r.current).sort((a,b)=>Number(b.current)-Number(a.current)||Number(b.kind==='native')-Number(a.kind==='native'));for(const m of moves){const n=document.createElement('option');n.value=m.sha256;n.textContent=m.label+(m.seconds?' · '+m.seconds+' 秒记录':'')+(m.kind==='native'?'（原生 1×）':'（离线缩时）')+(m.current?'':' · 历史批次');$('movement-view').append(n);}if(!moves.length){$('movement-empty').textContent='当前版本尚无可播放的连续移动图像记录。命令与通行矩阵结果见下方。';for(const id of ['movement-view','movement-play','movement-stop'])$(id).disabled=true;}function movementMetadata(m){return m.kind==='native'?'原生正常 1× · '+m.seconds+' 秒 · '+m.frames+' 个真实窗口帧。'+(m.current?' 输入仍匹配当前版本。':' 历史批次或终点握手不完整，未证明当前版本视觉。')+' '+m.limits:'生产路径离线缩时记录；时间压缩参数 '+JSON.stringify(m.timeCompression)+'，输出 '+m.fps+' FPS，不能据此推定原生速度。';}function playMovement(){const m=moves.find(r=>r.sha256===$('movement-view').value);if(!m)return;$('movement-empty').hidden=true;$('movement-image').hidden=false;$('movement-image').src=url(m)+'&play='+Date.now();$('movement-hash').textContent=m.sha256;$('movement-wrap').style.setProperty('--logical-width',(m.logicalWidth||(m.pixelSize[0]/(m.dpr||1)))+'px');$('movement-caption').textContent=movementMetadata(m);$('movement-frame').replaceChildren();const animation=document.createElement('option');animation.value='';animation.textContent='连续记录';$('movement-frame').append(animation);for(const [index,frame]of (m.review?.frames||[]).entries()){const option=document.createElement('option');option.value=frame.sha256;option.textContent='帧 '+(index+1)+(frame.phase?.terminal?' · 终点已入镜':'')+' · '+Number(frame.phase?.visualElapsed||0).toFixed(2)+' 秒';$('movement-frame').append(option);}$('movement-frame').disabled=!(m.review?.frames?.length);}function drawMovementFrame(){const m=moves.find(r=>r.sha256===$('movement-view').value),frame=m?.review?.frames?.find(r=>r.sha256===$('movement-frame').value);if(!frame){playMovement();return;}$('movement-empty').hidden=true;$('movement-image').hidden=false;$('movement-image').src=url(frame);$('movement-hash').textContent=frame.sha256;$('movement-caption').textContent=movementMetadata(m)+' 当前显示实际窗口静帧；'+(frame.phase?.terminal?'终点标记 '+(m.review.terminalCapture?.verified?'和驱动 PNG 确认已校验。':'尚未完整确认。'):'轨迹中间帧。');}$('movement-frame').onchange=drawMovementFrame;$('movement-play').onclick=playMovement;$('movement-view').onchange=playMovement;$('movement-stop').onclick=()=>{$('movement-image').hidden=true;$('movement-image').removeAttribute('src');$('movement-empty').hidden=false;$('movement-empty').textContent='记录已停止。';};$('movement-fit').onchange=e=>$('movement-wrap').classList.toggle('fit',e.target.checked);
for(const c of DATA.checks){const tr=document.createElement('tr');for(const t of [c.name,c.detail,c.hashDetail]){const td=document.createElement('td');td.textContent=t;tr.append(td);}$('checks').append(tr);}$('review-summary').textContent=DATA.visualReview.summary;$('top-review').textContent=DATA.visualReview.summary;if(DATA.visualReview.reviewScope?.description){$('scope-note').hidden=false;$('scope-note').textContent=DATA.visualReview.reviewScope.description;}for(const r of DATA.reportLinks){const a=document.createElement('a');a.href=url(r);a.textContent=r.label;a.target='_blank';a.rel='noopener';$('report-links').append(a);}$('manifest-hash').textContent=DATA.manifestSha256;$('updated').textContent=DATA.updated;$('resource-limit').textContent='实际清单 '+DATA.coverage.resourceCount+' 资源／context（含固定 quiet PNG、'+(DATA.coverage.foregroundPatches||0)+' 前景补片）；冻结清单解码尺寸 '+DATA.coverage.manifestBaselineDecodedBytes+' B；实际注册素材尺寸估算 '+(DATA.coverage.actualRegisteredDecodedBytes??'未完整绑定')+' B／context。'+(DATA.coverage.externalOverrideOrganCount?'心脏使用单独绑定的外部纹理，占用同一既有规格。':'')+(DATA.coverage.resourceBudget?.maxResourceSpecsPerContext?'预算 '+DATA.coverage.resourceBudget.maxResourceSpecsPerContext+' 规格 / '+(DATA.coverage.resourceBudget.maxDecodedRGBABytesPerContext/1048576)+' MiB 解码 RGBA／context。':'')+'此为文件尺寸预算，不是实际 GPU 显存测量。'+DATA.coverage.note;
</script></body></html>'''


def build():
    REVIEW.mkdir(parents=True, exist_ok=True)
    publisher = Publisher()
    manifest_path = BASE / "bake/manifest.json"
    manifest = read(manifest_path)
    contract = read(BASE / "contract.json")
    reference = read(STUDY / "final-reference-data.json")
    manifest_sha = sha(manifest_path)
    override_state = runtime_override_status()
    heart_override = (override_state["overrides"][0]["replacement"]
                      if override_state.get("required") and override_state["verified"] else None)
    asset_states = []
    for asset in manifest.get("assets", []):
        path = resolve(asset["path"])
        try:
            valid = path.is_file() and sha(path) == asset["sha256"] and list(Image.open(path).size) == asset["pixelSize"]
        except (OSError, ValueError):
            valid = False
        asset_states.append({"id": asset["id"], "valid": valid, "role": asset.get("role")})
    runtime_organs = {o["id"]: o for o in manifest.get("runtimeSpec", {}).get("organs", [])}
    asset_by_path = {a["path"]: a for a in manifest.get("assets", [])}
    organs = []
    for o in contract["organs"]:
        oid = o["id"]
        spec = runtime_organs.get(oid, {})
        path = ROOT / "assets" / spec.get("resource", "__missing__")
        geometry_path = resolve(o["geometryRef"])
        geometry = read(geometry_path)
        walls = geometry.get("wallRings", [])
        asset = asset_by_path.get(str(path.relative_to(ROOT)), {})
        art_source = "manifest-baseline"
        if oid == "heart" and override_state.get("required"):
            if heart_override:
                spec = {**spec, **heart_override}
                path = resolve(heart_override["path"])
                asset = heart_override
                art_source = "external-runtime-override"
            else:
                path = BASE / "__missing_unverified_heart_override__"
                asset = {}
                art_source = "unverified-runtime-override"
        organs.append({"id": oid, "name": NAMES.get(oid, o.get("name", oid)),
                       "sourceBox": spec.get("sourceBox", o["sourceBox"]),
                       "art": publisher.stage(path, "organs", asset.get("sha256")), "artSource": art_source,
                       "walls": [compact_ring(r) for r in walls]})
    gates = {}
    for o in contract["organs"]:
        for profile in o.get("gates", {}).values():
            for g in profile:
                if g.get("pipeAnchorSource") and g.get("tissueAnchorSource"):
                    gates[g["id"]] = {"id": g["id"], "pipe": g["pipeAnchorSource"], "tissue": g["tissueAnchorSource"]}
    routes = [{"id": e["id"], "system": e["system"], "width": e.get("lumenWidthSource", 2),
               "segments": [segment[::6] + ([segment[-1]] if len(segment) > 1 else []) for segment in e.get("visibleSegments", [])]}
              for e in reference["edges"]]
    junction_rows = []
    names = {"arch": "主动脉弓", "celiac-stomach": "腹腔分支 / 胃壁接入", "portal": "门静脉汇合", "mesenteric": "肠系膜分支",
             "lung-right": "右肺入口", "kidney-right": "右肾回流", "pelvis": "骨盆分叉 / 膀胱侧路",
             "arch-roof-and-junction": "主动脉弓前景与接头", "celiac-stomach-complete-junction": "胃肝入口完整接头",
             "pancreas-duct-and-crossings": "胰腺导管与跨层血管", "heart-venous-junction": "心脏静脉汇合",
             "kidney-right-hilum": "右肾肾门", "kidney-left-hilum": "左肾肾门",
             "large-gut-open-mouths": "大肠入口", "small-gut-open-mouths": "小肠入口",
             "lung-left-airway-mouths": "左肺气道入口"}
    used_path = BASE / "bake/junctions-used.json"
    used = read(used_path).get("junctions", []) if used_path.is_file() else []
    baked = manifest.get("junctions", [])
    for j in baked or used:
        raw = publisher.stage(resolve(j["path"]), "junctions-raw", j.get("sha256"))
        final_asset = next((a for a in manifest.get("assets", []) if a["id"] == j["id"]), {})
        final = publisher.stage(resolve(final_asset["path"]), "junctions-final", final_asset.get("sha256")) if final_asset else None
        junction_rows.append({"id": j["id"], "name": names.get(j["id"], j["id"]), "raw": raw,
                              "final": final, "edgeIds": j["edgeIds"], "sourceBox": j["sourceBox"],
                              "status": "已记录本次前景补片，视觉验收另列" if final else "原料已生成，合成结果见右侧资源坐标组装"})
    native, native_records = publisher.native()
    offline, movements, offline_records = publisher.offline()
    native_moves, native_movement_records = publisher.native_movement()
    movements = native_moves + movements
    reports = {name: publisher.report(BASE / relative) for name, relative in [
        ("motion", "qa/fullbody-motion-report.json"), ("clearance", "qa/clearance-report.json"),
        ("compatibility", "qa/compatibility-report.json"), ("render", "qa/render-report.json"),
        ("resources", "qa/resource-report.json"), ("visibility", "qa/visibility-report.json"),
        ("quietBase", "qa/quiet-base-report.json"),
        ("visual", "review/native-visual-review.json"), ("qaSummary", "qa/summary.json"),
        ("offlineVisual", "qa/independent-visual-review.json")]}
    reports["performance"] = publisher.performance()
    checks = []
    protected_edges = [e["id"] for e in manifest.get("edges", []) if not e.get("covered") and
                       e.get("hiddenByProtectedAreaSource", 0) > 0 and
                       e.get("surfaceAreaSource", 0)+e.get("exteriorAreaSource", 0)+e.get("deepAreaSource", 0) == 0]
    logical_intervals = sum(len(e.get("protectedForegroundIntervals", [])) for e in manifest.get("edges", []))
    visual_edges = sum("visualForegroundIntervals" in e for e in manifest.get("edges", []))
    visual_intervals = sum(len(e.get("visualForegroundIntervals", [])) for e in manifest.get("edges", []))
    coverage_valid = (all(r["valid"] for r in asset_states) and len(runtime_organs) == 12 and
                      len(manifest.get("edges", [])) == 202 and manifest.get("coveredEdgeCount", 0)+len(protected_edges) == 202)
    checks.append({"id": "assets", "name": "全身资源与覆盖", "detail": f'{len(runtime_organs)} 器官 / 202 坐标路线；{manifest.get("coveredEdgeCount", 0)} 可见材质、{len(protected_edges)} 保护通路内全遮挡；文件哈希与尺寸'+("一致" if coverage_valid else "仍有缺失或不一致"), "hashDetail": manifest_sha[:16]+" · 只证明资源清单"})
    if visual_edges:
        checks.append({"id": "actualVisibility", "name": "实际贴图遮挡 / 冻结逻辑遮挡", "detail": f'{visual_edges} / 202 条路线记录实际显示字段、{visual_intervals} 实际显示区间；保留 {logical_intervals} 冻结逻辑区间', "hashDetail": "显示字段用于可见贴图上的单位遮挡；逻辑冻结记录不改变 lane/宽度/导航。实际入口与接缝仍须原生读图。"})
    for key, name in [("motion", "生产命令 / 寻路 / 跨器官移动"), ("clearance", "组织入口净空"), ("compatibility", "旧模式 / 存档兼容"), ("render", "实际 Lua 离线渲染 / 双 context"), ("resources", "资源句柄 / 离线 context 释放"), ("visibility", "显示遮挡 / 冻结曲线"), ("quietBase", "底图注册 / 保护区")]:
        r = reports[key]
        counts = f'；{r.get("passed")} / {r.get("total")}' if r.get("total") is not None else ""
        status = r["status"] if r["hashState"].get("verified") else "未绑定当前输入：" + r["status"]
        checks.append({"id": key, "name": name, "detail": status + counts,
                       "hashDetail": r["hashState"].get("reason", "无输入绑定记录") + "；不证明原生表现"})
    current_native = [r for r in native if r["current"]]
    checks.append({"id": "native", "name": "原生窗口静帧", "detail": f'{len(current_native)} 张绑定当前版本；'+("见独立视觉复核" if current_native else "UNDETERMINED"), "hashDetail": "图片哈希与运行输入分别校验；单帧范围"})
    recorded_cases = sum(c["legacyRecordedCase"] for r in native_movement_records for c in r["cases"])
    current_cases = sum(c["verifiedRecordedCase"] for r in native_movement_records if r["current"] for c in r["cases"])
    checks.append({"id": "nativeMotion", "name": "原生 1× 移动 / 入口 / 会车", "detail": f'{current_cases} 个当前版本终点入镜并获驱动确认案例；{recorded_cases} 个 ≥15 秒正常移动记录（含历史批次）', "hashDetail": "逐 PNG 哈希、同 stateRunId、accepted resolved 终点、实际移动距离、正常主循环、终点标记与 PNG 确认；约 1 FPS 截图序列"})
    visual = reports["visual"]
    visual_summary = "尚未逐张完成本次原生窗口的独立视觉复核；接缝、遮挡、单位辨识度保留未确认。"
    current_visual, accepted, scoped_accepted, viewed = False, False, False, 0
    review_scope, scoped_state = {}, {}
    if visual["present"]:
        raw = visual["raw"]
        rows = raw.get("captures", raw.get("views", []))
        native_sha = {r["sha256"] for r in current_native if r["captureDirectory"] == raw.get("captureDirectory")}
        verified_review_rows = [r for r in rows if r.get("sha256") in native_sha and
                                r.get("path") and resolve(r["path"]).is_file() and sha(resolve(r["path"])) == r["sha256"]]
        viewed = sum(1 for r in verified_review_rows if r.get("independentlyViewed", r.get("viewed", False)))
        current_visual = bool(visual["hashState"]["verified"] and raw.get("manifestSha256") == manifest_sha and
                              rows and len(verified_review_rows) == len(rows))
        batch = next((r.get("batchState", {}) for r in native_records if r["directory"] == raw.get("captureDirectory")), {})
        reviewed_all = (current_visual and batch.get("verified") is True and
                        viewed == len(native_sha) == len(rows) == batch.get("expectedViews"))
        accepted = reviewed_all and raw.get("overallVisualAccepted") is True and raw.get("status") == "PASS"
        review_scope = raw.get("reviewScope", {})
        scoped_state = scoped_visual_status(raw, reviewed_all) if review_scope else {}
        scoped_accepted = scoped_state.get("verified") is True
        if review_scope.get("excludedRegions"):
            accepted = False
        review_status = "PASS" if accepted else raw.get("status", "RECORDED")
        if (review_status == "PASS" and not accepted) or (review_status == "PASS_SCOPED" and not scoped_accepted):
            review_status = "UNDETERMINED_REVIEW_BINDING_OR_COVERAGE"
        visual_summary = ("当前版本：" if current_visual else "历史版本或证据未完整绑定：")+f'{review_status}；已核对原生图片哈希并逐张查看 {viewed} 张。'+raw.get("summary", "")
        if current_visual:
            by_sha = {r["sha256"]: r for r in rows}
            for view in current_native:
                if view["sha256"] in by_sha:
                    item = by_sha[view["sha256"]]
                    view["visualReviewStatus"] = item.get("status")
                    view["visualReviewNote"] = item.get("finding", "")
    perf = reports["performance"]
    perf_raw = perf.get("raw", {})
    confirmed = perf.get("confirmed", False)
    measured = "; ".join(f'{"胃" if i == 0 else "主动脉弓"} off/on {v["offFrameP95Ms"]:.3f}/{v["onFrameP95Ms"]:.3f} ms（增量 {v["frameP95IncrementMs"]:+.3f}）' for i, v in enumerate(perf.get("views", [])))
    checks.append({"id": "performance", "name": "原生完整帧时 / P95", "detail": (("当前版本：" if perf["hashState"].get("verified") else "历史版本：") + perf["status"] if perf["present"] else "UNDETERMINED") + ("；"+measured if measured else ""), "hashDetail": perf["hashState"].get("reason", "")+"；暂停 17 实体 / 60 FPS cap / DPR2；quiet bitmap 一直开启；GPU 未单独测量"})
    menu_reviews = [(p, read(p)) for p in sorted(REVIEW.glob("native-menu-*-review.json"))]
    menu_review_path, menu_review = next(((p, r) for p, r in reversed(menu_reviews) if menu_hash_status(r)["verified"]),
                                       menu_reviews[-1] if menu_reviews else (None, {}))
    menu_binding = menu_hash_status(menu_review)
    menu_record_path = resolve(menu_review.get("recordPath", "__missing__"))
    menu_record_valid = menu_record_path.is_file() and sha(menu_record_path) == menu_review.get("recordSha256")
    menu_image = publisher.stage(resolve(menu_review.get("imagePath", "__missing__")), "native-menu", menu_review.get("sha256"))
    menu_current = bool(menu_binding["verified"] and menu_record_valid and menu_image and menu_review.get("independentlyViewed"))
    checks.append({"id": "normalEntry", "name": "恢复正常主菜单 / 全身地图按钮",
                   "detail": "真实菜单按钮已独立读图、绑定当前版本" if menu_current else "UNDETERMINED",
                   "hashDetail": menu_binding.get("reason", "")+"；只确认入口按钮展示，不以静帧证明点击流程"})
    ledger_path = BASE / "qa/native-evidence-ledger.json"
    ledger = read(ledger_path) if ledger_path.is_file() else {}
    readiness = ledger.get("previewReadiness", {})
    if readiness:
        readiness_current = ledger.get("manifestSha256") == manifest_sha
        checks.append({"id": "previewReadiness", "name": "原生预览 check / 既有资源错误",
                       "detail": ("本次记录：" if readiness_current else "历史记录：") + str(readiness.get("checkResult", "UNDETERMINED")) +
                                 "；" + "；".join(readiness.get("errors", [])),
                       "hashDetail": "来自原生证据 ledger；" + readiness.get("scope", "未记录检查范围")})
    links = [{**publisher.stage(manifest_path, "reports"), "label": "全身素材与坐标清单"},
             {**publisher.stage(BASE / "contract.json", "reports"), "label": "冻结范围合同"}]
    for key, r in reports.items():
        if r["present"]:
            links.append({**r["record"], "label": key+" 原始报告"})
    for r in native_records:
        links.append({**r["record"], "label": r["directory"]+" 截图记录"})
    for r in native_movement_records:
        links.append({**r["record"], "label": r["directory"]+" 原生移动截图记录"})
        if r["driver"]:
            links.append({**r["driver"], "label": r["directory"]+" 正常主循环到达判定"})
    for r in offline_records:
        links.append({**r["record"], "label": "离线绘制记录"})
    for path, label in ((menu_review_path, "正常主菜单独立读图"), (menu_record_path, "正常主菜单截图记录")):
        item = publisher.stage(path, "reports") if path else None
        if item:
            links.append({**item, "label": label})
    if menu_image:
        links.append({**menu_image, "label": "正常主菜单真实窗口 PNG"})
    evidence_paths = {BASE / file for file in (
        "qa/DELIVERY_STATE.md", "MAINTENANCE.md", "qa/independent-visual-review.md",
        "qa/native-evidence-ledger.json", "qa/entry-observation.json")}
    for pattern in ("review/native-*-visual-review.*", "review/native-movement-*-review.*",
                    "review/native-menu-*-review.*", "native-menu-*/record.json",
                    "native-menu-*/normal-entry.png"):
        evidence_paths.update(BASE.glob(pattern))
    for path in sorted(evidence_paths):
        if path in (menu_review_path, menu_record_path):
            continue
        item = publisher.stage(path, "reports")
        if item:
            links.append({**item, "label": str(path.relative_to(BASE))})
    composition_assets = []
    # Quiet is one fixed runtime bitmap in addition to the manifest layer specs.
    data_source = (ROOT / "scripts/war/FullBodyMapArtData.lua").read_text(encoding="utf8")
    runtime_manifest = re.search(r'\["manifestSha256"\]="([0-9a-f]{64})"', data_source)
    runtime_matches = bool(runtime_manifest and runtime_manifest[1] == manifest_sha)
    quiet = re.search(r'\["quietBase"\]=\{\["id"\]="([^"]+)",\["resource"\]="([^"]+)".*?\["sha256"\]="([0-9a-f]{64})"\}', data_source)
    quiet_valid, quiet_bytes = False, 0
    if quiet:
        quiet_path = ROOT / "assets" / quiet[2]
        quiet_art = publisher.stage(quiet_path, "composition", quiet[3])
        quiet_valid = bool(quiet_art and quiet_art.get("pixelSize") == [1024, 1536])
        if quiet_valid:
            quiet_bytes = 1024*1536*4
            composition_assets.append({"id": quiet[1], "role": "quiet-base", "sourceBox": [0, 0, 1024, 1536], "art": quiet_art})
    specs = [(layer, spec) for layer in RUNTIME_LAYERS for spec in manifest.get("runtimeSpec", {}).get(layer, [])]
    runtime_count = len(specs) + int(quiet_valid)
    assets_by_resource = {a["resource"]: a for a in manifest.get("assets", [])}
    specs_bound = all(s.get("resource") in assets_by_resource and
                      all(s.get(k) == assets_by_resource[s["resource"]].get(k) for k in ("id", "sourceBox", "pixelSize", "coreBox"))
                      for _, s in specs)
    baseline_decoded_bytes = sum(a["pixelSize"][0] * a["pixelSize"][1] * 4 for a in manifest.get("assets", [])) + quiet_bytes
    decoded_bytes = (override_state.get("effectiveDecodedRGBABytesPerContext") if override_state.get("required")
                     else baseline_decoded_bytes) if override_state["verified"] else None
    budget = manifest.get("resourceBudget", {})
    max_specs = budget.get("maxResourceSpecsPerContext")
    max_bytes = budget.get("maxDecodedRGBABytesPerContext")
    budget_valid = (decoded_bytes is not None and (max_specs is None or runtime_count <= max_specs) and
                    (max_bytes is None or decoded_bytes <= max_bytes))
    foreground_count = len(manifest.get("runtimeSpec", {}).get("foregroundPatches", []))
    coverage_valid = coverage_valid and quiet_valid and runtime_matches and specs_bound and budget_valid and override_state["verified"]
    checks.append({"id": "runtimeResources", "name": "运行资源清单 / quiet 底图 / 前景补片", "detail": f'{runtime_count} 资源／context，含 {foreground_count} 前景补片；quiet PNG 哈希'+("一致" if quiet_valid else "缺失或不一致")+"；运行 Data "+("绑定当前 manifest" if runtime_matches and specs_bound else "尚未完整绑定当前 manifest"), "hashDetail": "固定 quiet PNG 与全部运行层逐项验证；资源齐全不代表视觉通过"})
    if max_specs is not None or max_bytes is not None:
        checks.append({"id": "resourceBudget", "name": "资源规格 / 解码预算", "detail": f'{runtime_count} / {max_specs} 规格；冻结清单 {baseline_decoded_bytes}，实际注册尺寸估算 {decoded_bytes if decoded_bytes is not None else "未完整绑定"} / {max_bytes} RGBA 字节／context；'+("预算内" if budget_valid else "尚未确认"), "hashDetail": "从基线与独立替换 PNG 尺寸计算；mipmap、实际 GPU 占用与性能另行记录"})
    if override_state.get("required"):
        checks.append({"id": "runtimeOverride", "name": "外部心脏运行素材替换", "detail": override_state["reason"],
                       "hashDetail": override_state.get("recordSha256", "缺少记录")+"；替换同一既有规格，资源个数不增加；心肺美术待外部合并"})
        override_report = publisher.stage(resolve(override_state["recordPath"]), "reports", override_state["recordSha256"]) if override_state.get("recordPath") else None
        if override_report:
            links.append({**override_report, "label": "实际运行心脏替换与解码尺寸记录"})
    for layer, spec in specs:
        a = assets_by_resource.get(spec.get("resource"))
        if not a:
            continue
        if spec.get("id") == "heart" and override_state.get("required"):
            if not heart_override:
                continue
            a = {**a, **heart_override}
        pic = publisher.stage(resolve(a["path"]), "composition", a["sha256"])
        if pic:
            composition_assets.append({"id": a["id"], "role": a["role"], "runtimeLayer": layer, "sourceBox": a["sourceBox"],
                                       "coreBox": a.get("coreBox"), "art": pic})
    pipe_materials = []
    for system, material in manifest.get("pipeMaterials", {}).get("materials", {}).items():
        art = publisher.stage(resolve(material["path"]), "materials", material.get("sha256"))
        if art:
            pipe_materials.append({"system": system, "name": {"artery": "动脉", "vein": "静脉", "capillary": "毛细血管"}.get(system, system),
                                   "art": art, "crop": material.get("crop"), "repeatSourceLength": material.get("repeatSourceLength")})
    data = {"schema": "fullbody-015-review-page/v1", "updated": datetime.now(timezone.utc).isoformat(),
            "manifestSha256": manifest_sha, "reference": publisher.stage(ROOT / "assets/image/anatomy-reference/reference.png", "materials"),
            "strip": None if pipe_materials else publisher.stage(ROOT / "assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/gpt-material-flat-v2.png", "materials"),
            "pipeMaterials": pipe_materials,
            "organs": organs, "routes": routes, "gates": list(gates.values()), "junctions": junction_rows,
            "compositionAssets": composition_assets,
            "views": native+offline, "movements": movements, "checks": checks, "reportLinks": links,
            "visualReview": {"summary": visual_summary, "current": current_visual,
                             "overallVisualAccepted": accepted, "scopedVisualAccepted": scoped_accepted,
                             "reviewScope": review_scope, "scopedEvidenceState": scoped_state,
                             "verifiedViewedCaptures": viewed},
            "performance": {"confirmed": confirmed, "recorded": perf.get("recorded"), "views": perf.get("views", []), "remainingNativeCoverage": perf_raw.get("remainingNativeCoverage", [])},
            "coverage": {"validOrgans": sum(1 for r in asset_states if r["valid"] and r["role"] == "organ"),
                         "coveredEdges": manifest.get("coveredEdgeCount", 0), "expectedDecodedBytes": decoded_bytes,
                         "manifestBaselineDecodedBytes": baseline_decoded_bytes,
                         "actualRegisteredDecodedBytes": decoded_bytes,
                         "manifestBaselineOrganSpecs": len(runtime_organs),
                         "externalOverrideOrganCount": int(bool(heart_override)),
                         "resourceOverride": override_state,
                         "resourceCount": runtime_count, "quietBaseVerified": quiet_valid,
                         "runtimeLayers": {layer: len(manifest.get("runtimeSpec", {}).get(layer, [])) for layer in RUNTIME_LAYERS},
                         "runtimeSpecAssetsBound": specs_bound, "foregroundPatches": foreground_count,
                         "resourceBudget": {"maxResourceSpecsPerContext": max_specs, "maxDecodedRGBABytesPerContext": max_bytes, "withinBudget": budget_valid},
                         "runtimeDataBound": runtime_matches,
                         "visualVisibilityEdges": visual_edges, "visualVisibilityIntervals": visual_intervals,
                         "logicalVisibilityIntervals": logical_intervals,
                         "valid": coverage_valid, "protectedEdges": protected_edges,
                         "note": ("全遮挡路线："+", ".join(protected_edges)+"。" if protected_edges else "")+"资源预算与正式运行加载状态分开记录。"},
            "evidence": publisher.evidence, "nativeRecords": native_records, "offlineRecords": offline_records,
            "nativeMovementRecords": native_movement_records}
    # Asset role may be named 'organ-floor' by a future deterministic compiler.
    data["coverage"]["validOrgans"] = sum(1 for o in organs if o["art"] is not None and
                                             any(a["valid"] and a["id"] in (o["id"], "organ-"+o["id"]) for a in asset_states))
    page = HTML.replace("__DATA__", json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c"))
    (STUDY / "fullbody-015.html").write_text(page, encoding="utf8")
    (REVIEW / "page-data.json").write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n", encoding="utf8")
    PUBLIC.mkdir(parents=True, exist_ok=True)
    (PUBLIC / "fullbody-015.html").write_text(page, encoding="utf8")
    target_review = PUBLIC / "fullbody-015/review"
    for path in REVIEW.rglob("*"):
        if path.is_file():
            target = target_review / path.relative_to(REVIEW)
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.is_file() or sha(path) != sha(target):
                shutil.copy2(path, target)
    print(json.dumps({"page": str(STUDY / "fullbody-015.html"), "mirror": str(PUBLIC / "fullbody-015.html"),
                      "organs": len(organs), "edges": len(routes), "junctionMaterials": len(junction_rows),
                      "currentNativeStills": len(current_native), "currentOfflineViews": sum(r["current"] for r in offline),
                      "coverageValid": coverage_valid, "completeFrameTimeAccepted": confirmed,
                      "manifestSha256": manifest_sha}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    build()
