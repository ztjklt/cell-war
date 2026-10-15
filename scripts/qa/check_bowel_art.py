"""Inspect actual production draws through Cairo; this is not native evidence."""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b
from check_regional_vascular_refinement import convert
from prepare_bowel_remodel import OUT,ROOT

def main():
    for name in ['BowelBattlefieldData','BowelBattlefield','BowelVisualData','BowelVisual','OrganBattlefield','FullBodyMapArt','Save']:
        b.G.src=(OUT/f'{name}.lua').read_text();b.l.execute(f"package.preload['war.{name}']=assert(load(src))")
    b.l.execute('''
     S=require('war.FullBodyBattlefield').new(914);S.entities={};N=require('war.OrganBattlefield').net(S)
     R=require('war.Render');R.vg={};R.font=1;A=require('war.FullBodyMapArt');A.prepare(R.vg);require('war.Cells').init(R.vg);R.prepare(S)
     graphics={GetWidth=function()return vw*dpr end,GetHeight=function()return vh*dpr end,GetDPR=function()return dpr end}
     g={state=S,zoom=.15,camera={x=0,y=0},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false}
     assert(A.resourceError==nil);assert(A.ready(R.vg,S))
    ''')
    views=[('bowel-after',[415,592,603,755],.15),('left-entry',[440,628,475,666],.35),
           ('small-return',[533,656,559,696],.35),('left-return',[450,701,493,728],.35),
           ('right-return',[552,659,600,730],.25),('torso-after',[315,250,700,830],.04)]
    records=[]
    for name,roi,z in views:
        scale=64*z;w,h=round((roi[2]-roi[0])*scale),round((roi[3]-roi[1])*scale)
        b.G.vw,b.G.vh,b.G.dpr=w,h,1;b.G.g.zoom=z
        b.G.g.camera.x=roi[0]+roi[2];b.G.g.camera.y=roi[1]*2+512+h*.47/(32*z)
        b.reset();b.G.R.draw(b.G.g);image=Image.open(__import__('io').BytesIO(b.png(w,h)))
        image.save(OUT/(name+'.png'));records.append({'name':name,'roi':roi,'zoom':z,'size':[w,h],'draws':b.G.A.last.draws})
        print(name,'PASS',flush=True)
    gate_frames=[]
    organ=b.l.eval("require('war.OrganBattlefield')")
    for oid in ['small_intestine','large_intestine']:
        for _,gate in organ.organ(oid).gateContracts.siege.items():
            x,y=gate.pipeAnchorSource[1],gate.pipeAnchorSource[2];roi=[x-8,y-7,x+8,y+7];z=.3
            w,h=round(16*64*z),round(14*64*z);b.G.vw,b.G.vh,b.G.dpr=w,h,1;b.G.g.zoom=z
            b.G.g.camera.x=2*x;b.G.g.camera.y=roi[1]*2+512+h*.47/(32*z)
            b.reset();b.G.R.draw(b.G.g);gate_frames.append(Image.open(__import__('io').BytesIO(b.png(w,h))).convert('RGB'))
    sheet=Image.new('RGB',(gate_frames[0].width*2,gate_frames[0].height*2))
    for i,im in enumerate(gate_frames):sheet.paste(im,((i%2)*im.width,(i//2)*im.height))
    sheet.save(OUT/'four-membrane-mouths.png')
    # The original overview still bypasses registered map art at every zoom.
    perspective=b.l.eval("require('war.AnatomyPerspective')")
    assert perspective is not None
    # Explicit perspective selection and several zooms keep one cardiac/map
    # layer. Neither toggle nor drawing modifies the saved simulation state.
    b.l.execute('''
      local Save=require('war.Save');local P=require('war.AnatomyPerspective')
      function same(a,b)
       if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
       for k,v in pairs(a)do if not same(v,b[k])then return false end end
       for k in pairs(b)do if a[k]==nil then return false end end;return true
      end
      beforeDraw=Save.snapshot(S);require('war.ReferenceArt').prepareOriginal(R.vg)
      assert(P.set(g,'original',vw,vh));g.realTime=(g.realTime or 0)+P.duration;assert(P.original(g))
    ''')
    b.reset();b.G.R.draw(b.G.g)
    key=str((ROOT/'assets/image/anatomy-reference/reference.png').resolve())
    assert b.frame_images=={b.decoded_images[key].key}
    b.l.execute("assert(same(beforeDraw,require('war.Save').snapshot(S)));local P=require('war.AnatomyPerspective');assert(P.set(g,'map',vw,vh));g.realTime=g.realTime+P.duration")
    for z in [.06,.149,.15,.151,.3]:
        b.G.g.zoom=z;b.reset();b.G.R.draw(b.G.g)
        assert b.l.eval("require('war.HeartArt').last.atlasPanel==0 and require('war.HeartArt').last.detailVisible")
        assert b.l.eval("same(beforeDraw,require('war.Save').snapshot(S))")
    b.l.execute("Flow=require('war.BodyLifeFlow');assert(Flow.prepare(S).actualRoutes and Flow.prepare(S).net==N)")
    sampled=0
    from shapely.geometry import LineString,Point
    from register_simple_heart import rings
    d=json.loads((OUT/'runtime-data.json').read_text())
    for time in [0,.5,1.3,4,10]:
        for zoom in [.06,.15,.3]:
            result=b.G.Flow.sample(b.G.S,time,zoom,880,1200,1718,1974,b.l.table_from({'intensity':1}))
            for key in ['streaks','cells']:
                for _,item in result[key].items():
                    raw=d['rawBloodDomains'].get(str(item.edge))
                    if raw:
                        assert rings(raw).covers(Point(item.x*.5,(item.y-512)*.5))
                        sampled+=1
    assert sampled>0
    before=Image.open(ROOT/'docs/vascular-map-audit-20261013/bowel.png').convert('RGB')
    after=Image.open(OUT/'bowel-after.png').convert('RGB');assert before.size==after.size
    panel=Image.new('RGB',(before.width*2,before.height));panel.paste(before,(0,0));panel.paste(after,(before.width,0))
    panel.thumbnail((1500,900));panel.save(OUT/'before-after.png')
    after.thumbnail((950,850));after.save(OUT/'bowel-overview.png')
    specs=b.image_handles.values();images=sum(1 for _ in b.G.A.handles[b.G.R.vg].items());bytes_used=0
    for _,handle in b.G.A.handles[b.G.R.vg].items():
        record=b.image_handles[handle];pixels=record.pixels if hasattr(record,'pixels')else record
        if hasattr(pixels,'size'):bytes_used+=pixels.width*pixels.height*4
    report={'status':'PASS_PRODUCTION_RENDER_OFFLINE','nativeVisualEvidence':False,'backend':'actual Lua draw / SVG Cairo',
            'frames':records,'resourceError':b.G.A.resourceError,'registeredResourceSlots':images,'decodedBytes':bytes_used,
            'limits':{'maxSlots':43,'maxBytes':301989888},'perspectiveOriginalOnly':True,'zooms':[.06,.149,.15,.151,.3],
            'drawSimulationUnchanged':True,'oneDetailedHeartAtAllZooms':True,'remodeledFlowSamples':sampled,
            'flowUsesActualGraph':True}
    (OUT/'render-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:report[k]for k in ['status','registeredResourceSlots','decodedBytes']}))
if __name__=='__main__':main()
