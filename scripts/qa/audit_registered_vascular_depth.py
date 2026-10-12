"""Independent display-depth audit; never edits reference art or runtime geometry.

Run with Shapely 2 installed, for example the existing QA environment:
  PYTHONPATH=/tmp/passage-tools314 python3 scripts/qa/audit_registered_vascular_depth.py
Only registered-vessels-depth-audit.json is written. Coarse locators and passage
corridors are deliberately not promoted to pixel-accurate foreground masks.
"""
from pathlib import Path
import collections
import hashlib
import json
import math
import re
import sys
from io import BytesIO

from PIL import Image
from lupa import LuaRuntime
from shapely.geometry import GeometryCollection, LineString, Point, Polygon, box
from shapely.ops import unary_union, substring

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "docs/body-life/vascular-art-study"
REPORT = BASE / "registered-vessels-depth-audit.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((BASE / name).read_text())


def polygon_set(rings):
    positive = [Polygon(r["points"]).buffer(0) for r in rings if not r.get("hole")]
    negative = [Polygon(r["points"]).buffer(0) for r in rings if r.get("hole")]
    return unary_union(positive).difference(unary_union(negative))


def stroke(parts, radius):
    # Flat hidden ends prevent visible cap extensions; source named joints can
    # receive explicit shared-node discs, never arbitrary new intersections.
    return unary_union([LineString(p).buffer(radius, cap_style="flat", join_style="round",
                                             quad_segs=16) for p in parts if len(p) >= 2])


def pieces(geometry):
    if geometry.is_empty:
        return []
    if geometry.geom_type == "LineString":
        return [geometry] if geometry.length > 1e-7 else []
    return [p for child in getattr(geometry, "geoms", []) for p in pieces(child)]


def rounded(value):
    return round(float(value), 6)


def merge_intervals(intervals):
    result = []
    for a, b in sorted(intervals):
        if result and a <= result[-1][1] + 1e-6:
            result[-1][1] = max(result[-1][1], b)
        else:
            result.append([a, b])
    return result


def complement_intervals(intervals, length):
    out, start = [], 0.0
    for a, b in merge_intervals(intervals):
        if a > start + 1e-6:
            out.append([start, a])
        start = max(start, b)
    if start < length - 1e-6:
        out.append([start, length])
    return out


