-- Pure visual mathematics in the original 1024 x 1536 source coordinates.
-- No engine, map, simulation, clock, random generator or save dependencies.
local M={}
-- Primary rhythms must survive the full-body view. Secondary organs retain
-- their much lower perfusion gains; this is not a global flashing overlay.
M.visual={heartShadow=.18,heartRebound=.065,lungLight=.065,lungShadow=.09,
 stomachWave=.09,smallGutWave=.10,largeGutWave=.065,limbPerfusion=.028}
local pi=math.pi
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function smooth(x) x=clamp(x,0,1);return x*x*(3-2*x) end
local function phaseAt(time,period)
 local phase=(time%period)/period
 if phase<1e-12 or 1-phase<1e-12 then return 0 end
 return phase
end
local function envelope(p,a,b,c)
 if p<a or p>c then return 0 end
 return p<b and smooth((p-a)/(b-a)) or 1-smooth((p-b)/(c-b))
end
M.specs={
 heart={x=478,y=382,w=79,h=77,nx=6,ny=6},
 lung_r={x=375,y=292,w=102,h=188,nx=5,ny=6},
 lung_l={x=541,y=294,w=99,h=186,nx=5,ny=6},
 stomach={x=490,y=457,w=127,h=115,nx=4,ny=5},
 small_intestine={x=463,y=653,w=89,h=77,nx=5,ny=6},
 large_intestine={x=437,y=610,w=148,h=135,nx=6,ny=7},
}
-- Curves follow visible tissue, not navigation geometry. Endpoints receive no
-- displaced endpoint geometry: deformation only uses the caller's interior weights.
M.paths={
 stomach={{550,480},{567,492},{588,501},{594,521},{579,541},{557,552},{535,553},{510,547}},
 small_intestine={{477,666},{495,677},{517,666},{537,675},{534,690},{514,685},{492,687},{477,691},{481,707},{498,713},{515,703},{535,707},{526,721},{511,722}},
 large_intestine={{449,711},{449,688},{449,662},{452,636},{475,630},{499,640},{524,638},{550,625},{568,646},{574,672},{573,698},{563,719},{543,731},{517,735},{491,733}},
}
local periods={heart=1,lung_r=4.8,lung_l=4.8,stomach=8,small_intestine=10,large_intestine=12,bladder=4.8}
local shifts={brain=0,liver=.08,pancreas=.22,kidney_r=.14,kidney_l=.31,bladder=.12,
 torso=.07,arm_r=.23,arm_l=.49,leg_r=.67,leg_l=.83,marrow=.37}
