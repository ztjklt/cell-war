"""Compile display-only repairs from current vessels and accepted roof geometry.

No textures, routes, organ floors, membranes or save identities are edited.
Only missing foreground vessel pieces are painted over the registered artwork.
"""
from pathlib import Path
import hashlib
import json
import sys

from lupa.lua54 import LuaRuntime
from shapely.geometry import LineString
from shapely.ops import unary_union, substring

sys.path.insert(0, str(Path(__file__).parent))
from check_regional_vascular_refinement import convert
from check_fullbody_foreground_semantics import svg_geometry
from prepare_heart_battlefield import lua, rings as export_rings
from register_simple_heart import rings

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/abdominal-display-20261014"
TARGET = ROOT / "scripts/war/AbdominalVesselDisplayData.lua"
PRIORITY = {"capillary": 20, "vein": 30, "artery": 40}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def polygons(shape):
    if shape.geom_type == "Polygon":
        return [shape]
    return [p for child in getattr(shape, "geoms", []) for p in polygons(child)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute("package.path='scripts/?.lua;'..package.path;"
                    "package.loaded['urhox-libs/UI']={};print=function()end")

    def module(name):
        result = runtime.eval("require('war." + name + "')")
        return result[0] if isinstance(result, tuple) else result

    net = module("OrganBattlefield").net(runtime.table_from(
        {"anatomyVersion": 4, "fullbodyBattlefieldVersion": 1}))
    art = convert(module("FullBodyMapArtData"))
    bowel_art = convert(module("BowelVisualData"))
    bowel = convert(module("BowelBattlefieldData"))
    owned = {int(k) for k in bowel_art["ownedLanes"]}
    edges = {}
    for lane, edge in net.edges.items():
        edges[lane] = dict(lane=lane, name=edge.name, a=net.nodes[edge.a].id,
                           b=net.nodes[edge.b].id, system=edge.system,
                           width=edge.width * .5,
                           points=[(p[1] * .5, (p[2] - 512) * .5)
                                   for _, p in edge.points.items()])
    lines = {i: LineString(e["points"]) for i, e in edges.items()}
    domains = {i: line.buffer(edges[i]["width"] * .5, quad_segs=24)
               for i, line in lines.items()}
    for lane, raw in bowel["rawBloodDomains"].items():
        domains[int(lane)] = rings(raw)
    manifest = json.loads((ROOT / "docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json").read_text())
    roof_path = ROOT / manifest["actualArtForeground"]["geometrySvgPath"]
    roof = svg_geometry(roof_path)

    def visible_domain(i):
        line = lines[i]
        hidden = sorted((max(0, x["startDistance"]), min(line.length, x["endDistance"]))
                        for x in art["visibility"].get(edges[i]["name"], []))
        parts, start = [], 0
        for a, b in hidden:
            if a > start:
                parts.append(substring(line, start, a).buffer(edges[i]["width"] * .5 + .12,
                                                             cap_style="flat", quad_segs=24))
            start = max(start, b)
        if start < line.length:
            parts.append(substring(line, start, line.length).buffer(edges[i]["width"] * .5 + .12,
                                                                   cap_style="flat", quad_segs=24))
        return unary_union(parts)

    foreground = {i: visible_domain(i) for i in edges if i not in owned}
    drawings, front, rows = [], {}, []
    # The user explicitly requested that the right gastric wall vessel remain
    # visible above the organ, including its two obsolete hidden intervals.
    old_202 = domains[202]
    for interval in art["visibility"].get(edges[202]["name"], []):
        hidden = substring(lines[202], interval["startDistance"], interval["endDistance"])
        old_202 = old_202.difference(hidden.buffer(edges[202]["width"] * .5 + .65))
    front[202] = export_rings(domains[202].simplify(.015, preserve_topology=True))
    patch = domains[202].difference(old_202).buffer(.25).intersection(domains[202])
    drawings.append(dict(lane=202, system=edges[202]["system"], sourceBox=list(patch.bounds),
                         outer=export_rings(patch.simplify(.015, preserve_topology=True)),
                         inner=export_rings(domains[202].buffer(-.10).intersection(patch)
                                            .simplify(.015, preserve_topology=True))))
    rows.append(dict(lane=202, reason="right stomach wall vessel above organ",
                     recoveredCenterlineLength=lines[202].intersection(patch).length))
    for lane in sorted(owned, key=lambda i: (PRIORITY[edges[i]["system"]], i)):
        edge = edges[lane]
        old = rings(bowel_art["frontPipeRings"].get(lane, []))
        blockers, old_foreign = [], []
        for other, spec in edges.items():
            if other == lane or other > 202 or {edge["a"], edge["b"]} & {spec["a"], spec["b"]}:
                continue
            if other not in owned:
                blockers.append(foreground[other])
                old_foreign.append(domains[other].buffer(.12))
            elif (PRIORITY[spec["system"]], other) > (PRIORITY[edge["system"]], lane):
                blockers.append(domains[other].buffer(.12))
        blocked = unary_union(blockers)
        visible = domains[lane].difference(roof).difference(blocked)
        missing = visible.difference(old.buffer(.05))
        # Ignore subpixel edge differences; repair real gaps along the lumen.
        missing = unary_union([p for p in polygons(missing)
                               if p.area > .15 and p.intersects(lines[lane].buffer(.06))])
        patch = missing.buffer(.25).intersection(visible)
        front[lane] = export_rings(old.union(patch).simplify(.015, preserve_topology=True))
        if not patch.is_empty:
            drawings.append(dict(lane=lane, system=edge["system"], sourceBox=list(patch.bounds),
                                 outer=export_rings(patch.simplify(.015, preserve_topology=True)),
                                 inner=export_rings(domains[lane].buffer(-.10).intersection(patch)
                                                    .simplify(.015, preserve_topology=True))))
        rows.append(dict(lane=lane, name=edge["name"], recoveredArea=patch.area,
                         recoveredCenterlineLength=lines[lane].intersection(patch).length,
                         hiddenForeignMaskArea=patch.intersection(unary_union(old_foreign).difference(blocked)).area,
                         actualRoofOverlapArea=patch.intersection(roof).area,
                         upperBloodOverlapArea=patch.intersection(blocked).area))
        assert patch.intersection(roof).area < 1e-7
        assert patch.intersection(blocked).area < 1e-7
        assert patch.difference(domains[lane]).area < 1e-7

    bindings = {name: sha(ROOT / "scripts/war" / name) for name in
                ["BowelBattlefieldData.lua", "BowelVisualData.lua", "GastricBattlefieldData.lua",
                 "HeartBattlefieldData.lua", "FullBodyMapArtData.lua", "ReferenceVessels.lua",
                 "OrganBattlefield.lua", "HeartBattlefield.lua", "BowelBattlefield.lua"]}
    result = dict(schema="abdominal-vessel-display/v1", sourceTransform={"scale": 2, "oy": 512},
                  geometryBindings=bindings, foregroundSha256=sha(roof_path),
                  ownedLanes={i: True for i in front}, frontPipeRings=front, patches=drawings,
                  additionalTextureSlots=0, navigationEdited=False)
    TARGET.write_text("-- Display only: generated by prepare_abdominal_display_repair.py.\nreturn " + lua(result) + "\n")
    report = dict(status="COMPILED_DISPLAY_ONLY", nativeEvidence=False,
                  graphEdges=len(edges), rows=rows, additionalTextureSlots=0,
                  outputSha256=sha(TARGET), geometryBindings=bindings,
                  numericOwnedLaneKeys=True, bowelMembranesPreserved=True)
    (OUT / "geometry-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"patches": len(drawings), "repairedBowelLanes": [r["lane"] for r in rows[1:]
                                                                  if r["recoveredArea"] > .001],
                      "gastricRecoveredLength": rows[0]["recoveredCenterlineLength"],
                      "dataBytes": TARGET.stat().st_size}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