def main():
    data = read("final-reference-data.json")
    policy = read("remaining-vessels-inputs/bladder-wall-visibility.json")
    layers = read("organ-layers.json")
    edges = {e["id"]: e for e in data["edges"]}
    lines = {eid: LineString(e["samples"]) for eid, e in edges.items()}
    organs = {o["id"]: o for o in data["organs"]}
    organ_geo = {oid: polygon_set(o["outlines"]) for oid, o in organs.items()}
    passages = {p["id"]: p for p in data["protectedPassages"]}
    food = unary_union([Polygon(p).buffer(0) for p in data["stomachFoodUnion"]])
    passage_geo = {pid: food if pid == "food.stomach" else
                   LineString(p["points"]).buffer(p["width"] / 2, quad_segs=16)
                   for pid, p in passages.items()}
    ports = {p["id"]: p for p in data["ports"]}
    boundary_path = ROOT / "scripts/war/OrganBoundariesData.lua"
    visual_boundaries = LuaRuntime().execute(boundary_path.read_text())
    assert visual_boundaries["sourceSha256"] == sha(ROOT / "assets/image/anatomy-reference/reference.png")

    def lua_paths(paths):
        return [{"hole": bool(p["hole"]), "points": [[q[1], q[2]] for _, q in p["points"].items()]}
                for _, p in paths.items()]

    fine_bladder_outline = polygon_set(lua_paths(visual_boundaries["organs"]["bladder"]["outlinePaths"]))
    fine_bladder_core = polygon_set(lua_paths(visual_boundaries["organs"]["bladder"]["interiorPaths"]))
    assert policy["keepNamedWallPorts"]["supply"] == ports["bladder.entry"]["source"]
    assert policy["keepNamedWallPorts"]["return"] == ports["bladder.exit"]["source"]
    assert not policy["topologyEdited"] and not policy["productionInstalled"]

    def obstacle(occlusion):
        if occlusion["kind"] == "organ":
            return organ_geo[occlusion["owner"]]
        if occlusion["kind"] == "passage":
            return passage_geo[occlusion["owner"]]
        top = edges[occlusion["owner"].split(":", 1)[1]]
        return lines[top["id"]].buffer(top["lumenWidthSource"] / 2, quad_segs=16)

    # Existing interval expansion is lumen radius + .65 source px. An art
    # stroke with a broader wall/glow is not automatically safe under it.
    audit_occ = []
    for o in data["occlusions"]:
        edge = edges[o["edgeId"]]
        radius = edge["lumenWidthSource"] / 2
        geo = obstacle(o)
        visible = stroke(edge["visibleSegments"], radius)
        expanded = stroke(edge["visibleSegments"], radius + .65)
        loose_shadow = stroke(edge["visibleSegments"], radius + 1.0)
        record = {"id": o["id"], "edgeId": edge["id"], "kind": o["kind"],
                  "owner": o["owner"], "lumenRadiusSource": radius,
                  "visibleLumenOverlapAreaSource2": rounded(visible.intersection(geo).area),
                  "visibleEffectAtExistingMarginOverlapAreaSource2": rounded(expanded.intersection(geo).area),
                  "unclippedOnePixelHaloOverlapAreaSource2": rounded(loose_shadow.intersection(geo).area)}
        if o["kind"] == "organ":
            record["foregroundBoundaryKind"] = organs[o["owner"]]["boundaryKind"]
            record["preciseForegroundMaskCertified"] = False
        elif o["kind"] == "passage":
            record["foregroundBasis"] = passages[o["owner"]]["basis"]
            record["preciseForegroundMaskCertified"] = False
        audit_occ.append(record)

    # Conservative source-pigment evidence, not a mask. Counting actual orange
    # source pixel centers shows wrong paint even without trusting a polygon.
    original = Image.open(ROOT / "assets/image/anatomy-reference/reference.png").convert("RGB")
    orange_centers = []
    for y in range(737, 817):
        for x in range(474, 544):
            r, g, b = original.getpixel((x, y))
            if r > 220 and g > 120 and r - g > 40 and g - b > 50:
                orange_centers.append(Point(x + .5, y + .5))
    bladder = []
    for eid in ["e142", "e143", "e144", "e197", "e198"]:
        edge = edges[eid]
        footprint = stroke(edge["visibleSegments"], edge["lumenWidthSource"] / 2)
        line = lines[eid]
        vislines = unary_union([LineString(p) for p in edge["visibleSegments"]])
        bladder.append({"edgeId": eid, "visibleLengthSource": rounded(vislines.length),
                        "frozenHiddenLengthSource": rounded(max(0, line.length - vislines.length)),
                        "visibleStrokeAreaInCoarseBladderLocatorSource2": rounded(footprint.intersection(organ_geo["bladder"]).area),
                        "visibleStrokeAreaInSourceTracedBladderOutlineSource2": rounded(footprint.intersection(fine_bladder_outline).area),
                        "visibleStrokeAreaInSourceTracedSafeInteriorSource2": rounded(footprint.intersection(fine_bladder_core).area),
                        "visibleStrokeAreaAfterSafeInteriorSubtractionSource2": rounded(footprint.difference(fine_bladder_core).area),
                        "visibleCenterLengthInsideSourceTracedSafeInteriorSource": rounded(vislines.intersection(fine_bladder_core).length),
                        "sourceTracedSafeInteriorVertices": sum(len(p["points"]) for p in lua_paths(visual_boundaries["organs"]["bladder"]["interiorPaths"])),
                        "visibleStrokeOrangeSourcePixelCenters": sum(footprint.covers(p) for p in orange_centers),
                        "coarseLocatorNotFineMask": True,
                        "listedInPriorWallVisibilityPolicy": eid in policy["hideOnOrangeFace"],
                        "mustSubtractOrangeForeground": footprint.intersection(fine_bladder_core).area > .001,
                        "originalPixelProbeLimitation": "Conservative orange pigment only; highlights/rim/antialias pixels omitted. This count is evidence of intrusion, not a final alpha mask."})

    # Read named identity, not geometric intersection, to find all incident
    # existing paths. Actual display at a port can be fully hidden.
    selected_ports = ["lung_r.entry", "lung_r.exit", "lung_l.entry", "lung_l.exit",
                      "bladder.entry", "bladder.exit", "stomach.entry", "stomach.exit"]
    port_results = []
    for pid in selected_ports:
        p = ports[pid]
        q = Point(p["source"])
        incidents = []
        for eid, edge in edges.items():
            if pid not in {edge["a"], edge["b"]}:
                continue
            line = lines[eid]
            total = line.length
            at_start = edge["a"] == pid
            radius = edge["lumenWidthSource"] / 2
            visual = stroke(edge["visibleSegments"], radius)
            near = substring(line, 0 if at_start else max(0, total - 2 * edge["lumenWidthSource"]),
                             min(total, 2 * edge["lumenWidthSource"]) if at_start else total)
            visible_line = unary_union([LineString(s) for s in edge["visibleSegments"]])
            intervals = [list(h) for h in edge["hiddenIntervals"] if
                         (h[0] <= 1e-5 if at_start else h[1] >= total - 1e-5)]
            hidden_here = [o["owner"] for o in data["occlusions"] if o["edgeId"] == eid and
                           (o["startDistance"] <= 1e-5 if at_start else o["endDistance"] >= total - 1e-5)]
            incidents.append({"edgeId": eid, "namedEndpointDistanceSource": rounded(min(q.distance(Point(edge["samples"][0])), q.distance(Point(edge["samples"][-1])))),
                              "endpointHiddenIntervals": intervals, "endpointOccluderOwners": sorted(set(hidden_here)),
                              "portWithinVisibleLumenFootprint": visual.buffer(1e-5).covers(q),
                              "visibleCenterLengthWithinTwoDiametersSource": rounded(near.intersection(visible_line.buffer(1e-5)).length),
                              "trueVisibleArtPortalCertified": False})
        port_results.append({"id": pid, "source": p["source"], "incidentExistingEdges": incidents,
                             "insideSourceTracedBladderSafeInterior": fine_bladder_core.covers(q) if pid.startswith("bladder.") else None,
                             "fixedCoordinateRetained": True, "mayForceNewVisibleConnector": False})

    # Gastric controlled exits are blood-wall exits, not holes in organ outline.
    gate_results = []
    for g in data["gates"]:
        if g.get("edgeId") != "study.stomach.wall_service":
            continue
        line = lines[g["edgeId"]]
        point = Point(g["pipeCenterSource"])
        wall = Point(g["wallSource"])
        target = Point(g["tissueTargetSource"])
        opening = wall.buffer(g["radius"], quad_segs=16)
        path = LineString([point, wall, target])
        diameter = edges[g["edgeId"]]["lumenWidthSource"]
        visible = stroke(edges[g["edgeId"]]["visibleSegments"], diameter / 2)
        signed = (g["wallSource"][0] - g["pipeCenterSource"][0]) * g["nx"] + (g["wallSource"][1] - g["pipeCenterSource"][1]) * g["ny"]
        gate_results.append({"id": g["id"], "edgeId": g["edgeId"], "source": g["wallSource"],
                             "centerDistanceToFrozenPathSource": rounded(point.distance(line)),
                             "wallNormalLength": rounded(math.hypot(g["nx"], g["ny"])),
                             "signedWallNormalOffsetSource": rounded(signed),
                             "wallCenterDistanceToFoodSource": rounded(wall.distance(food)),
                             "openingFootprintDistanceToFoodSource": rounded(opening.distance(food)),
                             "bloodToTissueSpurFootprintDistanceToFoodSource": rounded(path.buffer(diameter / 2 + .65, cap_style="flat").distance(food)),
                             "openingFootprintOutsideFineStomachAreaSource2": rounded(opening.difference(organ_geo["stomach"]).area),
                             "tissueTargetInsideFineStomach": organ_geo["stomach"].covers(target),
                             "pipeCenterWithinFrozenVisibleFootprint": visible.buffer(1e-5).covers(point),
                             "distanceToClosestNamedPathEndSource": rounded(min(line.project(point), line.length-line.project(point))),
                             "actualRTSMovementCertified": False})

    airway_results = []
    for eid in ["e003", "e006", "e172", "e174", "e004", "e007"]:
        e = edges[eid]
        whole = lines[eid].buffer(e["lumenWidthSource"] / 2, cap_style="flat", quad_segs=16)
        visible = stroke(e["visibleSegments"], e["lumenWidthSource"] / 2)
        airway_results.append({"edgeId": eid, "wholeLengthSource": rounded(lines[eid].length),
                               "visibleLengthSource": rounded(sum(LineString(s).length for s in e["visibleSegments"])),
                               "visiblePieceLengthsSource": [rounded(LineString(s).length) for s in e["visibleSegments"]],
                               "airwayCandidateCorridorOverlaps": [{"passageId": pid,
                                   "wholeStrokeAreaSource2": rounded(whole.intersection(passage_geo[pid]).area),
                                   "visibleStrokeAreaSource2": rounded(visible.intersection(passage_geo[pid]).area)}
                                   for pid in ["air.trachea", "air.right", "air.left"]],
                               "fineSourceBronchialBranchMaskCertified": False})

    # Executable interval proposal: remove only these explicit source-invisible
    # passage records, then UNION all remaining occluders. Subtracting the old
    # merged hidden interval would incorrectly remove overlapping airway hides.
    override_ids = {"H055", "H056", "H057", "H068", "H069", "H154", "H155", "H156"}
    override_records = []
    for o in data["occlusions"]:
        if o["id"] not in override_ids:
            continue
        assert o["owner"] in {"food.esophagus", "food.rectum"}
        assert "not_visible_in_reference" in passages[o["owner"]]["basis"]
        line = lines[o["edgeId"]]
        segment = substring(line, o["startDistance"], o["endDistance"])
        samples = []
        for t in [0, .25, .5, .75, 1]:
            point = segment.interpolate(t, normalized=True)
            xy = list(point.coords[0])
            samples.append({"source": [rounded(x) for x in xy],
                            "rgb": list(original.getpixel(tuple(round(x) for x in xy)))})
        override_records.append({"spanId": o["id"], "edgeId": o["edgeId"],
             "removeOnlyOccluderOwner": o["owner"], "sourceBasis": passages[o["owner"]]["basis"],
             "startDistanceSource": o["startDistance"], "endDistanceSource": o["endDistance"],
             "startSource": o["startSource"], "endSource": o["endSource"],
             "sourceCenterlineColorProbes": samples,
             "sourceVisibleVesselIdentityProven": False,
             "qualification": "Nonvisible passage classification supports considering a display-depth change, but colors alone do not prove these pixels are a visible blood vessel. Red heart tissue is not arterial proof; orange bladder is a mandatory foreground blocker."})
    assert len(override_records) == 8
    override_edges = []
    for eid in sorted({o["edgeId"] for o in override_records}):
        remaining = [o for o in data["occlusions"] if o["edgeId"] == eid and o["id"] not in override_ids]
        retained = merge_intervals([[o["startDistance"], o["endDistance"]] for o in remaining])
        proposed = complement_intervals(retained, lines[eid].length)
        e = edges[eid]
        raw_parts = [list(substring(lines[eid], a, b).coords) for a, b in proposed]
        footprint = stroke(raw_parts, e["lumenWidthSource"] / 2)
        # The fine source-derived core is an additional display-only mask. The
        # complete exact rim/airway alpha must also be applied by composition.
        clipped = footprint.difference(fine_bladder_core) if eid.startswith("e14") or eid == "e197" else footprint
        affected_ports = []
        for pid, p in ports.items():
            if pid in {e["a"], e["b"]}:
                q = Point(p["source"])
                affected_ports.append({"id": pid, "source": p["source"],
                     "rawProposedFootprintCoversPort": footprint.buffer(1e-5).covers(q),
                     "afterSourceBladderSafeCoreCoversPort": clipped.buffer(1e-5).covers(q),
                     "finalAirwayCoreRimAlphaCoversPortNotTested": True})
        override_edges.append({"edgeId": eid, "frozenGeometryUnchanged": True,
             "removedOcclusionIds": [o["spanId"] for o in override_records if o["edgeId"] == eid],
             "remainingOcclusionIds": [o["id"] for o in remaining],
             "retainedHiddenIntervalsSource": retained,
             "proposedVisibleIntervalsSourceBeforeSourceForegroundClip": proposed,
             "proposedVisibleIntervalEndpointPairs": [[list(p[0]), list(p[-1])] for p in raw_parts],
             "proposedVisibleLengthSource": rounded(sum(b-a for a,b in proposed)),
             "afterSourceBladderSafeCoreFootprintAreaSource2": rounded(clipped.area),
             "affectedNamedPorts": affected_ports,
             "finalCompositionAccepted": False})

    files = ["final-reference-data.json", "remaining-vessels-inputs/bladder-wall-visibility.json",
             "organ-layers.json", "passages-data.json", "interface-contract.json", "occlusion-outlines.json"]
    hashes = {str((BASE/name).relative_to(ROOT)): sha(BASE/name) for name in files}
    hashes["assets/image/anatomy-reference/reference.png"] = sha(ROOT / "assets/image/anatomy-reference/reference.png")
    hashes[str(Path(__file__).relative_to(ROOT))] = sha(Path(__file__))
    hashes[str(boundary_path.relative_to(ROOT))] = sha(boundary_path)
    assert all(o["visibleLumenOverlapAreaSource2"] <= .001 for o in audit_occ)
    assert all(o["visibleEffectAtExistingMarginOverlapAreaSource2"] <= .001 for o in audit_occ)
    assert all(g["centerDistanceToFrozenPathSource"] < .01 and g["openingFootprintDistanceToFoodSource"] > 0 for g in gate_results)
    result = {"schema": "registered-vascular-independent-display-depth-audit/v1", "date": "2026-10-11",
              "status": "FROZEN_GEOMETRIC_DEPTH_AUDITED_FINE_FOREGROUND_COMPOSITION_PENDING",
              "pageSummary": "已按整条管壁 footprint 复核冻结可见段；膀胱内部仍需橙色固定前景遮住，肺部必须保留外侧供血弧并单独遮住支气管交叉。胃壁两出口保持原位且不占食物通路；精细膀胱与气道 mask、最终合成像素和实际移动尚未验收。",
              "inputHashes": hashes, "actualReferenceImageViewed": True,
              "displayDepthContract": {
                  "coordinateSpace": "1024x1536 source coordinates; every alpha/foreground shares this frame. World mapping and named ports remain frozen.",
                  "topology": "Only a/b stable node identity makes a connection. Projected overlap, a hidden span, or an artwork end cannot create a branch.",
                  "renderOrder": ["fixed original base/quiet underlay", "frozen visible vessel paint clipped to its lumen footprint", "edge-specific source foreground and blood crossing masks", "fixed organ rims and bronchial/food foreground", "existing named-port annotation, optional technical deep paths"],
                  "vesselFootprintRule": "All GPT pigment, pipe wall, highlight, shadow and moving shine share the frozen lumen clip. If effects extend outside the lumen, their maximal support must be declared and tested; existing hide intervals only budget radius + .65 source px. No arbitrary glows.",
                  "occlusionEdgeRule": "Draw visibleSegments with flat hidden ends. Fade only inward along the same path if necessary; never lengthen a short span. Explicit round joint discs only at an existing common named node, clipped by foreground too.",
                  "foregroundMaskRule": "Actual original-pixel alpha masks are required. Source-hashed OrganBoundariesData.lua includes fine bladder outline and safe interior; use those rather than the frozen coarse locator. Fine vectors must still be checked against final source alpha. Source blue pigment alone cannot distinguish vein from airway: restrict branch restoration to reviewed fine lung interior and preserve named blood access.",
                  "bladderRule": "Subtract the exact fixed orange core/rim foreground from ALL painted blood footprints, including e142/e144 approaches and e143/e197/e198 wall exchange. Keep short approaches at existing bladder.entry/exit where outside this foreground. Do not punch the orange core to expose internal nodes or move named ports.",
                  "lungRule": "Preserve e172/e174 outer visible supply arcs and capillary loops, restore fixed light-blue airway source artwork above crossing blood. A named lung supply port hidden by the airway stays an edge-specific deep continuation; do not bridge or attach it to a blue bronchial tip.",
                  "gastricRule": "Both study.stomach.wall_service exits use existing frozen wallSource/normal and clipped wall-only cap marks. They are not holes in the stomach silhouette or openings to food. No renewal of the rejected 0.15 fill art.",
                  "candidatePassageRule": "Candidate invisible food/urine corridors remain depth design constraints, not newly painted foreground anatomy. The existing hidden intervals are preserved conservatively until a reviewed edge-specific depth change exists.",
                  "protectedBrainLimbs": "Do not repaint the 116 protected edges or surrounding original head/limb pixels. No blanket foreground restoration may unexpectedly erase already accepted protected vessels.",
                  "acceptance": "Registered vessel alpha must have zero unauthorized support in blocked foreground, no added shared nodes, unchanged named ports/protected edges, and original outside-scope pixels. Native RTS clearance/movement is a separate test."
              },
              "occlusionFootprintChecks": audit_occ,
              "bladderFootprintChecks": bladder,
              "namedPortVisibilityChecks": port_results,
              "airwayFootprintChecks": airway_results,
              "gastricGateFootprintChecks": gate_results,
              "displayDepthOverrideProposal": {
                  "status": "PRECISE_CONDITIONAL_DISPLAY_ONLY_INTERVALS_SOURCE_FOREGROUND_REVIEW_REQUIRED",
                  "passagePropertyCheck": {pid: {"basis": passages[pid]["basis"],
                       "hasVisibleCandidateProperty": "visibleCandidate" in passages[pid],
                       "hasVisibilityProperty": "visibility" in passages[pid]}
                       for pid in ["food.esophagus", "food.rectum"]},
                  "scope": "Only the eight enumerated esophagus/rectum exclusions on e006/e008/e174/e175/e142/e197; never all food/urine exclusions or frozen gameplay routes.",
                  "algorithm": "Discard listed occlusion records from this separate DISPLAY list; union retained per-edge start/end distances, complement over frozen sampled arc length, render flat-cap lumen footprint. Then subtract exact original airway/food/core/rim/coronary foreground alpha from the whole footprint. Keep overlapping H169/H177 airway exclusions. No centerline relocation, port movement or graph reversal.",
                  "sourceEvidenceLimit": "Original bladder.entry and H155/H156 probes are orange face/rim. Those pixels cannot be exposed as visible blood. H056/H069 probes are red heart background, not proof of a blue vein. These are conditional depth proposals, not source-certified visible vessel reconstructions.",
                  "spans": override_records, "edges": override_edges,
                  "actualVisiblePortAcceptance": False},
              "highRiskFindings": [
                  {"id": "bladder-all-edge-core-subtract", "severity": "required-display-fix",
                   "edges": ["e142", "e143", "e144", "e197", "e198"],
                   "finding": "All five strokes overlap source-traced bladder safe interior. The earlier policy's three-edge list is insufficient by itself: e142/e144 also need the core foreground subtraction.",
                   "fix": "Apply the fixed source orange-face/rim alpha above every local vessel footprint; retain outside-core approaches and all immutable ports."},
                  {"id": "deep-candidate-port-visibility", "severity": "must-label-display-limitation",
                   "ports": ["lung_l.entry", "lung_l.exit", "bladder.entry"],
                   "finding": "Frozen visible lumen does not reach these ports because invisible candidate food.esophagus/food.rectum depth exclusions hide them. This is not proof of an actually visible opening.",
                   "fix": "Keep hidden continuation explicitly marked in the technical display. Do not force new artwork connectors; genuine visible exposure would require a separately reviewed per-edge display-depth override."},
                  {"id": "halo-footprint", "severity": "required-rendering-constraint",
                   "finding": "An unconstrained one-source-pixel halo overlaps 41 recorded occluders although the frozen visible lumen does not.",
                   "fix": "Clip wall/highlight/shadow/GPT material/flow effects to the lumen, or explicitly recompute and test the maximal expanded support; keep flat hidden caps."},
                  {"id": "lung-fine-airway-alpha", "severity": "pending-final-composition-check",
                   "finding": "Registered main airway corridors do not enumerate every fine light-blue source bronchial twig. Counting source blue alone mixes airway and veins.",
                   "fix": "Restore the source bronchial branch alpha in reviewed fine lung regions, inspect named blood access and test final vessel/bronchial alpha overlap. Preserve the outer e172/e174 arcs."}
              ],
              "sourceTracedBladderForeground": {"path": str(boundary_path.relative_to(ROOT)),
                    "sourceHashMatchesOriginal": True,
                    "outlineVertices": sum(len(p["points"]) for p in lua_paths(visual_boundaries["organs"]["bladder"]["outlinePaths"])),
                    "safeInteriorVertices": sum(len(p["points"]) for p in lua_paths(visual_boundaries["organs"]["bladder"]["interiorPaths"])),
                    "qualification": "Safe interior is a real source-derived trace, unlike the frozen 14-point locator. It excludes preserved original foreground and is not the entire face/rim alpha. Test the final registered core/rim alpha separately."},
              "foregroundMaskReadiness": {oid: {"frozenBoundaryKind": o["boundaryKind"],
                    "outlineVertices": sum(len(r["points"]) for r in o["outlines"]),
                    "rasterAlphaIndependentlyCertified": False,
                    "canUseAsFineVectorLocator": o["boundaryKind"] == "fine_visual",
                    "qualification": "Fine vector outline needs source-pixel verification; coarse locator is never final alpha."}
                    for oid, o in organs.items()},
              "checks": {"immutableBladderNamedPortsMatched": True,
                  "protectedEdgeCount": len(data["protectedEdges"]),
                  "frozenEdgeCount": len(edges), "occlusionCount": len(audit_occ),
                  "visibleLumenOverlapCount": sum(o["visibleLumenOverlapAreaSource2"] > .001 for o in audit_occ),
                  "visibleEffectsAtExistingMarginOverlapCount": sum(o["visibleEffectAtExistingMarginOverlapAreaSource2"] > .001 for o in audit_occ),
                  "unclippedOnePixelHaloOverlapCount": sum(o["unclippedOnePixelHaloOverlapAreaSource2"] > .001 for o in audit_occ),
                  "topologyModified": False, "productionInstalled": False,
                  "finalRenderedArtifactAudited": False, "fineForegroundMasksCertified": False,
                  "actualRTSMovementCertified": False},
              "limitations": ["Measured areas are geometric sampled-curve footprint units, not biological anatomy.",
                  "Occluder tests use fine source traces where available and explicitly coarse/candidate corridors elsewhere; they do not certify pixel-accurate foreground masks.",
                  "Orange pixel probes omit rim/highlight pixels and are only independent evidence of wrong visible paint.",
                  "No production rendering, new generation, rejected stomach battlefield, full-body performance or gameplay test was performed."]}
    REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(REPORT), "checks": result["checks"],
                      "bladder": bladder, "gastric": gate_results}, ensure_ascii=False, indent=2))


