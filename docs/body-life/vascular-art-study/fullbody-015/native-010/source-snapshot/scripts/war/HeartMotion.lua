-- Pure cardiac rhythm and displacement in the registered 1024 x 1536 frame.
-- Display motion never changes the simulation clock, collision, or saved state.
local M={period=1,amplitude=.085,atrialGain=1.15,maxOffsetSource=1}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function smooth(x)x=clamp(x,0,1);return x*x*(3-2*x)end
local function envelope(p,a,b,c)
 if p<=a or p>=c then return 0 end
 return p<b and smooth((p-a)/(b-a))or 1-smooth((p-b)/(c-b))
end
function M.sample(time)
 local phase=((time or 0)%M.period)/M.period
 local atrial=-envelope(phase,.01,.10,.23)+.18*envelope(phase,.22,.31,.43)
 local ventricular=-envelope(phase,.18,.30,.49)+.22*envelope(phase,.46,.59,.79)
 return {time=time or 0,phase=phase,atrial=atrial,ventricular=ventricular,
  pulse=math.max(0,-ventricular),atrialPulse=math.max(0,-atrial)}
end
-- Defaults are replaced with the authored chamber/connector contract at setup.
M.defaultContract={sourceBox={460,318,576,474},grid={12,16},edgeFadeSource=12,
 chambers={
  {id='right_atrium',kind='atrium',centerSource={494,375},radiusSource={13,13}},
  {id='left_atrium',kind='atrium',centerSource={534,374},radiusSource={12,12}},
  {id='right_ventricle',kind='ventricle',centerSource={500,417},radiusSource={15,22}},
  {id='left_ventricle',kind='ventricle',centerSource={537,425},radiusSource={14,25}},
 },connectors={}}
-- Exact frozen global route sections from docs/heart-v1/interface-contract.json.
-- These 13 source-box crossings are separate from the five proximal named ports.
M.crossBoxSourceBox={468,326,568,467}
M.crossBoxSections={
 {id='e009.heart-box.1',points={{534.55406941585272,464.449775976598},{539.34838164200698,469.550224023402}}},
 {id='e015.heart-box.1',points={{483.60928100232013,466.99432083843902},{476.60929021743368,467.00567916156098}}},
 {id='e017.heart-box.1',points={{482.20783306058888,326.24308221060443},{485.16817833699679,325.75691778939557}}},
 {id='e022.heart-box.1',points={{469.33838561195853,326.41280362313091},{472.22254453180324,325.58719637686909}}},
 {id='e067.heart-box.1',points={{532.96643208339049,325.73149838366038},{535.9179787166139,326.26850161633962}}},
 {id='e072.heart-box.1',points={{523.95509318233064,325.00379712980123},{526.19793052944954,326.99620287019877}}},
 {id='e153.heart-box.1',points={{504.82454895322797,325.2922541715767},{502.17948120940792,326.7077458284233}}},
 {id='e156.heart-box.1',points={{517.54511306792062,326.4036227292811},{514.65576110430823,325.5963772707189}}},
 {id='e158.heart-box.1',points={{529.56228646755471,327.18683031651545},{527.72769245273867,324.81316968348455}}},
 {id='e172.heart-box.1',points={{468.5822821647244,370.36266047206828},{467.4177178352756,371.98863400278009}}},
 {id='e173.heart-box.1',points={{468.25007095713005,412.04328970085635},{467.74992904286995,410.10683467540389}}},
 {id='e174.heart-box.1',points={{568.64086970258506,355.72128041629986},{567.35913029741494,354.18598106528253}}},
 {id='e175.heart-box.1',points={{568.5276576851013,420.55518157287935},{567.4723423148987,422.25409577595559}}},
}
function M.offset(x,y,contract,sampled,cellMargin)
 local q=sampled or M.sample(0);local b=contract.sourceBox
 local edge=math.min(x-b[1],b[3]-x,y-b[2],b[4]-y)
 local weight=smooth(edge/(contract.edgeFadeSource or 12))
 if weight==0 then return 0,0 end
 -- Section constraints are applied to the shared triangulation by
 -- HeartDisplayTransform. Local pins end near each actual interface, so a
 -- root never freezes an infinite stripe through unrelated heart chambers.
 local dx,dy,total=0,0,0
 local amplitude=clamp(contract.amplitude or M.amplitude,0,.10)
 for _,c in ipairs(contract.chambers or {})do
  local p,r=c.centerSource,c.radiiSource or c.radiusSource
  local rx,ry=1,1
  if type(r)=='table'then rx,ry=r[1],r[2]else rx,ry=r or 1,r or 1 end
  local xx,yy=(x-p[1])/rx,(y-p[2])/ry
  local distance=math.sqrt(xx*xx+yy*yy)
  local influence=1-smooth(distance/1.9)
  local beat=c.kind=='atrium'and q.atrial*clamp(contract.atrialGain or M.atrialGain,0,1.3)or q.ventricular
  dx=dx+(x-p[1])*amplitude*beat*influence
  dy=dy+(y-p[2])*amplitude*beat*influence
  total=total+influence
 end
 if total>1 then dx,dy=dx/total,dy/total end
 dx,dy=dx*weight,dy*weight
 local cap=math.min(contract.maxOffsetSource or M.maxOffsetSource,M.maxOffsetSource)
 local length=math.sqrt(dx*dx+dy*dy)
 if length>cap then return dx*cap/length,dy*cap/length end
 return dx,dy
end
return M
