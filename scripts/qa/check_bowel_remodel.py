"""Execute production moves on candidate intestinal geometry, without a preview."""
from pathlib import Path
import sys,json,math
from shapely.geometry import LineString,Point
from shapely.ops import unary_union
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
from check_regional_vascular_refinement import convert
from register_simple_heart import rings
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/bowel-remodel-20261013'
def runtime(candidate=True):
    l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
    if candidate:
        for name in ['BowelBattlefieldData','BowelBattlefield','OrganBattlefield','Save']:
            l.globals().src=(OUT/f'{name}.lua').read_text()
            l.execute(f"package.preload['war.{name}']=assert(load(src))")
    else:
        # Keep old-save fixtures reproducible after candidate activation.
        for name in ['OrganBattlefield','Save']:
            l.globals().src=(OUT/f'baseline-{name}.lua').read_text()
            l.execute(f"package.preload['war.{name}']=assert(load(src))")
    l.execute('''
      F=require('war.FullBodyBattlefield');O=require('war.OrganBattlefield');C=require('war.Commands');W=require('war.World');Save=require('war.Save')
      S=F.new(914);N=O.net(S)
      local M=require('war.Motion');local original=M.record;trace={}
      M.record=function(e)original(e);if e.id==traceId then trace[#trace+1]={x=e.x,y=e.y,lane=e.vesselLane}end end
      function prepare(kind,a)
       S.entities={};S.commands={};S.effects={};require('war.OrganTraffic').reset(S);require('war.Path').reset();W.rebuild(S)
       local e=assert(C.spawn(S,'unit',kind,1,a[1]*2,a[2]*2+512));e.x,e.y,e.vesselLane=a[1]*2,a[2]*2+512,a[3]
       traceId=e.id;trace={{x=e.x,y=e.y,lane=a[3]}};W.rebuild(S)
       assert(O.pointAllowed(S,e,e.x,e.y,a[3]));return e
      end
      function move(kind,a,b)
       local e=prepare(kind,a)
       assert(C.execute(S,{kind='move',faction=1,ids={e.id},x=b[1]*2,y=b[2]*2+512,lane=b[3]}))
       local steps=0;while steps<6000 and(#e.orders>0 or #S.commands>0)do F.step(S,.1);steps=steps+1 end
       local error=math.sqrt((e.x-b[1]*2)^2+(e.y-b[2]*2-512)^2)
       return {arrived=error<.04 and e.vesselLane==b[3]and #e.orders==0,errorWorld=error,steps=steps,trace=trace,finalLane=e.vesselLane}
      end
    ''');return l
def to_lua(l,v):
    if isinstance(v,dict):return l.table_from({k:to_lua(l,x)for k,x in v.items()})
    if isinstance(v,list):return l.table_from([to_lua(l,x)for x in v])
    return v