def svg_polygon_path(path):
    """The producers emit only absolute M/L/Z polygon rings, with evenodd fill."""
    if not path.strip():
        return GeometryCollection()
    result = GeometryCollection()
    for ring in re.findall(r"M\s+([^M]+?)\s+Z", path):
        nums = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", ring)]
        assert len(nums) % 2 == 0 and len(nums) >= 6
        poly = Polygon(list(zip(nums[::2], nums[1::2]))).buffer(0)
        result = result.symmetric_difference(poly)
    return result


def final_audit():
    import numpy as np
    import cffi  # Load system numpy/PIL before the existing Cairo tool environment.
    sys.path.insert(0, "/tmp/reference-map-tools")
    import cairosvg

    out = BASE / "registered-vessels"
    generation = json.loads((out / "generation.json").read_text())
    assert "hiddenEndFade" in generation, "Do not audit the rejected first pass"
    assert len(generation["outputs"]) == 8 and "cutaway-torso" in generation["outputs"], "Wait for the completed eight-output generation"
    assert generation["sourceBlueToneOpacity"] == 0
    import xml.etree.ElementTree as ET
    full_svg = ET.fromstring((out / "full-body.svg").read_bytes())
    assert "quietOverviewFragments" in generation, "Wait for the completed per-component overview rebuild"
    geo = json.loads((out / "geometry.json").read_text())
    frozen = read("final-reference-data.json")
    by_id = {e["id"]: e for e in frozen["edges"]}
    original_path = ROOT / "assets/image/anatomy-reference/reference.png"
    original = np.asarray(Image.open(original_path).convert("RGB"))
    final = np.asarray(Image.open(out / "full-body.png").convert("RGB"))
    assert original.shape == final.shape == (1536, 1024, 3)
    changed = np.any(original != final, axis=2)

    def raster(path):
        raw = ("<svg xmlns='http://www.w3.org/2000/svg' width='1024' height='1536' "
               "viewBox='0 0 1024 1536'><path fill='white' fill-rule='evenodd' d='" + path + "'/></svg>")
        return np.asarray(Image.open(BytesIO(cairosvg.svg2png(bytestring=raw.encode()))).convert("RGBA"))[:, :, 3]

    allowed_png = cairosvg.svg2png(bytestring=(out / "allowed-footprint.svg").read_bytes())
    allowed = np.asarray(Image.open(BytesIO(allowed_png)).convert("RGBA"))[:, :, 3]
    paint_alpha = raster(geo["paintUnionPath"])
    masks = {"airway": raster(geo["airwayForegroundPath"]),
             "bladder": raster(geo["bladderForegroundPath"]),
             "coronary": raster(geo["coronaryForegroundPath"])}
    source_box = geo["sourceBox"]
    outside_roi = np.ones(changed.shape, bool)
    outside_roi[source_box[1]:source_box[3], source_box[0]:source_box[2]] = False
    overview_alpha = raster(geo["overviewForegroundPath"])
    source_checks = {
        "changedPixelsTotal": int(changed.sum()),
        "changedPixelsOutsideAllowedEditAlpha": int(np.count_nonzero(changed & (allowed == 0))),
        "changedPixelsOutsideTorsoSourceBox": int(np.count_nonzero(changed & outside_roi)),
        "changedPixelsOutsideVesselPaintAlpha": int(np.count_nonzero(changed & (paint_alpha == 0))),
        "outsideVesselPaintQualification": "Source-blue toning has been removed. All remaining edits must lie within new-vessel paint support.",
        "intactOverviewOrganOpaquePixelChanges": int(np.count_nonzero(changed & (overview_alpha == 255))),
        "fixedForegroundOpaquePixelChanges": {key: int(np.count_nonzero(changed & (alpha == 255))) for key, alpha in masks.items()},
        "fixedForegroundAntialiasPixelChanges": {key: int(np.count_nonzero(changed & (alpha > 0) & (alpha < 255))) for key, alpha in masks.items()}}
    protected_area = unary_union([LineString(by_id[eid]["samples"]).buffer(by_id[eid]["lumenWidthSource"] / 2)
                                  for eid in frozen["protectedEdges"]])
    protected_changes = []
    yy, xx = np.where(changed)
    for x, y in zip(xx, yy):
        if protected_area.covers(Point(float(x), float(y))):
            protected_changes.append([int(x), int(y)])
    source_checks["changedPixelCentersWithinProtectedGraphLumen"] = len(protected_changes)
    source_checks["protectedGraphPixelChangeExamples"] = protected_changes[:30]
    source_checks["protectedGraphPixelQualification"] = "A projected graph lumen overlap does not by itself identify an original arm/head pigment pixel; head/near-arm strips are separately compared. Source-blue toning is now disabled."
    ygrid, xgrid = np.indices(changed.shape)
    source_checks["headAboveTorsoChangedPixels"] = int(np.count_nonzero(changed & (ygrid < source_box[1])))
    source_checks["innerArmInspectionROIChanges"] = {
        "left_x333_to369": int(np.count_nonzero(changed & (xgrid < 370))),
        "right_x651_to692": int(np.count_nonzero(changed & (xgrid > 650))),
        "qualification": "These fixed near-arm inspection strips lie inside the torso edit box. A zero outside-torso count cannot establish untouched inner arms."}
    by, bx = np.where(changed & (masks["bladder"] == 255))
    source_checks["bladderOpaqueBoundaryChangeEvidence"] = [
        {"sourcePixel": [int(x), int(y)], "originalRgb": original[y, x].tolist(),
         "finalRgb": final[y, x].tolist()} for x, y in zip(bx, by)]
    lua_boundaries = LuaRuntime().execute((ROOT / "scripts/war/OrganBoundariesData.lua").read_text())
    own_overview = []
    for oid, o in lua_boundaries["organs"].items():
        if oid not in {"lung_r", "lung_l", "heart", "liver", "stomach", "pancreas", "kidney_r", "kidney_l", "large_intestine", "small_intestine"}:
            continue  # Bladder has its stronger independent mask; brain is outside this authoring box.
        paths = [{"hole": bool(p["hole"]), "points": [[q[1], q[2]] for _, q in p["points"].items()]}
                 for _, p in o["outlinePaths"].items()]
        shape = polygon_set(paths)
        if oid in {"small_intestine", "large_intestine", "pancreas"}:
            shape = shape.convex_hull
        own_overview.append(shape.buffer(.65))
    own_overview = unary_union(own_overview)
    encoded_overview = svg_polygon_path(geo["overviewForegroundPath"])
    source_checks["overviewVsIndependentFineHullEnvelopeDifferenceAreaSource2"] = rounded(own_overview.symmetric_difference(encoded_overview).area)
    source_checks["overviewEnvelopeQualification"] = "For pancreas and bowel only, convex hull is an intentional visual hiding envelope for new vessel pigment. It is not an anatomical outline, food lumen or gameplay obstacle. Original source organ/food pixels are never replaced."

    fixed_masks = {key: svg_polygon_path(geo[key + "ForegroundPath"])
                   for key in ["airway", "bladder", "coronary"]}
    roi = box(*source_box)
    records = []
    overview_piece_checks = []
    override_ids = set(geo["displayContract"]["ignoredDeepCandidateOcclusionIds"])
    for edge in geo["edges"]:
        original_edge = by_id[edge["id"]]
        assert edge["samples"] == original_edge["samples"]
        assert edge["a"] == original_edge["a"] and edge["b"] == original_edge["b"]
        assert edge["widthSource"] == original_edge["lumenWidthSource"]
        line = LineString(edge["samples"])
        retained = [[o["startDistance"], o["endDistance"]] for o in frozen["occlusions"]
                    if o["edgeId"] == edge["id"] and o["id"] not in override_ids]
        expected = complement_intervals(retained, line.length)
        actual_segments = [LineString(p) for p in edge["visibleSegments"]]
        source_interval_error = max((abs(line.project(Point(s.coords[0])) - pair[0]) +
                                     abs(line.project(Point(s.coords[-1])) - pair[1])
                                     for s, pair in zip(actual_segments, expected)), default=0)
        assert len(actual_segments) == len(expected)
        lumen = stroke(edge["visibleSegments"], edge["widthSource"] / 2).intersection(roi)
        for q in [edge["samples"][0], edge["samples"][-1]]:
            if any(math.dist(q, endpoint) < .015 for s in edge["visibleSegments"] for endpoint in [s[0], s[-1]]):
                lumen = lumen.union(Point(q).buffer(edge["widthSource"] / 2)).intersection(roi)
        actual = svg_polygon_path(edge["paintPath"])
        expected_paint = lumen.difference(unary_union(list(fixed_masks.values())))
        records.append({"edgeId": edge["id"], "samplesNodeIDsWidthUnchanged": True,
                        "displayIntervalEndpointErrorSource": rounded(source_interval_error),
                        "paintOutsideFrozenLumenAreaSource2": rounded(actual.difference(lumen.buffer(.0002)).area),
                        "paintVsIndependentReconstructionAreaSource2": rounded(actual.symmetric_difference(expected_paint).area),
                        "paintVsForegroundOverlapSource2": {key: rounded(actual.intersection(mask).area) for key, mask in fixed_masks.items()}})
        overview_expected = actual.difference(encoded_overview)
        piece_shapes = []
        for index, piece in enumerate(edge["overviewPieces"]):
            shape = svg_polygon_path(piece["d"])
            assert shape.geom_type == "Polygon" and not shape.is_empty
            piece_shapes.append(shape)
            width = edge["widthSource"]
            near_port = any(shape.distance(Point(p["source"])) <= width * 2 + .0002
                            for p in frozen["ports"] if p["kind"] == "named_port" and p["id"] in {edge["a"], edge["b"]})
            x0,y0,x1,y1 = shape.bounds
            is_short = max(x1-x0,y1-y0) < width * 4 and shape.area < width * width * 5
            expected_opacity = .10 if is_short and not near_port else 1
            assert bool(piece["namedPortApproach"]) == near_port
            assert piece["opacity"] == expected_opacity
            assert abs(piece["areaSource"] - shape.area) < .003
            stem = edge["id"].replace(".", "-")
            clip_id = f"overview-{stem}-{index}"
            clip_elements = [p for p in full_svg.iter() if p.get("id") == clip_id]
            assert len(clip_elements) == 1 and clip_elements[0].tag.endswith("clipPath")
            displayed = [p for p in full_svg.iter() if p.get("clip-path") == f"url(#{clip_id})"]
            assert len(displayed) == 1 and float(displayed[0].get("opacity")) == expected_opacity
            overview_piece_checks.append({"edgeId": edge["id"], "piece": index,
                "areaSource": rounded(shape.area), "namedPortApproach": near_port,
                "opacity": expected_opacity,
                "outsideExpectedOverviewAreaSource2": rounded(shape.difference(overview_expected.buffer(.0002)).area)})
        piece_union = unary_union(piece_shapes)
        assert piece_union.symmetric_difference(overview_expected).area < .01
    assert set(geo["protectedEdgeIds"]) == set(frozen["protectedEdges"])
    assert not set(geo["protectedEdgeIds"]) & {e["id"] for e in geo["edges"]}
    assert geo["ports"] == frozen["ports"] and geo["gates"] == frozen["gates"]
    assert override_ids == {"H055", "H056", "H057", "H068", "H069", "H154", "H155", "H156"}
    port_visibility = []
    for p in frozen["ports"]:
        if p["kind"] != "named_port":
            continue
        if p["id"].startswith(("lung_", "stomach.", "bladder.")):
            point = Point(p["source"])
            incident = [e for e in geo["edges"] if p["id"] in {e["a"], e["b"]}]
            port_visibility.append({"id": p["id"], "source": p["source"],
                "existingNodeIdentityUnchanged": True,
                "displayFootprintAtNamedPort": [e["id"] for e in incident if svg_polygon_path(e["paintPath"]).buffer(.0002).covers(point)],
                "fixedForegroundAtNamedPort": [key for key, mask in fixed_masks.items() if mask.covers(point)],
                "artworkOpeningCertified": False})

    overlay = Image.open(out / "cutaway-overlay.png").convert("RGBA")
    overview_overlay = Image.open(out / "vessel-overlay.png").convert("RGBA")
    cutaway_pixels = np.asarray(overlay)[:, :, 3]
    overview_pixels = np.asarray(overview_overlay)[:, :, 3]
    assert overlay.size == overview_overlay.size == (1440, 2376)

    def crop_alpha(path):
        raw = ("<svg xmlns='http://www.w3.org/2000/svg' width='1440' height='2376' "
               "viewBox='333 250 360 594'><path fill='white' fill-rule='evenodd' d='" + path + "'/></svg>")
        return np.asarray(Image.open(BytesIO(cairosvg.svg2png(bytestring=raw.encode()))).convert("RGBA"))[:, :, 3]

    crop_masks = {key: crop_alpha(geo[key + "ForegroundPath"]) for key in ["airway", "bladder", "coronary"]}
    crop_overview = crop_alpha(geo["overviewForegroundPath"])
    crop_paint = crop_alpha(geo["paintUnionPath"])
    cutaway_checks = {"cutawayAlphaOutsideAllowedPaintPixels": int(np.count_nonzero((cutaway_pixels > 0) & (crop_paint == 0))),
                     "overviewAlphaOutsideAllowedPaintPixels": int(np.count_nonzero((overview_pixels > 0) & (crop_paint == 0))),
                     "overviewAlphaInsideOpaqueOrganForegroundPixels": int(np.count_nonzero((overview_pixels > 0) & (crop_overview == 255))),
                     "cutawayOpaqueForegroundIntrusionPixels": {key: int(np.count_nonzero((cutaway_pixels > 0) & (alpha == 255))) for key, alpha in crop_masks.items()},
                     "qualification": "Four-times-source output and independently rasterized fixed foreground/paint masks. Antialias boundary pixels are tracked separately from opaque support."}
    fade_probe = []
    for eid, index, side in [("e164", 0, "end"), ("e132", 1, "end"), ("e168", 2, "start"), ("e188", 0, "start")]:
        edge = next(e for e in geo["edges"] if e["id"] == eid)
        line = LineString(edge["visibleSegments"][index])
        probe = []
        for distance in [.08, .5, 1., 2., 3.]:
            point = line.interpolate(line.length - distance if side == "end" else distance)
            xy = point.coords[0]
            probe.append({"distanceInwardSource": distance, "source": [rounded(x) for x in xy],
                          "rgba": list(overlay.getpixel(tuple(round((x-offset) * 4) for x,offset in zip(xy,[333,250]))))})
        fade_probe.append({"edgeId": eid, "piece": index, "side": side,
                           "endpointSource": list(line.coords[-1] if side == "end" else line.coords[0]),
                           "samples": probe,
                           "fadeActuallyPresent": max(p["rgba"][3] for p in probe) > probe[0]["rgba"][3],
                           "observationPlane": "cutaway-only alpha; a segment outside organ wall foreground can have zero alpha here and instead belong to overview"})

    output_hashes = {}
    for name, record in generation["outputs"].items():
        for suffix, key in [("svg", "svgSha256"), ("png", "pngSha256")]:
            path = out / f"{name}.{suffix}"
            output_hashes[str(path.relative_to(ROOT))] = sha(path)
            assert sha(path) == record[key]
    inputs = [original_path, BASE / "final-reference-data.json", ROOT / "scripts/war/OrganBoundariesData.lua",
              ROOT / "scripts/qa/prepare_registered_vascular_layers.py", ROOT / "scripts/qa/build_registered_vascular_art.py",
              Path(__file__), out / "geometry.json", out / "generation.json", out / "allowed-footprint.svg",
              out / "material-prompt-v1.txt", ROOT / "assets/image/anatomy-reference/vascular-study/registered-vessels/gpt-matte-material-v1.png"]
    assert sha(original_path) == generation["sourceSha256"] == geo["sourceSha256"]
    assert sha(BASE / "final-reference-data.json") == generation["finalReferenceSha256"] == geo["finalReferenceSha256"]
    assert sha(out / "geometry.json") == generation["geometrySha256"]
    assert sha(inputs[-1]) == generation["atlasSha256"]
    assert sha(out / "material-prompt-v1.txt") == generation["promptSha256"]
    result = {"schema": "registered-vessels-independent-final-composition-audit/v1", "date": "2026-10-11",
              "status": "INTACT_OVERVIEW_SOURCE_PROTECTION_PASS_CUTAWAY_ART_STILL_CANDIDATE",
              "pageSummary": "新版主图已遮回器官内部覆线和肠袢空隙碎段，未靠命名接口的小露段降低显示强度；脑四肢检查区域、完整膀胱和支气管原像素保持，8项输出哈希与遮罩范围通过。剖面层仍偏线路试样，不能宣称最终局部战场美术或实际细胞移动通过。",
              "reviewedHiddenEndFade": generation["hiddenEndFade"],
              "inputHashes": {str(p.relative_to(ROOT)): sha(p) for p in inputs},
              "artifactHashes": output_hashes,
              "actualImagesViewed": [str((out / f"{name}.png").relative_to(ROOT)) for name in ["full-body", "torso", "lower-abdomen", "cutaway-torso"]],
              "sourcePixelChecks": source_checks, "edgeGeometryChecks": records,
              "overviewPieceChecks": overview_piece_checks,
              "cutawayRasterChecks": cutaway_checks,
              "namedPortVisibleFootprintChecks": port_visibility,
              "actualRasterFadeProbes": fade_probe,
              "visualFindings": [
                  {"id": "protected-source-pixel-toning", "result": "REPAIRED", "finding": f"Source-blue toning is removed. Actual head-above-torso and left/right near-arm pixel differences are zero; outside-torso pixels, including lower limbs, are unchanged. The {len(protected_changes)} projected protected-graph overlap pixels are not by themselves proof of changed arm/head art; source ROI checks are separate."},
                  {"id": "bladder-antialias-boundary", "result": "REPAIRED", "finding": "Complete fine bladder face protection uses a 1.5 source-pixel guard. Opaque and antialias foreground differences are both zero; the previous six boundary pixel changes are gone."},
                  {"id": "bladder-face", "result": "IMPROVED", "finding": "Full orange bladder face/outlet is clean in final actual images. No inner blood U-loop or groove is visible. Its supply port remains a deep continuation under the preserved orange face, not a real exposed lumen opening."},
                  {"id": "airway-separation", "result": "IMPROVED_WITH_LIMIT", "finding": "Light-blue original bronchial branches remain foreground and the blood access arcs do not visibly weld to airway tips. The lung exchange loops are split by this foreground and can still look like isolated purple segments."},
                  {"id": "intact-overview-organ-plane", "result": "SOURCE_PROTECTION_PASS_GAP_FRAGMENTS_REPAIRED", "finding": "Actual full-body/torso/lower images hide the internal stomach S return, liver loop, lung capillary arcs and heart overlays beneath intact original organ faces. The fine source-derived bowel/pancreas convex-hull hiding envelope closes distracting small gap windows without replacing any original tissue/food pixel. Small post-mask exposed components without a nearby named port are rendered at 10 percent opacity; continuous blood approaches remain. This is an intentional overview display envelope, not a changed organ boundary or gameplay obstacle."},
                  {"id": "remaining-flat-hidden-ends", "result": "CUTAWAY_REMAINS_CANDIDATE", "edges": ["e164", "e130", "e132", "e168", "e188"], "finding": "Actual cutaway-torso has softer hidden ends than the prior short fade. e164 and e188 inward alpha samples visibly ramp, but the stomach blue S/intestinal partial lines remain recognizable as diagram-like overlays on original organ pigment. This is not a complete natural wall-section battlefield.", "minimumNextArtAdjustment": "Judge the wall-section presentation with actual existing .15 fill and real cell glyphs before widening or adding texture. Keep original food/air/bladder foreground, frozen routes and named ports; no graph redesign in this art pass."},
                  {"id": "continuous-loop-reading", "result": "PARTIAL_BY_DESIGN", "finding": "The intact overview only reveals existing external approaches. Internal graph tracing belongs to the registered cutaway layer and is not visible on the complete organ face."},
                  {"id": "new-depth-clip-ends", "result": "IMPLEMENTATION_IMPROVED", "finding": "The producer now splits material centerline runs by fixed source foreground support before applying fades. Final alpha is still inspected separately."}
              ],
              "deliveryVerdict": {"registeredGeometryAudited": True, "bladderOrangeFaceVisuallyClean": True,
                  "inwardRasterFadeActuallyObserved": any(p["fadeActuallyPresent"] for p in fade_probe), "finalArtVisualPass": False,
                  "intactOverviewForegroundActuallyPassed": source_checks["intactOverviewOrganOpaquePixelChanges"] == 0 and cutaway_checks["overviewAlphaInsideOpaqueOrganForegroundPixels"] == 0,
                  "completeFixedForegroundOpaquePixelIdentityPassed": all(v == 0 for v in source_checks["fixedForegroundOpaquePixelChanges"].values()),
                  "originalInnerArmInspectionStripPixelsUnchangedPassed": source_checks["innerArmInspectionROIChanges"]["left_x333_to369"] == 0 and source_checks["innerArmInspectionROIChanges"]["right_x651_to692"] == 0,
                  "fullBodyArtworkComplete": False, "productionInstalled": False,
                  "nativeEvidence": False, "actualRTSMovementCertified": False},
              "limits": ["This independent pass reviews the final files with hiddenEndFade, not initial-fragments-rejected.png.",
                         "The earlier black-luminance overview mask did not subtract in CairoSVG. This audited revision checks every per-component clipPath against the independently reconstructed Shapely difference, not merely its metadata.",
                         "Pixel and geometry checks do not replace native rendering/performance or RTS navigation tests.",
                         "Source preserved pixels include AI-painted broad blood lines; preserving them does not certify each original pigment junction as graph topology."]}
    path = BASE / "registered-vessels-final-audit.json"
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(path), "sourcePixelChecks": source_checks,
                      "maxPaintOutsideLumenArea": max(r["paintOutsideFrozenLumenAreaSource2"] for r in records),
                      "maxPaintReconstructionDifference": max(r["paintVsIndependentReconstructionAreaSource2"] for r in records),
                      "pageSummary": result["pageSummary"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    final_audit() if "--final" in sys.argv else main()
