"""Make source-space unit occlusion follow the actual staged pipe alpha."""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from build_fullbody_vascular_material import raster_runs_geometry
from register_heart_port_connections import lua_value, BOX

def main():
    out=Path(sys.argv[1]).resolve();report=json.loads((out/'registration.json').read_text())
    resource=Path(__file__).resolve().parents[2]/'assets'/report['resource']
    assert hashlib.sha256(resource.read_bytes()).hexdigest()==report['atlasSha256']
    visual=out/'HeartVisualData.lua';before=visual.read_text();(out/'before-depth-HeartVisualData.lua').write_text(before)
    front={};checks=[]
    for group in report['groups']:
        path=out/(group['id']+'.png');alpha=np.asarray(Image.open(path).convert('RGBA'))[:,:,3]
        shape=raster_runs_geometry(alpha>=16,BOX,12).simplify(.07,preserve_topology=True)
        polygons=[shape]if shape.geom_type=='Polygon'else list(shape.geoms)
        rings=[dict(outer=[list(p)for p in poly.exterior.coords],holes=[[list(p)for p in h.coords]for h in poly.interiors])for poly in polygons if poly.geom_type=='Polygon'and poly.area>.01]
        for lane in group['lanes']:front['e'+str(lane).zfill(3)]=rings
        checks.append({'group':group['id'],'alphaSourceSha256':hashlib.sha256(path.read_bytes()).hexdigest(),'threshold':16,'sourceContourTolerance':.07})
    start=before.index('H.frontPipeRings=');end=before.index('\nlocal function inside(points,x,y)',start)
    after=before[:start]+'H.frontPipeRings='+lua_value(front)+before[end:]
    visual.write_text(after)
    report['candidateVisualSha256']=hashlib.sha256(visual.read_bytes()).hexdigest()
    report['unitDepthRegistration']={'algorithm':'actual pipe alpha >=16 -> source row runs -> simplify .07 source units','sources':checks,'atlasPixelsChanged':False,'builderSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (out/'registration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'depthRegisteredGroups':len(checks),'atlasPixelsChanged':False}))

if __name__=='__main__':main()
