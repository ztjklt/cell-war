-- Opt-in native view driver. Screenshots are taken externally by explicit user authorization.
local Q={}
local P=require("war.FullBodyMapArt")
local function canonical(v)
 if type(v)~='table' then return cjson.encode(v) end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local rows={};for _,k in ipairs(keys)do rows[#rows+1]=cjson.encode(tostring(k))..':'..canonical(v[k])end
 return '{'..table.concat(rows,',')..'}'
end
function Q.start(g,R,H,options)
 local opts=options or {}
 local OUT=opts.outputDir or 'qa/organ-atlas-native/fullbody-015-001'
 local O,A,UI,Save=require('war.OrganBattlefield'),require('war.FullBodyMapArt'),require('urhox-libs/UI'),require('war.Save')
 for _,p in ipairs({'qa','qa/organ-atlas-native',OUT})do
  assert(fileSystem:DirExists(p) or fileSystem:CreateDir(p),p)
 end
 local ackFile=File(OUT..'/ack.txt',FILE_WRITE);assert(ackFile and ackFile:IsOpen())
 ackFile:WriteString('0\n');ackFile:Close()
 g.startFullBodyMap();g.paused=true
 local visualProbes=opts.visibleProbes and require('qa.FullBodyMapVisibleCells').populate(g)or nil
 graphics:Raise()
 local frozen=canonical(Save.snapshot(g.state))
 local visibility=canonical(g.state.factions[1].visible)
 local steps={}
 for _,id in ipairs({'liver','stomach','brain','lung_r','lung_l','pancreas','kidney_r','kidney_l','large_intestine','small_intestine','bladder','heart'})do
  steps[#steps+1]={label=id..'-z0.15',organId=id,zoom=.15}
 end
 for _,z in ipairs({.085,.12,.149,.151})do steps[#steps+1]={label='stomach-z'..z,organId='stomach',zoom=z}end
 steps[#steps+1]={label='stomach-boundary-z0.15',organId='stomach',zoom=.15,boundary=true}
 steps[#steps+1]={label='whole-body',zoom=.0025}
 steps[#steps+1]={label='map-popup',organId='stomach',zoom=.15,popup=true}
 for _,v in ipairs({
  {'aortic-arch',528,349},{'celiac-stomach',532,490},{'portal',511,550},
  {'mesenteric',516,670},{'pelvis-main',509,753},{'arm-right',335,440},
  {'arm-left',685,440},{'leg-right',434,920},{'leg-left',581,920},
  {'foot-right',371,1440},{'foot-left',650,1440},{'neck-main',510,233},
  -- Center the coronary entry so its fixed shared node is outside the HUD.
  {'coronary-entry',542,385}
 })do steps[#steps+1]={label=v[1]..'-z0.15',sourcePoint={v[2],v[3]},zoom=.15}end
 -- Distal circulation and head entry need actual .15 views; an arm or a brain
 -- room centered screenshot cannot certify these separate regions.
 for _,v in ipairs({{'head-entry',510,119},{'hand-right',220,741},{'hand-left',794,741}})do
  steps[#steps+1]={label=v[1]..'-z0.15',sourcePoint={v[2],v[3]},zoom=.15}
 end
 -- Follow the distinct bend/width-change regions to the distal endpoints.
 -- Palm/upper-arm views alone do not cover fingers, elbow and wrist joins.
 for _,v in ipairs({
  {'neck-upper',510,173},
  {'brain-entry-right',488,123},{'brain-entry-left',538,123},
  {'elbow-right',300,555},{'elbow-left',721,555},
  {'forearm-right',273,650},{'forearm-left',747,650},
  {'wrist-right',234,735},{'wrist-left',788,735},
  {'fingers-right',211,797},{'fingers-left',804,797},
  {'knee-right',420,1004},{'knee-left',600,1004},
  {'shin-right',420,1150},{'shin-left',600,1150},
  {'calf-right',411,1250},{'calf-left',610,1250},
  {'ankle-right',400,1320},{'ankle-left',620,1320},
  {'heel-right',397,1380},{'heel-left',627,1380}
 })do steps[#steps+1]={label=v[1]..'-z0.15',sourcePoint={v[2],v[3]},zoom=.15}end
 if opts.steps then steps=opts.steps end
 local evidence={schema='native-system-capture/v1',outputDir=OUT,phases={},errors={},
  visualProbes=visualProbes,
  runId=tostring(os.time()),
  api=graphics:GetApiName(),physicalWidth=graphics:GetWidth(),physicalHeight=graphics:GetHeight(),dpr=graphics:GetDPR(),
  scope='Paused new fullbody map; capture only the verified game window externally.'}
 local function write(name,value)
  local f=File(OUT..'/'..name,FILE_WRITE);assert(f and f:IsOpen(),name)
  f:WriteString(cjson.encode(value));f:Close()
 end
 local index,frames,draws,lastDraw,started,published,finished=0,0,0,0,false,false,false
 local old=R.draw
 local fixedCamera,fixedZoom
 R.draw=function(...)
  if fixedCamera then g.camera.x=fixedCamera.x;g.camera.y=fixedCamera.y;g.zoom=fixedZoom end
  local result=table.pack(old(...));draws=draws+1
  return table.unpack(result,1,result.n)
 end
 _FullBodyMapNativeEvents=ScriptObject()
 local node=Node();local receiver=node:CreateScriptObject('_FullBodyMapNativeEvents')
 local function finish(reason)
  if finished then return end;finished=true
  evidence.finishedReason=reason;evidence.completed=reason=='all-views-captured'
  evidence.finalSnapshotUnchanged=canonical(Save.snapshot(g.state))==frozen
  evidence.finalVisibilityUnchanged=canonical(g.state.factions[1].visible)==visibility
  R.draw=old;receiver:UnsubscribeFromAllEvents();write('report.json',evidence)
  print('[FullBodyNative] FINISHED '..reason)
 end
 local function advance()
  index=index+1;local step=steps[index]
  if not step then finish('all-views-captured');return end
  H.closeModal(g);g.paused=true;g.zoom=step.zoom
  local d=step.organId and O.organ(step.organId)
  local p=step.sourcePoint or (d and d.rooms[1].centerSource or {512,768})
  if step.boundary then p={d.sourceBox[1]+10,(d.sourceBox[2]+d.sourceBox[4])*.5}end
  g.camera={x=p[1]*2,y=p[2]*2+512};g.selection={}
  fixedCamera={x=g.camera.x,y=g.camera.y};fixedZoom=step.zoom
  if opts.beforeView then opts.beforeView(step)end
  for id,e in pairs(g.state.entities)do
   if e.faction==1 and O.organAt(g.state,e,e.x,e.y)==step.organId then g.selection[id]=true end
  end
  if visualProbes and visualProbes[step.label]then
   g.selection={}
   for _,cell in ipairs(visualProbes[step.label].cells)do if cell.selected then g.selection[cell.id]=true end end
  end
  H.sidebar(g)
  if step.popup then H.mapMenu(g)end
  frames=0;lastDraw=draws;published=false
 end
 receiver:SubscribeToEvent('Update',function()
  local ok,err=pcall(function()
   frames=frames+1
   if not started then
    if frames>=120 and A.ready(R.vg,g.state) and A.ready(UI.GetNVGContext(),g.state)then started=true;advance()
    elseif frames>1200 then finish('resources-timeout')end
    return
   end
   if published and frames%15==0 then
    local row=evidence.phases[#evidence.phases]
    if row then row.camera={x=g.camera.x,y=g.camera.y};row.zoom=g.zoom;row.wallTime=os.time();row.realTime=g.realTime;write('current.json',row)end
   end
   if frames>18000 then finish('capture-ack-timeout');return end
   if frames>=60 and draws-lastDraw>=30 and not published then
    local step=steps[index]
    local row={runId=evidence.runId,index=index,total=#steps,label=step.label,organId=step.organId,zoom=g.zoom,camera={x=g.camera.x,y=g.camera.y},wallTime=os.time(),
     frame=GetTime():GetFrameNumber(),draws=draws,phaseDraws=draws-lastDraw,realTime=g.realTime,fps=g.fps,
     simulationTime=g.state.time,tick=g.state.tick,rng=g.state.rng,modal=g.modal,
     worldReady=A.ready(R.vg,g.state),uiReady=A.ready(UI.GetNVGContext(),g.state),fullbodyStats=A.stats(),
     snapshotUnchanged=canonical(Save.snapshot(g.state))==frozen,
     visualProbes=visualProbes and visualProbes[step.label]or nil,
     visibilityUnchanged=canonical(g.state.factions[1].visible)==visibility}
    evidence.phases[#evidence.phases+1]=row;write('report.json',evidence);write('current.json',row)
    published=true;print('[FullBodyNative] CAPTURE_READY '..index..' '..row.label)
   elseif published and fileSystem:FileExists(OUT..'/ack.txt')then
    local f=File(OUT..'/ack.txt',FILE_READ)
    if f and f:IsOpen()then local ack=tonumber(f:ReadLine());f:Close();if ack==index then advance()end end
   end
  end)
  if not ok then evidence.errors[#evidence.errors+1]=tostring(err);finish('driver-error')end
 end)
 write('report.json',evidence);print('[FullBodyNative] START phases='..#steps)
 return evidence
end
return Q
