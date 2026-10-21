#!/usr/bin/env python3
"""Install the approved trapezoid platelet and its five animation atlases."""
from pathlib import Path
import hashlib
import json
import shutil
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/platelet-cartoon-v2-20261021'
GAME=ROOT/'godot'
ACTIONS={'move':'plateletMove','connect':'plateletConnect','defend':'plateletDefend','hit':'plateletHit','death':'plateletDeath'}
COUNTS={'move':16,'connect':12,'defend':12,'hit':8,'death':12}

def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

def simplify(points,epsilon=1.5):
    if len(points)<3: return points
    a,b=np.array(points[0]),np.array(points[-1])
    delta=b-a
    if np.dot(delta,delta)==0: distances=np.linalg.norm(np.array(points)-a,axis=1)
    else:
        t=np.clip(np.dot(np.array(points)-a,delta)/np.dot(delta,delta),0,1)
        distances=np.linalg.norm(np.array(points)-(a+t[:,None]*delta),axis=1)
    i=int(distances.argmax())
    if distances[i]<=epsilon: return [points[0],points[-1]]
    return simplify(points[:i+1],epsilon)[:-1]+simplify(points[i:],epsilon)

def outline(image):
    solid=np.asarray(image.getchannel('A').resize((256,256),Image.Resampling.NEAREST))>=96
    edges={}
    def edge(a,b): edges.setdefault(a,[]).append(b)
    for y,x in zip(*np.nonzero(solid)):
        x,y=int(x),int(y)
        if y==0 or not solid[y-1,x]: edge((x,y),(x+1,y))
        if x==255 or not solid[y,x+1]: edge((x+1,y),(x+1,y+1))
        if y==255 or not solid[y+1,x]: edge((x+1,y+1),(x,y+1))
        if x==0 or not solid[y,x-1]: edge((x,y+1),(x,y))
    loops=[]
    while edges:
        start=next(iter(edges)); p=start; loop=[]; heading=0
        while p in edges:
            loop.append(p)
            # A diagonal pixel junction can have two outgoing edges. Keep
            # occupied pixels on the right instead of overwriting one branch.
            def direction(q):
                dx,dy=q[0]-p[0],q[1]-p[1]
                return {(1,0):0,(0,1):1,(-1,0):2,(0,-1):3}[(dx,dy)]
            q=min(edges[p],key=lambda q:{1:0,0:1,3:2,2:3}[(direction(q)-heading)%4])
            heading=direction(q)
            edges[p].remove(q)
            if not edges[p]: del edges[p]
            p=q
            if p==start: break
        if p==start and len(loop)>3: loops.append(loop)
    if not loops: return []
    def area(points):
        return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]+points[:1])))
    loop=max(loops,key=area)
    half=len(loop)//2
    points=simplify(loop[:half+1])+simplify(loop[half:]+[loop[0]])[1:-1]
    return [[round((x*2-256)/150,5),round((y*2-300)/150,5)] for x,y in points]

def main():
    clips,outlines,deliveries={},{},[]
    for action,key in ACTIONS.items():
        folder=ART/f'{action}-{COUNTS[action]}'
        doc=json.loads((folder/'animation.json').read_text())
        relative=(folder/'spritesheet.png').relative_to(ROOT).as_posix()
        clips[key]={'path':relative.removeprefix('assets/'),'frameSize':512,'columns':doc['columns'],'rows':doc['rows'],
                    'anchorX':256,'anchorY':300,'occupancy':300/512,'duration':doc['durationMs']/1000,
                    'durations':[f['duration']/1000 for f in doc['frames']]}
        outlines[key]=[outline(Image.open(folder/f['name']).convert('RGBA')) for f in doc['frames']]
        deliveries.append(relative)
    data={'schema':1,'name':'血小板','unitKind':'scout','approvedPortrait':'2026-10-21',
          'character':'image/platelet-cartoon-v2-20261021/character-v4-original-trapezoid.png',
          'clips':clips,'outlines':outlines,
          'hull':[[-.48,-.96],[.48,-.96],[1,.82],[.9,.94],[-.9,.94],[-1,.82]],
          'wall':{'spacingInRadii':2.65,'maxLinksPerCell':2,'stationaryPushMultiplier':.22,'linkedPushMultiplier':.05}}
    write(ART/'runtime.json',data)
    deliveries += [(ART/'runtime.json').relative_to(ROOT).as_posix(),(ART/'character-v4-original-trapezoid.png').relative_to(ROOT).as_posix()]
    manifest_path=GAME/'data/asset_manifest.json'
    manifest={r['path']:r for r in json.loads(manifest_path.read_text())}
    for relative in deliveries:
        destination='data/platelet.json' if relative.endswith('/runtime.json') else relative
        target=GAME/destination; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/relative,target)
        manifest[destination]={'source':relative,'path':destination,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    write(manifest_path,list(manifest.values()))
    baseline_path=GAME/'data/source_manifest.json'
    baseline=json.loads(baseline_path.read_text()); baseline['assets']=len(manifest); baseline['assetBytes']=sum(r['bytes'] for r in manifest.values())
    write(baseline_path,baseline)
    config_path=GAME/'data/config.json'; config=json.loads(config_path.read_text())
    config['CellFrames']['assets']['platelet']={'path':data['character'],'occupancy':.8}
    config['CellFrames']['kinds']['scout']='platelet'
    write(config_path,config)
    print(json.dumps({'unit':'scout','frames':COUNTS,'runtimeAssets':len(deliveries)},ensure_ascii=False))

if __name__=='__main__': main()
