-- Bilateral nasal mucosa unfolded into the face of the existing body map.
-- Polygon obstacles, vascular walls and drawings use the same canonical geometry.
local G={bounds={x=1080,y=360,w=216,h=160},home={x=1272,y=450},entry={x=1110,y=472}}
G.entries={{x=1110,y=472},{x=1114,y=410}}
local ox,oy=G.bounds.x,G.bounds.y
local function polygon(points)
 local p={};for i=1,#points,2 do p[#p+1]=ox+points[i];p[#p+1]=oy+points[i+1] end;return p
end
function G.contains(p,x,y)
 local inside=false;local j=#p-1
 for i=1,#p,2 do local ax,ay,bx,by=p[i],p[i+1],p[j],p[j+1]
  if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then inside=not inside end;j=i
 end;return inside
end
G.outline=polygon{0,104,8,82,20,64,22,40,32,22,56,8,106,0,160,10,196,28,212,58,216,110,204,142,180,158,128,160,72,152,28,144,8,128}
local function clip(p,value,greater)
 local out={};local ax,ay=p[#p-1],p[#p]
 for i=1,#p,2 do local bx,by=p[i],p[i+1];local a=(ax>=value)==greater;local b=(bx>=value)==greater
  if a~=b then local t=(value-ax)/(bx-ax);out[#out+1]=value;out[#out+1]=ay+(by-ay)*t end
  if b then out[#out+1]=bx;out[#out+1]=by end;ax,ay=bx,by
 end;return out
end
G.zones={
 {id="entry",name="入口黏膜",x=1114,y=472,polygon=clip(G.outline,1140,false)},
 {id="turbinate",name="鼻甲通道",x=1188,y=472,polygon=clip(clip(G.outline,1140,true),1234,false)},
 {id="barrier",name="后鼻屏障",x=1260,y=470,polygon=clip(G.outline,1234,true)},
}
G.obstacles={{name="鼻中隔",kind="septum",polygon=polygon{14,77,38,71,158,73,177,79,176,83,158,87,38,86,11,94}}}
local function concha(name,x,y,rx,ry)
 local p={};for i=0,23 do local a=i*math.pi/12;p[#p+1]=x+math.cos(a)*rx;p[#p+1]=y+math.sin(a)*ry end
 G.obstacles[#G.obstacles+1]={name=name,kind="concha",x=ox+x,y=oy+y,polygon=polygon(p)}
end
for _,side in ipairs({1,-1}) do
 local function mirror(y) return side==1 and y or 160-y end
 concha("上鼻甲",118,mirror(27),27,3.5)
 concha("中鼻甲",94,mirror(43),39,3.5)
 concha("下鼻甲",93,mirror(61),47,4)
end
G.landmarks={
 {name="左鼻腔",x=166,y=34},{name="右鼻腔",x=164,y=126},
 {name="鼻前庭",x=28,y=111},{name="嗅区",x=112,y=9},
 {name="上鼻道",x=100,y=35},{name="中鼻道",x=93,y=51},
 {name="下鼻道",x=94,y=70},{name="后鼻孔",x=182,y=80},
 {name="鼻底 / 硬腭",x=112,y=154},
}
for _,p in ipairs(G.landmarks) do p.x,p.y=ox+p.x,oy+p.y end
function G.allowed(x,y) return G.contains(G.outline,x,y) end
function G.blocked(x,y)
 for _,o in ipairs(G.obstacles) do if G.contains(o.polygon,x,y) then return true end end;return false
end
G.vascular={nodes={},edges={},gates={},organs={}}
local L=G.vascular
local function node(id,x,y,name) L.nodes[#L.nodes+1]={id=id,x=ox+x,y=oy+y,name=name,heart=false};return #L.nodes end
local fu=node("front_upper",40,30,"前鼻上支")
local ua=node("upper_a",70,18,"筛动脉前支")
local ub=node("upper_b",150,21,"筛动脉后支")
local ur=node("upper_rear",184,40,"后鼻上支")
local rear=node("rear",194,80,"蝶腭动脉调入支")
local lr=node("lower_rear",184,128,"后鼻下支")
local lb=node("lower_b",150,144,"下鼻甲血管丛")
local la=node("lower_a",65,139,"前鼻血管丛")
local fl=node("front_lower",40,121,"鼻前庭血管支")
local cu=node("cap_upper",44,50,"上侧黏膜交换区")
local du=node("cap_rear_upper",174,59,"后上黏膜交换区")
local cl=node("cap_lower",44,105,"下侧黏膜交换区")
local dl=node("cap_rear_lower",174,100,"后下黏膜交换区")
local function edge(a,b,name,system,width,via)
 local p={{L.nodes[a].x,L.nodes[a].y}}
 for _,v in ipairs(via or {}) do p[#p+1]={ox+v[1],oy+v[2]} end
 p[#p+1]={L.nodes[b].x,L.nodes[b].y}
 L.edges[#L.edges+1]={a=a,b=b,name=name,system=system,width=width,points=p};return #L.edges
end
edge(fu,ua,"前鼻上行支","artery",8)
edge(ua,ub,"上侧快速血管","artery",8,{{108,16}})
edge(ub,ur,"后上血管弯","artery",8)
edge(ur,rear,"后鼻上汇合","artery",10,{{195,58}})
edge(rear,lr,"后鼻下汇合","artery",10)
edge(lr,lb,"后下回流弯","vein",8)
edge(lb,la,"下侧快速血管","vein",8,{{106,147}})
edge(la,fl,"前鼻下行支","vein",8)
local a=edge(ua,cu,"前上黏膜支","capillary",6,{{49,34}})
local b=edge(ub,du,"后上黏膜支","capillary",6,{{173,39}})
local c=edge(la,cl,"前下黏膜支","capillary",6,{{47,127}})
local d=edge(lb,dl,"后下黏膜支","capillary",6,{{170,123}})
for _,q in ipairs({{a,cu,-1,0},{b,du,-1,0},{c,cl,-1,0},{d,dl,-1,0}}) do
 local n=L.nodes[q[2]];L.gates[#L.gates+1]={edge=q[1],x=n.x,y=n.y,nx=q[3],ny=q[4],name=n.name.."膜口"}
end
-- One rear exchange portal links the deployment vessel to both mucosal lanes.
L.gates[#L.gates+1]={edge=5,x=ox+190,y=oy+99,nx=-1,ny=0,name="后鼻调入膜口"}
return G
