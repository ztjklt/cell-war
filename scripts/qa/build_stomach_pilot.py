"""Author a quiet coordinate-locked stomach cutaway; no raster editing or runtime switch."""
from pathlib import Path
import json, hashlib, math, shutil
ROOT=Path(__file__).resolve().parents[2]; DOC=ROOT/'docs/body-life/vascular-art-study'; PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
def smooth(vertices,closed=True,n=8):
    out=[];v=vertices
    for i in range(len(v) if closed else len(v)-1):
        p0=v[(i-1)%len(v)] if closed or i else v[0];p1=v[i];p2=v[(i+1)%len(v)];p3=v[(i+2)%len(v)] if closed or i+2<len(v) else v[-1]
        for j in range(n):
            t=j/n;out.append([round(.5*((2*p1[k])+(-p0[k]+p2[k])*t+(2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*t*t+(-p0[k]+3*p1[k]-3*p2[k]+p3[k])*t*t*t),4) for k in range(2)])
    if not closed:out.append(v[-1])
    return out

def ribbon(points,width):
    c=smooth(points,False);left=[];right=[]
    for i,p in enumerate(c):
        a=c[max(0,i-1)];b=c[min(len(c)-1,i+1)];dx=b[0]-a[0];dy=b[1]-a[1];d=math.hypot(dx,dy)
        left.append([round(p[0]-dy/d*width/2,4),round(p[1]+dx/d*width/2,4)])
        right.append([round(p[0]+dy/d*width/2,4),round(p[1]-dx/d*width/2,4)])
    return left+right[::-1]
graph=json.loads((DOC/'network.json').read_text()); ports=next(r['ports'] for r in json.loads((DOC/'interface-contract.json').read_text())['regions'] if r['id']=='stomach')
outline=json.loads((DOC/'occlusion-outlines.json').read_text())['stomach'][0]['points']
inlet=[[540,463],[540,475],[560,480],[580,483],[594,495]]
outlet=[[598,536],[585,549],[562,559],[542,558],[521,551],[501,552],[480,558],[469,579],[475,605],[490,618],[525,620]]
cavity=smooth([[587,489],[599,493],[607,506],[607,522],[599,536],[587,545],[577,547],[580,537],[589,528],[592,516],[588,506],[581,497]])
edgeids={'e123','e124','e164','e183','e184'}
data=dict(version=1,sourceNetworkSha256=hashlib.sha256((DOC/'network.json').read_bytes()).hexdigest(),sourceSize=[1024,1536],transform=dict(scale=2,offsetY=512),
    organ=dict(id='stomach',outline=outline,tissueColor=[180,142,127],boundaryColor=[127,100,90],boundaryWidthSource=.8),
    food=dict(cavity=cavity,inlet=ribbon(inlet,7),outlet=ribbon(outlet,7),fillColor=[212,184,145],boundaryColor=[158,130,102],boundaryWidthSource=.65,route=smooth(inlet+[[599,506],[601,522]]+outlet,False)),
    folds=[dict(points=smooth(p,False),widthSource=.9,color=[166,129,115],alpha=.48) for p in [[[555,513],[553,522],[557,532]],[[573,495],[578,503],[580,511]],[[542,537],[551,542],[562,546]],[[600,503],[602,513],[601,522]]]],
    vessels=[dict(edgeId=e['id'],points=e['points'],lumenWidthSource=e['lumenWidthSource'],kind=e['kind'],layer=e['drawOrder']) for e in graph['edges'] if e['id'] in edgeids],ports=ports,
    study=dict(crop=[454,455,180,176],navigationCases=[dict(id='membrane-tissue-clear',fromSource=[563,507],toSource=[563,515],expected='clear',lane=0),dict(id='cavity-rim-detour',fromSource=[583,491],toSource=[584,502],expected='detour',lane=0)],
       status='ISOLATED_COORDINATE_LOCKED_GAME_CUTAWAY',foodCollision='not installed in production',note='Food chamber is a game cutaway, not a medical section. No gastric nutrient reward is implemented. Portal return remains a separate blood route to liver; food leaves via pylorus/duodenum.'))
def inside(p,poly):
    x,y=p;v=False;j=len(poly)-1
    for i,(a,b) in enumerate(poly):
        c,d=poly[j]
        if (b>y)!=(d>y) and x<(c-a)*(y-b)/(d-b)+a:v=not v
        j=i
    return v

def distance(p,a,b):
    dx=b[0]-a[0];dy=b[1]-a[1];t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy or 1)))
    return math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
foodpolys=[data['food'][k] for k in ['cavity','inlet','outlet']]
for e in data['vessels']:
    e['depth']='deep' if e['edgeId']=='e164' else 'surface'
    if e['depth']=='surface':e['visibleSegments']=[e['points']];continue
    margin=e['lumenWidthSource']/2+data['food']['boundaryWidthSource']+.25
    def hidden(p):return any(inside(p,poly) or min(distance(p,a,poly[(i+1)%len(poly)]) for i,a in enumerate(poly))<margin for poly in foodpolys)
    samples=[]
    for a,b in zip(e['points'],e['points'][1:]):
        steps=math.ceil(math.dist(a,b)/.15)
        samples.extend([[a[k]+(b[k]-a[k])*i/steps for k in range(2)] for i in range(steps)])
    samples.append(e['points'][-1]);segments=[];current=[];previous=None;was_hidden=None
    for p in samples:
        h=hidden(p)
        if previous is not None and h!=was_hidden:
            lo=previous[:];hi=p[:]
            for _ in range(18):
                mid=[(lo[k]+hi[k])/2 for k in range(2)]
                if hidden(mid)==was_hidden:lo=mid
                else:hi=mid
            boundary=[round((lo[k]+hi[k])/2,6) for k in range(2)]
            if h:current.append(boundary);segments.append(current);current=[]
            else:current=[boundary]
        if not h:current.append(p)
        previous=p;was_hidden=h
    if current:segments.append(current)
    e['visibleSegments']=segments
    e['occlusion']='Food boundary foreground; complete lane continues below, no junction or tissue opening.'
(DOC/'stomach-pilot.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
PUB.mkdir(exist_ok=True);shutil.copy2(DOC/'stomach-pilot.json',PUB/'stomach-pilot.json')
print('Wrote stomach-pilot.json: exact fine outline and 5 canonical edges; fixed source coordinates')
