"""Independent atlas/organ-boundary/near-view integration checks, offline only."""
import argparse,hashlib,io,json
from pathlib import Path
import numpy as np
import cv2
from PIL import Image
from lupa.lua54 import LuaRuntime
import render_body_closeups as c


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',default='docs/body-life/closeup-interactive-v2/organ-closeup-checks.json');a=p.parse_args();results=[];e={}
 def check(name,fn):
  try:fn();results.append({'name':name,'pass':True})
  except Exception as ex:results.append({'name':name,'pass':False,'error':str(ex)})
 def resources():
  l=LuaRuntime(unpack_returned_tuples=True);l.execute("""package.path='scripts/?.lua;'..package.path
   NVG_IMAGE_GENERATE_MIPMAPS=1;D=require('war.OrganDetail');O=require('war.OrganBoundaries');created=0;deleted=0;live={};nextId=0;failPath=false;failValue=0;paintHandles={}
   local function up(fn,key)for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==key then return value,i end end;error('missing tested runtime upvalue '..key)end
   local override=up(D.draw,'overrideImage');local names=up(override,'overrideNames');local fields,fieldIndex=up(D.draw,'fields')
   resourceKinds={};for _,id in ipairs(O.ids())do assert(names[id],'organ has no configured HD kind');resourceKinds[names[id]]=true end
   local kindCount=0;for _ in pairs(resourceKinds)do kindCount=kindCount+1 end;assert(kindCount==10)
   function nvgCreateImage(vg,path,flags)created=created+1;if path==failPath then if failValue=='nil'then return nil end;return failValue end;nextId=nextId+1;live[nextId]=vg;return nextId end
   function nvgDeleteImage(vg,id)assert(id>0 and live[id]==vg,'invalid/double/cross-context delete');live[id]=nil;deleted=deleted+1 end
   for _,name in ipairs({'nvgSave','nvgRestore','nvgIntersectScissor','nvgTranslate','nvgScale','nvgBeginPath','nvgMoveTo','nvgLineTo','nvgQuadTo','nvgBezierTo','nvgClosePath','nvgPathWinding','nvgFillPaint','nvgFill','nvgEllipse'})do _G[name]=function()end end
   function nvgImagePattern(vg,x,y,w,h,angle,id)paintHandles[#paintHandles+1]=id;return {}end
   require('war.BodyLife').enabled=false
   local function drawKind(vg,id)
    local field;for _,f in ipairs(fields)do if f.id==id then field=f end end;assert(field)
    debug.setupvalue(D.draw,fieldIndex,{field});paintHandles={}
    local r={vg=vg,project=function(g,x,y)return x,y end};local g={zoom=.15,realTime=0}
    local ok,err=pcall(function()assert(D.draw(r,g,{anatomyVersion=4},field.x1*2,field.x2*2,field.y1*2+512,field.y2*2+512));assert(D.last.details==1)end)
    debug.setupvalue(D.draw,fieldIndex,fields);assert(ok,err)
   end
   local a,b={},{};assert(D.prepare(a) and D.prepare(a) and D.prepare(b));assert(created==2 and D.images[a]~=D.images[b],'prepare eagerly loads HD')
   drawKind(a,'heart');local after=created;drawKind(a,'heart');assert(created==after);drawKind(b,'heart');assert(created==after+1)
   for _,id in ipairs(O.ids())do drawKind(a,id)end
   assert(created==2+kindCount+1,'shared left/right kinds load twice or configured resource omitted')
   D.release(a);D.release(a);local remaining=0;for _ in pairs(live)do remaining=remaining+1 end;assert(remaining==2)
   D.release(b);D.release(b);assert(not next(live))
   for _,value in ipairs({0,-1,'nil'})do
    -- Every optional override must use the working atlas and cache its failure.
    for _,id in ipairs(O.ids())do
     assert(D.prepare(a));failPath='image/anatomy-reference/body-life/'..names[id]..'-tissue-hires.png';failValue=value
     local before=created;drawKind(a,id);assert(created==before+1 and paintHandles[1]==D.images[a]);drawKind(a,id);assert(created==before+1)
     D.release(a);assert(not next(live));failPath=false
    end
    failPath='image/anatomy-reference/body-life/organ-tissue-atlas.png';failValue=value
    local before=created;assert(not D.prepare(a) and not D.prepare(a) and created==before+1);D.release(a);failPath=false;assert(D.prepare(a));D.release(a);assert(not next(live))
   end
   """)
  e['resourceStrategy']={'configuredKinds':sorted(l.globals().resourceKinds.keys()),'atlasLoadsBeforeVisibility':1,'overrides':'lazy per visible shared kind/context; failure cached with atlas fallback','failureValues':['nil',0,-1]}
 check('Actual configured HD kinds load lazily per context; missing overrides use atlas; all owned handles release',resources)
 c.r.initialise();b=c.r.b;b.l.execute("D=require('war.OrganDetail');O=require('war.OrganBoundaries');M=require('war.ReferenceMap');Save=require('war.Save');B=require('war.BodyLife')")
 D,O,M=b.l.globals().D,b.l.globals().O,b.l.globals().M
 def commands(x,y,z,t=1.92,dpr=1):
  b.reset();cy=y*2+512-.03*480/(32*z)
  b.l.execute(f"graphics={{GetWidth=function() return {640*dpr} end,GetHeight=function() return {480*dpr} end,GetDPR=function() return {dpr} end}};game.camera={{x={x*2},y={cy}}};game.zoom={z};game.realTime={t};R.draw(game)")
 def boundary():
  e['boundaries']={}
  for key in O.ids().values():
   o=O.get(key);count=0
   for path in o.interiorPaths.values():
    for pt in path.points.values():
     assert O.clearance(key,pt[1]*2,pt[2]*2+512)==0,(key,'boundary vertex admitted')
     count+=1
   bounds=o.bounds;inside=0
   for x in range(int(bounds[1])+1,int(bounds[3]),3):
    for y in range(int(bounds[2])+1,int(bounds[4]),3):inside+=int(bool(O.contains(key,x*2,y*2+512)))
   assert inside>0 and count>0,(key,inside,count)
   e['boundaries'][key]={'testedBoundaryVertices':count,'interiorGridSamples':inside,'cavities':len(o.cavityPaths)}
  assert len(O.get('large_intestine').cavityPaths)>0
  for x,y in [(495,683),(512,690),(525,705)]:assert not O.contains('large_intestine',x*2,y*2+512),(x,y,'large-intestine cavity filled')
 check('Every organ rejects boundary vertices and the large-intestine cavity remains empty',boundary)
 views=[v for v in c.catalog([.4],640,480,True) if v['anchor']=='center']
 def fields():
  # Query actual runtime draw fields, not the marrow cache left over from the
  # removed patch renderer. Missing/empty fields are an explicit test failure.
  b.l.execute("""function qaUp(fn,key)for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==key then return value,i end end;error('missing '..key)end
   qaFields,qaFieldsIndex=qaUp(D.draw,'fields');qaFillPaint=nvgFillPaint
   function qaSelectField(field)debug.setupvalue(D.draw,qaFieldsIndex,{field})end
   function qaRestoreFields()debug.setupvalue(D.draw,qaFieldsIndex,qaFields);nvgFillPaint=qaFillPaint end
   """)
  actual={f.id:f for f in b.l.globals().qaFields.values()};organIds=list(O.ids().values());assert len(organIds)==12
  assert all(key in actual for key in organIds),'an organ has no real rendered field'
  e['renderedFieldClips']={}
  try:
   for key in organIds:
    field=actual[key];assert len(field.paths)>0,(key,'empty paths')
    scale=min(600/(field.x2-field.x1+8),440/(field.y2-field.y1+8));x0=(field.x1+field.x2)/2-320/scale;y0=(field.y1+field.y2)/2-240/scale
    b.reset();b.l.globals().qaSelectField(field);b.l.globals().qaScale=scale;b.l.globals().qaX0=x0;b.l.globals().qaY0=y0
    b.l.execute("""nvgFillPaint=function(vg,paint)nvgFillColor(vg,nvgRGBA(255,255,255,255))end
     local rr={vg=R.vg,project=function(g,x,y)return (x*.5-qaX0)*64*g.zoom,((y-512)*.5-qaY0)*64*g.zoom end}
     local g={zoom=.15,realTime=0};nvgSave(rr.vg);nvgScale(rr.vg,qaScale/(64*g.zoom),qaScale/(64*g.zoom))
     assert(D.draw(rr,g,{anatomyVersion=4},qaX0*2,(qaX0+640/qaScale)*2,qaY0*2+512,(qaY0+480/qaScale)*2+512));nvgRestore(rr.vg);assert(D.last.details==1)
     """)
    rendered=np.array(Image.open(io.BytesIO(b.png(640,480))).convert('RGBA'))[:,:,3]>127
    expected=np.zeros((480,640),np.uint8)
    for path in O.paths(key).values():
     points=np.array([[round((pt[1]-x0)*scale),round((pt[2]-y0)*scale)] for pt in path.points.values()],np.int32);cv2.fillPoly(expected,[points],0 if path.hole else 255)
    radius=max(2,int(np.ceil(scale*2)));kernel=np.ones((radius*2+1,radius*2+1),np.uint8)
    core=cv2.erode(expected,kernel)>0;protected=cv2.dilate(expected,kernel)==0
    assert core.sum()>300 and rendered.sum()>300,(key,'vacuous/empty clip')
    coverage=float(rendered[core].mean());escaped=int(rendered[protected].sum())
    assert coverage>=.98 and escaped==0,(key,coverage,escaped)
    if key=='large_intestine':
     for sx,sy in [(495,683),(512,690),(525,705)]:assert not rendered[round((sy-y0)*scale),round((sx-x0)*scale)],'large gut hole painted'
    e['renderedFieldClips'][key]={'actualFieldPaths':len(field.paths),'renderedPixels':int(rendered.sum()),'interiorCorePixels':int(core.sum()),'coreCoverage':coverage,'protectedPixelsPainted':escaped,'edgeMarginSourcePixels':2}
  finally:b.l.globals().qaRestoreFields()
  assert len(e['renderedFieldClips'])==12,'not all real organ fields tested'
  e['organsAtZoom04']={}
  for v in views:
   assert O.contains(v['organ'],v['sourceCenter'][0]*2,v['sourceCenter'][1]*2+512),'tissue focus belongs to another region/hole'
   commands(*v['sourceCenter'],.4);count=int(D.last.details)
   e['organsAtZoom04'][v['organ']]={'renderedFieldsAndMarrow':count,'tissueFocus':v['sourceCenter'],'geometryCenter':v['geometryCenter']}
   assert D.last.ready and 0<count<=D.budget,(v['organ'],count)
   assert len(D['keys'])<=D.cacheLimit and len(list(D.cache.values()))<=D.cacheLimit
  pack=D.packs[b.l.globals().R.vg];names=e['resourceStrategy']['configuredKinds']
  e['actualHighResolutionLoads']={name:bool(pack[name] and pack[name]>0) for name in names}
  assert all(e['actualHighResolutionLoads'].values()),('delivered HD asset missing',e['actualHighResolutionLoads'])
 check('All twelve actual field draw clips have nonzero interior coverage, preserve protected space and large-gut cavity',fields)
 def state():
  b.l.execute('''
   function eq(a,b)if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not eq(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
   savedSnapshot=Save.snapshot(state);savedSeed=state.seed
   math.randomseed(91731);expectedRandom=math.random();math.randomseed(91731)
   ''')
  for i,v in enumerate(views):commands(*v['sourceCenter'],.15 if i%2 else .9,t=i*.37)
  b.l.execute("assert(eq(savedSnapshot,Save.snapshot(state)) and savedSeed==state.seed);assert(math.random()==expectedRandom)")
 check('Close-up navigation and animation leave Save snapshot and simulation random state unchanged',state)
 def fallback():
  b.l.execute('''D.release(R.vg);originalCreate=nvgCreateImage;nvgCreateImage=function(vg,path,flags)if path:find('organ%-tissue%-atlas')then return 0 end;return originalCreate(vg,path,flags)end''')
  try:
   v=next(v for v in views if v['organ']=='heart');commands(*v['sourceCenter'],.4)
   assert not D.last.ready
   assert b.l.eval("require('war.ReferenceArt').last.details")>0
  finally:b.l.execute('D.release(R.vg);nvgCreateImage=originalCreate')
 check('Missing atlas actually falls back to existing tissue drawing without absent anatomy',fallback)
 def dpr():
  v=next(v for v in views if v['organ']=='stomach');documents=[]
  for d in (1,2,3):commands(*v['sourceCenter'],.4,dpr=d);documents.append(b.document(640,480))
  assert len(set(documents))==1,'DPR changes logical drawing geometry'
 check('Atlas and membranes retain identical logical drawing commands at DPR 1/2/3',dpr)
 def continuity():
  e['continuousLOD']={};v=next(v for v in views if v['organ']=='lung_r')
  for z0,z1 in [(.079999,.080001),(.1499,.1501),(.199999,.200001),(.399999,.400001),(.899999,.900001)]:
   images=[]
   for z in (z0,z1):
    commands(*v['sourceCenter'],z);images.append(np.array(Image.open(io.BytesIO(b.png(640,480))).convert('RGB'),np.float32))
   raw=np.abs(images[1]-images[0]);ratio=z0/z1
   # Register camera magnification before judging the LOD change. Raw pixels
   # also include up to .43px of camera motion at .1499/.1501.
   aligned=cv2.warpAffine(images[1],np.array([[ratio,0,320*(1-ratio)],[0,ratio,240*(1-ratio)]],np.float32),(640,480),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
   delta=np.abs(aligned[3:-3,3:-3]-images[0][3:-3,3:-3]);row={'rawMeanRgbDifference':float(raw.mean()),'rawP99RgbDifference':float(np.percentile(raw,99)),'registrationScale':ratio,'meanRgbDifference':float(delta.mean()),'p99RgbDifference':float(np.percentile(delta,99)),'maxRgbDifference':float(delta.max())};e['continuousLOD'][f'{z0}/{z1}']=row
   assert row['meanRgbDifference']<1 and row['p99RgbDifference']<8,(z0,z1,row)
 check('Entry fade and .1499/.1501 atlas transition remain continuous in actual lossless frames',continuity)
 paths=list((b.ROOT/'scripts/war').glob('OrganDetail*.lua'))+list((b.ROOT/'scripts/war').glob('OrganBoundaries*.lua'))+list((b.ROOT/'scripts/war').glob('OrganForeground*.lua'))+[b.ROOT/'scripts/war/ReferenceArt.lua',b.ROOT/'scripts/war/Render.lua',b.ROOT/'scripts/war/HUD.lua',b.ROOT/'scripts/war/SmoothTerrain.lua',b.ROOT/'scripts/war/BodyLife.lua']
 report={'nativeEvidence':False,'passed':sum(x['pass'] for x in results),'total':len(results),'results':results,'evidence':e,'runtimeSha256':{str(x.relative_to(b.ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in paths},'limitations':['Context load failure is mocked; actual resource pixels are used for rendering checks.','Geometry and image differences do not establish perceptible motion or visual attractiveness.','Cairo filtering/AA differs from native NanoVG; no native frame time claim.']}
 Path(a.output).parent.mkdir(parents=True,exist_ok=True);Path(a.output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False,indent=2));assert report['passed']==report['total']
if __name__=='__main__':main()
