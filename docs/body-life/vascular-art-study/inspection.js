/* A read-only replay of real Lua coordinates. No browser movement simulation. */
'use strict';
const $=s=>document.querySelector(s),NS='http://www.w3.org/2000/svg';
function svg(tag,attributes){const e=document.createElementNS(NS,tag);for(const [k,v] of Object.entries(attributes))e.setAttribute(k,v);return e;}
const source=p=>[p[0]/2,(p[1]-512)/2],fmt=p=>source(p).map(x=>x.toFixed(2)).join(', '),points=p=>p.map(q=>q.join(',')).join(' ');
let graph,report,geometry,contract,organIndex=0,zoom=.15,center=[563,532],selected=0,elapsed=0,playing=false,lastFrame=0;
const paths=[],stage=$('#stage');
function blend(z){const p=geometry.projection,t=Math.max(0,Math.min(1,(z-p.overviewEnd)/(p.fillFull-p.overviewEnd)));return t*t*(3-2*t);}
function view(){if(!graph)return;const box=stage.getBoundingClientRect(),scale=geometry.projection.sourceScale*geometry.projection.logicalCellSize*zoom;
 const w=box.width/scale,h=box.height/scale;stage.setAttribute('viewBox',`${center[0]-w/2} ${center[1]-h/2} ${w} ${h}`);
 for(const [k,v] of Object.entries({x:center[0]-w/2,y:center[1]-h/2,width:w,height:h}))$('#viewport').setAttribute(k,v);
 const b=blend(zoom);$('#art').setAttribute('opacity',1-b);$('#flat').setAttribute('opacity',b);$('#routes').setAttribute('opacity',.15+.85*b);
 $('#zoom').value=zoom;$('#zoomText').value=zoom.toFixed(3);$('#viewStatus').textContent=`zoom ${zoom.toFixed(3)} · 检视层 ${Math.round(b*100)}% · 1 原图像素 = ${scale.toFixed(2)} 逻辑像素`;
}
function focusPoint(kind){const o=report.interfaces[organIndex];center=source(kind==='entry'?o.entryWorld:kind==='exit'?o.exitWorld:o.membraneCentre);view();}
function showPorts(index){organIndex=index;$('#organ').value=index;$('#ports').replaceChildren();const o=report.interfaces[index];
 for(const port of contract.regions.find(r=>r.id===o.id).ports){const [x,y]=port.source,color={supply:'#a1524e',return:'#316a89',controlledTissueAccess:'#3f784e',portalSupply:'#8e658d'}[port.role];$('#ports').append(svg('rect',{x:x-.6,y:y-.6,width:1.2,height:1.2,fill:'#eef0df',stroke:color,'stroke-width':.3,'data-port':port.id}));}
}
function selectOrgan(index){showPorts(index);const o=report.interfaces[index];
 focusPoint('access');const m=report.movementTests.findIndex(t=>t.interfaceId===o.id&&t.direction==='forward');if(m>=0)selectMovement(m,false);
}
function selectMovement(index,focus=true){selected=index;elapsed=0;playing=false;$('#play').textContent='播放记录';$('#movement').value=index;const t=report.movementTests[index];const trace=t.trace||[];
 if(focus){const part=t.id.split('.'),region=t.interfaceId||(['elbow','wrist'].includes(part[1])?'arm_':'leg_')+part[0];const i=report.interfaces.findIndex(o=>o.id===region);if(i>=0)showPorts(i);}
 $('#trail').setAttribute('points',points(trace.map(p=>source([p.x,p.y]))));if(trace.length&&focus)center=source([trace[0].x,trace[0].y]);view();renderReplay();
}
function renderReplay(){const t=report.movementTests[selected];if(!t)return;const trace=t.trace||[];if(!trace.length){$('#cell').setAttribute('visibility','hidden');$('#movementStatus').textContent='此项没有移动轨迹。';return;}
 $('#cell').setAttribute('visibility','visible');let i=0;while(i<trace.length-2&&trace[i+1].t<elapsed)i++;
 const a=trace[i],b=trace[Math.min(i+1,trace.length-1)],mix=b.t>a.t?Math.max(0,Math.min(1,(elapsed-a.t)/(b.t-a.t))):0;
 const p=source([a.x+(b.x-a.x)*mix,a.y+(b.y-a.y)*mix]);$('#cell').setAttribute('cx',p[0]);$('#cell').setAttribute('cy',p[1]);
 const end=trace.at(-1).t;$('#movementStatus').textContent=`${t.arrived?'已到达':'未通过'} · ${Math.min(elapsed,end).toFixed(1)} / ${end.toFixed(1)} 秒 · 非法步 ${t.invalidSteps??'未记录'} · 通路 ${a.lane}`;
 $('#movementStatus').className=t.arrived?'status passed':'status pending';
}
function frame(now){if(playing&&report){elapsed+=(now-lastFrame)/1000;const end=report.movementTests[selected].trace.at(-1)?.t||0;if(elapsed>=end){elapsed=end;playing=false;$('#play').textContent='重新播放';}renderReplay();}lastFrame=now;requestAnimationFrame(frame);}
async function start(){[graph,report,geometry,contract]=await Promise.all(['network.json','navigation-review.json','inspection-geometry.json','interface-contract.json'].map(async f=>{const r=await fetch(f);if(!r.ok)throw Error(`${f} 加载失败`);return r.json();}));
 if(contract.sourceNetworkSha256!==report.sourceSha256)throw Error('接口与移动记录版本不一致');
 const s=report.summary;$('#summary').textContent=`组织口 ${s.interfaces} 处 · 进入 ${s.forwardArrived}/${s.interfaces} · 返回 ${s.reverseArrived}/${s.interfaces} · 非连通交叉 ${report.crossings.checked} 处 · ${s.projectionPass?'投影校验通过':'投影仍有问题'}`;
 $('#flat').append(svg('polygon',{points:points(geometry.outline),fill:'#d9b9a5'}));
 for(const o of geometry.organs)$('#flat').append(svg('polygon',{points:points(o.points),fill:'#c89f90',stroke:'#b58d80','stroke-width':.7}));
 const defs=svg('defs',{});$('#routes').append(defs);
 const edgeById=new Map(graph.edges.map(e=>[e.id,e]));
 for(const e of [...graph.edges].sort((a,b)=>a.drawOrder-b.drawOrder)){
  const cross=graph.geometry.crossings.filter(c=>c.under===e.id),mask=svg('mask',{id:'gap-'+e.id,maskUnits:'userSpaceOnUse',x:0,y:0,width:1024,height:1536});mask.append(svg('rect',{width:1024,height:1536,fill:'white'}));
  for(const c of cross){const over=edgeById.get(c.over);mask.append(svg('circle',{cx:c.point[0],cy:c.point[1],r:over.lumenWidthSource/2+.65,fill:'black'}));}defs.append(mask);
  const color=e.kind==='vein'||e.kind==='pulmonary_artery'?'#7499ac':e.kind==='portal'?'#9f869f':e.kind==='exchange'?'#b3a485':'#bd8079';
  $('#routes').append(svg('polyline',{points:points(e.points),fill:'none',stroke:color,'stroke-width':e.lumenWidthSource,'stroke-linejoin':'round','stroke-linecap':'round',mask:`url(#gap-${e.id})`,'data-edge':e.id}));
 }
 // Calibrated tissue access may include a short declared service spur.
 for(const o of report.adapterOnlyAdditions||[])$('#routes').append(svg('polyline',{points:points(o.sourcePoints),fill:'none',stroke:'#b3a485','stroke-width':2}));
 report.interfaces.forEach((o,i)=>{const name=graph.organs.find(r=>r.id===o.id)?.name||o.id;$('#organ').add(new Option(name,i));const tr=document.createElement('tr'),portal=contract.regions.find(r=>r.id===o.id).ports.find(p=>p.role==='portalSupply');for(const val of [name,fmt(o.entryWorld)+(portal?'；门静脉 '+fmt(portal.world):''),fmt(o.exitWorld),fmt(o.membraneCentre),`${o.forward.arrived?'通过':'失败'} / ${o.reverse.arrived?'通过':'失败'}`]){const td=document.createElement('td');td.textContent=val;tr.append(td);}$('#records').append(tr);});
 report.movementTests.forEach((t,i)=>{const name=graph.organs.find(o=>o.id===t.interfaceId)?.name,parts=t.id.split('.');const limb=(parts[0]==='r'?'右':'左')+({elbow:'肘',knee:'膝',ankle:'踝',wrist:'腕掌',foot:'足部'}[parts[1]]||parts[1])+' · '+(parts[2]==='forward'?'去程':'回程');$('#movement').add(new Option(`${name?name+(t.direction==='forward'?' · 进入血管':' · 返回组织'):limb}${t.arrived?' ✓':' · 待修'}`,i));});
 $('#organ').onchange=e=>selectOrgan(+e.target.value);$('#movement').onchange=e=>selectMovement(+e.target.value);for(const key of ['entry','exit','access'])$('#'+key).onclick=()=>focusPoint(key);
 $('#fit').onclick=()=>{center=[512,768];const r=stage.getBoundingClientRect();zoom=Math.min(r.width/1024,r.height/1536)/64;view();};
 $('#zoom').oninput=e=>{zoom=+e.target.value;view();};document.querySelectorAll('[data-zoom]').forEach(b=>b.onclick=()=>{zoom=+b.dataset.zoom;view();});
 $('#play').onclick=()=>{const end=report.movementTests[selected].trace?.at(-1)?.t||0;if(!end)return;if(elapsed>=end)elapsed=0;playing=!playing;lastFrame=performance.now();$('#play').textContent=playing?'暂停记录':'继续播放';};
 $('#reset').onclick=()=>selectMovement(selected,false);
 let drag=null;stage.onpointerdown=e=>{drag={x:e.clientX,y:e.clientY,center:[...center]};stage.setPointerCapture(e.pointerId);};stage.onpointermove=e=>{if(drag){const scale=64*zoom;center=[drag.center[0]-(e.clientX-drag.x)/scale,drag.center[1]-(e.clientY-drag.y)/scale];view();}};stage.onpointerup=stage.onpointercancel=()=>drag=null;
 new ResizeObserver(view).observe(stage);const initial=Math.max(0,report.interfaces.findIndex(o=>o.id==='stomach'));$('#organ').value=initial;selectOrgan(initial);requestAnimationFrame(frame);
}
start().catch(e=>{$('#error').textContent=e.message;$('#summary').textContent='数据未齐备，不能展示通过结果。';$('#play').disabled=true;});
