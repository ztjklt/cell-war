-- Named major circulation, with an anterior, game-readable planar unfolding.
-- Preserve legacy edge/node numbering; new branches are appended only.
local U=require('war.Util')
local O=require('war.Organs')
local L=U.copy(require('war.VesselLayout'))
L.version=2;L.organs=O.list;L.explicitGates=false
local positions={
 ra={2060,2460},rv={2030,2830},la={2300,2460},lv={2300,2910},
 pulmonary_trunk={2170,2170},aortic_root={2410,2690},aortic_arch={2320,2030},
 thoracic_aorta={2430,3290},aorta_celiac={2320,3520},aorta_sma={2310,3950},
 aorta_renal={2310,4300},aorta_ima={2270,4700},aorta_iliac={2230,5150},
 svc={1970,2140},ivc_upper={1990,3300},ivc_hepatic={2100,3530},ivc_renal={2140,4340},ivc_iliac={2020,5150},
 portal={2130,3860},coronary_sinus={1900,3070},willis={2048,1040},
 ['brain.a']={1998,630},['brain.v']={2098,750},
 ['lung_r.a']={1760,2630},['lung_r.v']={1750,2780},['lung_l.a']={2530,2510},['lung_l.v']={2530,2700},
 ['liver.a']={1950,3650},['liver.v']={1830,3420},['stomach.a']={2450,3460},['stomach.v']={2600,3830},
 ['spleen.a']={2820,3690},['spleen.v']={2840,3890},['gut.a']={2020,4600},['gut.v']={2110,4900},
 ['kidney_r.a']={1600,4350},['kidney_r.v']={1570,4490},['kidney_l.a']={2660,4230},['kidney_l.v']={2700,4350},
 ['myocardium.a']={2380,3040},['myocardium.v']={2280,3140},['pelvis.a']={1980,5470},['pelvis.v']={2110,5560},
}
local ids={}
-- Some historical IDs use abbreviated names. Explicit indices lock compatibility.
local fixed={ [1]={2060,2460},[2]={2030,2830},[3]={2300,2460},[4]={2300,2910},[5]={2170,2170},[6]={2410,2690},[7]={2320,2030},[8]={2430,3290},[9]={2440,3450},[10]={2440,3950},[11]={2440,4300},[12]={2270,4700},[13]={2230,5150},[14]={1970,2140},[15]={1990,3300},[16]={2100,3530},[17]={2140,4340},[18]={2020,5150},[28]={1850,1450},[29]={2246,1450},[27]={2048,1040},[32]={2130,3860},[33]={1900,3070}}
for i,n in ipairs(L.nodes) do
 local p=fixed[i] or positions[n.id];if p then n.x,n.y=p[1],p[2] end
 n.edges=nil;ids[n.id]=i
 if n.heart then n.rx=(i==2 or i==4) and 95 or 75;n.ry=(i==2 or i==4) and 165 or 100 end
end
local function node(id,name,x,y)
 local i=#L.nodes+1;L.nodes[i]={id=id,name=name,x=x,y=y,heart=false};ids[id]=i;return i
