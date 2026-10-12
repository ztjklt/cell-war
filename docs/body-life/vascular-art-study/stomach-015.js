'use strict';
const $=s=>document.querySelector(s), NS='http://www.w3.org/2000/svg';
let artData,nav,join,mode='composition',paint='art',zoom=.15,center=[554,525],selected='scout',time=0,playing=false,last=0,drag=null;
const scene=$('#scene'),stomachPanel=$('#stomachPanel');
const smooth=z=>{const t=Math.max(0,Math.min(1,(z-.085)/.065));return t*t*(3-2*t);};
const source=p=>[p.x/2,(p.y-512)/2];
const el=(tag,attrs,parent)=>{const n=document.createElementNS(NS,tag);for(const [k,v]of Object.entries(attrs))n.setAttribute(k,v);parent.appendChild(n);return n;};
const d=ps=>'M '+ps.map(p=>p.join(' ')).join(' L ');
function frame(){
 const r=scene.getBoundingClientRect();if(!r.width||!r.height)return;
 let w,h;
 if(mode==='composition'){w=Math.max(153,116*r.width/r.height);h=w*r.height/r.width;}else{w=r.width/(64*zoom);h=r.height/(64*zoom);}
 const x=center[0]-w/2,y=center[1]-h/2;
 scene.setAttribute('viewBox',`${x} ${y} ${w} ${h}`);
 const alpha=paint==='base'?0:paint==='art'?1:smooth(zoom);
 $('#artLayer').setAttribute('opacity',alpha);
 scene.dataset.zoom=String(zoom);scene.dataset.mode=mode;scene.dataset.alpha=String(alpha);scene.dataset.logicalScale=String(r.width/w);
 $('#zoom').value=zoom;
 $('#readout').textContent=mode==='composition'?'全胃构图预览 · 完全填色 · 同一原图坐标':`实际 zoom=${zoom.toFixed(3)} · 1 原图像素 = ${(64*zoom).toFixed(2)} 逻辑像素 · 填色 ${Math.round(alpha*100)}%`;
 $('#fit').setAttribute('aria-pressed',String(mode==='composition'));
 for(const [id,value]of [['art','art'],['base','base'],['transition','transition']])$('#'+id).setAttribute('aria-pressed',String(paint===value));
 for(const [k,v]of Object.entries({x:x-350,y:y-450,width:w,height:h}))$('#cameraBox').setAttribute(k,v);
 $('#depthLayer').style.display=$('#tech').checked?'':'none';$('#targetLayer').style.display=$('#gates').checked?'':'none';
 if(nav)drawReplay();
}
function caseData(){return selected==='meeting'?nav.meeting:nav.routes.find(r=>r.kind===selected);}
function recordedAt(trace,t){let a=0,b=trace.length-1;while(a<b){const m=Math.ceil((a+b)/2);if(trace[m].t<=t)a=m;else b=m-1;}return trace[a];}
function drawReplay(){
 const item=caseData(),trace=item.trace,record=recordedAt(trace,time),group=$('#unitLayer');group.replaceChildren();
 let units;
 if(selected==='meeting')units=record.units.map((u,i)=>({...u,kind:nav.meeting.units[i].kind,radius:nav.routes.find(r=>r.kind===nav.meeting.units[i].kind).cellRadiusWorld/2}));
 else units=[{...record,kind:selected,radius:item.cellRadiusWorld/2}];
 for(const u of units){const p=source(u);el('circle',{cx:p[0],cy:p[1],r:u.radius,fill:u.kind==='siege'?'#e8d3a0':'#e5efe3',stroke:'#334c47','stroke-width':.075,'data-kind':u.kind,'data-source-radius':u.radius},group);}
 const pathGroup=$('#traceLayer');pathGroup.replaceChildren();
 if($('#trail').checked&&selected!=='meeting')el('path',{d:d(trace.filter(p=>p.t<=time).map(source)),fill:'none',stroke:'#e4e0c4','stroke-width':.17,'stroke-opacity':.64},pathGroup);
 $('#timeline').value=item.seconds?time/item.seconds:0;
 $('#clock').textContent=`记录时间 ${time.toFixed(1)} / ${item.seconds.toFixed(1)} 秒`;
 scene.dataset.replayTime=String(time);scene.dataset.case=selected;
 const labels={'supply-to-outer-gate':'沿定稿支管到外侧口','outer-outward':'外侧口出管','outer-fixed-target':'外侧组织区','outer-return-to-gate':'返回外侧口','outer-inward':'外侧口入管','forward-vascular-transfer':'沿支管前往内侧口','inner-outward':'内侧口出管','inner-fixed-target':'内侧组织区','inner-return-to-gate':'返回内侧口','inner-inward':'内侧口入管','gate-to-venous-junction':'接入回流节点'};
 $('#motionStatus').textContent=selected==='meeting'?'真实位置采样回放 · 4× · 先候位再单列跨膜，保留原管径':'真实位置采样回放 · 4× · '+(labels[record.stage]||'供血节点起点');
}
function focusGate(id){mode='game';zoom=.15;const gate=artData.gates.find(g=>g.id.endsWith('.'+id));center=[...gate.wallSource];frame();}
function replayView(){
 if($('#follow').checked){const record=recordedAt(caseData().trace,time),units=selected==='meeting'?record.units:[record];
  center=units.map(source).reduce((a,p)=>[a[0]+p[0]/units.length,a[1]+p[1]/units.length],[0,0]);mode='game';frame();
 }else drawReplay();
}
function setZoom(z,anchor){
 const old=Number(scene.dataset.logicalScale)||64*zoom;const rect=scene.getBoundingClientRect();
 const px=anchor?anchor[0]-rect.left-rect.width/2:0,py=anchor?anchor[1]-rect.top-rect.height/2:0;
 const before=[center[0]+px/old,center[1]+py/old];mode='game';zoom=Math.max(.02,Math.min(.24,z));
 center=[before[0]-px/(64*zoom),before[1]-py/(64*zoom)];frame();
}
function toggleTab(seam){$('#seamPanel').style.display=seam?'block':'none';stomachPanel.style.display=seam?'none':'block';$('#tabStomach').setAttribute('aria-pressed',String(!seam));$('#tabSeam').setAttribute('aria-pressed',String(seam));if(!seam)frame();}
function raf(now){if(playing){const delta=last?Math.min(.1,(now-last)/1000):0;time=Math.min(caseData().seconds,time+delta*4);replayView();if(time>=caseData().seconds){playing=false;$('#play').textContent='再次播放';}}last=now;requestAnimationFrame(raf);}
$('#fit').onclick=()=>{$('#follow').checked=false;mode='composition';center=[554,525];frame();};
$('#inner').onclick=()=>{$('#follow').checked=false;focusGate('inner');};$('#outer').onclick=()=>{$('#follow').checked=false;focusGate('outer');};
$('#plus').onclick=()=>setZoom(zoom*1.2);$('#minus').onclick=()=>setZoom(zoom/1.2);
$('#zoom').oninput=e=>setZoom(Number(e.target.value));
for(const id of ['art','base','transition'])$('#'+id).onclick=()=>{paint=id;frame();};
for(const id of ['tech','gates','trail'])$('#'+id).onchange=frame;
$('#tabStomach').onclick=()=>toggleTab(false);$('#tabSeam').onclick=()=>toggleTab(true);
$('#seamMarks').onchange=()=>$('#seamGuide').style.display=$('#seamMarks').checked?'':'none';
for(const id of ['New','Old'])$('#seam'+id).onclick=()=>{$('#seamImage').setAttribute('href',id==='New'?'abdomen-join-output/registered-full-body-v2.png':'upper-abdomen-output/registered-full-body.png');for(const key of ['New','Old'])$('#seam'+key).setAttribute('aria-pressed',String(key===id));};
$('#case').onchange=e=>{selected=e.target.value;time=0;playing=false;$('#play').textContent='播放真实轨迹';if(selected==='meeting'&&mode==='game')focusGate('inner');replayView();};
$('#play').onclick=()=>{if(time>=caseData().seconds)time=0;playing=!playing;last=0;$('#play').textContent=playing?'暂停回放':'继续回放';};
$('#reset').onclick=()=>{time=0;playing=false;$('#play').textContent='播放真实轨迹';replayView();};
$('#timeline').oninput=e=>{playing=false;time=Number(e.target.value)*caseData().seconds;$('#play').textContent='继续回放';replayView();};
$('#follow').onchange=()=>{if($('#follow').checked){zoom=.15;replayView();}};
scene.addEventListener('wheel',e=>{e.preventDefault();setZoom((mode==='composition'?Number(scene.dataset.logicalScale)/64:zoom)*Math.exp(-e.deltaY*.001),[e.clientX,e.clientY]);},{passive:false});
scene.addEventListener('pointerdown',e=>{$('#follow').checked=false;drag=[e.clientX,e.clientY,...center];scene.setPointerCapture(e.pointerId);scene.classList.add('dragging');});
scene.addEventListener('pointermove',e=>{if(!drag)return;const scale=Number(scene.dataset.logicalScale);center=[drag[2]-(e.clientX-drag[0])/scale,drag[3]-(e.clientY-drag[1])/scale];frame();});
scene.addEventListener('pointerup',()=>{drag=null;scene.classList.remove('dragging');});scene.addEventListener('pointercancel',()=>{drag=null;scene.classList.remove('dragging');});
new ResizeObserver(frame).observe(scene);
(async()=>{
 [artData,nav,join]=await Promise.all(['final-stomach-art-data.json','final-stomach-navigation-evidence/report.json','abdomen-join-art-data.json'].map(async url=>{const r=await fetch(url);if(!r.ok)throw Error(url+' 加载失败');return r.json();}));
 if(artData.finalReferenceSha256!==nav.sourceSha256||join.finalReferenceSha256!==nav.sourceSha256)throw Error('图像与移动记录版本不一致');
 for(const v of artData.bloodFullPaths)el('path',{d:d(v.points),fill:'none',stroke:'#514b61','stroke-width':.35,'stroke-dasharray':'1.4 1.4',opacity:.65},$('#depthLayer'));
 for(const gate of artData.gates){const p=gate.wallSource;el('circle',{cx:p[0],cy:p[1],r:1.35,fill:'none',stroke:'#e6d5a6','stroke-width':.17},$('#targetLayer'));}
 el('path',{d:'M 350 666 L 674 666',fill:'none',stroke:'#2f696e','stroke-width':.55,'stroke-dasharray':'2.8 2.8'},$('#seamGuide'));
 for(const p of join.renderedPieces)el('path',{d:d(p.points),fill:'none',stroke:'#f0d4a0','stroke-width':.45,opacity:.7},$('#seamGuide'));
 const s=nav.summary;$('#reportLine').textContent=`单体 ${s.stagesPassed}/${s.stages} 阶段；候位 ${nav.meeting.stagesPassed}/4 阶段；食物、封墙和建筑负例通过。`;
 frame();requestAnimationFrame(raf);
})().catch(e=>{$('#error').textContent=e.message;console.error(e);});
