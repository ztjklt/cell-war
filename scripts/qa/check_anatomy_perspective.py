"""Exercise the production perspective callback, rendering and input isolation."""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
from PIL import Image

sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b


def main():
    out=b.ROOT/'docs/heart-simple-20261012/perspective-v7'
    b.l.execute('''
      S=require('war.FullBodyBattlefield').new(72026)
      R=require('war.Render');A=require('war.FullBodyMapArt')
      Ref=require('war.ReferenceArt');P=require('war.AnatomyPerspective')
      Save=require('war.Save');I=require('war.Input')
      worldContext={};uiContext={};R.vg=worldContext;R.font=1
      A.prepare(worldContext);A.prepare(uiContext)
      Ref.prepareOriginal(worldContext);Ref.prepareOriginal(uiContext)
      require('war.Cells').init(worldContext);R.prepare(S)
      assert(A.ready(worldContext,S)and A.ready(uiContext,S))
      function same(a,b)
       if type(a)~=type(b)then return false end
       if type(a)~='table'then return a==b end
       for k,v in pairs(a)do if not same(v,b[k])then return false end end
       for k in pairs(b)do if a[k]==nil then return false end end
       return true
      end
      baseline=Save.snapshot(S)
      game={state=S,zoom=.15,camera={x=1036,y=1305},selection={},started=true,
       fogDisabled=true,realTime=0,flowTime=S.time,pointer={wx=1,wy=1},groups={{},{},{}}}
      ui=package.loaded['urhox-libs/UI'];ui.GetScale=function()return density*dpr end
      H=require('war.HUD')
      H.refs={toolbar={GetAbsoluteLayout=function()return toolbarRect end},
       dock={GetAbsoluteLayout=function()return dockRect end},
       perspective={SetStyle=function(self,style)self.lastStyle=style end}}
      input={GetKeyDown=function()return false end}
      MOUSEB_LEFT=1;MOUSEB_RIGHT=4
      math.random=function()error('Perspective consumed RNG')end
      math.randomseed=function()error('Perspective reseeded RNG')end
    ''')
    original_path=(b.ROOT/'assets/image/anatomy-reference/reference.png').resolve()
    original_key=str(original_path)
    samples=[];frames=[]
    # Logical pixels, DPR and UI density vary independently. Invoke the actual
    # HUD callback so its conversion from UI bounds to map pixels is checked.
    for w,h,dpr in [(1280,720,1),(1024,768,2),(844,390,3),(430,932,3)]:
      density=max(.625,min(1,(min(w,h)/720)**.5))
      b.G.dpr=dpr;b.G.density=density
      b.G.graphics=b.l.table_from({'GetWidth':lambda *_:w*dpr,'GetHeight':lambda *_:h*dpr,'GetDPR':lambda *_:dpr})
      b.G.R.w=w;b.G.R.h=h
      b.G.toolbarRect=b.l.table_from({'x':w/density-400,'y':100/density,'w':388/density,'h':44/density})
      b.G.dockRect=b.l.table_from({'x':12/density,'y':(h-168)/density,'w':(w-24)/density,'h':156/density})
      b.l.execute("P.reset(game);game.zoom=.15;game.camera.x,game.camera.y=1036,1305")
      for zoom in [.003,.06,.149,.15,.25]:
        b.G.game.zoom=zoom;b.reset();b.G.R.draw(b.G.game)
        assert b.l.eval("require('war.HeartArt').last.atlasPanel==0")
        assert b.l.eval("require('war.HeartArt').last.detailVisible")
        assert b.decoded_images[original_key].key not in b.frame_images
        assert b.l.eval('same(baseline,Save.snapshot(S))')
        samples.append({'view':'map','logicalSize':[w,h],'dpr':dpr,'zoom':zoom,'fixedDetailedHeart':True})
        if w==1024 and zoom in [.06,.15]:
          name='internal-small.png'if zoom==.06 else'internal-heart.png'
          (out/name).write_bytes(b.png(w,h));frames.append(name)
      old=(b.G.game.camera.x,b.G.game.camera.y,b.G.game.zoom)
      b.G.H.togglePerspective(b.G.game)
      assert b.G.P.original(b.G.game)
      # Every original image corner must fit between the toolbar and dock.
      ax,ay=b.G.R.project(b.G.game,0,512)
      bx,by=b.G.R.project(b.G.game,2048,3584)
      assert 12<=ax<=bx<=w-12 and 156<=ay<=by<=h-180,(w,h,ax,ay,bx,by)
      b.reset();b.G.R.draw(b.G.game)
      assert b.frame_images=={b.decoded_images[original_key].key},'Mixed map art on original image'
      assert b.l.eval('same(baseline,Save.snapshot(S))')
      if w==1024:(out/'original-body.png').write_bytes(b.png(w,h));frames.append('original-body.png')
      # All anatomy popups/minimaps use the same selected original raster.
      b.reset();b.G.R.minimap(b.G.uiContext,b.G.game,b.l.table_from({'x':0,'y':0,'w':300,'h':400}),True,False)
      assert b.frame_images=={b.decoded_images[original_key].key}
      b.l.execute("selectionBefore=game.selection;commandsBefore=#S.commands;I.tap(game,200,200,true);assert(#S.commands==commandsBefore and game.selection==selectionBefore);assert(I.issue(game,'move',1,1)==false)")
      # In the original view, mouse drag pans instead of selecting invisible units.
      event=b.l.table_from({'x':200/density,'y':200/density,'pointerType':'mouse','pointerId':0,'button':1,'isPrimary':True})
      b.G.I.down(b.G.game,event);assert not b.G.game.drag.box
      b.G.R.pan(b.G.game,8,9);b.G.R.zoom(b.G.game,1.2)
      b.G.H.togglePerspective(b.G.game)
      assert not b.G.P.original(b.G.game)
      assert old==(b.G.game.camera.x,b.G.game.camera.y,b.G.game.zoom)
      assert b.l.eval('same(baseline,Save.snapshot(S))')
      samples.append({'view':'original','logicalSize':[w,h],'dpr':dpr,'onlyOriginalRaster':True,'fullImageFits':True,'cameraRestored':True,'worldInputIsolated':True})
    # The current heart is exactly the repaired panel; the mistaken old-heart
    # restoration from v6 is absent from the playable map at every scale.
    heart=b.l.eval("require('war.HeartVisualData').resource")
    exact=np.array(Image.open(b.ROOT/'assets'/heart).convert('RGBA'))
    repaired=np.array(Image.open(b.ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/unified-v5/heart-unified-atlas-v1.png').convert('RGBA'))[:,1200:]
    assert np.array_equal(exact,repaired)
    b.l.execute('A.release(worldContext);A.release(uiContext);Ref.release(worldContext);Ref.release(uiContext);assert(A.stats().images==0)')
    report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeVisualEvidence':False,
      'samples':samples,'sameSavedState':True,'sameVesselGeometry':True,
      'originalOnlyOneRaster':True,'mapHeartExactRepairedPanel':True,
      'automaticHeartZoomSwitchRemoved':True,'frames':frames,
      'heartSha256':hashlib.sha256((b.ROOT/'assets'/heart).read_bytes()).hexdigest(),
      'originalSha256':hashlib.sha256(original_path.read_bytes()).hexdigest(),
      'limitations':['SVG/Cairo rendering; native window pixels are not captured.']}
    (out/'perspective-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'samples':len(samples),'repairedHeartByteExact':True,'originalViewSingleRaster':True}))


if __name__=='__main__':main()
