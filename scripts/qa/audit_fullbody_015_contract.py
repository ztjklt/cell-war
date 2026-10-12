"""Freeze and audit the complete source-coordinate 0.15 battlefield scope.

This is an inventory/contract checker, not a renderer or runtime certification.
The default command is read-only. --write-contract creates the initial contract
once; it refuses to replace an existing baseline. No image pixels define paths.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs/body-life/vascular-art-study"
CONTRACT = DOC / "fullbody-015/contract.json"
FINAL = DOC / "final-reference-data.json"
EXPECTED_FINAL_SHA = "3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c"
ORGAN_IDS = ["brain", "lung_r", "lung_l", "heart", "liver", "stomach",
             "pancreas", "kidney_r", "kidney_l", "small_intestine",
             "large_intestine", "bladder"]
STAGES = ["frozenReference", "gptMappedSurface", "junctionArtwork",
          "fullbodyComposition", "productionRuntime", "crossRegionMovement",
          "nativeAcceptance", "formalMap"]
REGION_TO_ORGAN = {"brain_r": "brain", "brain_l": "brain",
                   "coronary": "heart", "colon_proximal": "large_intestine",
                   "colon_distal": "large_intestine"}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def value_sha(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False).encode()).hexdigest()


def read(path: Path):
    return json.loads(path.read_text())


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def gate_summary(gate: dict, profile: str, data_path: Path) -> dict:
    keys = ["id", "edgeId", "laneIndex", "fromLane", "toLane", "pipeAnchorSource",
            "tissueAnchorSource", "wallSource", "radiusSource", "openingWidthSource",
            "requiresSingleFileInBlood"]
    result = {k: gate[k] for k in keys if k in gate}
    result.update(profile=profile, dataRef=rel(data_path),
                  geometrySha256=value_sha(gate), collisionAuthority="authored_gate_contract")
    return result


def initial_contract() -> dict:
    final = read(FINAL)
    assert sha(FINAL) == EXPECTED_FINAL_SHA, "The approved final reference changed"
    interfaces_path = DOC / "interface-contract.json"
    interfaces = read(interfaces_path)
    atlas_path = DOC / "organ-atlas/contract.json"
    atlas = read(atlas_path)
    runtime_path = DOC / "organ-atlas/runtime-data.json"
    runtime = read(runtime_path)
    gastric_path = DOC / "stomach-playable/layout.json"
    gastric = read(gastric_path)
    art = read(DOC / "organ-atlas/art.json")
    material_pilot = read(DOC / "vessel-material-pilot/geometry.json")
    pilot_ids = set(material_pilot["selectedEdgeIds"])
    frozen_paths = {FINAL, interfaces_path, atlas_path, runtime_path, gastric_path,
                    DOC / "organ-layers.json", DOC / "passages-data.json",
                    ROOT / "assets/image/anatomy-reference/reference.png",
                    ROOT / "scripts/war/OrganBoundariesData.lua",
                    ROOT / "scripts/war/OrganBattlefieldData.lua",
                    ROOT / "scripts/war/GastricBattlefieldData.lua",
                    ROOT / "scripts/war/FinalVascularStudyData.lua"}
    for spec in atlas["organs"]:
        frozen_paths.add(ROOT / spec["geometryPath"])
    # Preserve approved artwork sources. The new atlas is a sibling resource;
    # its existence must never silently replace these accepted baselines.
    for oid in ORGAN_IDS:
        if oid == "stomach":
            frozen_paths.add(ROOT / "assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png")
        else:
            frozen_paths.add(ROOT / f"assets/image/anatomy-reference/vascular-study/organ-atlas/{oid}/gpt-terrain-v2.png")
    input_hashes = {rel(p): sha(p) for p in sorted(frozen_paths)}
    organ_specs = []
    all_gates = []
    for oid in ORGAN_IDS:
        spec = next(s for s in atlas["organs"] if s["organId"] == oid)
        data = gastric if oid == "stomach" else runtime["organs"][oid]
        data_path = gastric_path if oid == "stomach" else runtime_path
        gates = {profile: [gate_summary(g, profile, data_path)
                           for g in data["gateContracts"][profile]]
                 for profile in ("scout", "siege")}
        all_gates.extend(dict(g, organId=oid) for g in gates["siege"])
        art_spec = next(a for a in art["organs"] if a["organId"] == oid)
        organ_specs.append({"id": oid, "name": spec["name"],
                            "sourceBox": art_spec["sourceBox"],
                            "geometryRef": spec["geometryPath"], "runtimeDataRef": rel(data_path),
                            "bloodLaneIds": {p: sorted(int(lane) for lane in data["bloodLanes"][p])
                                             for p in ("scout", "siege")},
                            "gates": gates,
                            "namedPorts": [p for p in final["ports"]
                                           if REGION_TO_ORGAN.get(p["region"], p["region"]) == oid],
                            "baselineCoverage": {"floor": "EXISTING_LOCAL_GPT_MATERIAL",
                                                 "runtime": "OPT_IN_TRIAL_ONLY",
                                                 "formalMap": "NOT_INSTALLED"}})
    edges = []
    for index, edge in enumerate(final["edges"]):
        geometry = {k: edge[k] for k in ("id", "a", "b", "points", "d", "samples",
                                         "system", "layer", "lumenWidthSource")}
        coverage = {stage: {"status": "NOT_ACCEPTED", "evidence": []} for stage in STAGES}
        coverage["frozenReference"] = {"status": "VERIFIED", "evidence": [rel(FINAL)]}
        baseline = "PILOT_PARTIAL_ONLY" if edge["id"] in pilot_ids else "NOT_DEDICATED_GPT_MAPPED"
        edges.append({"id": edge["id"], "a": edge["a"], "b": edge["b"],
                      "system": edge["system"], "layer": edge["layer"],
                      "lumenWidthSource": edge["lumenWidthSource"],
                      "logicalLumenWidthAt015": edge["lumenWidthSource"] * 9.6,
                      "points": edge["points"], "d": edge["d"],
                      "geometryRef": {"path": rel(FINAL), "edgeId": edge["id"],
                                      "arrayIndex0": index, "geometrySha256": value_sha(geometry),
                                      "samplesSha256": value_sha(edge["samples"])},
                      "protectedPosition": edge["id"] in final["protectedEdges"],
                      "overviewHiddenIntervals": edge["hiddenIntervals"],
                      "occlusionIds": [q["id"] for q in final["occlusions"] if q["edgeId"] == edge["id"]],
                      "baselineSurfaceCoverage": baseline, "coverage": coverage})
    regions = []
    for region in interfaces["regions"]:
        oid = REGION_TO_ORGAN.get(region["id"], region["id"])
        regions.append(dict(region, organId=oid if oid in ORGAN_IDS else None,
                            organizationDomain=("EXISTING_OPT_IN_ORGAN_DOMAIN" if oid in ORGAN_IDS
                                                else "NO_ORGAN_TRIAL_TISSUE_DOMAIN"),
                            fullbodyAccepted=False))
    return {"schema": "fullbody-015-contract/v1", "status": "IN_PROGRESS_NOT_FULLBODY_ACCEPTED",
            "objective": "Complete the full-body 0.15 RTS battlefield, not another stomach-only pilot",
            "coordinateSystem": {"sourceSize": [1024, 1536], "worldScale": 2,
                                 "worldOffset": [0, 512], "logicalPixelsPerWorld": "32*zoom",
                                 "logicalPixelsPerSourceAt015": 9.6,
                                 "DPRPolicy": "mode_B_logical_pixels", "overviewBlend": [0.085, 0.15]},
            "authority": {"path": rel(FINAL), "sha256": sha(FINAL),
                          "compilerRule": "Use all 202 final-reference edges and full samples. Registered 80-edge ROI is not full-body authority."},
            "frozenInputs": input_hashes,
            "counts": {"organs": len(organ_specs), "edges": len(edges),
                       "nodes": len({n for e in edges for n in (e["a"], e["b"])}),
                       "namedAndTissuePorts": len(final["ports"]),
                       "namedPorts": sum(p["kind"] == "named_port" for p in final["ports"]),
                       "tissuePorts": sum(p["kind"] == "tissue_exit" for p in final["ports"]),
                       "regionInterfaces": len(regions), "explicitOrganGates": len(all_gates),
                       "protectedPositionEdges": len(final["protectedEdges"]),
                       "protectedPassages": len(final["protectedPassages"])},
            "organs": organ_specs, "edges": edges, "ports": final["ports"],
            "regionInterfaces": regions, "explicitOrganGates": all_gates,
            "protectedPassages": final["protectedPassages"], "crossings": final["crossings"],
            "rules": {"brainAndLimbRoutePositionsUnchanged": True,
                      "allAuthoredBloodTopologyUnchanged": True,
                      "greenAllowedOrgans": ["stomach", "liver"],
                      "greenAllowedInBlood": False, "foodAirUrineAreBlood": False,
                      "foodInletCellEntry": False, "pixelColorsDefineCollision": False,
                      "oldSavesMigrated": False, "oldVersionRoutingRetained": True,
                      "materialExistsMeansInstalled": False,
                      "invisibleCrossingCreatesJunction": False,
                      "headAndLimbPosturesStable": True},
            "deliveryMapMode": {"kind": "NEW_INDEPENDENT_FULLBODY_PLAYABLE_MAP",
                                "stateMarker": "fullbodyBattlefieldVersion=1",
                                "explicitOptIn": True, "menuEntryRequired": True,
                                "step": "reuse OrganTrial production Commands/Path/Workers/Collision",
                                "campaignExpansionIncluded": False,
                                "peripheralRegionPolicy": "blood-lane travel only; no new peripheral tissue domains",
                                "oldModesAndSavesRetained": True,
                                "saveVersionIncreaseRequired": False},
            "acceptanceStages": [{"id": stage, "status": "PENDING", "evidence": []}
                                 for stage in STAGES if stage != "frozenReference"],
            "completionRequirements": ["All 202 edges accounted for, including intentional depth occlusion",
                                       "All 12 organ terrains assembled in the actual 0.15 renderer",
                                       "Every named supply/return interface and explicit tissue gate reviewed",
                                       "Body region tissue policy explicit; no unmarked walkable-looking closed floor",
                                       "Continuous arterial/venous/junction artwork coherent across regional seams",
                                       "Cross-region production movement, exit clearance and traffic accepted",
                                       "Native movement/zoom/DPR/resource/P95 evidence bound to current inputs",
                                       "New formal map installed; existing saves and old anatomy retain their prior map"],
            "runtimeBaselineConstraints": {"trialRejectsCampaign": True,
                                           "organTrialDomains": 12,
                                           "peripheralTissueDomainsAbsent": [r["id"] for r in regions if r["organId"] is None],
                                           "formalIntegrationStatus": "NOT_INSTALLED_AT_BASELINE",
                                           "saveRule": "Do not enable a new geometry flag on old saves; optional opt-in for new formal maps must be validated through generation, restoration, campaign-event routing and collision."}}


def audit(contract: dict) -> dict:
    errors = []
    final = read(FINAL)
    def check(ok: bool, message: str):
        if not ok:
            errors.append(message)
    check(contract.get("schema") == "fullbody-015-contract/v1", "Unsupported contract schema")
    check(contract["authority"]["sha256"] == sha(FINAL) == EXPECTED_FINAL_SHA,
          "Approved final reference hash changed")
    for path, expected in contract["frozenInputs"].items():
        p = ROOT / path
        check(p.is_file() and sha(p) == expected, "Frozen input changed/missing: " + path)
    edges = contract["edges"]
    check(len(edges) == 202 and len({e["id"] for e in edges}) == 202, "Expected 202 unique edges")
    check({e["id"] for e in edges} == {e["id"] for e in final["edges"]}, "Incomplete/full-body edge IDs differ")
    nodes = {}
    by_id = {e["id"]: e for e in final["edges"]}
    for e in edges:
        original = by_id.get(e["id"])
        if not original:
            continue
        source_index = e["geometryRef"]["arrayIndex0"]
        check(e["geometryRef"]["path"] == rel(FINAL) and
              isinstance(source_index, int) and 0 <= source_index < len(final["edges"]) and
              final["edges"][source_index]["id"] == e["id"],
              "Geometry source/index differs: " + e["id"])
        for key in ("a", "b", "points", "d", "system", "layer", "lumenWidthSource"):
            check(e[key] == original[key], "Authored geometry differs: " + e["id"] + "/" + key)
        geometry = {k: original[k] for k in ("id", "a", "b", "points", "d", "samples", "system", "layer", "lumenWidthSource")}
        check(e["geometryRef"]["geometrySha256"] == value_sha(geometry), "Geometry fingerprint differs: " + e["id"])
        check(e["geometryRef"]["samplesSha256"] == value_sha(original["samples"]), "Samples fingerprint differs: " + e["id"])
        check(set(e["coverage"]) == set(STAGES), "Missing edge acceptance stages: " + e["id"])
        for node, point in ((e["a"], e["points"][0]), (e["b"], e["points"][-1])):
            check(node not in nodes or math.dist(nodes[node], point) < 1e-6,
                  "Named junction has mismatched endpoint: " + node)
            nodes[node] = point
    check(set(o["id"] for o in contract["organs"]) == set(ORGAN_IDS), "Expected all 12 organ IDs")
    check(contract["ports"] == final["ports"], "Named/tissue ports changed")
    check(contract["protectedPassages"] == final["protectedPassages"], "Food/air/urine routes changed")
    check(contract["crossings"] == final["crossings"], "Depth-crossing contract changed")
    expected_regions = read(DOC / "interface-contract.json")["regions"]
    actual_regions = contract["regionInterfaces"]
    check(len(actual_regions) == 19 and {r["id"] for r in actual_regions} == {r["id"] for r in expected_regions},
          "Full-body region interfaces incomplete")
    expected_by_region = {r["id"]: r for r in expected_regions}
    for region in actual_regions:
        expected = expected_by_region.get(region["id"])
        if expected:
            check(all(region.get(k) == value for k, value in expected.items()),
                  "Region interface coordinates/role changed: " + region["id"])
    check(contract["rules"]["greenAllowedOrgans"] == ["stomach", "liver"], "Green exception scope changed")
    check(contract["deliveryMapMode"]["stateMarker"] == "fullbodyBattlefieldVersion=1" and
          contract["deliveryMapMode"]["campaignExpansionIncluded"] is False and
          contract["deliveryMapMode"]["oldModesAndSavesRetained"] is True,
          "New-map/old-mode compatibility scope changed")
    gate_ids = [g["id"] for g in contract["explicitOrganGates"]]
    check(len(gate_ids) == 18 and len(set(gate_ids)) == 18, "Expected 18 unique explicit organ gates")
    for o in contract["organs"]:
        data = read(ROOT / o["runtimeDataRef"])
        if o["id"] != "stomach":
            data = data["organs"][o["id"]]
        for profile, gates in o["gates"].items():
            actual = {g["id"]: g for g in data["gateContracts"][profile]}
            check({g["id"] for g in gates} == set(actual), "Missing organ gates: " + o["id"] + "/" + profile)
            for g in gates:
                check(g["id"] in actual and g["geometrySha256"] == value_sha(actual[g["id"]]),
                      "Gate contract differs: " + o["id"] + "/" + profile + "/" + g["id"])
    flattened = [dict(g, organId=o["id"]) for o in contract["organs"] for g in o["gates"]["siege"]]
    check(flattened == contract["explicitOrganGates"], "Flat gate inventory differs from per-organ authority")
    # A PASS declaration is not evidence. Require existing, hash-bound artifacts
    # before this inventory checker can consider a completion ledger fulfilled.
    evidence_hashes = {}
    def evidence_bound(record: dict) -> bool:
        refs = record.get("evidence", [])
        if not refs:
            return False
        for ref in refs:
            if not isinstance(ref, dict) or not ref.get("path") or not ref.get("sha256"):
                return False
            p = ROOT / ref["path"]
            if p not in evidence_hashes:
                evidence_hashes[p] = sha(p) if p.is_file() else None
            if evidence_hashes[p] != ref["sha256"]:
                return False
        return True
    for e in edges:
        for stage in STAGES:
            if stage == "frozenReference":
                continue
            record = e["coverage"][stage]
            if record["status"] in ("PASS", "INTENTIONALLY_OCCLUDED_VERIFIED"):
                check(evidence_bound(record), "Accepted edge stage lacks hash-bound evidence: " + e["id"] + "/" + stage)
    for record in contract["acceptanceStages"]:
        if record["status"] == "PASS":
            check(evidence_bound(record), "Accepted global stage lacks hash-bound evidence: " + record["id"])
    stage_counts = {stage: dict(collections.Counter(e["coverage"][stage]["status"] for e in edges))
                    for stage in STAGES}
    unfinished = [s["id"] for s in contract["acceptanceStages"] if s["status"] != "PASS"]
    return {"schema": "fullbody-015-contract-audit/v1", "status": "FAIL" if errors else "PASS_FROZEN_INVENTORY_ONLY",
            "contractSha256": sha(CONTRACT), "errors": errors, "counts": contract["counts"],
            "edgeStageCounts": stage_counts, "unacceptedStages": unfinished,
            "fullbodyAccepted": not errors and not unfinished and all(
                all(e["coverage"][s]["status"] in ("PASS", "INTENTIONALLY_OCCLUDED_VERIFIED")
                    and evidence_bound(e["coverage"][s]) for s in STAGES if s != "frozenReference")
                for e in edges),
            "evidenceScope": "Frozen coordinates, inventory and declared acceptance ledger only; no native pixels or gameplay are tested here."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-contract", action="store_true", help="Create the initial immutable baseline once")
    parser.add_argument("--require-complete", action="store_true", help="Fail while any full-body stage is unaccepted")
    args = parser.parse_args()
    if args.write_contract:
        if CONTRACT.exists():
            parser.error("Contract already exists; refusing to overwrite the frozen baseline")
        CONTRACT.parent.mkdir(parents=True, exist_ok=True)
        CONTRACT.write_text(json.dumps(initial_contract(), ensure_ascii=False, indent=2) + "\n")
    if not CONTRACT.exists():
        parser.error("Contract missing; use --write-contract for the first baseline")
    report = audit(read(CONTRACT))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return int(bool(report["errors"]) or (args.require_complete and not report["fullbodyAccepted"]))


if __name__ == "__main__":
    raise SystemExit(main())