local gains={brain=.008,liver=.025,pancreas=.018,kidney_r=.022,kidney_l=.022,bladder=.006}
local prepared={}
for id,path in pairs(M.paths) do
 local nodes={};local cumulative=0
 for i,p in ipairs(path) do
  if i>1 then local q=path[i-1];cumulative=cumulative+math.sqrt((p[1]-q[1])^2+(p[2]-q[2])^2) end
  local prev,nextp=path[math.max(1,i-1)],path[math.min(#path,i+1)]
  local tx,ty=nextp[1]-prev[1],nextp[2]-prev[2];local length=math.sqrt(tx*tx+ty*ty)
  nodes[i]={x=p[1],y=p[2],nx=-ty/length,ny=tx/length,distance=cumulative}
 end
 prepared[id]={nodes=nodes,length=cumulative}
end
-- A compact pulse travels at constant arc speed. Neighboring tissue samples
-- crossfade; first/last pulse fade through silence instead of jumping at wrap.
function M.activeSegments(time,id)
 local p=prepared[id];if not p then return {} end
 local period=periods[id];local travel=phaseAt(time or 0,period)
 local padding=p.length/(#p.nodes-1)
 local at=travel*(p.length+2*padding)-padding
 local nodes=p.nodes;local a,b
 if at<0 then a={distance=-padding};b=nodes[1]
 elseif at>=p.length then a=nodes[#nodes];b={distance=p.length+padding}
 else
  for i=1,#nodes-1 do if at>=nodes[i].distance and at<nodes[i+1].distance then a=nodes[i];b=nodes[i+1];break end end
 end
 local mix=smooth((at-a.distance)/(b.distance-a.distance));local result={}
 for i,node in ipairs(nodes) do
  if node==a and 1-mix>1e-12 then result[#result+1]={index=i,weight=1-mix} end
  if node==b and mix>1e-12 then result[#result+1]={index=i,weight=mix} end
 end
 return result
end
function M.sample(time,id)
 local t=time or 0;id=id or 'heart'
 local phase=phaseAt(t,1)
 local beat=-envelope(phase,0,.13,.32)+.32*envelope(phase,.28,.39,.57)
 local bp=phaseAt(t,4.8)
 local breath=bp<.4 and smooth(bp/.4) or 1-smooth((bp-.4)/.6)
 local shift=shifts[id] or 0
 local perfusion=(gains[id] or .008)*math.sin(2*pi*(t-shift))
 if id=='brain' then perfusion=-beat*gains.brain
 elseif id=='bladder' then perfusion=(breath-.5)*2*gains.bladder
 elseif id=='heart' then perfusion=-beat*.065
 elseif id=='lung_r' or id=='lung_l' then perfusion=(breath-.5)*.03 end
 local period=periods[id] or 1
 return {time=t,beat=beat,breath=breath,phase=phaseAt(t,period),
  perfusion=perfusion,pulse=math.max(0,-beat),
  detail=.004*math.sin(2*pi*(t/11+shift)),segments=M.activeSegments(t,id)}
end
function M.lod(height,zoom)
 return smooth((height-16)/32)*(1-smooth(((zoom or 0)-.085)/.065))
end
function M.offset(id,v,s,time,scale,zoom,sampled)
 scale=math.max(scale or 0,0)
 local weight=clamp(v.weight or 0,0,1)*M.lod(s.h*scale,zoom)
 if weight==0 or scale==0 then return 0,0 end
 local q=sampled or M.sample(time,id);local dx,dy=0,0
 if id=='heart' then
  dx=(v.x-s.x-s.w*.5)*.08*q.beat
  dy=(v.y-s.y-s.h*.4)*.072*q.beat
 elseif id=='lung_r' or id=='lung_l' then
  dx=(v.x-s.x-s.w*.5)*.025*(q.breath-.5)*2
  dy=(v.y-s.y)*.02*(q.breath-.5)*2
 elseif prepared[id] then
  local radius=id=='stomach' and 30 or 20
  local amplitude=id=='large_intestine' and .005 or .01
  for _,active in ipairs(q.segments) do
   local node=prepared[id].nodes[active.index]
   local rx,ry=v.x-node.x,v.y-node.y
   local dist=math.sqrt(rx*rx+ry*ry)
   local falloff=1-smooth(dist/radius)
   local across=clamp((rx*node.nx+ry*node.ny)/radius,-1,1)
   -- across*falloff peaks at ~0.26, not 1. Normalize the local kernel so
   -- configured 1% tissue motion is not accidentally reduced fourfold.
   local contract=-across*falloff*3.85*active.weight*math.min(s.w,s.h)*amplitude
   dx,dy=dx+node.nx*contract,dy+node.ny*contract
  end
 end
 local cap=(id=='heart' and 1.5 or ((id=='lung_r' or id=='lung_l') and 2 or 1))/scale
 -- Bound source-space motion as well as screen motion. The old radius-based
 -- coefficients accidentally used only a fraction of these intended limits.
 if id=='heart' then cap=math.min(cap,math.min(s.w,s.h)*.02)
 elseif id=='lung_r' or id=='lung_l' then cap=math.min(cap,s.h*.015)
 elseif prepared[id] then cap=math.min(cap,math.min(s.w,s.h)*(id=='large_intestine' and .005 or .01)) end
 local length=math.sqrt(dx*dx+dy*dy);local k=length>cap and cap/length or 1
 return dx*weight*k,dy*weight*k
end
return M
