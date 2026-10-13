"""Inspect the staged simplified cardiac atlas with production drawing code."""
from pathlib import Path
import json, hashlib, sys
sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b

def main():
    out=Path(sys.argv[1]).resolve()
    guarded=[p for p in out.glob('*.lua')if not p.name.startswith('baseline-')]
    binding={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in guarded}
    for name in ['HeartBattlefieldData','HeartBattlefield','HeartVisualData','HeartArt','FullBodyMapArt','BodyLifeFlow','ReferenceArt','Render','Save']:
        if (out/(name+'.lua')).exists():
            b.G.moduleSource=(out/(name+'.lua')).read_text()
            b.G.moduleName='war.'+name
            b.l.execute('package.loaded[moduleName]=assert(load(moduleSource))()')
    b.G.candidateSource=(out/'HeartVisualData.lua').read_text()
    if (out/'FullBodyMapArt.lua').exists():
        b.G.candidateRenderer=(out/'FullBodyMapArt.lua').read_text()
        b.l.execute("package.loaded['war.HeartVisualData']=assert(load(candidateSource))();package.loaded['war.FullBodyMapArt']=assert(load(candidateRenderer))()")
    b.l.execute('''
      package.loaded['war.HeartVisualData']=assert(load(candidateSource))()
      S=require('war.FullBodyBattlefield').new(72026)
      A=require('war.FullBodyMapArt');R=require('war.Render');Save=require('war.Save')
      worldContext={};uiContext={};R.vg=worldContext;R.font=1
      A.prepare(worldContext);A.prepare(uiContext)
      assert(A.ready(worldContext,S)and A.ready(uiContext,S))
      require('war.Cells').init(worldContext);R.prepare(S)
      function same(a,b)
       if type(a)~=type(b)then return false end
       if type(a)~='table'then return a==b end
       for k,v in pairs(a)do if not same(v,b[k])then return false end end
       for k in pairs(b)do if a[k]==nil then return false end end
       return true
      end
      baseline=Save.snapshot(S)
      graphics={GetWidth=function()return 1024*dpr end,GetHeight=function()return 768*dpr end,GetDPR=function()return dpr end}
      game={state=S,zoom=.06,camera={x=1036,y=1305},selection={},started=true,fogDisabled=true,realTime=0,flowTime=S.time}
      math.random=function()error('Render consumed RNG')end
      math.randomseed=function()error('Render reseeded RNG')end
    ''')
    resource=b.ROOT/'assets'/b.l.eval("require('war.HeartVisualData').resource")
    binding[str(resource)]=hashlib.sha256(resource.read_bytes()).hexdigest()
    quiet=b.l.eval("require('war.HeartVisualData').quietResource")
    if quiet:
      quiet=b.ROOT/'assets'/quiet
      binding[str(quiet)]=hashlib.sha256(quiet.read_bytes()).hexdigest()
    samples=[];frames=[]
    heart_draw=b.G.__heart_draw_original=b.l.eval("require('war.HeartArt').drawSpec")
    b.l.execute("heartDrawCount=0;require('war.HeartArt').drawSpec=function(...)heartDrawCount=heartDrawCount+1;return __heart_draw_original(...)end")
    for zoom in [.06,.085,.12,.149,.15,.151,.25]:
      for dpr in [1,2,3]:
       for time in [0,.3,.59]:
        b.G.dpr=dpr;b.G.game.zoom=zoom;b.G.game.realTime=time
        b.G.heartDrawCount=0;b.reset();b.G.R.draw(b.G.game)
        if b.l.eval("require('war.HeartVisualData').quietResource~=nil"):
          old_key=str((b.ROOT/'assets/image/anatomy-reference/reference.png').resolve())
          old=b.decoded_images.get(old_key)
          assert not old or old.key not in b.frame_images,'Legacy total-map raster painted at '+str(zoom)
          assert b.decoded_images[str(quiet.resolve())].key in b.frame_images,'Clean whole-body base not painted'
        unified=b.G.A and b.l.eval("require('war.HeartVisualData').coarsePanel~=nil")
        assert b.G.heartDrawCount==(1 if unified or zoom>=.15 else 0),'Heart route draw at '+str(zoom)
        if unified:
          detail=b.l.eval("require('war.HeartArt').last.detailVisible")
          panel=b.l.eval("require('war.HeartArt').last.atlasPanel")
          assert detail==(zoom>=.15) and panel==(1 if zoom>=.15 else 0),'Cardiac detail gate '+str(zoom)
        assert b.l.eval('same(baseline,Save.snapshot(S))')
        samples.append({'zoom':zoom,'dpr':dpr,'time':time,'cardiacRouteDrawn':bool(b.G.heartDrawCount),'detailedHeartTextureDrawn':bool(b.G.heartDrawCount)and zoom>=.15})
        if dpr==1 and time==0 and zoom in [.06,.085,.12,.149,.15,.151]:
          name={.06:'context',.085:'whole-heart',.12:'chambers',.149:'zoom-0149',.15:'close',.151:'zoom-0151'}[zoom]
          p=out/(name+'.png');p.write_bytes(b.png(1024,768))
          frames.append({'file':str(p.relative_to(b.ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    assert b.G.A.stats()['images']==86
    b.G.game.camera.y=1210;b.G.game.zoom=.15;b.G.dpr=1
    b.reset();b.G.R.draw(b.G.game);(out/'ports.png').write_bytes(b.png(1024,768))
    b.l.execute('graphics.GetWidth=function()return 1440 end;graphics.GetHeight=function()return 1280 end;game.camera.y=1305;game.realTime=0')
    b.reset();b.G.R.draw(b.G.game)
    p=out/'full-heart-015.png';p.write_bytes(b.png(1440,1280))
    frames.append({'file':str(p.relative_to(b.ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'zoom':.15,'logicalSize':[1440,1280]})
    b.l.execute('A.release(worldContext);A.release(uiContext);assert(A.stats().images==0)')
    report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeEvidence':False,'samples':samples,'frames':frames,
      'twoContextsImageCount':86,'releaseLeaks':0,'renderStateUnchanged':True,'renderRNGConsumed':False,
      'limits':['SVG/Cairo approximation; native filtering/performance not measured.']}
    report['candidateVisualSha256']=hashlib.sha256((out/'HeartVisualData.lua').read_bytes()).hexdigest()
    report['activeRendererSha256']=hashlib.sha256((b.ROOT/'scripts/war/FullBodyMapArt.lua').read_bytes()).hexdigest()
    report['inputHashes']=binding
    report['inputsStable']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in binding.items())
    report['legacyTotalMapNotPaintedWhileReady']=bool(b.l.eval("require('war.HeartVisualData').quietResource~=nil"))
    assert report['inputsStable'],'Cardiac rendering inputs changed during checks'
    (out/'production-render-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'renderSamples':len(samples),'releaseLeaks':0}))

if __name__=='__main__':main()
