'use strict';
const $=id=>document.getElementById(id), NS='http://www.w3.org/2000/svg';
const make=(tag,attrs={},parent)=>{const n=document.createElementNS(NS,tag);for(const[k,v]of Object.entries(attrs))n.setAttribute(k,v);if(parent)parent.append(n);return n;};
const scene=$('artScene'),defs=$('sceneDefs'), hitCanvas=document.createElement('canvas'),hit=hitCanvas.getContext('2d');
let geometry,reference,fillData,atlas,replayData,checks,zoom=.01,center=[513,547],region='torso',revised=true,time=0,playing=false,lastFrame=0;
const clips=new Map(),footprints=new Map(),fillNodes=[],gradientStops=[],regions={whole:[135,10,890,1520],torso:[333,250,693,844],chest:[333,250,693,490],upper:[350,450,674,666],lower:[350,628,674,844],bladder:[450,718,565,835]};
let bladderForeground,overviewForeground,closeForeground;
const overviewFootprints=new Map();
const polyline=ps=>'M '+ps.map(p=>p.join(' ')).join(' L ');
const rgba=(v,alpha=1)=>`rgba(${v[0]},${v[1]},${v[2]},${v[3]*alpha})`;
const fillAlpha=z=>{const t=Math.max(0,Math.min(1,(z-.085)/.065));return Math.floor((t*t*(3-2*t))*255)/255;};
const frame=()=>scene.getBoundingClientRect();
function fit(id){const b=regions[id],r=frame();center=[(b[0]+b[2])/2,(b[1]+b[3])/2];zoom=Math.min(r.width/(b[2]-b[0]),r.height/(b[3]-b[1]))*.94/64;region=id;view();}
function sourcePoint(x,y){const r=frame();return[center[0]+(x-r.left-r.width/2)/(64*zoom),center[1]+(y-r.top-r.height/2)/(64*zoom)];}
function zoomAt(value,x,y){const before=sourcePoint(x,y);zoom=Math.max(.002,Math.min(.45,value));const after=sourcePoint(x,y);center=[center[0]+before[0]-after[0],center[1]+before[1]-after[1]];view();}
const selectedReplay=()=> $('replay').value==='meeting'?replayData.meeting:replayData.routes.find(r=>r.kind===$('replay').value);
function traceAt(trace,t){let lo=0,hi=trace.length-1;while(lo<hi){const m=Math.ceil((lo+hi)/2);if(trace[m].t<=t)lo=m;else hi=m-1;}return trace[lo];}
function currentUnits(){const r=selectedReplay();if($('replay').value==='meeting'){const q=traceAt(r.trace,time);return q.units.map((u,i)=>({...u,kind:i===0?'scout':'siege',selected:i===0}));}return[{...traceAt(r.trace,time),kind:r.kind,selected:true}];}
function pointAlpha(q){const [x,y]=q.source;if(hit.isPointInPath(closeForeground,x,y,'evenodd'))return 0;const p=footprints.get(q.edgeId);if(p?!hit.isPointInPath(p,x,y,'evenodd'):q.recordedGraphHidden)return 0;return hit.isPointInPath(overviewForeground,x,y,'evenodd')?(revised?fillAlpha(zoom):0):1;}
function drawCells(){const group=$('cellLayer');group.replaceChildren();$('replayControls').hidden=!$('cells').checked;if(!$('cells').checked)return;const r=selectedReplay();time=Math.max(0,Math.min(r.seconds,time));$('timeline').max=r.seconds;$('timeline').value=time;$('timeReadout').textContent=`${time.toFixed(1)} / ${r.seconds.toFixed(1)} 秒`;
 for(const q of currentUnits()){
  const alpha=pointAlpha(q),visible=alpha>0,p=q.source;
  if(!visible){if($('deep').checked)make('circle',{cx:p[0],cy:p[1],r:3/(64*zoom),fill:'none',stroke:'#737a81','stroke-width':1/(64*zoom),'stroke-dasharray':`${1/(64*zoom)} ${1/(64*zoom)}`},group);continue;}
  const key=zoom<.14?`ally-${q.selected?'selected':'normal'}-far`:`${q.kind}-${q.selected?'selected':'normal'}`,s=atlas.sprites[key],side=zoom<.14?16/(64*zoom):s.sourceSide;
  // Foreground clips the body and selection together; no solid unit is shown
  // in an organ face simply because its graph edge continues behind it.
  const g=make('g',{'clip-path':'url(#unit-foreground)',opacity:alpha},group);
  const n=make('image',{href:`registered-vessels-game-evidence/${s.png||s.file}`,x:p[0]-side/2,y:p[1]-side/2,width:side,height:side,'data-kind':q.kind,'data-edge':q.edgeId||'tissue'},g);make('title',{},n).textContent=`${q.kind} · ${q.stage||q.edgeId||'组织内'} · ${time.toFixed(2)}秒`;
 }
}
function drawGuides(){const group=$('guideLayer');group.replaceChildren();if(!$('guide').checked)return;
 const rendered=new Map(geometry.edges.map(e=>[e.id,e]));for(const e of reference.edges){const segments=rendered.get(e.id)?.visibleSegments||e.visibleSegments;for(const ps of segments)make('path',{d:polyline(ps),fill:'none',stroke:e.system==='artery'?'#9b362a':e.system==='vein'?'#185c88':'#856477','stroke-width':.9/(64*zoom),'stroke-opacity':.8},group);}
}
function intervalPoints(e,a,b){let d=0,out=[];for(let i=1;i<e.samples.length;i++){const p=e.samples[i-1],q=e.samples[i],len=Math.hypot(q[0]-p[0],q[1]-p[1]);if(len>0&&d+len>=a&&d<=b){for(const x of [Math.max(a,d),Math.min(b,d+len)]){const t=(x-d)/len;out.push([p[0]+(q[0]-p[0])*t,p[1]+(q[1]-p[1])*t]);}}d+=len;if(d>b)break;}return out;}
function drawDeep(){const group=$('deepLayer');group.replaceChildren();if(!$('deep').checked)return;for(const e of reference.edges){if(!e.hiddenIntervals.length)continue;for(const [a,b]of e.hiddenIntervals)make('path',{d:polyline(intervalPoints(e,a,b)),fill:'none',stroke:'#737a82','stroke-width':.8/(64*zoom),'stroke-dasharray':`${2.2/(64*zoom)} ${3.3/(64*zoom)}`,'stroke-opacity':.5},group);}}
function drawPorts(){const group=$('portLayer');group.replaceChildren();if(!$('ports').checked)return;
 for(const p of geometry.ports.filter(p=>p.kind==='named_port')){
  const incident=reference.edges.filter(e=>e.a===p.id||e.b===p.id),visible=incident.some(e=>{const f=(fillAlpha(zoom)>.5?footprints:overviewFootprints).get(e.id);return f?hit.isPointInPath(f,...p.source,'evenodd'):reference.protectedEdges.includes(e.id)&&e.visibleSegments.some(ps=>ps.some(q=>Math.hypot(q[0]-p.source[0],q[1]-p.source[1])<.05));})&&!hit.isPointInPath(bladderForeground,...p.source,'evenodd');
  const color=p.role==='supply'?'#a73e30':'#255e87',n=make('circle',{cx:p.source[0],cy:p.source[1],r:3.5/(64*zoom),fill:visible?color:'white',stroke:color,'stroke-width':1.2/(64*zoom),'stroke-dasharray':visible?'':`${1.5/(64*zoom)} ${1.2/(64*zoom)}`,'data-port':p.id},group);
  const text=`${p.organName} ${p.role==='supply'?'供血':'回流'} · ${p.id} · 原图(${p.source.map(v=>v.toFixed(2)).join(', ')}) · ${visible?(fillAlpha(zoom)>.5?'切面血管坐标':'外侧血管坐标'):'壁后接续'}`;make('title',{},n).textContent=text;n.style.cursor='pointer';n.addEventListener('click',()=>{$('portInfo').textContent=text;});
 }
 if(zoom>.04)for(const g of geometry.gates){const p=g.wallSource,n=make('circle',{cx:p[0],cy:p[1],r:2.3/(64*zoom),fill:'#cbd1b8',stroke:'#687752','stroke-width':1/(64*zoom)},group);make('title',{},n).textContent=`${g.id} · 血管—组织膜口，不接食物通道`;}
}
function view(){if(!geometry)return;const r=frame(),w=r.width/(64*zoom),h=r.height/(64*zoom);scene.setAttribute('viewBox',`${center[0]-w/2} ${center[1]-h/2} ${w} ${h}`);const b=revised?fillAlpha(zoom):0;
 for(let i=0;i<fillNodes.length;i++){const q=fillData.paths[i],n=fillNodes[i];if(q.rgba)n.setAttribute('fill',rgba(q.rgba,b));else for(let j=0;j<gradientStops[i].length;j++)gradientStops[i][j].setAttribute('stop-color',rgba(q.gradient.stops[j].rgba,b));}
 $('vesselArt').style.display=revised?'':'none';$('cutawayArt').style.display=revised?'':'none';$('cutawayArt').setAttribute('opacity',b);$('zoomReadout').textContent=`缩放 ${zoom.toFixed(4)} · 填色 ${Math.round(b*100)}%`;
 scene.dataset.zoom=zoom;scene.dataset.fillAlpha=b;scene.dataset.region=region;scene.dataset.paint=revised?'registered':'source';for(const n of document.querySelectorAll('[data-region]'))n.setAttribute('aria-pressed',n.dataset.region===region);$('revised').setAttribute('aria-pressed',revised);$('source').setAttribute('aria-pressed',!revised);
 drawGuides();drawDeep();drawPorts();drawCells();$('caption').textContent=b===1?'当前已完全进入现有填色。血管沿同一原图坐标接续；打开细胞回放可检查实际尺寸与膜口。':`当前为${revised?'连续血管试贴':'原图对照'}，填色在 0.085–0.15 逐渐接管。隐藏在器官前景后的血管只显示可见段。`;}
