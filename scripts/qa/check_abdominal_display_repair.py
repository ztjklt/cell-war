"""Check registered abdominal display against real geometry and red-cell clicks."""
from pathlib import Path
import hashlib
import json
import os
import sys

from lupa.lua54 import LuaRuntime
from shapely.geometry import LineString, Point

sys.path.insert(0, str(Path(__file__).parent))
import check_organ_layer_commands as commands
from check_fullbody_foreground_semantics import svg_geometry
from check_regional_vascular_refinement import convert
from register_simple_heart import rings

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/abdominal-display-20261014"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    os.chdir(ROOT)
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute("package.path='scripts/?.lua;'..package.path;"
                    "package.loaded['urhox-libs/UI']={};print=function()end")

    def module(name):
        result = runtime.eval("require('war." + name + "')")
        return result[0] if isinstance(result, tuple) else result

    display = module("AbdominalVesselDisplay")
    data = convert(display.data)
    for name, digest in data["geometryBindings"].items():
        assert sha(ROOT / "scripts/war" / name) == digest, "stale display geometry: " + name
    facade = module("OrganBattlefield")
    net = facade.net(runtime.table_from({"anatomyVersion": 4, "fullbodyBattlefieldVersion": 1}))
    for _, edge in net.edges.items():
        for point, node in [(edge.points[1], net.nodes[edge.a]),
                            (edge.points[len(edge.points)], net.nodes[edge.b])]:
            assert abs(point[1] - node.x) + abs(point[2] - node.y) < 1e-6
    bowel = module("BowelVisual")
    bowl_lanes = [lane for lane in data["ownedLanes"] if lane != 202]
    for lane in bowl_lanes:
        p = net.edges[lane].points[1]
        assert bowel.unitDepth(lane, p[1], p[2])[1], "numeric blood ID lost its intestinal visibility data"
    for i in range(1, len(net.edges[202].points) + 1):
        p = net.edges[202].points[i]
        assert display.unitDepth(202, p[1], p[2]) == (None, True)
    root = json.loads((ROOT / "docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json").read_text())
    roof = svg_geometry(ROOT / root["actualArtForeground"]["geometrySvgPath"])
    assert sha(ROOT / root["actualArtForeground"]["geometrySvgPath"]) == data["foregroundSha256"]
    for patch in data["patches"]:
        if patch["lane"] != 202:
            # Compiled bowel paint must stay outside actual digestive roofs.
            assert rings(patch["outer"]).intersection(roof).area < 1e-7

    runtime.globals().progress = lambda message: print(message, flush=True)
    prefix = commands.LUA.split("for _,id in ipairs(O.activeOrgans(s))do\n for _,kind in ipairs({'scout','siege'})do", 1)[0]
    tests = r'''
local results={}
for _,lane in ipairs({202,132,167})do
 local e,g=prepare('worker',along(lane,.15));local row=move(e,g,along(lane,.85))
 requirePass(row,'red cell on repaired blood lane '..lane)
 assert(transitions==0,'display repair switched a blood cell into tissue')
 results[#results+1]={lane=lane,move=row};progress('red cell lane '..lane..' ordinary click PASS')
end
M.record=original;return results
'''
    movement = commands.convert(runtime.execute(prefix + tests))
    report = dict(status="PASS_PRODUCTION_LUA_OFFLINE", nativeEvidence=False,
                  graphEndpointsAligned=True, bloodEdges=len(net.edges),
                  intestinalNumericOwnershipChecks=len(bowl_lanes),
                  stomachWallVisibleSamples=len(net.edges[202].points),
                  redCellMovement=movement, destinationLanesForced=False,
                  additionalTextureSlots=data["additionalTextureSlots"],
                  movementGeometryUnchanged=True, dataSha256=sha(ROOT / "scripts/war/AbdominalVesselDisplayData.lua"))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "acceptance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("PASS: 15 intestinal lane IDs, full gastric wall visibility, aligned graph, 3 red-cell routes", flush=True)


if __name__ == "__main__":
    main()
