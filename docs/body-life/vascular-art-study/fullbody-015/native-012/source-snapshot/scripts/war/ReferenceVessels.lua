-- Visible red/blue routes traced from reference.png. No inherited legacy vessel positions.
local M=require('war.ReferenceMap')
local L={version=4,nodes={},edges={},gates={},organs=M.organs,explicitGates=true}
local ids={}
local function node(id,x,y)
 if ids[id] then return ids[id] end
 local wx,wy=M.world(x,y);L.nodes[#L.nodes+1]={id=id,name=id,x=wx,y=wy,heart=false};ids[id]=#L.nodes;return #L.nodes
end
local function route(a,b,system,width,p)
 local points={};for i=1,#p,2 do local x,y=M.world(p[i],p[i+1]);points[#points+1]={x,y} end
 local na=node(a,p[1],p[2]);local nb=node(b,p[#p-1],p[#p])
 points[1]={L.nodes[na].x,L.nodes[na].y};points[#points]={L.nodes[nb].x,L.nodes[nb].y}
 local e={a=na,b=nb,name=a..' → '..b,system=system,oxygen=system=='vein' and 'low' or system=='capillary' and 'exchange' or 'high',width=width*2,points=points,curved=true}
 L.edges[#L.edges+1]=e;return #L.edges
end
local function gate(edge,x,y,nx,ny,name)
 local wx,wy=M.world(x,y);L.gates[#L.gates+1]={edge=edge,x=wx,y=wy,nx=nx,ny=ny,name=name}
end
-- Core routes independently traced from the new source. Organs occlude deep returns.
route('heart.a','arch','artery',7,{524,383,529,360,523,343,514,341})
route('arch','shoulder_r.a','artery',6,{514,341,493,320,485,294,465,280,442,278,420,286})
route('arch','shoulder_l.a','artery',6,{514,341,532,320,537,294,555,280,577,278,598,286})
route('shoulder_r.a','head_r.a','artery',4,{420,286,451,272,470,255,479,230,480,191,480,147})
route('shoulder_l.a','head_l.a','artery',4,{598,286,568,272,549,255,540,230,539,191,539,146})
route('head_r.a','brain_r','artery',2,{480,147,479,127,488,113,496,95})
route('head_l.a','brain_l','artery',2,{539,146,540,126,530,111,521,95})
route('brain_r','head_r.v','capillary',1.5,{496,95,491,109,487,125,490,150})
route('brain_l','head_l.v','capillary',1.5,{521,95,527,110,529,125,527,150})
route('head_r.v','heart.v','vein',5,{490,150,488,191,484,229,476,258,463,278,479,305,486,345,483,379})
route('head_l.v','heart.v','vein',5,{527,150,529,191,533,230,542,258,553,278,539,303,532,336,515,366,483,379})
route('arch','aorta_upper','artery',7,{514,341,528,358,535,398,535,446,524,481})
route('aorta_upper','aorta_mid','artery',6,{524,481,515,526,515,582})
route('aorta_mid','aorta_abd','artery',6,{515,582,518,635})
route('aorta_abd','iliac.a','artery',6,{518,635,517,685,512,719,509,747})
route('iliac.a','hip_r.a','artery',5,{509,747,474,754,446,772,435,801})
route('iliac.a','hip_l.a','artery',5,{509,747,544,754,568,773,577,802})
route('heart.v','cava_upper','vein',7,{483,379,481,410,480,452,481,482,477,521})
route('cava_upper','cava_mid','vein',5,{477,521,459,557,456,600})
local bridge=route('cava_mid','cava_abd','vein',4,{456,600,432,625,425,656});L.edges[bridge].hidden=true
route('cava_abd','iliac.v','vein',4,{425,656,421,694,435,726,469,747,509,763})
route('iliac.v','hip_r.v','vein',5,{509,763,477,763,452,779,439,811})
route('iliac.v','hip_l.v','vein',5,{509,763,540,763,565,779,579,811})
-- Blue return also skirts the screen-right intestine; it shares real pelvic nodes only.
local bridgeRight=route('cava_mid','gut_right.v','vein',4,{456,600,568,618,590,644});L.edges[bridgeRight].hidden=true
route('gut_right.v','iliac.v','vein',4,{590,644,597,668,597,692,582,727,548,749,509,763})
for _,p in ipairs({{'liver',446,520},{'stomach',563,532},{'kidney_r',421,611},{'kidney_l',600,611},{'gut',507,687},{'bladder',508,768}}) do
 local upper=p[3]<565;local ax,ay=upper and 524 or 515,upper and 481 or 582
 local a=route(upper and 'aorta_upper' or 'aorta_mid',p[1]..'.a','artery',2.5,{ax,ay,p[2]+9,p[3]+5,p[2],p[3]});L.edges[a].hidden=true
 local e=route(p[1]..'.a',p[1]..'.v','capillary',1.6,{p[2],p[3],p[2]-4,p[3]+9,p[2]-10,p[3]+5})
 local ve=route(p[1]..'.v',upper and 'cava_upper' or 'cava_mid','vein',2.5,{p[2]-10,p[3]+5,p[2]-15,p[3]+15,upper and 477 or 456,upper and 521 or 600});L.edges[ve].hidden=true
 L.edges[e].hidden=true;gate(e,p[2]-4,p[3]+9,0,1,p[1]..'组织膜口')
end
-- Arms authored separately: shoulder crossings are not graph junctions.
for _,s in ipairs({
 {'r',{420,286,395,289,376,304,355,344,334,392,320,430,308,479,297,523,292,555,271,602,253,660,233,732},{422,297,394,310,373,335,354,377,335,416,319,456,306,507,292,555,282,587,264,633,252,676,237,724,232,742}},
 {'l',{598,286,625,290,646,305,663,344,684,392,697,430,711,479,722,523,726,555,748,602,765,660,782,732},{596,297,624,310,646,335,664,377,684,416,700,456,711,507,726,555,736,587,754,633,765,676,780,724,782,742}},
}) do
 local side,red,blue=s[1],s[2],s[3]
 route('shoulder_'..side..'.a','wrist_'..side..'.a','artery',3.2,red)
 local wrist,elbow,fork,shoulder='wrist_'..side..'.v','elbow_'..side..'.v','armfork_'..side..'.v','shoulder_'..side..'.v'
 local fx,fy=side=='r' and 335 or 684,416
 local ex,ey=side=='r' and 292 or 726,555
 local forearm={};for i=#blue-1,15,-2 do forearm[#forearm+1]=blue[i];forearm[#forearm+1]=blue[i+1] end
 route(wrist,elbow,'vein',4,forearm)
 route(elbow,fork,'vein',4,{ex,ey,blue[13],blue[14],blue[11],blue[12],fx,fy})
 route(fork,shoulder,'vein',4,{fx,fy,blue[7],blue[8],blue[5],blue[6],blue[3],blue[4],blue[1],blue[2]})
 route(fork,elbow,'vein',2.2,side=='r' and {335,416,350,436,345,472,329,512,310,537,292,555} or {684,416,667,436,671,472,687,512,708,537,726,555})
 route(elbow,wrist,'vein',2.2,side=='r' and {292,555,281,590,259,632,242,682,232,742} or {726,555,737,590,759,632,775,682,782,742})
 local internal=route('shoulder_'..side..'.v','heart.v','vein',4,{blue[1],blue[2],side=='r' and 458 or 558,292,483,379});L.edges[internal].hidden=true
 local fingers=side=='r' and {{179,779},{193,802},{211,810},{228,805},{239,795}} or {{834,779},{820,802},{803,810},{786,805},{775,795}}
 local ax=red[#red-1];local vx=blue[#blue-1]
 for i,f in ipairs(fingers) do
  route('wrist_'..side..'.a',side..'.finger'..i..'.a','artery',1.5,{ax,732,ax+(f[1]-ax)*.55,767,f[1],f[2]})
  local bed=route(side..'.finger'..i..'.a',side..'.finger'..i..'.v','capillary',1.3,{f[1],f[2],f[1]+2,f[2]+3})
  route(side..'.finger'..i..'.v','wrist_'..side..'.v','vein',1.8,{f[1]+2,f[2]+3,vx+(f[1]-vx)*.6,770,vx,742});gate(bed,f[1]+2,f[2]+3,1,0,'指端膜口')
 end
end
for _,s in ipairs({
 {'r',{435,801,440,849,443,900,433,952,420,984,411,1027,405,1084,401,1152,399,1220,399,1280,400,1325,396,1360,381,1438},{439,811,433,854,426,896,414,943,405,985,397,1035,396,1090,398,1150,399,1210,399,1265,402,1318,397,1350,368,1438}},
 {'l',{577,802,573,850,570,901,580,952,594,984,600,1027,606,1084,609,1152,610,1220,609,1280,609,1325,614,1360,629,1438},{579,811,587,854,593,896,602,943,612,985,619,1035,620,1090,617,1150,615,1210,615,1265,609,1318,614,1350,647,1438}},
}) do
 local side,red,blue=s[1],s[2],s[3]
 route('hip_'..side..'.a','foot_'..side..'.a','artery',3,red)
 local foot,knee,fork,hip,calfFork='foot_'..side..'.v','knee_'..side..'.v','thighfork_'..side..'.v','hip_'..side..'.v','calffork_'..side..'.v'
 local calf={};for i=#blue-1,13,-2 do calf[#calf+1]=blue[i];calf[#calf+1]=blue[i+1] end
 route(foot,calfFork,'vein',4,calf)
 route(calfFork,knee,'vein',4,{blue[13],blue[14],blue[11],blue[12],blue[9],blue[10]})
 route(knee,fork,'vein',4,{blue[9],blue[10],blue[7],blue[8],blue[5],blue[6]})
 route(fork,hip,'vein',4,{blue[5],blue[6],blue[3],blue[4],blue[1],blue[2]})
 route(fork,knee,'vein',2.5,side=='r' and {426,896,403,922,394,942,397,963,405,985} or {593,896,614,922,622,942,619,963,612,985})
 -- Small visible calf twigs end locally; they do not invent a circulation shortcut.
 route(calfFork,side..'.calf_tip.v','vein',1.5,side=='r' and {396,1090,379,1094,370,1107} or {620,1090,635,1094,643,1107})
 local toes=side=='r' and {{351,1435},{365,1438},{378,1441},{392,1443},{403,1434}} or {{666,1435},{653,1438},{639,1441},{626,1443},{616,1434}}
 for i,f in ipairs(toes) do
  local ax,ay=red[#red-1],red[#red];local vx,vy=blue[#blue-1],blue[#blue]
  route('foot_'..side..'.a',side..'.toe'..i..'.a','artery',1.4,{ax,ay,f[1],f[2]-5,f[1],f[2]})
  local bed=route(side..'.toe'..i..'.a',side..'.toe'..i..'.v','capillary',1.2,{f[1],f[2],f[1]+2,f[2]+3})
  route(side..'.toe'..i..'.v','foot_'..side..'.v','vein',1.7,{f[1]+2,f[2]+3,f[1]+4,f[2]-4,vx,vy});gate(bed,f[1]+2,f[2]+3,1,0,'趾端膜口')
 end
end
local function access(a,b,x,y,nx,ny)
 for id,e in ipairs(L.edges) do if e.a==ids[a] and e.b==ids[b] then gate(id,x,y,nx,ny,'组织通行口');return end end
 error('missing reference access edge '..a..' '..b)
end
access('cava_upper','cava_mid',460,554,-1,0)
access('shoulder_r.a','wrist_r.a',316,445,-1,0)
access('hip_l.a','foot_l.a',572,871,1,0)
for _,e in ipairs(L.edges) do
 local a=L.nodes[e.a].id
 if a=='head_r.a' or a=='head_l.a' or a=='brain_r' or a=='brain_l' or a=='aorta_upper' or a=='aorta_mid' or a=='aorta_abd' or a=='iliac.a' then e.hidden=true end
end
return L
