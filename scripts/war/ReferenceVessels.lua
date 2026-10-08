-- Visible red/blue routes traced from reference.png. No inherited legacy vessel positions.
local M=require('war.ReferenceMap')
local L={version=3,nodes={},edges={},gates={},organs=M.organs,explicitGates=true}
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
route('heart.a','arch','artery',9,{532,408,542,396,550,381,541,364,521,359})
route('arch','shoulder_r.a','artery',8,{521,359,497,345,491,315,474,291,453,285,428,291,409,300})
route('arch','shoulder_l.a','artery',8,{521,359,534,339,539,313,549,293,573,286,601,293,613,299})
route('shoulder_r.a','head_r.a','artery',6,{409,300,448,279,475,257,483,227,484,193})
route('shoulder_l.a','head_l.a','artery',6,{613,299,576,277,549,254,539,224,539,190})
route('head_r.a','brain_r','artery',3,{484,193,482,166,482,142,489,126,498,105})
route('head_l.a','brain_l','artery',3,{539,190,542,166,544,143,537,124,526,105})
route('brain_r','head_r.v','capillary',2,{498,105,491,114,496,135,498,178})
route('brain_l','head_l.v','capillary',2,{526,105,533,118,527,139,527,178})
route('head_r.v','heart.v','vein',6,{498,178,494,222,487,258,473,282,477,309,483,355,482,390})
route('head_l.v','heart.v','vein',6,{527,178,530,221,538,259,552,282,551,317,548,348,516,363,482,390})
route('arch','aorta_upper','artery',8,{521,359,542,365,553,402,557,449,550,490})
route('aorta_upper','aorta_mid','artery',8,{550,490,535,544,531,606})
route('aorta_mid','aorta_abd','artery',8,{531,606,537,664})
route('aorta_abd','iliac.a','artery',7,{537,664,547,703,548,748,538,783,526,820})
route('iliac.a','hip_r.a','artery',6,{526,820,479,812,450,802,430,815,415,850})
route('iliac.a','hip_l.a','artery',6,{526,820,558,802,586,812,605,832,616,863})
route('heart.v','cava_upper','vein',9,{482,390,473,419,479,455,475,483,460,500,451,551})
route('cava_upper','cava_mid','vein',7,{451,551,450,604})
route('cava_mid','cava_abd','vein',6,{450,604,444,655})
route('cava_abd','iliac.v','vein',6,{444,655,426,684,429,736,452,779,482,814,511,834})
route('iliac.v','hip_r.v','vein',6,{511,834,477,845,446,879,426,896})
route('iliac.v','hip_l.v','vein',6,{511,834,554,824,579,853,597,893})
-- Lung trees are bronchi, defined separately in TracheaTerrain.airways.
for _,p in ipairs({{'liver',455,544},{'stomach',581,545},{'kidney_r',419,641},{'kidney_l',606,641},{'gut',509,713},{'bladder',511,800}}) do
 local upper=p[3]<590;local ax,ay=upper and 550 or 531,upper and 490 or 606
 local a=route(upper and 'aorta_upper' or 'aorta_mid',p[1]..'.a','artery',3,{ax,ay,p[2]+9,p[3]+5,p[2],p[3]});L.edges[a].hidden=true
 local e=route(p[1]..'.a',p[1]..'.v','capillary',2,{p[2],p[3],p[2]-4,p[3]+9,p[2]-10,p[3]+5})
 local ve=route(p[1]..'.v',upper and 'cava_upper' or 'cava_mid','vein',3,{p[2]-10,p[3]+5,p[2]-15,p[3]+15,upper and 451 or 450,upper and 551 or 604});L.edges[ve].hidden=true
 L.edges[e].hidden=true
 gate(e,p[2]-4,p[3]+9,0,1,p[1]..'组织膜口')