scene.addEventListener('wheel',e=>{e.preventDefault();$('follow').checked=false;zoomAt(zoom*Math.exp(-e.deltaY*.002),e.clientX,e.clientY);},{passive:false});
let drag;scene.addEventListener('pointerdown',e=>{if(e.target.closest('[data-port]'))return;drag={x:e.clientX,y:e.clientY,c:[...center]};scene.setPointerCapture(e.pointerId);$('follow').checked=false;});scene.addEventListener('pointermove',e=>{if(!drag)return;center=[drag.c[0]-(e.clientX-drag.x)/(64*zoom),drag.c[1]-(e.clientY-drag.y)/(64*zoom)];view();});scene.addEventListener('pointerup',()=>drag=null);scene.addEventListener('pointercancel',()=>drag=null);
for(const n of document.querySelectorAll('[data-region]'))n.onclick=()=>{playing=false;$('play').textContent='播放';$('follow').checked=false;fit(n.dataset.region);};
$('revised').onclick=()=>{revised=true;view();};$('source').onclick=()=>{revised=false;view();};
$('zoomIn').onclick=()=>{zoom=Math.min(.45,zoom*1.3);view();};$('zoomOut').onclick=()=>{zoom=Math.max(.002,zoom/1.3);view();};
$('zoom015').onclick=()=>{zoom=.15;region='upper';center=[571.3938412930886,539.9630801451746];$('replay').value='meeting';$('ports').checked=true;$('cells').checked=true;$('follow').checked=true;time=0;view();};
for(const id of ['guide','ports','deep','cells'])$(id).onchange=()=>view();
$('replay').onchange=()=>{time=0;if($('follow').checked)center=currentUnits()[0].source;view();};$('timeline').oninput=()=>{time=Number($('timeline').value);if($('follow').checked)center=currentUnits()[0].source;view();};$('play').onclick=()=>{playing=!playing;$('play').textContent=playing?'暂停':'播放';};
function tick(now){if(playing&&$('cells').checked&&replayData){time+=Math.min((now-lastFrame)/1000,.1);if(time>selectedReplay().seconds)time=0;if($('follow').checked)center=currentUnits()[0].source;view();}lastFrame=now;requestAnimationFrame(tick);}requestAnimationFrame(tick);
new ResizeObserver(()=>view()).observe(scene);
async function json(url){const r=await fetch(url);if(!r.ok)throw Error(`${url}: ${r.status}`);return r.json();}
(async()=>{
 [geometry,reference,fillData,atlas,replayData]=await Promise.all([json('registered-vessels/geometry.json'),json('final-reference-data.json'),json('registered-vessels-game-evidence/fill-display-data.json'),json('registered-vessels-game-evidence/sprite-atlas.json'),json('registered-vessels-game-evidence/actual-lua-replay.json')]);
 bladderForeground=new Path2D(geometry.bladderForegroundPath);overviewForeground=new Path2D(geometry.unitOverviewForegroundPath);closeForeground=new Path2D(geometry.unitCloseForegroundPath);for(const e of geometry.edges){footprints.set(e.id,new Path2D(e.paintPath));overviewFootprints.set(e.id,new Path2D(e.overviewPaintPath));const id=`cell-edge-${e.id.replaceAll('.','-')}`,clip=make('clipPath',{id,'clipPathUnits':'userSpaceOnUse'},defs);make('path',{d:e.paintPath,'clip-rule':'evenodd'},clip);clips.set(e.id,id);}
 const foreground=make('clipPath',{id:'unit-foreground','clipPathUnits':'userSpaceOnUse'},defs);make('path',{d:`M0 0 H1024 V1536 H0 Z ${geometry.unitCloseForegroundPath}`,'clip-rule':'evenodd'},foreground);
 for(const q of fillData.paths){const n=make('path',{d:q.d,'fill-rule':q.fillRule||'nonzero'},$('fillLayer'));fillNodes.push(n);gradientStops.push([]);if(q.gradient){const g=q.gradient,id=`fill-${q.order}`,grad=make('linearGradient',{id,gradientUnits:'userSpaceOnUse',x1:g.x1,y1:g.y1,x2:g.x2,y2:g.y2},defs);for(const s of g.stops)gradientStops[gradientStops.length-1].push(make('stop',{offset:s.offset,'stop-color':rgba(s.rgba,0)},grad));n.setAttribute('fill',`url(#${id})`);}}
 fit('torso');try{checks=await json('registered-vessels/checks.json');$('review').textContent=checks.summary;}catch{$('review').textContent='坐标与原图锁定；独立像素报告尚未发布。';}
})().catch(e=>{$('error').textContent=`图层载入失败：${e.message}`;console.error(e);});
