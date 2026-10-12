"""Bake GPT vessel raster material over the complete frozen 202-edge map.

The source geometry, widths, graph nodes, organ silhouettes and protected
food/air/urine passages are inputs, never inferred from generated pixels.
Common named junctions are composed as one open footprint: bank material is
sampled from the OUTSIDE of the union, so independent segment banks cannot
close the middle of a branch. Independent crossings remain independent.

This is an offline renderer/compositor for existing GPT art, not an image
generation substitute. --material supplies a GPT atlas with three horizontal
rows (artery, vein, exchange); matching metadata supplies exact row bounds.
--junctions supplies GPT regional
edits with sourceBox and frozen clip stencil. No source asset is overwritten.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter, defaultdict
import hashlib
from io import BytesIO
import json
import math
from pathlib import Path
import re
import sys

sys.path.insert(0, "/tmp/reference-map-tools")
import cairosvg
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from scipy.ndimage import binary_closing, map_coordinates, gaussian_filter
from scipy.spatial import cKDTree
from shapely.geometry import GeometryCollection, LineString, Point, Polygon, box
from shapely.ops import substring, unary_union
from shapely import set_precision

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs/body-life/vascular-art-study"
OUT = DOC / "fullbody-015/bake"
ASSET = ROOT / "assets/image/anatomy-reference/vascular-study/fullbody-015"
SOURCE = ROOT / "assets/image/anatomy-reference/reference.png"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rings_geometry(rings):
    return unary_union([Polygon(p["outer"], p.get("holes", [])) for p in rings])


def svg_geometry(path):
    result = GeometryCollection()
    for ring in re.findall(r"M\s*([^M]+)", path or ""):
        nums = [float(v) for v in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", ring)]
        pts = list(zip(nums[::2], nums[1::2]))
        if len(pts) > 2:
            poly = Polygon(pts)
            if not poly.is_valid:
                poly = poly.buffer(0)
            result = result.symmetric_difference(poly)
    return result


def polygons(shape):
    if shape.geom_type == "Polygon":
        return [shape]
    return [p for g in getattr(shape, "geoms", []) for p in polygons(g)]


def remove_numeric_slivers(shape):
    # Shared masks can differ by ~1e-13 source px after floating-point unions.
    # These are not blood fragments or visible authoring features.
    return unary_union([p.buffer(0) for p in polygons(shape) if p.area >= .0001])


def area_intersection(first, second):
    """Remove touching line remnants between each fixed-precision overlay.

    GEOS does not accept a mixed Polygon/LineString collection as a precise
    overlay input. Touch-only lines have zero paint area, so discard those
    rather than moving/expanding a visible footprint to hide an error.
    """
    first,second=remove_numeric_slivers(first),remove_numeric_slivers(second)
    if first.is_empty or second.is_empty:
        return Polygon()
    return remove_numeric_slivers(first.intersection(second,grid_size=.00001))


def geometry_path(shape):
    return " ".join("M " + " L ".join(f"{x:.5f},{y:.5f}" for x, y in ring.coords) + " Z"
                    for p in polygons(shape)
                    for ring in [p.exterior, *p.interiors])


def paint(shape, fill, ink=None, width=.16):
    if shape.is_empty:
        return ""
    return '<path d="' + geometry_path(shape) + '" fill="' + fill + '" fill-rule="evenodd"' + (
        f' stroke="{ink}" stroke-width="{width}" stroke-linejoin="round"' if ink else "") + "/>"


def line_parts(shape):
    if shape.geom_type == "LineString":
        return [shape] if shape.length > 1e-6 else []
    return [p for g in getattr(shape, "geoms", []) for p in line_parts(g)]


def stroke(lines, radius):
    return unary_union([line.buffer(radius, cap_style=2, join_style=1, quad_segs=8) for line in lines])


def mask(shape, bounds, size):
    x, y, xx, yy = bounds
    clipped = shape.intersection(box(*bounds)).simplify(.008, preserve_topology=True)
    if clipped.is_empty:
        return np.zeros((size[1], size[0]), dtype=np.uint8)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" '
           f'viewBox="{x} {y} {xx-x} {yy-y}">' + paint(clipped, "white") + "</svg>")
    return np.asarray(Image.open(BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert("RGBA"))[:, :, 3].copy()


def safe_bounds(shape, padding=2):
    x, y, xx, yy = shape.bounds
    return [math.floor(x-padding), math.floor(y-padding), math.ceil(xx+padding), math.ceil(yy+padding)]


def alpha_over(base, foreground):
    """PIL does standard straight-alpha compositing with no darkened triangles."""
    return np.asarray(Image.alpha_composite(Image.fromarray(base), Image.fromarray(foreground))).copy()


def save_png(array, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(array).save(path)


def asset_record(path, source_box, role, **extra):
    im = Image.open(path)
    return dict(id=path.stem, role=role, path=str(path.relative_to(ROOT)),
                resource=str(path.relative_to(ROOT / "assets")), sourceBox=source_box,
                pixelSize=list(im.size), sha256=sha(path), **extra)


def cross_section(line, at, radius):
    """Exact-width transverse line at the existing sampled route position."""
    at = min(max(at, 0), line.length)
    delta = min(.10, max(.005, radius*.08))
    before, after = line.interpolate(max(0,at-delta)), line.interpolate(min(line.length,at+delta))
    dx,dy=after.x-before.x,after.y-before.y
    length=math.hypot(dx,dy)
    p=line.interpolate(at)
    if length<1e-10:
        return Point(p)
    nx,ny=-dy/length*radius,dx/length*radius
    return LineString([(p.x+nx,p.y+ny),(p.x-nx,p.y-ny)])


def transverse_hidden_intervals(line, intervals, radius, protected):
    """Display-only flat mouths at the first complete-width contact.

    The unit-depth intervals are deliberately left untouched. Their circular
    Minkowski clearance hides a cell conservatively, but a painted flat tube
    end is transverse, not a circular capsule: stopping it at the clearance
    boundary leaves half a tube width of empty floor before the foreground.
    Locate the actual cross-section contact along the SAME frozen centerline.
    """
    result=[]
    for entry in intervals:
        a,b=entry['startDistance'],entry['endDistance']
        steps=max(4,math.ceil((b-a)/max(.03,radius*.10)))
        positions=np.linspace(a,b,steps+1)
        hits=[cross_section(line,float(t),radius).intersects(protected) for t in positions]
        hit_ids=[i for i,h in enumerate(hits) if h]
        if not hit_ids:
            continue
        first,last=hit_ids[0],hit_ids[-1]
        left=positions[max(0,first-1)];right=positions[first]
        for _ in range(18):
            mid=(left+right)/2
            if cross_section(line,float(mid),radius).intersects(protected): right=mid
            else: left=mid
        start=float(left)
        left=positions[last];right=positions[min(steps,last+1)]
        for _ in range(18):
            mid=(left+right)/2
            if cross_section(line,float(mid),radius).intersects(protected): left=mid
            else: right=mid
        end=float(right)
        result.append(dict(startDistance=start,endDistance=end,
                           sourceStart=list(line.interpolate(start).coords[0]),
                           sourceEnd=list(line.interpolate(end).coords[0]),
                           foregroundIds=entry['foregroundIds'],
                           cap='open-flat', collisionEdited=False))
    return result


def raster_runs_geometry(selected, bounds, scale):
    """Lossless binary row-run registration; generated colors do not navigate."""
    rectangles=[];active={}
    for row in range(selected.shape[0]+1):
        ids=[]
        if row<selected.shape[0]:
            padded=np.pad(selected[row].astype(np.int8),(1,1))
            diff=np.diff(padded)
            ids=list(zip(np.flatnonzero(diff==1),np.flatnonzero(diff==-1)))
        now=set(ids)
        for span,first in list(active.items()):
            if span not in now:
                rectangles.append(box(bounds[0]+span[0]/scale,bounds[1]+first/scale,
                                      bounds[0]+span[1]/scale,bounds[1]+row/scale))
                del active[span]
        for span in ids:
            if span not in active: active[span]=row
    return unary_union(rectangles).simplify(.06,preserve_topology=True)


def foreground_intervals(line, foreground, regions):
    records=[]
    for part in line_parts(line.intersection(foreground)):
        a,b=sorted([line.project(Point(part.coords[0])),line.project(Point(part.coords[-1]))])
        if b-a<=1e-5: continue
        records.append(dict(startDistance=a,endDistance=b,
            sourceStart=list(line.interpolate(a).coords[0]),sourceEnd=list(line.interpolate(b).coords[0]),
            foregroundIds=[p['id'] for p in regions if p['geometry'].distance(part)<.15],
            unitDepth='under-foreground',connectsToForeground=False,
            reason='actual visible cream foreground + full stomach food cavity; independent display plane'))
    return sorted(records,key=lambda q:q['startDistance'])


class Bake:
    def __init__(self, args):
        self.args = args
        self.final = json.loads((DOC / "final-reference-data.json").read_text())
        self.registered = json.loads((DOC / "registered-vessels/geometry.json").read_text())
        self.art = json.loads((DOC / "organ-atlas/art.json").read_text())
        self.material_path = Path(args.material).resolve()
        self.atlas = np.asarray(Image.open(self.material_path).convert("RGBA"))
        self.material_rows = {"artery": [0, self.atlas.shape[0]/3],
                              "vein": [self.atlas.shape[0]/3, self.atlas.shape[0]*2/3],
                              "capillary": [self.atlas.shape[0]*2/3, self.atlas.shape[0]]}
        metadata = Path(args.material_meta).resolve() if args.material_meta else DOC / "fullbody-015/gpt/material-v2.json"
        if metadata.exists():
            meta = json.loads(metadata.read_text())
            if meta.get("sha256") == sha(self.material_path):
                self.material_rows = meta["rows"]
        # A generated band is painted on paper, not a perfect rectangular UV
        # strip. Map each column from its actual colored bank into its lumen;
        # the former y=.012*band-height sampled white at artery y0..8 and made
        # a dotted paper seam along otherwise valid frozen blood footprints.
        self.material_profiles = {}
        for system, (lo, hi) in self.material_rows.items():
            low, high = int(math.ceil(lo)), int(math.floor(hi))
            rgb = self.atlas[low:high, :, :3].astype(np.int16)
            r,g,b = rgb[:, :, 0],rgb[:, :, 1],rgb[:, :, 2]
            color = ((r-g>=18)&(r-b>=10) if system=='artery' else
                     (b-g>=10)&(b-r>=3) if system=='vein' else
                     (r-g>=15)&(b-g>=9))
            valid = color.any(axis=0)
            assert valid.all(), f'GPT {system} band has an empty color column'
            top = low + color.argmax(axis=0)
            bottom = high-1 - color[::-1].argmax(axis=0)
            self.material_profiles[system] = (top, bottom)
        self.pipe_spec = json.loads(Path(args.pipe_materials).read_text()) if args.pipe_materials else None
        self.pipe_sources = {}
        self.boundary_uv_cache = {}
        if self.pipe_spec:
            for system, item in self.pipe_spec['materials'].items():
                path=Path(item['path']);path=path if path.is_absolute() else ROOT/path
                assert sha(path)==item['sha256'], f'GPT {system} pipe source SHA changed'
                source=np.asarray(Image.open(path).convert('RGBA'))
                x1,y1,x2,y2=item['crop'];source=source[y1:y2,x1:x2].copy()
                colored=source[:,:,3]>=248
                assert colored.any(axis=0).all(), f'{system} pipe has nonopaque UV columns'
                top=colored.argmax(axis=0);bottom=source.shape[0]-1-colored[::-1].argmax(axis=0)
                # Texture alpha only registers the two generated outer lines.
                # Frozen physical route masks still own geometry and collision.
                ny,nx=np.mgrid[:source.shape[0],:source.shape[1]]
                normalized_y=top[None,:]+.75+(ny/(source.shape[0]-1))*np.maximum(0,bottom-top-1.5)[None,:]
                normalized=np.stack([map_coordinates(source[:,:,c].astype(np.float32),[normalized_y,nx],order=1,mode='nearest')for c in range(3)],axis=2)
                self.pipe_sources[system]=dict(item,array=source,top=top,bottom=bottom,path=path,normalized=np.clip(np.rint(normalized),0,255).astype(np.uint8),filtered={})
        self.junction_spec = json.loads(Path(args.junctions).read_text()) if args.junctions else {"junctions": []}
        if 'patches' in self.junction_spec and 'junctions' not in self.junction_spec:
            self.junction_spec['junctions']=self.junction_spec['patches']
        self.foreground_spec=json.loads(Path(args.foreground_patches).read_text()) if args.foreground_patches else self.junction_spec
        self.inputs = {str(p.relative_to(ROOT)): sha(p) for p in [
            DOC / "final-reference-data.json", DOC / "registered-vessels/geometry.json",
            DOC / "organ-atlas/art.json", ROOT / "scripts/war/OrganBoundariesData.lua", SOURCE,
            Path(__file__).resolve(),
        ]}
        self.inputs[str(self.material_path.relative_to(ROOT))] = sha(self.material_path)
        for meta_path in [args.junctions,args.foreground_patches]:
            if meta_path:
                meta_path=Path(meta_path).resolve();self.inputs[str(meta_path.relative_to(ROOT))]=sha(meta_path)
        for path,digest in self.junction_spec.get('inputs',{}).items():
            assert sha(ROOT/path)==digest,'patch input metadata changed';self.inputs[path]=digest
        if args.pipe_materials:
            self.inputs[str(Path(args.pipe_materials).resolve().relative_to(ROOT))]=sha(args.pipe_materials)
            for source in self.pipe_sources.values():self.inputs[str(source['path'].relative_to(ROOT))]=sha(source['path'])
        self.organs = {}
        for o in self.art["organs"]:
            oid = o["organId"]
            gp = DOC / ("stomach-playable/layout.json" if oid == "stomach" else f"organ-atlas/geometry/{oid}.json")
            g = json.loads(gp.read_text())
            ap = ROOT / ("assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png"
                         if oid == "stomach" else f"assets/image/anatomy-reference/vascular-study/organ-atlas/{oid}/battlefield.png")
            self.inputs[str(gp.relative_to(ROOT))] = sha(gp)
            self.inputs[str(ap.relative_to(ROOT))] = sha(ap)
            outer = rings_geometry(g["outerRings"])
            reserved = rings_geometry(g["foodRings"] if oid == "stomach" else g["foodAirUrineRings"])
            walls = rings_geometry(g["wallRings"])
            owned = {e["id"] for e in g.get("frozenBloodEdges", [])}
            if oid == "stomach":
                owned = {e["id"] for e in self.final["edges"]
                         if e["a"].startswith("stomach.") or e["b"].startswith("stomach.")}
            self.organs[oid] = dict(id=oid, sourceBox=o["sourceBox"], geometry=g, base=ap,
                                    outer=outer, reserved=reserved, walls=walls,
                                    ownEdges=owned)
        self.outer_union = unary_union([o["outer"] for o in self.organs.values()])
        # Exact, independently positioned lumen exclusions. Deep foreign paths
        # remain separate planes, but no painted blood is allowed on a food/air/
        # urine foreground. Local pixel-derived airway masks are also included.
        self.protected_regions = [dict(id=p["id"], system=p["system"],
                                       geometry=LineString(p["points"]).buffer(p["width"]/2+.15, cap_style=2))
                                  for p in self.final["protectedPassages"] if len(p["points"]) > 1]
        for o in self.organs.values():
            if not o["reserved"].is_empty:
                self.protected_regions.append(dict(id=o["id"]+".reserved", system="food" if o["id"] in
                                                   ["stomach","small_intestine","large_intestine"] else
                                                   "air" if o["id"].startswith("lung") else "urine" if
                                                   o["id"]=="bladder" else "organ-reserve", geometry=o["reserved"]))
        passage_shapes = [p["geometry"] for p in self.protected_regions]
        self.protected = unary_union(passage_shapes + [o["reserved"] for o in self.organs.values()])
        self.airway = svg_geometry(self.registered["airwayForegroundPath"])
        # Overview bladderForegroundPath deliberately covers the WHOLE intact
        # bladder. At command zoom its wall tissue is a playable organ plane;
        # only the independent urinary lumen remains protected foreground.
        self.bladder_core = self.organs["bladder"]["reserved"]
        self.protected = self.protected.union(self.airway).union(self.bladder_core)
        # Logical safety/depth and actual painted foreground have separate
        # contracts. Some source protected polygons cover ordinary pink floor,
        # so treating their border as a roof left floating capsules/rectangles.
        # Register the visible cream food/air/urine roof from accepted imagery,
        # constrained by that same frozen semantic candidate region. The actual
        # stomach food cavity stays protected in full, including yellow terrain.
        self.art_foreground,self.art_foreground_record=self.visible_foreground()
        self.mouth_foreground = self.art_foreground.buffer(.025)
        self.protected_regions.append(dict(id="reference.airway-foreground", system="air", geometry=self.airway))
        self.protected_clearance_cache = {}
        ignored = set(self.registered["displayContract"]["ignoredDeepCandidateOcclusionIds"])
        known = {e["id"]: e for e in self.registered["edges"]}
        self.edges = []
        self.node_edges = defaultdict(list)
        self.assets = []
        self.coverage = []
        self.junctions = []
        self.patch_usage = defaultdict(int)
        self.crossings = []
        self.shared_nodes = []
        for frozen in self.final["edges"]:
            e = dict(frozen)
            e["widthSource"] = e["lumenWidthSource"]
            e["line"] = LineString(e["samples"])
            e["full"] = stroke([e["line"]], e["widthSource"]/2)
            # Rounded ends are allowed only at original graph nodes.
            e["full"] = e["full"].union(Point(e["samples"][0]).buffer(e["widthSource"]/2)).union(
                Point(e["samples"][-1]).buffer(e["widthSource"]/2))
            # Physical material boundary precedes every display/foreground cut.
            # A view-plane cut must not sample an outer wall across the throat.
            e["materialFootprint"] = e["full"]
            if e["id"] in known:
                v = known[e["id"]]
                e["surface"] = svg_geometry(v["paintPath"])
                e["displaySegments"] = v["visibleSegments"]
                e["footprintBasis"] = "registered-fine-paintPath"
            else:
                intervals = []
                for q in self.final["occlusions"]:
                    if q["edgeId"] == e["id"] and q["id"] not in ignored:
                        intervals.append([q["startDistance"], q["endDistance"]])
                merged = []
                for a, b in sorted(intervals):
                    if merged and a <= merged[-1][1] + 1e-6:
                        merged[-1][1] = max(b, merged[-1][1])
                    else:
                        merged.append([a, b])
                parts = []
                at = 0
                for a, b in merged + [[e["line"].length, e["line"].length]]:
                    if a > at + 1e-6:
                        parts.append(substring(e["line"], at, a))
                    at = max(at, b)
                e["surface"] = stroke(parts, e["widthSource"]/2)
                for end in [e["samples"][0], e["samples"][-1]]:
                    if any(Point(end).distance(Point(p)) < .02 for line in parts for p in [line.coords[0], line.coords[-1]]):
                        e["surface"] = e["surface"].union(Point(end).buffer(e["widthSource"]/2))
                e["displaySegments"] = [list(map(list, line.coords)) for line in parts]
                e["footprintBasis"] = "frozen-samples-width-and-reviewed-occlusion-complement"
            e["surface"] = e["surface"].difference(self.art_foreground)
            e["full"] = e["full"].difference(self.art_foreground)
            # Foreground intersections are genuine underpasses, not a new
            # graph connection to food/air/urine. A hidden tube CENTER must not
            # leave its shaved-off rim as a sharp triangular shard. Unit-depth
            # intervals remain the original conservative clearance contract.
            # Display mouths use transverse contact, independently below.
            clearance = e["widthSource"]/2+.08
            if clearance not in self.protected_clearance_cache:
                self.protected_clearance_cache[clearance] = self.protected.buffer(clearance)
            full_width_hidden = self.protected_clearance_cache[clearance]
            e["protectedForegroundIntervals"] = []
            for part in line_parts(e["line"].intersection(full_width_hidden)):
                a,b=sorted([e["line"].project(Point(part.coords[0])),e["line"].project(Point(part.coords[-1]))])
                if b-a <= 1e-5:
                    continue
                region_ids=[p["id"] for p in self.protected_regions if p["geometry"].distance(part)<=clearance+1e-6]
                e["protectedForegroundIntervals"].append(dict(startDistance=a,endDistance=b,
                    sourceStart=list(e["line"].interpolate(a).coords[0]), sourceEnd=list(e["line"].interpolate(b).coords[0]),
                    foregroundIds=region_ids, unitDepth="under-foreground", connectsToForeground=False,
                    reason="full-width tube hidden beneath reserved foreground; rounded mouth retained before crossing"))
            if e["protectedForegroundIntervals"]:
                # The FOREGROUND'S actual flat plane, not an artificial
                # perpendicular cap, shapes the mouth. This lets both side
                # banks meet its visible lip even at an oblique crossing.
                # Discard detached off-center rim fragments beneath that roof;
                # keep every component containing a visible route center.
                visible_centers=e['line'].difference(self.art_foreground)
                supported=[p for p in polygons(e['full'])
                           if p.intersection(visible_centers).length>1e-5]
                owned=remove_numeric_slivers(unary_union(supported))
                old_area = e["full"].area
                e["full"] = owned
                e["surface"] = e["surface"].intersection(e["full"])
                e["protectedOcclusionRimRemovedArea"] = max(0,old_area-owned.area)
            e['visualForegroundIntervals']=foreground_intervals(e['line'],self.mouth_foreground,self.protected_regions)
            e['openMouthIntervals']=foreground_intervals(e['line'],self.art_foreground,self.protected_regions)
            # Fixed precision is 0.00001 SOURCE px (0.000096 logical px at
            # .15). It prevents GEOS overlay failures at exactly shared edges;
            # frozen sampled centerlines and navigation remain untouched.
            e["full"] = set_precision(remove_numeric_slivers(e["full"]), .00001)
            e["surface"] = set_precision(remove_numeric_slivers(e["surface"]), .00001)
            # A tiny paint-plane overlap stays strictly INSIDE the same blood
            # footprint. Two complementary AA masks otherwise provide only
            # 75% coverage at an organ border and expose its old outline through
            # a real fixed vascular gate. This is filtering gutter, not width.
            e["exterior"] = e["full"].difference(self.outer_union.buffer(-.22))
            e["deep"] = e["full"].intersection(self.outer_union.buffer(.22))
            # An organ's own circulation is baked into its accepted floor.
            # Foreign trunks remain on the independent deep command plane.
            # Subtract the whole named ownership area, not a slightly different
            # surface polygon: that former approach left thin AA ghost shards.
            for o in self.organs.values():
                if e["id"] in o["ownEdges"]:
                    e["deep"] = e["deep"].difference(o["outer"].buffer(.22))
            e["deep"] = remove_numeric_slivers(e["deep"])
            self.edges.append(e)
            self.node_edges[e["a"]].append((e, e["samples"][0]))
            self.node_edges[e["b"]].append((e, e["samples"][-1]))
        self.edge_by_id = {e["id"]: e for e in self.edges}
        # Share only TRUE named graph-node participants. Image-space crossings
        # never join this distance field. Material extends continuously through
        # protected display cuts while its independent alpha stays outside them.
        for e in self.edges:
            additional=[]
            for node in [e['a'],e['b']]:
                incident=self.node_edges[node]
                if len(incident)<2 or any(math.dist(incident[0][1],p)>.02 for _,p in incident):
                    continue
                radius=max(q['widthSource'] for q,_ in incident)*2.0
                zone=Point(incident[0][1]).buffer(radius)
                additional.extend(q['materialFootprint'].intersection(zone) for q,_ in incident)
            e['continuousMaterialFootprint']=unary_union([e['materialFootprint'],*additional])
        # An under-route is clipped at exact authored crossing intervals. The
        # over-route receives its own continuous banks, never a merged junction.
        for crossing in self.final["crossings"]:
            under, over = self.edge_by_id[crossing["under"]], self.edge_by_id[crossing["over"]]
            x = Point(crossing["source"])
            zone = over["full"].buffer(.28).intersection(x.buffer(max(over["widthSource"], under["widthSource"])*2))
            for key in ["full", "surface", "exterior", "deep"]:
                under[key] = under[key].difference(zone)
            self.crossings.append(dict(**crossing, cutAreaSource=round(zone.area, 6),
                                       compositing="under clipped by over bank footprint; no graph connection"))
        # Organ-owned blood is already present in the organ image, but that
        # image is drawn BEFORE the independent deep command plane. Omitting
        # an owned high-layer edge from deep lets a lower-layer foreign trunk
        # overpaint half of it (e188 over e134 at small_intestine.exit). Restore
        # only those real overlapping fixed footprints to the existing deep
        # plane, then the normal global layer ordering applies to both routes.
        # This adds no body domains, no new tiles, and no projected connections.
        deep_domain = unary_union([e['deep'] for e in self.edges]).buffer(.22)
        self.deep_ownership_repairs = []
        for e in self.edges:
            restored = remove_numeric_slivers(e['full'].intersection(deep_domain).difference(e['deep']))
            if restored.is_empty:
                continue
            e['deep'] = remove_numeric_slivers(e['deep'].union(restored))
            self.deep_ownership_repairs.append(dict(edgeId=e['id'], layer=e['layer'],
                areaSource=restored.area, geometrySourcePath=geometry_path(restored),
                reason='preserve fixed global blood layer order across organ-image/deep-plane split'))
        self.assign_pipe_phases()

    def assign_pipe_phases(self):
        """Immutable graph anchors, not viewport/RNG, own the material phase."""
        phases={};self.pipe_phase_anchors=[]
        for root in sorted(self.node_edges):
            if root in phases:continue
            phases[root]=0.;queue=[root];self.pipe_phase_anchors.append(root)
            while queue:
                node=queue.pop(0)
                for e,_ in sorted(self.node_edges[node],key=lambda ep:ep[0]['id']):
                    other=e['b'] if node==e['a'] else e['a']
                    if other not in phases:
                        phases[other]=phases[node]+e['line'].length;queue.append(other)
        for e in self.edges:
            e['pipePhaseSource']=phases[e['a']]
            e['pipeDirection']=1. if phases[e['b']]>=phases[e['a']] else -1.
            points=np.asarray(e['samples'],np.float64)
            vec=points[1:]-points[:-1];length=np.linalg.norm(vec,axis=1)
            keep=length>1e-10
            e['uvStarts']=points[:-1][keep];e['uvVectors']=vec[keep];e['uvLengths']=length[keep]
            e['uvArcStarts']=np.r_[0.,np.cumsum(length)][:-1][keep]
            # Midpoint lookup followed by exact neighbouring segment projection.
            e['uvTree']=cKDTree((points[:-1]+points[1:])[keep]*.5)

    def visible_foreground(self):
        if self.args.foreground_guides:
            guide_path=Path(self.args.foreground_guides).resolve()
            guides=json.loads(guide_path.read_text())
            path=ROOT/guides['sharedForegroundSvgPath']
            match=re.search(r'<path[^>]* d="([^"]+)"',path.read_text())
            assert match, 'Explicit shared foreground source SVG lacks path geometry'
            geometry=set_precision(remove_numeric_slivers(svg_geometry(match.group(1))),.00001)
            bounds=safe_bounds(geometry,1);scale=16
            target=ASSET/'masks/actual-art-foreground-v4.png'
            pixels=mask(geometry,bounds,[round((bounds[2]-bounds[0])*scale),round((bounds[3]-bounds[1])*scale)])
            save_png(pixels,target)
            quiet=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'
            record=dict(schema='fullbody-actual-foreground/v4',sourceBox=bounds,
                        pixelSize=[pixels.shape[1],pixels.shape[0]],registrationScale=scale,
                        path=str(target.relative_to(ROOT)),sha256=sha(target),maskEncoding='gray-L',
                        geometrySvgPath=str(path.relative_to(ROOT)),geometrySvgSha256=sha(path),
                        guideContractPath=str(guide_path.relative_to(ROOT)),guideContractSha256=sha(guide_path),
                        logicalGeometrySha256=sha(DOC/'final-reference-data.json'),
                        quietBasePath=str(quiet.relative_to(ROOT)),quietBaseSha256=sha(quiet),
                        acceptedOrganInputs=[dict(id=o['id'],path=str(o['base'].relative_to(ROOT)),sha256=sha(o['base']),sourceBox=o['sourceBox'])for o in self.organs.values()],
                        formula='Explicit registered visible lip SVG, shared by foreground raster / blood clip / open-mouth / display-depth; no generated-pigment inference',
                        localDisplayRoundingSource=guides['localDisplayRoundingSource'],
                        scopeSourceBoxes=guides['scopeSourceBoxes'],displayMaskRevision=guides.get('displayRevision',1),
                        displayMaskExceptions=guides.get('displayMaskExceptions',[]),
                        displayContourSimplifySource=guides.get('displayContourSimplifySource',0),
                        displayHoleMinimumAreaSource=guides.get('displayHoleMinimumAreaSource',0),
                        airwayRoofRepair=guides.get('airwayRoofRepair'),
                        archOrdinaryFloorException=guides.get('archOrdinaryFloorException'),
                        organOrdinaryFloorExceptions=guides.get('organOrdinaryFloorExceptions',[]),
                        archFullCropAirRoofException=guides.get('archFullCropAirRoofException'),
                        gastricOutsideForegroundException=guides.get('gastricOutsideForegroundException'),
                        canonicalAirwayBuffer=dict(capStyle=1,joinStyle=1,quadSegs=24,precisionSource=.00001),
                        generatorInputGuideManifestSha256=guides.get('guideInputsManifestSha256',sha(guide_path)),
                        visualUnitDepthGuardSource=.025,
                        logicalUnitDepthIntervalsUnchanged=True,generatedColorsDefineCollision=False)
            self.foreground_guides=guides
            self.inputs[str(guide_path.relative_to(ROOT))]=sha(guide_path)
            self.inputs[str(path.relative_to(ROOT))]=sha(path)
            (OUT/'fourth-repair').mkdir(parents=True,exist_ok=True)
            (OUT/'fourth-repair/actual-art-foreground-v4.json').write_text(json.dumps(record,indent=2)+'\n')
            return geometry,record
        quiet=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'
        b=safe_bounds(self.protected,1);scale=4
        size=[round((b[2]-b[0])*scale),round((b[3]-b[1])*scale)]
        canvas=Image.open(quiet).convert('RGBA').transform(tuple(size),Image.Transform.AFFINE,
                    (1/scale,0,b[0],0,1/scale,b[1]),resample=Image.Resampling.BILINEAR)
        for o in self.organs.values():
            q=o['sourceBox'];im=Image.open(o['base']).convert('RGBA')
            sx,sy=im.width/(q[2]-q[0]),im.height/(q[3]-q[1])
            layer=im.transform(tuple(size),Image.Transform.AFFINE,
                       (sx/scale,0,(b[0]-q[0])*sx,0,sy/scale,(b[1]-q[1])*sy),resample=Image.Resampling.BILINEAR)
            canvas=Image.alpha_composite(canvas,layer)
        rgb=np.asarray(canvas)[:,:,:3].astype(np.int16)
        red,green,blue=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
        candidate_alpha=mask(self.protected,b,size)
        candidate=candidate_alpha>127
        # Warm cream is distinct from pink tissue. Morphological closing seals
        # low-contrast texture flecks inside a visible roof, not gaps between
        # independent systems. Stomach's colored food cavity is explicit below.
        cream=(red>155)&(green>140)&(red-green<48)&(green-blue>17)&(red-blue>30)
        selected=binary_closing(candidate&cream,iterations=2)&candidate
        geometry=raster_runs_geometry(selected,b,scale).buffer(.10,join_style=1).intersection(self.protected)
        geometry=geometry.union(self.organs['stomach']['reserved'])
        geometry=set_precision(remove_numeric_slivers(geometry),.00001)
        path=ASSET/'masks/actual-art-foreground-v3.png'
        candidate_path=ASSET/'masks/actual-art-logical-candidate-v3.png'
        save_png(candidate_alpha,candidate_path)
        # Independent source-canvas mask can be decoded by QA without deriving
        # protection from the newly baked output image.
        full=mask(geometry,[0,0,1024,1536],[4096,6144])
        save_png(full,path)
        record=dict(schema='fullbody-actual-foreground/v3',sourceBox=[0,0,1024,1536],pixelSize=[4096,6144],
                    path=str(path.relative_to(ROOT)),sha256=sha(path),registrationScale=4,
                    logicalGeometrySha256=sha(DOC/'final-reference-data.json'),
                    quietBasePath=str(quiet.relative_to(ROOT)),quietBaseSha256=sha(quiet),
                    acceptedOrganInputs=[dict(id=o['id'],path=str(o['base'].relative_to(ROOT)),sha256=sha(o['base']),sourceBox=o['sourceBox'])for o in self.organs.values()],
                    formula='warm-cream pigment inside frozen logical protection + complete stomach food cavity; binary closing2 at4x, .10source-px coverage guard; mouth matches actual foreground plane without perpendicular cap',
                    creamClassifier=dict(redMinimum=155,greenMinimum=140,redMinusGreenMaximum=48,greenMinusBlueMinimum=17,redMinusBlueMinimum=30,comparisons='strict > and <'),
                    binaryClosingIterations=2,rowRunSimplifySource=.06,foregroundBufferSource=.10,
                    maskSimplifySource=.008,precisionSource=.00001,
                    compositionOrder=['quiet-base','liver','kidney_r','kidney_l','lung_r','lung_l','heart','brain','pancreas','bladder','small_intestine','large_intestine','stomach'],
                    candidateSourceBox=b,candidatePixelSize=size,candidateMembership='logical geometry alpha>127 at texel centers; CairoSVG evenodd raster',
                    candidatePath=str(candidate_path.relative_to(ROOT)),candidateSha256=sha(candidate_path),
                    geometryConversion='binary row-run boxes at4x→union→simplify .06 source-px preserving topology→buffer .10 source-px clipped to logical geometry→union full stomach food cavity→precision .00001',
                    visualUnitDepthGuardSource=.025,alphaProtection='actualArtForeground alpha255 pixels copied from accepted floors / external+deep zeroed; visible unit interval at geometric foreground +.025 source-px',
                    logicalUnitDepthIntervalsUnchanged=True,generatedColorsDefineCollision=False,
                    rawCreamPixels=int(np.sum(candidate&cream)),actualForegroundAreaSource=geometry.area,
                    logicalForegroundAreaSource=self.protected.area)
        (OUT/'third-repair').mkdir(parents=True,exist_ok=True)
        (OUT/'third-repair/actual-art-foreground-v3.json').write_text(json.dumps(record,indent=2)+'\n')
        return geometry,record

    def material(self, shape, bounds, size, system, width=None, edge=None):
        """Sample GPT floor/banks using the external boundary of one footprint."""
        if self.pipe_sources and edge is not None:
            return self.pipe_material(shape,bounds,size,system,width,edge)
        if shape.is_empty:
            return np.zeros((size[1], size[0], 4), dtype=np.uint8)
        alpha = mask(shape, bounds, size)
        inside = alpha > 127
        sx = (bounds[2]-bounds[0])/size[0]
        sy = (bounds[3]-bounds[1])/size[1]
        distance = distance_transform_edt(inside, sampling=(sy, sx))
        # Quiet tube center uses the center of the GPT row. The narrow wall
        # strip depends on UNION boundary distance, hence no internal end caps.
        bank = max(.10, min(.45, (width or 3)*.12))
        t = np.minimum(distance / bank, 1)
        h, w = self.atlas.shape[:2]
        lo, hi = self.material_rows.get(system, self.material_rows["capillary"])
        ys, xs = np.mgrid[:size[1], :size[0]]
        u = ((bounds[0]+(xs+.5)*sx)*13 + (bounds[1]+(ys+.5)*sy)*7) % max(1, w-2)
        column = u.astype(np.int32)
        top,bottom = self.material_profiles.get(system, self.material_profiles['capillary'])
        first = top[column] + .5
        middle = (top[column]+bottom[column])*.5
        v = np.minimum(np.maximum((first+(middle-first)*t).astype(np.int32), top[column]), bottom[column])
        out = self.atlas[v, column].copy()
        out[:, :, 3] = (out[:, :, 3].astype(np.float32)*alpha/255).astype(np.uint8)
        out[alpha == 0, :3] = 0
        return out

    def pipe_material(self,shape,bounds,size,system,width,edge):
        """Complete GPT left bank / flat floor / right bank in frozen arc UV."""
        output=np.zeros((size[1],size[0],4),np.uint8)
        if shape.is_empty:return output
        alpha=mask(shape,bounds,size)
        iy,ix=np.nonzero(alpha>0)
        if len(ix)==0:return output
        sx=(bounds[2]-bounds[0])/size[0];sy=(bounds[3]-bounds[1])/size[1]
        points=np.column_stack([bounds[0]+(ix+.5)*sx,bounds[1]+(iy+.5)*sy])
        k=min(4,len(edge['uvLengths']))
        _,ids=edge['uvTree'].query(points,k=k,workers=1)
        if k==1:ids=ids[:,None]
        start=edge['uvStarts'][ids];vec=edge['uvVectors'][ids];length=edge['uvLengths'][ids]
        delta=points[:,None,:]-start
        t=np.clip(np.sum(delta*vec,axis=2)/(length*length),0,1)
        offset=delta-t[:,:,None]*vec
        best=np.argmin(np.sum(offset*offset,axis=2),axis=1);row=np.arange(len(points))
        chosen=ids[row,best];local=offset[row,best]
        tangent=edge['uvVectors'][chosen]/edge['uvLengths'][chosen,None]
        signed=tangent[:,0]*local[:,1]-tangent[:,1]*local[:,0]
        arc=edge['uvArcStarts'][chosen]+t[row,best]*edge['uvLengths'][chosen]
        # Banks use precise SOURCE boundary segments, not the6x binary EDT.
        # Quantized distance formerly turned a continuous GPT wall into dotted
        # stitches, especially on oblique tubes. Dense segment lookup keeps
        # filtering/tile/foreground cuts outside this physical wall domain.
        distance=self.pipe_boundary_distance(shape,points)
        src=self.pipe_sources[system];flo,fhi=src.get('floorRangeNormalized',[.14,.86])
        radius=(width or 3)/2
        bank=max(.15,min(radius*.28,(width or 3)*max(flo,1-fhi)))
        side=np.where(signed<0,-1.,1.)
        floor_position=np.clip(.5+signed/(2*max(.05,radius-bank)),0,1)
        v=flo+(fhi-flo)*floor_position
        # Another incident branch can lie far from the chosen dominant UV
        # centerline while still INSIDE the true union floor. Clamping that
        # signed coordinate to a floor edge sampled a dark inner-wall stripe
        # across the open node. Use flat central lumen there; only precise
        # union-boundary distance is allowed to classify an outer bank.
        v=np.where((distance>=bank)&(np.abs(signed)>radius-bank),.5,v)
        if edge.get('flatUnionFloor'):
            # A real node is one flat open lumen. Its floor does not inherit
            # the dominant branch's side-bank UV at an oblique merge.
            v=np.where(distance>=bank,.5,v)
        depth=np.clip(distance/bank,0,1)
        boundary_v=np.where(side<0,flo*depth,1-(1-fhi)*depth)
        v=np.where(distance<bank,boundary_v,v)
        # The original1536px pipe is repeated over18sourcepx. At6x output,
        # unfiltered point samples compress14texels into one pixel and alias
        # the hand-drawn wall into speckles. Area-prefilter actual GPT pixels
        # in registered UV before the final bilinear sample; no wall repaint.
        filter_key=(round(width or 3,5),round(sx,6),round(sy,6))
        if filter_key not in src['filtered']:
            density=1/min(sx,sy)
            filtered_size=(max(8,math.ceil(src.get('repeatSourceLength',18)*density)),max(8,math.ceil((width or 3)*density)))
            src['filtered'][filter_key]=np.asarray(Image.fromarray(src['normalized']).resize(filtered_size,Image.Resampling.BOX)).copy()
        image=src['filtered'][filter_key];h,w=image.shape[:2]
        u=((edge['pipePhaseSource']+edge['pipeDirection']*arc)/src.get('repeatSourceLength',18)*w)%w
        texture_y=np.clip(v*h-.5,0,h-1)
        for channel in range(3):
            sampled=map_coordinates(image[:,:,channel].astype(np.float32),[texture_y,u],order=1,mode='nearest',prefilter=False)
            output[iy,ix,channel]=np.clip(np.rint(sampled),0,255).astype(np.uint8)
        output[:,:,3]=alpha
        return output

    def pipe_boundary_distance(self,shape,points):
        """Exact registered pipe-boundary distance, independent of raster cuts."""
        key=hash(shape.wkb)
        if key not in self.boundary_uv_cache:
            starts=[];vectors=[]
            for polygon in polygons(shape):
                for ring in [polygon.exterior,*polygon.interiors]:
                    xy=np.asarray(ring.coords,np.float64)
                    for a,b in zip(xy[:-1],xy[1:]):
                        count=max(1,math.ceil(np.linalg.norm(b-a)/.5))
                        subdivided=np.linspace(a,b,count+1)
                        starts.extend(subdivided[:-1]);vectors.extend(np.diff(subdivided,axis=0))
            bs,bv=np.asarray(starts),np.asarray(vectors)
            lengths=np.sum(bv*bv,axis=1);good=lengths>1e-16;bs,bv,lengths=bs[good],bv[good],lengths[good]
            self.boundary_uv_cache[key]=(bs,bv,lengths,cKDTree(bs+bv*.5))
        bs,bv,bl,tree=self.boundary_uv_cache[key]
        _,bid=tree.query(points,k=min(8,len(bl)),workers=1)
        if bid.ndim==1:bid=bid[:,None]
        delta=points[:,None,:]-bs[bid]
        bt=np.clip(np.sum(delta*bv[bid],axis=2)/bl[bid],0,1)
        return np.sqrt(np.min(np.sum((delta-bt[:,:,None]*bv[bid])**2,axis=2),axis=1))

    def mouth_inner_tint(self, raster, edge, bounds, size):
        """Very shallow floor tint at an open UNDERPASS; never a cap wall.

        Use the same GPT floor pixels and leave both longitudinal banks intact.
        The last fraction of a source pixel becomes slightly quieter where it
        goes under the foreground. No new pixels/port/connection are invented.
        """
        mouths=edge.get('openMouthIntervals',[])
        if not mouths: return raster
        sx,sy=(bounds[2]-bounds[0])/size[0],(bounds[3]-bounds[1])/size[1]
        ys,xs=np.mgrid[:size[1],:size[0]]
        px,py=bounds[0]+(xs+.5)*sx,bounds[1]+(ys+.5)*sy
        tint=np.zeros((size[1],size[0]),dtype=np.float32)
        radius=edge['widthSource']/2
        reach=max(.22,min(.75,radius*.45))
        for mouth in mouths:
            for key,direction in [('startDistance',1),('endDistance',-1)]:
                at=mouth[key]
                if at<1e-5 or at>edge['line'].length-1e-5: continue
                p=edge['line'].interpolate(at)
                if p.x<bounds[0]-reach-radius or p.x>bounds[2]+reach+radius or p.y<bounds[1]-reach-radius or p.y>bounds[3]+reach+radius: continue
                before=edge['line'].interpolate(max(0,at-.08));after=edge['line'].interpolate(min(edge['line'].length,at+.08))
                dx,dy=after.x-before.x,after.y-before.y;length=math.hypot(dx,dy)
                if length<1e-8: continue
                tx,ty=dx/length,dy/length
                along=((px-p.x)*tx+(py-p.y)*ty)*direction
                across=np.abs(-(px-p.x)*ty+(py-p.y)*tx)
                throat=np.clip((radius-.10-across)/max(.15,radius*.2),0,1)
                fade=np.clip(1+along/reach,0,1)*(along<=.025)
                tint=np.maximum(tint,fade*throat)
        raster[:,:,:3]=np.rint(raster[:,:,:3]*(1-.055*tint[:,:,None])).astype(np.uint8)
        return raster

    def render_layer(self, shape_key, bounds, size, allowed=None, clip=None):
        output = np.zeros((size[1], size[0], 4), dtype=np.uint8)
        # Expected material follows the frozen layer/node ownership, not a
        # global OR of artery/vein masks at a projected crossing.
        type_ids={'artery':1,'vein':2,'capillary':3}
        paint_owner=np.zeros((size[1],size[0]),np.uint8)
        crop = box(*bounds)
        geometry_union = []
        used = []
        for e in sorted(self.edges, key=lambda q: (q["layer"], q["id"])):
            if allowed is not None and e["id"] not in allowed:
                continue
            shape = area_intersection(e[shape_key],crop)
            if clip is not None:
                shape = area_intersection(shape,clip)
            if shape.is_empty:
                continue
            # The material's banks belong to the complete vessel footprint.
            # Organ/deep/tile crop boundaries are NOT new vessel end walls.
            # Compute material before masking those display-plane boundaries.
            fg = self.material(e["continuousMaterialFootprint"], bounds, size, e["system"], e["widthSource"],edge=e)
            fg = self.mouth_inner_tint(fg,e,bounds,size)
            fg[:, :, 3] = np.minimum(fg[:, :, 3], mask(shape, bounds, size))
            output = alpha_over(output, fg)
            paint_owner[fg[:,:,3]>127]=type_ids[e['system']]
            geometry_union.append(shape)
            used.append(e["id"])
        # Every real named connection gets one open boundary. This removes the
        # internal wall stripes which separate per-edge stamps at a Y/T join.
        for node, incident in self.node_edges.items():
            incident = [(e, p) for e, p in incident if allowed is None or e["id"] in allowed]
            if len(incident) < 2:
                continue
            point = Point(incident[0][1])
            if any(point.distance(Point(p)) > .02 for _, p in incident):
                continue
            radius = max(e["widthSource"] for e, _ in incident)*2.0
            zone = point.buffer(radius)
            if not zone.intersects(crop):
                continue
            own = area_intersection(area_intersection(unary_union([e[shape_key] for e, _ in incident]),zone),crop)
            if clip is not None:
                own = area_intersection(own,clip)
            own=remove_numeric_slivers(own)
            if own.is_empty:
                continue
            # Pick the upstream largest tube's biological material. Color
            # transitions are quieter than extra banks obstructing the throat.
            dominant = max(incident, key=lambda ep: (ep[0]["widthSource"], ep[0]["system"] == "artery"))[0]
            full_union = unary_union([e["materialFootprint"] for e, _ in incident])
            node_edge=dict(dominant,flatUnionFloor=True)
            fg = self.material(full_union, bounds, size, dominant["system"], dominant["widthSource"],edge=node_edge)
            patch_alpha = mask(own, bounds, size)
            fg[:, :, 3] = np.minimum(fg[:, :, 3], patch_alpha)
            # Replace only this junction, avoiding opaque overpainting of an
            # unrelated foreground crossing at the same source position.
            for e in self.edges:
                if e["id"] not in {q["id"] for q, _ in incident} and e["layer"] > dominant["layer"]:
                    obscures = e[shape_key].intersection(own)
                    if not obscures.is_empty:
                        fg[:, :, 3] = np.minimum(fg[:, :, 3], 255-mask(obscures, bounds, size))
            # RGB replacement preserves the already-composited edge alpha.
            # An extra transparent stamp used to double its AA pixels and draw
            # a visible circular patch seam at the bank/strip handoff.
            sx,sy=(bounds[2]-bounds[0])/size[0],(bounds[3]-bounds[1])/size[1]
            ys,xs=np.mgrid[:size[1],:size[0]]
            dist=np.hypot(bounds[0]+(xs+.5)*sx-point.x,bounds[1]+(ys+.5)*sy-point.y)
            blend=np.clip((radius-dist)/max(.4,radius*.25),0,1)
            blend=blend*blend*(3-2*blend)
            weight=blend*(fg[:,:,3]/255)*(output[:,:,3]>0)
            output[:,:,:3]=np.rint(output[:,:,:3]*(1-weight[:,:,None])+fg[:,:,:3]*weight[:,:,None]).astype(np.uint8)
            paint_owner[weight>.5]=type_ids[dominant['system']]
        # GPT regional edits are applied after the continuous procedural
        # material mapping, strictly inside the same frozen vessel stencil.
        union = remove_numeric_slivers(unary_union(geometry_union))
        for item in sorted(self.junction_spec.get("junctions", []),key=lambda q:q.get('artOwnershipPriority',q.get('priority',50))):
            jb = item["sourceBox"]
            if not box(*jb).intersects(crop):
                continue
            target = Path(item["path"])
            if not target.is_absolute():
                target = ROOT / target
            if not target.exists():
                continue
            eligible = set(item.get("edgeIds", []))
            # A region guide may list its main visible segments only. Complete
            # their actual frozen node participants for clipping; never invent
            # a route simply because two strokes intersect in the image.
            expanded=set(eligible)
            for node,incident in self.node_edges.items():
                if any(e["id"] in eligible for e,_ in incident) and box(*jb).covers(Point(incident[0][1])):
                    expanded.update(e["id"]for e,_ in incident)
            eligible=expanded
            stencil = unary_union([e[shape_key] for e in self.edges if not eligible or e["id"] in eligible])
            # Generated tile edges are not authoritative joins. Limit regional
            # patches to true shared-node interiors, retaining authored channel
            # material at every fixed crop port and adjoining long segment.
            node_zones=[];node_blends=[]
            for node, incident in self.node_edges.items():
                picked=[(e,p)for e,p in incident if not eligible or e["id"] in eligible]
                if len(picked)>1 and all(math.dist(picked[0][1],p)<.02 for _,p in picked):
                    diameter=max(e["widthSource"]for e,_ in picked)
                    node_zones.append(Point(picked[0][1]).buffer(diameter*1.7))
                    node_blends.append((picked[0][1],diameter*1.7,max(1,diameter*.8)))
            complete=item.get('compositionMode')=='whole-pipe-and-foreground'
            patch=area_intersection(area_intersection(stencil,box(*jb)),union)
            if not complete:
                patch=area_intersection(patch,unary_union(node_zones))
            if patch.is_empty:
                continue
            im = Image.open(target).convert("RGBA")
            sw,sh=jb[2]-jb[0],jb[3]-jb[1]
            # SVG guides use xMidYMid meet on a square canvas. GPT preserves
            # that letterboxed content; crop it mathematically before mapping.
            factor=min(im.width/sw,im.height/sh)
            cw,ch=sw*factor,sh*factor
            cx,cy=(im.width-cw)/2,(im.height-ch)/2
            content=item.get("contentBox",[cx,cy,cx+cw,cy+ch])
            if item.get('guideContentRectNormalized'):
                content=[v*im.width for v in item['guideContentRectNormalized']]
            elif item.get('guideContentBox') and not item.get('contentBox'):
                content=[v*im.width/item.get('guidePixelSize',[1536,1536])[0]for v in item['guideContentBox']]
            cx,cy,cxx,cyy=content;cw,ch=cxx-cx,cyy-cy
            # Fixed source coordinates; no freehand rescale/re-fit.
            x, y, xx, yy = bounds
            coeff = ((xx-x)/size[0]*cw/sw, 0, cx+(x-jb[0])*cw/sw,
                     0, (yy-y)/size[1]*ch/sh, cy+(y-jb[1])*ch/sh)
            fg = np.asarray(im.transform(tuple(size), Image.Transform.AFFINE, coeff, resample=Image.Resampling.BILINEAR)).copy()
            fg[:, :, 3] = np.minimum(fg[:, :, 3], mask(patch, bounds, size))
            # Model backdrop/food/urine pixels never become vascular floor.
            # A guide's slight outline drift is tolerated by keeping the
            # already continuous GPT strip wherever the region is background.
            rgb=fg[:,:,:3].astype(np.int16);red,green,blue=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
            checks={"artery":(red-green>=22)&(red-blue>=8)&((green-blue)<=(red-blue)*.35),
                    "vein":(blue-green>=12)&(blue-red>=3),
                    "capillary":(red-green>=15)&(blue-green>=9)}
            if complete:
                # Regional generation can shift a pipe while keeping the
                # letterbox/camera. Its orange tissue backdrop must not erase
                # a correctly registered artery. These checks accept source
                # RGB as TEXTURE only: every footprint/port remains frozen.
                # Reject a misplaced dark raw bank inside the fixed open
                # lumen as well; the continuous whole GPT strip underneath
                # already supplies a complete, correctly placed wall/floor.
                checks['artery']=(red-green>=20)&(red-blue>=10)&(green-blue<=12)
            accepted=np.zeros((size[1],size[0]),dtype=bool)
            texture_confidence=np.ones((size[1],size[0]),dtype=np.float32)
            for system in ["artery","vein","capillary"]:
                typed_edges=[e for e in self.edges if e['id']in eligible and e['system']==system]
                typed=unary_union([e[shape_key]for e in typed_edges])
                belongs=(mask(area_intersection(typed,patch),bounds,size)>0)&(paint_owner==type_ids[system])
                valid=checks[system].copy()
                if complete and typed_edges and belongs.any():
                    yi,xi=np.nonzero(belongs)
                    sx,sy=(xx-x)/size[0],(yy-y)/size[1]
                    points=np.column_stack([x+(xi+.5)*sx,y+(yi+.5)*sy])
                    physical=unary_union([e['continuousMaterialFootprint']for e in typed_edges])
                    distance=self.pipe_boundary_distance(physical,points)
                    # Complete dark outer banks remain accepted. Only raw
                    # transverse/loop walls drifting through a flat lumen are
                    # rejected, without drawing another wall from code.
                    floor_uv=self.pipe_sources.get(system,{}).get('floorRangeNormalized',[.14,.86])
                    diameter=max(e['widthSource']for e in typed_edges)
                    wall=max(.15,min(diameter*.14,diameter*max(floor_uv[0],1-floor_uv[1])))
                    core=distance>wall+.12
                    # Generated inner rings/caps often remain fairly bright.
                    # They are thin, high-contrast strokes against the raw
                    # floor and darker than the registered GPT strip beneath.
                    # Reject only their misplaced core texture; true outside
                    # banks are still accepted as complete generated walls.
                    local_green=gaussian_filter(green.astype(np.float32),sigma=max(.7,.4/min(sx,sy)))
                    stroke=(local_green[yi,xi]-green[yi,xi]>6)&(output[yi,xi,1].astype(np.int16)-green[yi,xi]>9)
                    misplaced=core & ((green[yi,xi]<108)|stroke)
                    valid[yi[misplaced],xi[misplaced]]=False
                    # Complete raw outside banks remain eligible. Inside the
                    # gameplay floor, mix only quiet matching generated RGB.
                    # True nodes always use the open registered strip floor.
                    low_contrast=np.max(np.abs(rgb[yi,xi]-output[yi,xi,:3].astype(np.int16)),axis=1)<=18
                    texture_confidence[yi[core],xi[core]]=np.where(low_contrast[core],.3,0)
                    for pos,radius,transition in node_blends:
                        node_core=np.hypot(points[:,0]-pos[0],points[:,1]-pos[1])<radius*.88
                        texture_confidence[yi[core&node_core],xi[core&node_core]]=0
                accepted |= valid & belongs
            fg[:,:,3]=np.where(accepted,fg[:,:,3],0)
            # Longitudinal blend follows each true node's approach radius.
            # The entire outer bank remains the SAME continuous strip; GPT
            # patches influence only its interior floor, never a second bank.
            sx,sy=(xx-x)/size[0],(yy-y)/size[1]
            ys,xs=np.mgrid[:size[1],:size[0]]
            px,py=x+(xs+.5)*sx,y+(ys+.5)*sy
            blend=np.zeros((size[1],size[0]),dtype=np.float32)
            for pos,radius,transition in node_blends:
                t=np.clip((radius-np.hypot(px-pos[0],py-pos[1]))/transition,0,1)
                blend=np.maximum(blend,t*t*(3-2*t))
            interior=distance_transform_edt(mask(stencil,bounds,size)>127,sampling=(sy,sx))
            bank_blend=np.clip((interior-.45)/.35,0,1)
            color_blend=np.clip(distance_transform_edt(fg[:,:,3]>0,sampling=(sy,sx))/.65,0,1)
            if complete:
                # Whole GPT pipe replaces BOTH banks and its flat floor. The
                # only handoff is longitudinal at the fixed crop ports; no old
                # independent wall is retained through an actual node.
                distance_to_crop=np.minimum.reduce([px-jb[0],jb[2]-px,py-jb[1],jb[3]-py])
                transition=max(1.,max((e['widthSource']for e in self.edges if e['id']in eligible),default=3)*1.6)
                taper=np.clip(distance_to_crop/transition,0,1);taper=taper*taper*(3-2*taper)
                weight=taper*color_blend*texture_confidence*(fg[:,:,3]/255)*(output[:,:,3]>0)
            else:
                weight=blend*bank_blend*color_blend*(fg[:,:,3]/255)*(output[:,:,3]>0)
            self.patch_usage[item["id"]] += int(np.sum(weight>0))
            output[:,:,:3]=np.rint(output[:,:,:3]*(1-weight[:,:,None])+fg[:,:,:3]*weight[:,:,None]).astype(np.uint8)
        return output, used, union

    def guides(self):
        guide_dir = OUT / "junction-guides"
        guide_dir.mkdir(parents=True, exist_ok=True)
        specs = [
            ("arch", [489, 319, 564, 374], [514, 341], ["e008", "e009", "e153", "e156", "e158"]),
            ("celiac-stomach", [507, 472, 579, 540], [537, 489], ["e009", "e010", "e116", "e117", "e123", "e183", "e184"]),
            ("portal", [466, 516, 568, 589], [523, 561], ["e119", "e125", "e126", "e129", "e164", "e169", "e171"]),
            ("mesenteric", [451, 584, 578, 680], [524, 606], ["e011", "e012", "e127", "e128", "e129", "e130", "e132", "e136"]),
            ("pelvis", [463, 724, 558, 807], [509, 747], ["e012", "e013", "e038", "e039", "e088", "e089", "e140", "e142", "e197", "e198"]),
            ("lung-right", [439, 329, 524, 401], [475.161, 374.015], ["e002", "e005", "e006", "e007", "e172", "e173"]),
            ("kidney-right", [400, 550, 491, 649], [439, 606], ["e014", "e120", "e121", "e122", "e137", "e138", "e185", "e186"]),
        ]
        records = []
        encoded = base64.b64encode(SOURCE.read_bytes()).decode()
        palette = {"artery": "#cc898e", "vein": "#a89cc6", "capillary": "#c49fac"}
        for ident, bounds, center, edge_ids in specs:
            edges = [self.edge_by_id[i] for i in edge_ids if i in self.edge_by_id]
            x, y, xx, yy = bounds
            markup = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="1536" viewBox="{x} {y} {xx-x} {yy-y}">',
                      f'<rect x="{x}" y="{y}" width="{xx-x}" height="{yy-y}" fill="#eedbd2"/>',
                      f'<image width="1024" height="1536" opacity=".35" href="data:image/png;base64,{encoded}"/>']
            markup.append(paint(self.protected.intersection(box(*bounds)), "#ecd8b2", "#b59183", .16))
            for e in sorted(edges, key=lambda q: q["layer"]):
                # Guides intentionally show the continuous blood plane, with
                # protected foreground punched out. Native hidden route
                # interpretation is recorded separately, not erased from guide.
                markup.append(paint(e["full"].intersection(box(*bounds)), palette.get(e["system"], "#c49fac"), "#8d6970", .12))
            markup.append("</svg>")
            svg = "".join(markup)
            (guide_dir / (ident + ".svg")).write_text(svg)
            cairosvg.svg2png(bytestring=svg.encode(), write_to=str(guide_dir / (ident + ".png")))
            ports = []
            for e in edges:
                for piece in line_parts(e["line"].intersection(box(*bounds))):
                    for side in [0, 1]:
                        pts = list(piece.coords)
                        endpoint = pts[0] if side == 0 else pts[-1]
                        p = piece.interpolate(min(.4, piece.length/3) if side == 0 else max(0, piece.length-.4))
                        dx, dy = p.x-endpoint[0], p.y-endpoint[1]
                        length = math.hypot(dx, dy)
                        ports.append(dict(edgeId=e["id"], system=e["system"], source=list(endpoint),
                                          widthSource=e["widthSource"], directionIntoCrop=[dx/length, dy/length] if length else [0, 0],
                                          side="start" if side == 0 else "end", layer=e["layer"]))
            records.append(dict(id=ident, sourceBox=bounds, guidePath=str((guide_dir/(ident+".png")).relative_to(ROOT)),
                                centerSource=center, edgeIds=[e["id"] for e in edges], fixedPorts=ports,
                                instruction="GPT refine one complete connected region; preserve crop mapping, edge ports and reserved cream food/air/urine. Flat quiet surface, open unioned junctions, no new branches or green."))
        (guide_dir / "manifest.json").write_text(json.dumps(dict(schema="fullbody-vessel-junction-guides/v1", referenceSha256=sha(SOURCE),
                                                               finalReferenceSha256=sha(DOC/"final-reference-data.json"), junctions=records), ensure_ascii=False, indent=2)+"\n")
        return records

    def cleanup_masks(self):
        """Authoring candidates for ROOT's GPT vessel-free background edit.

        Source pigment + ORIGINAL reference routes constrain old arterial
        selection. New frozen routes are deliberately not a cleanup mask.
        This exports masks, never recolors the original raster itself.
        """
        sys.path.insert(0,"/tmp/passage-tools314")
        from lupa.lua54 import LuaRuntime
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute("package.path='"+str(ROOT/"scripts")+"/?.lua;'..package.path")
        vessels=lua.eval("require('war.ReferenceVessels')")
        vessels=vessels[0] if isinstance(vessels,tuple) else vessels
        trace=lua.eval("require('war.ReferenceTrace')")
        trace=trace[0] if isinstance(trace,tuple) else trace
        contour=Polygon([[trace.outline[i][1],trace.outline[i][2]] for i in range(1,len(trace.outline)+1)])
        arterial=[]
        for i in range(1,len(vessels.edges)+1):
            e=vessels.edges[i]
            if e.system!="artery":
                continue
            points=[[e.points[j][1]/2,(e.points[j][2]-512)/2]for j in range(1,len(e.points)+1)]
            arterial.append(LineString(points).buffer(e.width/2*.9+1.5,cap_style=1,join_style=1))
        b=[0,0,1024,1536];size=[1024,1536]
        rgb=np.asarray(Image.open(SOURCE).convert("RGB")).astype(np.int16)
        red,green,blue=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
        organ=mask(self.outer_union,b,size)>0
        protected=mask(self.protected,b,size)>0
        contour_guard=mask(contour.buffer(-2),b,size)>127
        corridor=mask(unary_union(arterial),b,size)>0
        old_blue=(blue-red>20)&(green-red>-30)&(blue>105)&~organ&~protected&contour_guard
        old_red=(red>145)&(red-green>45)&(red-blue>45)&corridor&~organ&~protected&contour_guard
        output=ASSET/"masks";output.mkdir(parents=True,exist_ok=True)
        records={}
        for name,selected in [("old-blue-external",old_blue),("old-red-corridor-external",old_red),
                              ("old-blood-candidate",old_blue|old_red),("protected-foreground",protected),
                              ("organ-foreground",organ),("body-interior-with-2px-guard",contour_guard)]:
            p=output/(name+".png");Image.fromarray(selected.astype(np.uint8)*255).save(p)
            records[name]=dict(path=str(p.relative_to(ROOT)),pixelSize=size,sha256=sha(p),pixels=int(np.sum(selected)))
        record=dict(schema="fullbody-old-source-vessel-cleanup-candidates/v1",sourceSize=size,sourceBox=b,
                    referenceSha256=sha(SOURCE),sourceTraceSha256=sha(ROOT/"scripts/war/ReferenceTrace.lua"),
                    originalVesselTraceSha256=sha(ROOT/"scripts/war/ReferenceVessels.lua"),
                    maskStatus="review-required candidate; red pigment restricted to independently traced ORIGINAL routes, never new 202 routes",
                    protection="12 organ silhouettes + precise food/air/urine + 2 source px body-outline guard",
                    masks=records)
        (OUT/"quietbase-mask-candidates.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n")
        print(json.dumps(record,ensure_ascii=False),flush=True)

    def tiles(self, role, shape_key):
        """Fixed grid partition, cropped to occupied bounds, with source gutter.

        Runtime must clip to coreBox; sourceBox includes 1px gutter so filtering
        across tile boundaries samples the exact same global material phase.
        """
        all_shape = unary_union([e[shape_key] for e in self.edges])
        for y in range(0, 1536, self.args.tile):
            for x in range(0, 1024, self.args.tile):
                core = [x, y, min(1024, x+self.args.tile), min(1536, y+self.args.tile)]
                occupied = all_shape.intersection(box(*core))
                if occupied.is_empty:
                    continue
                b = safe_bounds(occupied, 1)
                b = [max(core[0]-1, b[0]), max(core[1]-1, b[1]), min(core[2]+1, b[2]), min(core[3]+1, b[3])]
                size = [round((b[2]-b[0])*self.args.scale), round((b[3]-b[1])*self.args.scale)]
                raster, used, union = self.render_layer(shape_key, b, size)
                protected_mask=mask(self.art_foreground,b,size)
                raster[protected_mask==255]=0
                path = ASSET / role / f"{role}-{x:04d}-{y:04d}.png"
                save_png(raster, path)
                entry = asset_record(path, b, role, coreBox=core, edgeIds=used, alphaPixels=int(np.sum(raster[:,:,3]>0)),
                                     sourcePixelsPerTexel=1/self.args.scale, noAlphaAttenuation=True)
                self.assets.append(entry)
                print(f"tile {role} {x},{y} {len(used)} edges {size}", flush=True)

    def organ_floors(self):
        for oid, o in self.organs.items():
            b = o["sourceBox"]
            base = np.asarray(Image.open(o["base"]).convert("RGBA")).copy()
            size = [base.shape[1], base.shape[0]]
            own = o["ownEdges"]
            # Related organ blood planes stay inside the exact tissue silhouette
            # and outside local protected lumens. A foreign deep main trunk is
            # in a separate output layer, never spliced into the organ supply.
            clip = o["outer"].difference(self.art_foreground)
            raster, used, geom = self.render_layer("full", b, size, allowed=own)
            # Copy accepted base floor outside the tiny prior vascular AA guard.
            replace = geom.buffer(.10).intersection(clip)
            am = mask(replace, b, size)
            # New bank footprint owns same pixels. No unrelated floor, wall,
            # silhouette or food tint is re-rendered.
            candidate = alpha_over(base, raster)
            out = np.where((am>0)[:,:,None], candidate, base)
            # Do not accumulate source silhouette AA when drawing new blood
            # over the accepted organ. Preserve exact original alpha bytes.
            out[:,:,3]=base[:,:,3]
            logical_reserved_mask = mask(o["reserved"], b, size)
            protected_mask = mask(self.art_foreground.intersection(o['outer']), b, size)
            all_protected_mask = mask(self.art_foreground, b, size)
            out[(protected_mask==255)|(all_protected_mask==255)]=base[(protected_mask==255)|(all_protected_mask==255)]
            path = ASSET / "organs" / f"{oid}.png"
            save_png(out, path)
            mask_path = ASSET / "organs" / f"{oid}-blood-mask.png"
            save_png(np.dstack([am, am, am, am]), mask_path)
            self.assets.append(asset_record(path, b, "organ", organId=oid, basePath=str(o["base"].relative_to(ROOT)),
                                             edgeIds=used, replacementMaskPath=str(mask_path.relative_to(ROOT)),
                                             sourcePixelsPerTexel=(b[2]-b[0])/size[0],
                                             approvedFloorRetained=True, collisionEdited=False,
                                             gateCount=len(o["geometry"].get("proposedAccess", [])) if oid != "stomach" else 5))
            changed = np.any(out != base, axis=2)
            self.coverage.append(dict(organId=oid, edgeIds=used, unchangedOutsideReplacement=int(np.sum(changed & (am==0)))==0,
                                      protectedPixelsChanged=int(np.sum(changed & (protected_mask==255))),
                                      logicalReservedPixelsChanged=int(np.sum(changed & (logical_reserved_mask==255))),
                                      contourSourceUnchanged=True, acceptedFloorSha256=sha(o["base"]),
                                      outputSha256=sha(path), totalChangedPixels=int(np.sum(changed)),
                                      phase="complete whole-organ blood material replacement, same accepted floor and silhouette"))
            print(f"organ {oid} {len(used)} related edges {size}", flush=True)

    def accepted_floor(self,bounds,size):
        quiet=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'
        sx,sy=(bounds[2]-bounds[0])/size[0],(bounds[3]-bounds[1])/size[1]
        base=Image.open(quiet).convert('RGBA').transform(tuple(size),Image.Transform.AFFINE,(sx,0,bounds[0],0,sy,bounds[1]),resample=Image.Resampling.BILINEAR)
        for o in self.organs.values():
            b=o['sourceBox']
            if not box(*b).intersects(box(*bounds)):continue
            im=Image.open(o['base']).convert('RGBA');fx,fy=im.width/(b[2]-b[0]),im.height/(b[3]-b[1])
            layer=im.transform(tuple(size),Image.Transform.AFFINE,(sx*fx,0,(bounds[0]-b[0])*fx,0,sy*fy,(bounds[1]-b[1])*fy),resample=Image.Resampling.BILINEAR)
            base=Image.alpha_composite(base,layer)
        return np.asarray(base).copy()

    def foreground_patches(self):
        """Registered GPT lip texture, clipped by the SAME explicit source edge."""
        items=self.foreground_spec.get('foregroundPatches',self.foreground_spec.get('junctions',self.foreground_spec.get('patches',[])))
        selected=[q for q in items if q.get('compositionMode')=='whole-pipe-and-foreground']
        for item in sorted(selected,key=lambda q:q.get('artOwnershipPriority',q.get('priority',50))):
            path=Path(item['path']);path=path if path.is_absolute() else ROOT/path
            if not path.exists():continue
            b=item['sourceBox'];im=Image.open(path).convert('RGBA');sw,sh=b[2]-b[0],b[3]-b[1]
            factor=min(im.width/sw,im.height/sh);cw,ch=sw*factor,sh*factor;cx,cy=(im.width-cw)/2,(im.height-ch)/2
            content=item.get('contentBox',[cx,cy,cx+cw,cy+ch])
            if item.get('guideContentRectNormalized'):content=[v*im.width for v in item['guideContentRectNormalized']]
            elif item.get('guideContentBox') and not item.get('contentBox'):content=[v*im.width/item.get('guidePixelSize',[1536,1536])[0]for v in item['guideContentBox']]
            cx,cy,cxx,cyy=content;cw,ch=cxx-cx,cyy-cy
            # Keep generated effective resolution, crop off contain letterbox.
            size=[max(1,round(cw)),max(1,round(ch))]
            fg=np.asarray(im.transform(tuple(size),Image.Transform.AFFINE,(cw/size[0],0,cx,0,ch/size[1],cy),resample=Image.Resampling.BILINEAR)).copy()
            alpha=mask(self.art_foreground,b,size)
            # A fixed crop is not a new transverse foreground wall. Blend its
            # RGB into the accepted registered floor along the existing lip,
            # retaining the SAME full alpha edge for clipping and unit depth.
            yy,xx=np.mgrid[:size[1],:size[0]];px=b[0]+(xx+.5)*sw/size[0];py=b[1]+(yy+.5)*sh/size[1]
            edge_distance=np.minimum.reduce([px-b[0],b[2]-px,py-b[1],b[3]-py])
            transition=2.5
            taper=np.clip(edge_distance/transition,0,1);taper=taper*taper*(3-2*taper)
            accepted=self.accepted_floor(b,size)
            fg[:,:,:3]=np.rint(accepted[:,:,:3]*(1-taper[:,:,None])+fg[:,:,:3]*taper[:,:,None]).astype(np.uint8)
            fg[:,:,3]=alpha;fg[alpha==0,:3]=0
            target=ASSET/'foreground'/f"{item['id']}.png";save_png(fg,target)
            mpath=ASSET/'foreground'/f"{item['id']}-mask.png";save_png(alpha,mpath)
            self.assets.append(asset_record(target,b,'foreground',coreBox=b,rawPath=str(path.relative_to(ROOT)),rawSha256=sha(path),
                                           generatedContentBox=content,geometrySvgPath=self.art_foreground_record.get('geometrySvgPath'),
                                           geometrySvgSha256=self.art_foreground_record.get('geometrySvgSha256'),
                                           acceptedMaskPath=str(mpath.relative_to(ROOT)),acceptedMaskSha256=sha(mpath),acceptedMaskEncoding='gray-L',
                                           effectivePixelsPerSource=size[0]/sw,priority=item.get('artOwnershipPriority',item.get('priority',50)),
                                           depthBoundary='same explicit art_foreground +.025source unit-center guard',cropRGBBlendSource=2.5,alphaBlend=False,collisionEdited=False))
            self.inputs[str(path.relative_to(ROOT))]=sha(path)
            print(f"foreground {item['id']} {size}",flush=True)

    def finish(self, guides):
        edge_records = []
        for e in self.edges:
            assets = [a["resource"] for a in self.assets if e["id"] in a.get("edgeIds", [])]
            edge_records.append(dict(id=e["id"], a=e["a"], b=e["b"], system=e["system"], layer=e["layer"],
                                     widthSource=e["widthSource"], basis=e["footprintBasis"],
                                     fullLengthSource=e["line"].length, surfaceAreaSource=e["surface"].area,
                                     exteriorAreaSource=e["exterior"].area, deepAreaSource=e["deep"].area,
                                     originalVisibleLengthSource=sum(LineString(p).length for p in e["visibleSegments"]),
                                     assets=assets, covered=bool(assets),
                                     hiddenByProtectedAreaSource=stroke([e["line"]],e["widthSource"]/2).intersection(self.protected).area,
                                     protectedOcclusionRimRemovedArea=e.get("protectedOcclusionRimRemovedArea",0),
                                     protectedForegroundIntervals=e["protectedForegroundIntervals"],
                                     openMouthIntervals=e.get('openMouthIntervals',[]),
                                     visualForegroundIntervals=e['visualForegroundIntervals'],
                                     materialBoundary="unclipped physical footprint + true named-node union; visibility cuts never form bank caps",
                                     visibilityStatus="painted" if assets else "fully-foreground-occluded" if e["full"].is_empty else "uncovered",
                                     sourceSampleSha256=hashlib.sha256(json.dumps(e["samples"],separators=(",",":")).encode()).hexdigest(),
                                     routeEdited=False,materialClass=e['system'],
                                     materialUV=dict(longitudinal='frozen centerline arclength',transverse='signed nearest segment coordinate; union outside distance owns bank',
                                                     phaseAnchorSource=e.get('pipePhaseSource'),phaseDirection=e.get('pipeDirection'),
                                                     sourceRawSha256=self.pipe_sources.get(e['system'],{}).get('sha256'),
                                                     repeatSourceLength=self.pipe_sources.get(e['system'],{}).get('repeatSourceLength'),
                                                     twoSidedBanks=bool(self.pipe_sources),
                                                     textureFilter='column-normalized original GPT RGB, area-prefilter to repeat*outputdensity × width*outputdensity, then bilinear',
                                                     bankDistance='precise fixed source boundary segment projection; lookup subdivision max .5source, nearest8',
                                                     alphaFrom='frozen physical vessel geometry, not texture alpha')))
        for node, entries in self.node_edges.items():
            if len(entries) < 2:
                continue
            p = entries[0][1]
            if all(math.dist(p,q)<.02 for _,q in entries):
                self.shared_nodes.append(dict(node=node, source=p, edgeIds=[e["id"] for e,_ in entries],
                                              composition="single union boundary at true shared named graph node; whole generated left/right banks + flat lumen; no internal wall caps",
                                              completeWallAndFloor=True,physicalUnionSourcePath=geometry_path(unary_union([e['materialFootprint']for e,_ in entries]))))
        for item in self.junction_spec.get("junctions", []):
            p=Path(item["path"]);p=p if p.is_absolute() else ROOT/p
            if p.exists():
                self.inputs[str(p.relative_to(ROOT))]=sha(p)
                im=Image.open(p);sw,sh=item["sourceBox"][2]-item["sourceBox"][0],item["sourceBox"][3]-item["sourceBox"][1]
                factor=min(im.width/sw,im.height/sh);cw,ch=sw*factor,sh*factor;cx,cy=(im.width-cw)/2,(im.height-ch)/2
                self.junctions.append(dict(item, sha256=sha(p), generator="GPT", applied=self.patch_usage[item["id"]]>0,
                                           paintedPixelCount=self.patch_usage[item["id"]],
                                           generatedPixelSize=list(im.size),guidePixelSize=[1536,1536],
                                           generatedContentBox=[cx,cy,cx+cw,cy+ch],
                                           guideContentBox=[v*1536/im.width for v in [cx,cy,cx+cw,cy+ch]],
                                           mapping="xMidYMid contain content crop then fixed sourceBox affine; whole wall/floor within frozen typed pipe stencil" if item.get('compositionMode')=='whole-pipe-and-foreground' else "xMidYMid contain; true named-node interior only"))
        manifest=dict(schema="fullbody-015-vascular-material/v1", model="GPT built-in image generation",
                      coordinates=dict(sourceSize=[1024,1536], worldFromSource=dict(scale=2,offset=[0,512]),
                                       logicalPixelsPerSourceAt015=9.6), inputs=self.inputs,
                      assets=self.assets, organs=self.coverage, edges=edge_records,
                      junctions=self.junctions, sharedJunctions=self.shared_nodes,
                      actualArtForeground=self.art_foreground_record,
                      pipeMaterials=self.pipe_spec,pipePhaseAnchors=self.pipe_phase_anchors,
                      pipeUVDomains={key:dict(leftBank=[0,q.get('floorRangeNormalized',[.14,.86])[0]],lumen=q.get('floorRangeNormalized',[.14,.86]),rightBank=[q.get('floorRangeNormalized',[.14,.86])[1],1],alphaOnlyTextureCrop=True,alphaDefinesCollision=False)for key,q in self.pipe_sources.items()},
                      deepPlaneOwnershipRepairs=self.deep_ownership_repairs,
                      junctionGuides=guides, crossings=self.crossings,
                      completeFrozenEdgeCount=len(self.edges), completedOrganCount=len(self.organs),
                      coveredEdgeCount=sum(e["covered"] for e in edge_records),
                      uncoveredEdges=[e["id"] for e in edge_records if not e["covered"]],
                      fullyOccludedEdges=[dict(id=e["id"],a=e["a"],b=e["b"],hiddenSegments=e["protectedForegroundIntervals"],
                                              geometryRetained=True,materialSuppressed=True)
                                          for e in edge_records if e["visibilityStatus"]=="fully-foreground-occluded"],
                      protectedGreenVesselPolicy="no green pigments added to any blood material",
                      runtimeTriangles=0, authoringOnly=True, generatedPixelsDefineCollision=False,
                      deepTraceDefaultOpacity=1, nativeEvidence=False,
                      expectedGPUDecodedBytes=sum(a["pixelSize"][0]*a["pixelSize"][1]*4 for a in self.assets),
                      tileRules="sourceBox includes filtering gutter; clip each image to coreBox before drawing; never independently refit a crop",
                      layerRules=["external material under intact organ floor", "organ-specific fixed blood replacement",
                                  "deep continuation material on independent command plane with explicit crossing clips; never a tissue junction", "protected food/air/urine remains foreground"],
                      limitations=["Native resource loading, seam sampling, phase handoff, unit readability and P95 are separate root integration checks.",
                                   "Deep routes covered by reserved lumens stay hidden under that precise foreground; route geometry is not moved.",
                                   "No new non-organ walkable body tissue domains are invented."])
        manifest["runtimeSpec"] = dict(
            organs=[dict(id=a["organId"],resource=a["resource"],sourceBox=a["sourceBox"],pixelSize=a["pixelSize"])
                    for a in self.assets if a["role"]=="organ"],
            surfaceTiles=[{k:a[k]for k in ["id","resource","sourceBox","pixelSize","coreBox"]}
                          for a in self.assets if a["role"]=="external"],
            deepTiles=[{k:a[k]for k in ["id","resource","sourceBox","pixelSize","coreBox"]}
                       for a in self.assets if a["role"]=="deep"],
            junctions=[],foregroundPatches=[{k:a[k]for k in ['id','resource','sourceBox','pixelSize','coreBox']}
                                           for a in self.assets if a['role']=='foreground'])
        manifest['visualDisplayContract']=dict(geometry='actualArtForeground explicit registered source SVG',
            actualBoundarySha256=self.art_foreground_record.get('geometrySvgSha256',self.art_foreground_record['sha256']),
            bloodClipAndMouthAndUnitDepthShareGeometry=True,unitCenterGuardSource=.025,legacy135Retained=True,
            imageColorsDefineNavigation=False,visualForegroundIntervalCount=sum(len(e['visualForegroundIntervals'])for e in self.edges))
        if self.foreground_guides:
            art_contract=OUT/'fourth-repair/actual-art-foreground-v4.json'
            manifest['actualArtForegroundContractPath']=str(art_contract.relative_to(ROOT))
            manifest['actualArtForegroundContractSha256']=sha(art_contract)
            manifest['inputs'][str(art_contract.relative_to(ROOT))]=sha(art_contract)
        manifest['regionalTextureAcceptance']=dict(
            geometryOrDepthFromColors=False,wholeGeneratedBanksRetained=True,
            expectedType='explicit frozen edge-layer paint owner; true named-node dominant union owns its center, projected systems never global-OR',
            artery='red-green>=20; red-blue>=10; green-blue<=12',
            vein='blue-green>=12; blue-red>=3',capillary='red-green>=15; blue-green>=9',
            misplacedInnerWall='only beyond fixed physical wall band+.12source: raw green<108 OR local .4source Gaussian contrast>6 and raw green<same registered GPT strip green-9',
            rejectedTextureFallback='same original GPT complete pipe strip in frozen arclength/transverse UV',
            flatUnionFloor='true-node core samples central GPT lumen; regional core RGB only low-contrast delta<=18 at30%, real named-node floor never takes raw transverse bank',
            validityHandoffSource=.65)
        manifest['resourceBudget']=dict(maxResourceSpecsPerContext=42,maxDecodedRGBABytesPerContext=301989888,
            activeCandidateSpecsWithoutQuiet=len(self.assets),decodedRGBABytesWithoutQuiet=manifest['expectedGPUDecodedBytes'],
            quietBaseExtraSpecs=1,quietBaseDecodedRGBABytes=1024*1536*4,
            totalDecodedRGBABytesPerContext=manifest['expectedGPUDecodedBytes']+1024*1536*4,
            mipmapsIncluded=False,gpuMeasured=False)
        assert len(self.assets)+1<=42,'candidate exceeds42resource specs/context'
        assert manifest['expectedGPUDecodedBytes']+1024*1536*4<=301989888,'candidate exceeds288MiB decoded/context'
        OUT.mkdir(parents=True,exist_ok=True)
        (OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
        print(json.dumps(dict(manifest=str(OUT/"manifest.json"), assets=len(self.assets),edges=len(self.edges),
                              covered=manifest["coveredEdgeCount"],organs=len(self.organs),
                              decodedBytes=manifest["expectedGPUDecodedBytes"])),flush=True)


def main():
    global OUT,ASSET
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--material",default=str(ROOT/"assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/gpt-material-flat-v2.png"))
    p.add_argument("--material-meta",help="Optional GPT atlas metadata with sha256 and rows:{artery:[y0,y1],vein:...,capillary:...}")
    p.add_argument("--junctions",help="JSON object with junctions:[{id,path,sourceBox,edgeIds}]")
    p.add_argument('--pipe-materials',help='Three independent GPT complete pipe sources with path/SHA/crop/floor/repeat metadata')
    p.add_argument('--foreground-guides',help='Explicit high-resolution shared lip source SVG and9 registered crop masks')
    p.add_argument('--foreground-patches',help='GPT regional material edits sharing the accepted explicit foreground edge')
    p.add_argument('--asset-dir',help='Private candidate asset directory; active assets unchanged unless explicitly selected')
    p.add_argument('--out',help='Private candidate manifest/diagnostic directory')
    p.add_argument("--scale",type=float,default=6,help="pixels per original-reference pixel for exterior/deep textures")
    p.add_argument("--tile",type=int,default=256,help="fixed source-coordinate tile grid; all pixels use global material phase")
    p.add_argument("--guides-only",action="store_true")
    p.add_argument("--cleanup-masks-only",action="store_true",help="Export original-pigment cleanup candidates for GPT quiet-base generation; never recolor source")
    args=p.parse_args()
    if args.asset_dir:ASSET=Path(args.asset_dir).resolve()
    if args.out:OUT=Path(args.out).resolve()
    OUT.mkdir(parents=True,exist_ok=True);ASSET.mkdir(parents=True,exist_ok=True)
    b=Bake(args)
    if args.cleanup_masks_only:
        b.cleanup_masks();return
    guides=b.guides()
    if args.guides_only:
        print(json.dumps(dict(guides=[g["guidePath"]for g in guides])));return
    b.tiles("external","exterior")
    b.tiles("deep","deep")
    b.organ_floors()
    b.foreground_patches()
    b.finish(guides)


if __name__=="__main__":
    main()