end
-- Arms and hands: screen-left and screen-right authored independently, never mirrored.
for _,s in ipairs({
 {'r',{409,300,388,319,373,356,361,397,341,435,323,478,307,524,292,560,279,606,261,661,247,711,244,754},{409,308,394,328,379,369,359,418,347,456,330,497,310,540,296,586,281,637,263,691,253,727,248,765}},
 {'l',{613,299,634,320,650,354,662,397,682,435,700,480,714,524,730,560,745,607,762,661,777,710,777,754},{615,309,630,329,646,370,666,419,679,456,696,498,713,541,727,587,743,638,760,691,768,727,773,765}},
}) do
 local side,red,blue=s[1],s[2],s[3]
 route('shoulder_'..side..'.a','wrist_'..side..'.a','artery',4,red)
 local reverse={};for i=#blue-1,1,-2 do reverse[#reverse+1]=blue[i];reverse[#reverse+1]=blue[i+1] end
 route('wrist_'..side..'.v','shoulder_'..side..'.v','vein',4,reverse)
 local internal=route('shoulder_'..side..'.v','heart.v','vein',4,{blue[1],blue[2],side=='r' and 440 or 585,295,482,390})
 L.edges[internal].hidden=true -- return is occluded by the lungs in the reference
 local fingers=side=='r' and {{201,814},{214,809},{229,824},{243,809},{253,811}} or {{822,814},{810,809},{795,824},{780,809},{770,811}}
 for i,f in ipairs(fingers) do
  local wx=side=='r' and 244 or 777;local vx=side=='r' and 248 or 773
  route('wrist_'..side..'.a',side..'.finger'..i..'.a','artery',2.3,{wx,754,wx+(f[1]-wx)*.6,794,f[1],f[2]})
  local bed=route(side..'.finger'..i..'.a',side..'.finger'..i..'.v','capillary',1.6,{f[1],f[2],f[1]+3,f[2]+4})
  route(side..'.finger'..i..'.v','wrist_'..side..'.v','vein',2,{f[1]+3,f[2]+4,vx+(f[1]-vx)*.6,794,vx,765})
  gate(bed,f[1]+3,f[2]+4,1,0,'指端膜口')
 end
end
for _,s in ipairs({
 {'r',{415,850,419,898,423,942,413,983,393,1030,385,1080,388,1140,396,1203,394,1263,391,1318,375,1360,352,1407},{426,896,421,936,415,978,415,1035,412,1100,412,1160,408,1220,402,1281,399,1319,386,1360,366,1418}},
 {'l',{616,863,613,902,608,945,616,983,638,1030,646,1080,641,1140,633,1203,633,1263,632,1318,648,1360,673,1407},{597,893,600,935,609,978,610,1035,613,1100,614,1160,618,1220,624,1281,625,1319,640,1360,659,1418}},
}) do
 local side,red,blue=s[1],s[2],s[3];route('hip_'..side..'.a','foot_'..side..'.a','artery',4,red)
 local reverse={};for i=#blue-1,1,-2 do reverse[#reverse+1]=blue[i];reverse[#reverse+1]=blue[i+1] end
 route('foot_'..side..'.v','hip_'..side..'.v','vein',4,reverse)
 local toes=side=='r' and {{348,1431},{359,1417},{374,1414},{385,1419},{399,1412}} or {{675,1431},{664,1417},{649,1414},{638,1419},{624,1412}}
 for i,f in ipairs(toes) do
  local ax,ay=red[#red-1],red[#red];local vx,vy=blue[#blue-1],blue[#blue]
  route('foot_'..side..'.a',side..'.toe'..i..'.a','artery',2,{ax,ay,f[1],math.min(1420,f[2]-4),f[1],f[2]})
  local bed=route(side..'.toe'..i..'.a',side..'.toe'..i..'.v','capillary',1.6,{f[1],f[2],f[1]+3,f[2]+3})
  route(side..'.toe'..i..'.v','foot_'..side..'.v','vein',2,{f[1]+3,f[2]+3,f[1]+5,math.min(1422,f[2]+1),vx,vy})
  gate(bed,f[1]+3,f[2]+3,1,0,'趾端膜口')
 end
end
-- Name-based bindings survive authored branch insertion/removal.
local function access(a,b,x,y,nx,ny)
 for id,e in ipairs(L.edges) do if e.a==ids[a] and e.b==ids[b] then gate(id,x,y,nx,ny,'组织通行口');return end end
 error('missing reference access edge '..a..' '..b)
end
access('cava_upper','cava_mid',450.55,575,-1,0)
access('shoulder_r.a','wrist_r.a',323,478,1,0)
access('hip_l.a','foot_l.a',613,902,1,0)
-- Cranial returns and abdominal trunks pass behind the foreground organs.
for _,e in ipairs(L.edges) do
 local a,b=L.nodes[e.a].id,L.nodes[e.b].id
 if a=='head_r.a' or a=='head_l.a' or a=='brain_r' or a=='brain_l' or a=='head_r.v' or a=='head_l.v' or a=='aorta_upper' or a=='aorta_mid' or a=='aorta_abd' or a=='iliac.a' or a=='iliac.v' then e.hidden=true end
end
return L