def main():
    l=runtime();d=json.loads((OUT/'runtime-data.json').read_text())
    net=json.loads((OUT/'network.json').read_text());edges={e['lane']:e for e in net}
    curves={i:LineString(e['points'])for i,e in edges.items()}
    for i,e in l.globals().N.edges.items():
        for key,index in [('a',1),('b',len(e.points))]:
            p=e.points[index];node=l.globals().N.nodes[e[key]]
            assert math.hypot(p[1]-node.x,p[2]-node.y)<1e-5,(i,key,'endpoint mismatch')
    def along(i,t):p=curves[i].interpolate(t,normalized=True);return[p.x,p.y,i]
    rows=[]
    cases=[('small-supply',along(130,.1),along(187,.9)),('small-return',along(188,.1),along(166,.95)),
           ('colon-left-supply',along(132,.08),along(189,.85)),('colon-left-return',along(190,.12),along(167,.92)),
           ('colon-right-return',along(192,.08),along(168,.92)),
           ('small-exchange',along(187,.8),along(188,.1)),('colon-left-exchange',along(189,.8),along(190,.1)),
           ('colon-right-exchange',along(191,.8),along(192,.1))]
    for gate in d['gateContracts']['siege']:
        cases.append((gate['id'],gate['pipeAnchorSource']+[gate['laneIndex']],gate['tissueAnchorSource']+[0]))
    # Stomach now uses the same adapted network; its own membrane remains valid.
    for _,gate in l.globals().O.organ('stomach').gateContracts.siege.items():
        cases.append((gate.id,convert(gate.pipeAnchorSource)+[gate.laneIndex],convert(gate.tissueAnchorSource)+[0]))
    for kind,radius in [('scout',.21875),('siege',.53125)]:
        domains={i:rings(d['rawBloodDomains'][str(i)]) if str(i)in d['rawBloodDomains']else curves[i].buffer(edges[i]['widthSource']/2,quad_segs=24)for i in edges}
        safe={i:g.buffer(-radius+.0002,quad_segs=24)for i,g in domains.items()}
        # Gastric authored lumen and in-progress membrane transit are explicit
        # domains; a nominal reference tube is not an oracle for either one.
        stomach=l.globals().O.organ('stomach')
        for i,blood in stomach.bloodLanes[kind].items():
            if i not in d['edgeUpdates'] and str(i)not in d['edgeUpdates']:
                safe[i]=rings(convert(blood.safeRings)).buffer(.021)
        for gate in d['gateContracts'][kind]+convert(stomach.gateContracts[kind]):
            i=gate['laneIndex'];safe[i]=safe[i].union(rings(gate['throatRings']).buffer(.001))
        for name,a,b in cases:
            for reverse in [False,True]:
                aa,bb=(b,a)if reverse else(a,b)
                r=convert(l.globals().move(kind,l.table_from(aa),l.table_from(bb)));trace=r.pop('trace')
                bad=[]
                for p,q in zip(trace,trace[1:]):
                    if p['lane']==q['lane'] and p['lane']>0:
                        segment=LineString([(p['x']*.5,(p['y']-512)*.5),(q['x']*.5,(q['y']-512)*.5)])
                        if not safe[p['lane']].covers(segment):bad.append((p,q))
                assert r['arrived'] and not bad,(kind,name,reverse,r,len(bad))
                rows.append(dict(name=name,kind=kind,reverse=reverse,**r,fullDiskSweepFailures=0))
                print(kind,name,reverse,'PASS',flush=True)
        # The moved blue endpoint is not an implicit passage into the red artery.
        e=l.globals().prepare(kind,l.table_from([548,678,166]));p=curves[134].interpolate(curves[134].project(Point(548,678)))
        result=l.globals().O.sweep(l.globals().S,e,e.x,e.y,p.x*2,p.y*2+512,166,134)
        assert not(result[0]if isinstance(result,tuple)else result)
    # Old cells on every changed lane migrate within their original compartment.
    old=runtime(False);old.execute('S.entities={};S.commands={};W.rebuild(S)');fixtures=[]
    for kind in ['scout','siege']:
        for i in d['edgeUpdates']:
            i=int(i);e=old.globals().N.edges[i];line=LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()])
            p=line.interpolate(.32 if kind=='scout'else .72,normalized=True)
            unit=old.globals().C.spawn(old.globals().S,'unit',kind,1,p.x*2,p.y*2+512)
            unit.x,unit.y,unit.vesselLane=p.x*2,p.y*2+512,i
            fixtures.append({'id':unit.id,'lane':i,'kind':kind})
    snap=convert(old.globals().Save.snapshot(old.globals().S));assert 'bowelLayoutRevision'not in snap
    restored=l.globals().Save.restore(to_lua(l,snap))
    for row in fixtures:
        e=restored.entities[row['id']];assert e.vesselLane==row['lane']and l.globals().O.pointAllowed(restored,e,e.x,e.y,e.vesselLane)
    l.globals().S=restored;fresh=l.globals().Save.snapshot(restored);assert fresh.bowelLayoutRevision==1
    roundtrip=l.globals().Save.restore(fresh)
    for _,e in roundtrip.entities.items():assert l.globals().O.pointAllowed(roundtrip,e,e.x,e.y,e.vesselLane)
    # Existing standalone gastric mode and original 202-edge map remain intact.
    l.execute("legacy={anatomyVersion=4,gastricBattlefieldVersion=1};assert(#O.net(legacy).edges==202);assert(#N.edges==211)")
    report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeEvidence':False,'routes':rows,'falseAVShortcutRejected':True,
            'saveMigrationFixtures':fixtures,'roundtripRevision':1,'gateCount':4,'optedEdges':211,'legacyEdges':202,
            'allNamedNodeEndpointsAligned':True,'dataSha256':__import__('hashlib').sha256((OUT/'runtime-data.json').read_bytes()).hexdigest()}
    (OUT/'navigation-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'moves':len(rows),'saveFixtures':len(fixtures)}))
if __name__=='__main__':main()
