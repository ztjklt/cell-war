-- Opt-in native view driver. Screenshots are taken externally by explicit user authorization.
local Q={}
local P=require("war.VascularMaterialArt")
local function canonical(v)
 if type(v)~='table' then return cjson.encode(v) end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local rows={};for _,k in ipairs(keys)do rows[#rows+1]=cjson.encode(tostring(k))..':'..canonical(v[k])end
 return '{'..table.concat(rows,',')..'}'
end
function Q.start(g,R,H,options)
 local opts=options or {}
 local OUT=opts.outputDir or 'qa/organ-atlas-native/vessel-pilot-001'
 local O,A,UI,Save=require('war.OrganBattlefield'),require('war.OrganAtlasArt'),require('urhox-libs/UI'),require('war.Save')
 for _,p in ipairs({'qa','qa/organ-atlas-native',OUT})do
  assert(fileSystem:DirExists(p) or fileSystem:CreateDir(p),p)
 end
 local ackFile=File(OUT..'/ack.txt',FILE_WRITE);assert(ackFile and ackFile:IsOpen())
 ackFile:WriteString('0\n');ackFile:Close()
 g.startOrganTrial();g.paused=true
 graphics:Raise()
 local frozen=canonical(Save.snapshot(g.state))
 local visibility=canonical(g.state.factions[1].visible)
 local steps={}
 for _,id in ipairs({'liver','stomach','brain','lung_r','lung_l','pancreas','kidney_r','kidney_l','large_intestine','small_intestine','bladder','heart'})do
  steps[#steps+1]={label=id..'-z0.15',organId=id,zoom=.15}
 end
 for _,z in ipairs({.085,.12,.149,.151})do steps[#steps+1]={label='stomach-z'..z,organId='stomach',zoom=z}end
 steps[#steps+1]={label='stomach-boundary-z0.15',organId='stomach',zoom=.15,boundary=true}
 steps[#steps+1]={label='whole-body',zoom=.006}
 steps[#steps+1]={label='map-popup',organId='stomach',zoom=.15,popup=true}
 if opts.steps then steps=opts.steps end
 local evidence={schema='native-system-capture/v1',outputDir=OUT,phases={},errors={},
  runId=tostring(os.time()),
  api=graphics:GetApiName(),physicalWidth=graphics:GetWidth(),physicalHeight=graphics:GetHeight(),dpr=graphics:GetDPR(),
  scope='Paused existing native organ trial; capture only the verified game window externally.'}
 local function write(name,value)
  local f=File(OUT..'/'..name,FILE_WRITE);assert(f and f:IsOpen(),name)
  f:WriteString(cjson.encode(value));f:Close()
 end
 local index,frames,draws,lastDraw,started,published,finished=0,0,0,0,false,false,false
 local old=R.draw
 R.draw=function(...)
  local result=table.pack(old(...));draws=draws+1
  return table.unpack(result,1,result.n)
 end
 _NativeScreenshotViewsEvents=ScriptObject()
 local node=Node();local receiver=node:CreateScriptObject('_NativeScreenshotViewsEvents')
 local function finish(reason)
  if finished then return end;finished=true
  evidence.finishedReason=reason;evidence.completed=reason=='all-views-captured'
  evidence.finalSnapshotUnchanged=canonical(Save.snapshot(g.state))==frozen
  evidence.finalVisibilityUnchanged=canonical(g.state.factions[1].visible)==visibility
  R.draw=old;receiver:UnsubscribeFromAllEvents();write('report.json',evidence)
  print('[NativeScreenshotViews] FINISHED '..reason)
 end
 local function advance()
  index=index+1;local step=steps[index]
  if not step then finish('all-views-captured');return end
  H.closeModal(g);g.paused=true;g.zoom=step.zoom
  local d=step.organId and O.organ(step.organId)
  local p=step.sourcePoint or (d and d.rooms[1].centerSource or {512,768})
  if step.boundary then p={d.sourceBox[1]+10,(d.sourceBox[2]+d.sourceBox[4])*.5}end
  g.camera={x=p[1]*2,y=p[2]*2+512};g.selection={}
  for id,e in pairs(g.state.entities)do
   if e.faction==1 and O.organAt(g.state,e,e.x,e.y)==step.organId then g.selection[id]=true end
  end
  H.sidebar(g)
  if step.popup then H.mapMenu(g)end
  frames=0;lastDraw=draws;published=false
 end
 receiver:SubscribeToEvent('Update',function()
  local ok,err=pcall(function()
   frames=frames+1
   if not started then
    if frames>=120 and A.ready(R.vg,g.state) and A.ready(UI.GetNVGContext(),g.state) and P.ready(R.vg,g.state) and P.ready(UI.GetNVGContext(),g.state)then started=true;advance()
    elseif frames>1200 then finish('resources-timeout')end
    return
   end
   if frames>18000 then finish('capture-ack-timeout');return end
   if frames>=60 and draws-lastDraw>=30 and not published then
    local step=steps[index]
    local row={runId=evidence.runId,index=index,total=#steps,label=step.label,organId=step.organId,zoom=g.zoom,camera=g.camera,
     frame=GetTime():GetFrameNumber(),draws=draws,phaseDraws=draws-lastDraw,realTime=g.realTime,fps=g.fps,
     simulationTime=g.state.time,tick=g.state.tick,rng=g.state.rng,modal=g.modal,
     worldReady=A.ready(R.vg,g.state),uiReady=A.ready(UI.GetNVGContext(),g.state),pilotWorldReady=P.ready(R.vg,g.state),pilotUiReady=P.ready(UI.GetNVGContext(),g.state),pilotStats=P.stats(),
     snapshotUnchanged=canonical(Save.snapshot(g.state))==frozen,
     visibilityUnchanged=canonical(g.state.factions[1].visible)==visibility}
    evidence.phases[#evidence.phases+1]=row;write('report.json',evidence);write('current.json',row)
    published=true;print('[NativeScreenshotViews] CAPTURE_READY '..index..' '..row.label)
   elseif published and fileSystem:FileExists(OUT..'/ack.txt')then
    local f=File(OUT..'/ack.txt',FILE_READ)
    if f and f:IsOpen()then local ack=tonumber(f:ReadLine());f:Close();if ack==index then advance()end end
   end
  end)
  if not ok then evidence.errors[#evidence.errors+1]=tostring(err);finish('driver-error')end
 end)
 write('report.json',evidence);print('[NativeScreenshotViews] START phases='..#steps)
 return evidence
end
return Q