end
local function anchors(e,middle)
 local a,b=L.nodes[e.a],L.nodes[e.b];e.points={{a.x,a.y}}
 for _,p in ipairs(middle or {}) do e.points[#e.points+1]=p end
 e.points[#e.points+1]={b.x,b.y}
end
local function edge(a,b,name,system,width,middle,oxygen,organ)
 local e={a=a,b=b,name=name,system=system,width=width,oxygen=oxygen,organ=organ};anchors(e,middle)
 L.edges[#L.edges+1]=e;return #L.edges
end
for _,e in ipairs(L.edges) do
 anchors(e)
 e.curved=true
 -- Boolean precedence is made explicit for the oxygen marker.
 if e.system=='vein' or e.system=='portal' then e.oxygen='low' else e.oxygen='high' end
 if e.system=='pulmonary' then e.oxygen=(e.b==3) and 'high' or 'low' end
 if e.system=='coronary' and (e.a==53 or e.a==33) then e.oxygen='low' end
 if e.system=='valve' and (e.a==1 or e.a==2) then e.oxygen='low' end
end
local function find(a,b)
 for _,e in ipairs(L.edges) do if e.a==a and e.b==b then return e end end
 error('missing legacy vessel '..a..':'..b)
end
anchors(find(6,7),{{2500,2390},{2510,2140},{2410,1980}})
anchors(find(7,8),{{2530,2140},{2580,2690},{2520,3160}})
anchors(find(2,5),{{1850,2700},{1900,2240}})
anchors(find(5,36),{{1910,2210},{1750,2410}})
anchors(find(5,38),{{2430,2220}})
anchors(find(37,3),{{1810,2860},{1990,2720},{2220,2590}})
anchors(find(39,3),{{2470,2760},{2390,2570}})
anchors(find(35,28),{{1830,970},{1840,1220}})
anchors(find(35,29),{{2350,1010}})
anchors(find(31,14),{{2460,2000},{2180,2000}})
anchors(find(18,17),{{2080,4810}})
anchors(find(15,1),{{1910,2980}})
anchors(find(47,32),{{2230,4620},{2240,4180}})
anchors(find(45,32),{{2640,3940},{2360,3940}})
anchors(find(32,40),{{2090,3740}})
anchors(find(6,52),{{2570,2780},{2560,3010}})
local coronaryCount=0
for _,e in ipairs(L.edges) do if e.a==6 and e.b==52 then coronaryCount=coronaryCount+1
 if coronaryCount==2 then anchors(e,{{2250,2300},{1850,2390},{1810,2930},{2100,3180}}) end
end end
find(10,46).name='肠系膜上动脉·小肠';find(46,47).name='小肠组织交换区'
anchors(find(46,47),{{1820,4700},{1920,4950}})
find(13,54).name='膀胱供血';find(54,55).name='膀胱组织交换区'
local celiac=node('celiac_trunk','腹腔干',2160,3350)
local hepatic=node('common_hepatic','肝总动脉',1980,3400)
edge(9,celiac,'腹腔干','artery',33,{},'high')
edge(celiac,hepatic,'肝总动脉','artery',28,{},'high')
for _,e in ipairs(L.edges) do if e.a==9 and (e.b==40 or e.b==42 or e.b==44) then
 e.a=e.b==40 and hepatic or celiac
 if e.b==40 then e.name='肝固有动脉' elseif e.b==42 then e.name='胃左动脉' end
 anchors(e,e.b==44 and {{2410,3420},{2750,3540}} or nil)
end end
-- The circle of Willis is a real polygonal ring, not a single star junction.
local ring={27,node('willis_l','左后交通动脉',2248,950),node('willis_l_front','左前脑动脉',2210,805),node('willis_front','前交通动脉',2048,760),node('willis_r_front','右前脑动脉',1886,805),node('willis_r','右后交通动脉',1848,950)}
for i,a in ipairs(ring) do edge(a,ring[i%#ring+1],'脑底动脉环','artery',16,{},'high','brain') end
local rCarotid,lCarotid=find(20,27),find(21,27)
rCarotid.b=ring[6];lCarotid.b=ring[2];anchors(rCarotid);anchors(lCarotid)
edge(ring[4],34,'前脑动脉供血','artery',14,{{1960,700}},'high','brain')
local faceA=node('face.a','面部入流',1960,1370);local faceV=node('face.v','面部出流',2040,1460)
edge(20,faceA,'右颈外动脉','artery',18,{},'high')
edge(21,faceA,'左颈外动脉','artery',18,{},'high')
edge(faceA,faceV,'头面组织交换区','capillary',10,{},'exchange')
edge(faceV,28,'面静脉回流','vein',20,{},'low')
local pancreasA=node('pancreas.a','胰入流',2180,4040);local pancreasV=node('pancreas.v','胰出流',2490,4030)
edge(44,pancreasA,'脾动脉胰支','artery',16,{{2700,3970},{2440,3980}},'high','pancreas')
edge(10,pancreasA,'胰十二指肠动脉支','artery',14,{},'high','pancreas')
edge(pancreasA,pancreasV,'胰组织交换区','capillary',10,{{2310,4110}},'exchange','pancreas')
edge(pancreasV,32,'胰静脉门脉回流','portal',18,{{2310,3980}},'low','pancreas')
local colonA=node('colon.a','右半结肠入流',1570,4590);local colonV=node('colon.v','右半结肠出流',1580,4930)
local distalA=node('colon_distal.a','左半结肠入流',2630,4900);local distalV=node('colon_distal.v','左半结肠出流',2560,5130)
edge(10,colonA,'肠系膜上动脉·右半结肠','artery',24,{{2000,4250},{1660,4370}},'high','large_intestine')
edge(colonA,colonV,'右半结肠组织交换区','capillary',10,{{1530,4770}},'exchange','large_intestine')
edge(colonV,32,'结肠肠系膜上静脉','portal',20,{{1850,4560},{2110,4150}},'low','large_intestine')
local ima=find(12,46);ima.b=distalA;ima.name='肠系膜下动脉·左半结肠';anchors(ima,{{2480,4780}})
edge(distalA,distalV,'左半结肠组织交换区','capillary',10,{{2650,5060}},'exchange','large_intestine')
edge(distalV,45,'肠系膜下静脉至脾静脉汇流','portal',18,{{2730,4580},{2750,4150}},'low','large_intestine')
local internal=node('internal_iliac','髂内动脉',2080,5230)
local vesical=find(13,54);vesical.a=internal;vesical.name='膀胱上动脉';anchors(vesical)
edge(13,internal,'髂内动脉盆腔支','artery',24,{},'high','bladder')
local hepaticPortal=node('liver.portal','肝门静脉入口',2040,3590)
local portalDelivery=find(32,40);portalDelivery.b=hepaticPortal;anchors(portalDelivery,{{2080,3720}})
edge(hepaticPortal,40,'肝内门静脉至聚合交换区','portal',24,{},'low','liver')
-- Organ ports reference the very same graph nodes used for pathfinding.
local ports={brain={34,35},heart={52,53},lung_r={36,37},lung_l={38,39},liver={40,41},stomach={42,43},spleen={44,45},pancreas={pancreasA,pancreasV},small_intestine={46,47},large_intestine={colonA,colonV},kidney_r={48,49},kidney_l={50,51},bladder={54,55}}
for id,p in pairs(ports) do local o=O.byId[id];o.ports={artery=p[1],vein=p[2]};o.regions={{name='组织交换区',a=p[1],b=p[2]}} end
O.byId.liver.ports.portal=hepaticPortal;O.byId.large_intestine.regions[2]={name='左半结肠交换区',a=distalA,b=distalV}
for _,e in ipairs(L.edges) do
 e.curved=true
 if e.system=='capillary' then e.oxygen='exchange' end
 -- A mid-organ meander makes a visible exchange area instead of a tiny diagonal.
 if e.system=='capillary' and #e.points==2 then local a,b=e.points[1],e.points[2]
  local dx,dy=b[1]-a[1],b[2]-a[2];local len=math.sqrt(dx*dx+dy*dy)
  if len>0 then anchors(e,{{(a[1]+b[1])*.5-dy*.18,(a[2]+b[2])*.5+dx*.18}}) end
 end
end
return L
