"""Single production Render stroke trace, with header-only image handles.

Does not decode, rasterize, capture native UI, or change production files.
The image API is controlled; paths and call stacks are actual Lua rendering.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import sys
import time

for dependency in ['/tmp/reference-map-tools','/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0,dependency)
from PIL import Image
import body_life_backend as backend

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    os.chdir(ROOT);started=time.perf_counter();lua,G=backend.l,backend.G
    report_path=DOC/'native-007/driver-report.json'
    native=json.loads(report_path.read_text())
    phase=next(p for p in native['phases']if p['label']=='portal-z0.15')
    handles={};next_handle=1

    def create_image(ctx,resource,flags=0):
        nonlocal next_handle
        p=ROOT/'assets'/resource
        if not p.is_file():return 0
        with Image.open(p)as im:width,height=im.size
        handle=next_handle;next_handle+=1
        handles[handle]=dict(resource=resource,pixelSize=[width,height])
        return handle

    G.nvgCreateImage=create_image
    G.nvgImageSize=lambda _,ident:tuple(handles[ident]['pixelSize'])if ident in handles else(0,0)
    G.nvgDeleteImage=lambda _,ident:handles.pop(ident,None)
    patterns={}
    def image_pattern(ctx,x,y,w,h,angle,ident,alpha,*extra):
        key='url(#header-only-pattern-'+str(len(patterns))+')'
        patterns[key]=dict(imageHandle=ident,resource=handles.get(ident,{}).get('resource'),
            x=x,y=y,width=w,height=h,angle=angle,alphaOrTint=str(alpha),extra=[str(v)for v in extra])
        return key
    G.nvgImagePattern=image_pattern
    G.nvgImagePatternTinted=image_pattern
    trace=lua.eval("function()return debug.traceback('',2)end")
    strokes=[];fills=[];order=[]

    def stroke(ctx):
        row=dict(index=len(strokes)+1,svgIndex=len(backend.svg),path=list(backend.path),
            color=str(backend.stroke),width=backend.sw,alpha=backend.alpha,
            lineCap=backend.line_cap,lineJoin=backend.line_join,
            antialias=backend.antialias,traceback=trace())
        backend.stroke_path(ctx);row['svg']=backend.svg[-1];strokes.append(row)
        order.append(dict(kind='stroke',index=row['index']))

    def fill(ctx):
        row=dict(index=len(fills)+1,svgIndex=len(backend.svg),path=list(backend.path),
            paint=str(backend.fill),alpha=backend.alpha,antialias=backend.antialias,
            pattern=patterns.get(str(backend.fill)),traceback=trace())
        backend.fill_path(ctx);row['svg']=backend.svg[-1];fills.append(row)
        order.append(dict(kind='fill',index=row['index']))

    G.nvgStroke=stroke
    G.nvgFill=fill
    lua.execute(r'''
      S=require('war.FullBodyBattlefield').new(72026)
      A=require('war.FullBodyMapArt');R=require('war.Render');O=require('war.OrganBattlefield')
      Save=require('war.Save');U=require('war.Util')
      before=Save.snapshot(S);worldContext={};uiContext={};R.vg=worldContext;R.font=1
      A.prepare(worldContext);A.prepare(uiContext)
      assert(A.ready(worldContext,S)and A.ready(uiContext,S))
      require('war.Cells').init(worldContext);R.prepare(S)
      function same(a,b)
       if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
       for k,v in pairs(a)do if not same(v,b[k])then return false end end
       for k in pairs(b)do if a[k]==nil then return false end end;return true
      end
    ''')
    G.cx=phase['camera']['x'];G.cy=phase['camera']['y'];G.rt=phase['realTime']
    lua.execute(r'''
      R.w,R.h=1249,702
      graphics={GetWidth=function()return 2498 end,GetHeight=function()return 1404 end,GetDPR=function()return 2 end}
      game={state=S,zoom=.15,camera={x=cx,y=cy},realTime=rt,flowTime=S.time,
       selection={},accumulator=0,started=true,fogDisabled=true,paused=true}
      for id,e in pairs(S.entities)do
       if e.faction==1 and O.organAt(S,e,e.x,e.y)=='__none__'then game.selection[id]=true end
      end
    ''')
    backend.reset();lua.execute('R.draw(game);assert(same(before,Save.snapshot(S)))')
    bindings={str(report_path.relative_to(ROOT)):sha(report_path),
              'scripts/qa/trace_fullbody_native007_portal.py':sha(Path(__file__).resolve()),
              'scripts/qa/body_life_backend.py':sha(ROOT/'scripts/qa/body_life_backend.py'),
              'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json':sha(DOC/'bake/manifest.json')}
    for name in ['FullBodyBattlefield','FullBodyMapArt','FullBodyMapArtData','ReferenceArt',
                 'Render','View','BodyLife','Cells','Save','World']:
        p=ROOT/('scripts/war/'+name+'.lua')
        if p.exists():bindings[str(p.relative_to(ROOT))]=sha(p)
    result=dict(schema='fullbody-single-production-stroke-trace/v1',
        createdAt=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        scope='One actual Lua production Render; image handles/dimensions are header-only controlled APIs.',
        nativeEvidence=False,actualAssetDecodeVerified=False,actualPNGProduced=False,
        sourceReferenceBatch='native-007',referencePhase=phase,
        camera=phase['camera'],zoom=.15,realTime=phase['realTime'],logicalSize=[1249,702],dpr=2,
        factorySeed=72026,strokeCount=len(strokes),strokes=strokes,
        fillCount=len(fills),fills=fills,drawOrder=order,imagePatterns=patterns,inputHashes=bindings,
        imageHeaderCount=len(handles),decodedImageCount=len(backend.decoded_images),
        saveUnchanged=True,elapsedSeconds=round(time.perf_counter()-started,4),
        limits=['Native driver entity positions/state and HUD are not serialized; factory/selection matches production fullbody initialization with no organ selected, matching portal source-point view.',
                'Header-only image controls preserve resource-ready branch and real stroke geometry, but cannot certify native image filtering or texture pixel defects.'])
    output=DOC/'qa/fourth-repair/native007-portal-lines-review/stroke-trace.json'
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
    print('STROKES',len(strokes),'SECONDS',result['elapsedSeconds'],'SHA',sha(output))
    print('FIRST',[(s['index'],s['color'],s['width'],s['traceback'].splitlines()[2:4])for s in strokes[:5]])


if __name__=='__main__':
    main()
