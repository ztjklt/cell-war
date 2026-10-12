/* Fixed art reference. View controls do not alter the draft or runtime graph. */
(function () {
  'use strict';
  const $=id=>document.getElementById(id),NS='http://www.w3.org/2000/svg';
  const map=$('finalMap'),colors={artery:'#bd514b',vein:'#3678a6',capillary:'#796780'};
  const names={outer_detour:'外缘绕行',fixed_deep_connector:'固定深层接续',foreground_occlusion:'器官前景遮挡'};
  const layers=['foodLayer','organLayer','oldLayer','deepLayer','routeLayer','vesselLayer','portLayer','gateLayer','labelLayer','selectedLayer'];
  let data,checks,edges,center=[512,768],zoom=.006,selected='',hidden='',gate='',gesture=null,frame=0;
  const make=(tag,attrs={})=>{const el=document.createElementNS(NS,tag);for(const [k,v] of Object.entries(attrs))el.setAttribute(k,v);return el;};
  const path=points=>'M '+points.map(p=>p.join(' ')).join(' L ');
  const rings=rs=>rs.map(r=>path(r.points)+' Z').join(' ');
  const fmt=p=>p.map(n=>Number(n).toFixed(2)).join(', ');
  const line=(points,attrs)=>make('path',{d:path(points),fill:'none','stroke-linecap':'round','stroke-linejoin':'round',...attrs});
  const para=text=>{const p=document.createElement('p');p.textContent=text;return p;};
  function slice(e,a,b){let dist=0,out=[];for(let i=1;i<e.samples.length;i++){
    const p=e.samples[i-1],q=e.samples[i],span=Math.hypot(q[0]-p[0],q[1]-p[1]);
    if(dist+span>=a&&dist<=b&&span>0){const lo=Math.max(0,(a-dist)/span),hi=Math.min(1,(b-dist)/span);if(!out.length)out.push(p.map((v,k)=>v+(q[k]-v)*lo));out.push(p.map((v,k)=>v+(q[k]-v)*hi));}dist+=span;if(dist>b)break;}return out;}
  function fit(b){const r=map.getBoundingClientRect();center=[(b[0]+b[2])/2,(b[1]+b[3])/2];zoom=Math.min(r.width/((b[2]-b[0])*1.13),r.height/((b[3]-b[1])*1.13))/64;view();}
  function bounds(points){return [Math.min(...points.map(p=>p[0]))-12,Math.min(...points.map(p=>p[1]))-12,Math.max(...points.map(p=>p[0]))+12,Math.max(...points.map(p=>p[1]))+12];}
  function source(e){const r=map.getBoundingClientRect(),s=64*zoom;return [center[0]+(e.clientX-r.left-r.width/2)/s,center[1]+(e.clientY-r.top-r.height/2)/s];}
  function setZoom(value,p=center){const prev=zoom;zoom=Math.max(.002,Math.min(.45,value));center=p.map((v,k)=>v+(center[k]-v)*prev/zoom);view();}
  function view(){if(!data)return;const r=map.getBoundingClientRect(),s=64*zoom;map.setAttribute('viewBox',[center[0]-r.width/s/2,center[1]-r.height/s/2,r.width/s,r.height/s].join(' '));
    $('mapZoom').textContent=`zoom ${zoom.toFixed(4)} · ${(64*zoom).toFixed(2)} 逻辑像素 / 原图像素`;
    for(const el of $('vesselLayer').children)el.setAttribute('stroke-width',Math.max(Number(el.dataset.lumen),1.4/s));
    for(const el of $('routeLayer').children)el.setAttribute('stroke-width',Math.max(Number(el.dataset.lumen),1.4/s)+2.8/s);
    $('mapCaption').textContent=Math.abs(zoom-.15)<.00001?'0.15 比例：管壁绿点 → 组织出口，淡金色区域是独立食物通路。新出口保持封闭胃腔，不连通食物。':'滚轮缩放、拖动平移。虚线表示遮挡下的完整通路；交叉处不会自动连通。浅色原图用于定位。';
    drawMarkers();drawSelection();
  }
  function draw(){if(!data)return;for(const id of layers)$(id).replaceChildren();
    if($('showFood').checked)for(const p of data.protectedPassages.filter(p=>p.system==='food'))$('foodLayer').append(p.id==='food.stomach'?make('path',{d:data.stomachFoodUnion.map(ps=>path(ps)+' Z').join(' '),fill:'#c1a05d','fill-opacity':.34,stroke:'none','pointer-events':'none'}):line(p.points,{stroke:'#bd9d60','stroke-width':p.width,'stroke-opacity':.38,'pointer-events':'none'}));
    if($('showOrgans').checked)for(const o of data.organs)$('organLayer').append(make('path',{d:rings(o.outlines),fill:'none',stroke:'#617363','stroke-opacity':.8,'stroke-width':1,'stroke-dasharray':'4 3','vector-effect':'non-scaling-stroke','pointer-events':'none'}));
    if($('showOld').checked)for(const r of data.routeChoices.filter(r=>r.mode!=='fixed_deep_connector'))$('oldLayer').append(make('path',{d:r.sourceD,fill:'none',stroke:'#515e58','stroke-width':1.5,'stroke-dasharray':'2 4','stroke-opacity':.65,'vector-effect':'non-scaling-stroke','pointer-events':'none'}));
    for(const e of data.edges){
      if($('showDeep').checked)for(const span of e.hiddenIntervals){const ps=slice(e,...span);if(ps.length>1)$('deepLayer').append(line(ps,{stroke:'#41658a','stroke-width':1.15,'stroke-dasharray':'4 4','stroke-opacity':.6,'vector-effect':'non-scaling-stroke','data-deep-edge':e.id,'pointer-events':'none'}));}
      const changed=data.routeChoices.some(r=>r.edgeId===e.id&&r.mode!=='fixed_deep_connector');
      for(const ps of e.visibleSegments){if($('showChanges').checked&&changed)$('routeLayer').append(line(ps,{stroke:'#d7a853','stroke-width':Math.max(e.lumenWidthSource,1.4/(64*zoom))+2.8/(64*zoom),'stroke-opacity':.9,'data-route':e.id,'data-lumen':e.lumenWidthSource,'pointer-events':'none'}));
        const el=line(ps,{stroke:colors[e.system]||colors.capillary,'stroke-width':e.lumenWidthSource,'data-lumen':e.lumenWidthSource,'data-visible-edge':e.id,'pointer-events':'none'});$('vesselLayer').append(el);}
    }view();
  }
  function drawMarkers(){const s=64*zoom;$('portLayer').replaceChildren();$('gateLayer').replaceChildren();$('labelLayer').replaceChildren();
    if($('showPorts').checked||gate)for(const p of data.ports.filter(p=>p.kind==='named_port'&&($('showPorts').checked||p.organ==='stomach'))){const g=make('g',{'data-port':p.id,role:'button','aria-label':p.organName+' '+p.id+' 固定接口',tabindex:0});g.append(make('circle',{cx:p.source[0],cy:p.source[1],r:3.2/s,fill:'#eff3df',stroke:'#366b54','stroke-width':1.2,'vector-effect':'non-scaling-stroke'}));g.onclick=()=>{center=p.source;zoom=.15;view();};$('portLayer').append(g);}
    for(const g of data.gates){const selectedGate=gate===g.id,group=make('g',{'data-gate':g.id,role:'button','aria-label':g.id.includes('.inner')?'查看胃壁内侧出口':'查看胃壁外侧出口',tabindex:0}),p=g.wallSource,q=g.tissueTargetSource;
      group.append(line([g.pipeCenterSource,p,q],{stroke:'#2d855e','stroke-width':selectedGate?2.6:1.8,'vector-effect':'non-scaling-stroke'}),make('circle',{cx:p[0],cy:p[1],r:3.2/s,fill:'#e5f0d9',stroke:'#20714e','stroke-width':1.4,'vector-effect':'non-scaling-stroke'}));
      if(zoom>.04){const tip=q,back=q.map((v,k)=>v-g[['nx','ny'][k]]*6/s),side=[-g.ny*3/s,g.nx*3/s];group.append(make('path',{d:path([back.map((v,k)=>v+side[k]),tip,back.map((v,k)=>v-side[k])])+' Z',fill:'#2d855e',stroke:'none'}));}
      group.onclick=()=>chooseGate(g.id);group.onkeydown=e=>{if(e.key==='Enter')chooseGate(g.id);};$('gateLayer').append(group);
      if(gate&&zoom>.015){const text=make('text',{x:p[0]+8/s,y:p[1]+12/s,fill:'#1f6546','font-size':11/s,'paint-order':'stroke',stroke:'#f5f3ea','stroke-width':2.5/s,'pointer-events':'none'});text.textContent=g.id.includes('.inner')?'组织口Ⅰ':'组织口Ⅱ';$('labelLayer').append(text);}
    }
    if(gate){const e=edges.get(data.stomachWall.edgeId);for(const [p,label] of [[e.samples[0],'胃壁供血'],[e.samples[e.samples.length-1],'胃壁回流']]){const returning=label==='胃壁回流';$('portLayer').append(make('circle',{cx:p[0],cy:p[1],r:3.4/s,fill:'#f1f2df',stroke:returning?colors.vein:colors.artery,'stroke-width':1.5,'vector-effect':'non-scaling-stroke','pointer-events':'none'}));const text=make('text',{x:p[0]+(returning?-8:8)/s,y:p[1]-8/s,'text-anchor':returning?'end':'start',fill:returning?colors.vein:colors.artery,'font-size':11/s,'paint-order':'stroke',stroke:'#f5f3ea','stroke-width':2.5/s,'pointer-events':'none'});text.textContent=label;$('labelLayer').append(text);}
      for(const t of [.17,.45,.75]){const i=Math.min(e.samples.length-2,Math.floor(t*e.samples.length)),p=e.samples[i],q=e.samples[i+1],l=Math.hypot(q[0]-p[0],q[1]-p[1]),n=[(q[0]-p[0])/l,(q[1]-p[1])/l],back=p.map((v,k)=>v-n[k]*6/s),side=[-n[1]*3/s,n[0]*3/s];$('gateLayer').append(make('path',{d:path([back.map((v,k)=>v+side[k]),p,back.map((v,k)=>v-side[k])])+' Z',fill:'#544361','pointer-events':'none'}));}}
    if(zoom<.015){const text=make('text',{x:730,y:499,fill:'#43594a','font-size':11/s,'paint-order':'stroke',stroke:'#f5f3ea','stroke-width':3/s});text.textContent='胸腹路线已定稿';$('labelLayer').append(text);}
  }
  function drawSelection(){const s=64*zoom;$('selectedLayer').replaceChildren();const r=data.decisions.find(r=>r.id===selected),h=data.occlusions.find(h=>h.id===hidden);
    if(r){const e=edges.get(r.edgeId);for(const ps of e.visibleSegments)$('selectedLayer').append(line(ps,{stroke:'#f1bf50','stroke-width':4,'stroke-opacity':.65,'vector-effect':'non-scaling-stroke','pointer-events':'none'}));for(const span of e.hiddenIntervals){const ps=slice(e,...span);if(ps.length>1)$('selectedLayer').append(line(ps,{stroke:'#315f98','stroke-width':2.4,'stroke-dasharray':'5 4','vector-effect':'non-scaling-stroke','pointer-events':'none'}));}}
    if(h){$('selectedLayer').append(line(h.points,{stroke:'#253f6c','stroke-width':3,'stroke-dasharray':'5 3','vector-effect':'non-scaling-stroke','pointer-events':'none'}));for(const [i,p] of [h.startSource,h.endSource].entries()){const marker=make('circle',{cx:p[0],cy:p[1],r:5/s,fill:i?'#c6d8e8':'#f3ce81',stroke:'#263f5e','stroke-width':1.5,'vector-effect':'non-scaling-stroke'});$('selectedLayer').append(marker);}}
  }
  function list(){const filter=$('decisionFilter').value;$('caseList').replaceChildren();for(const r of data.decisions.filter(r=>filter==='all'||r.resolution===filter)){
    const b=document.createElement('button');b.className='case'+(selected===r.id?' active':'');b.dataset.decision=r.id;b.style.borderLeftColor=r.positionChanged?'#d7a853':'#7098b5';b.textContent=`${r.organName} · ${names[r.resolution]} · ${r.edgeId}`;const small=document.createElement('small');small.textContent=`${r.id} · ${r.hiddenSegments.length} 个固定遮挡段`;b.append(small);b.onclick=()=>chooseDecision(r.id);$('caseList').append(b);}}
  function ownerName(h){return data.organs.find(o=>o.id===h.owner)?.name||data.protectedPassages.find(p=>p.id===h.owner)?.name||(h.kind==='vascular_crossing'?'上层血管 '+h.owner.replace('crossing:',''):h.owner);}
  function showHidden(id,focus=true){const h=data.occlusions.find(h=>h.id===id);if(!h)return;hidden=id;$('hiddenSelect').value=id;$('hiddenSelect').closest('details').open=true;$('showDeep').checked=true;$('hiddenDetail').textContent=`${h.id} · ${h.edgeId} 被 ${ownerName(h)} 遮挡：起点 (${fmt(h.startSource)}) → 终点 (${fmt(h.endSource)})，长度 ${h.lengthSource.toFixed(2)} 原图像素。${h.reason}`;if(focus)fit(bounds(h.points));draw();}
  function chooseDecision(id){const r=data.decisions.find(r=>r.id===id),e=edges.get(r.edgeId);selected=id;hidden='';gate='';const detail=$('caseDetail');detail.replaceChildren();const h=document.createElement('h2');h.textContent=r.organName+' · '+names[r.resolution];detail.append(h,para(r.reason),para(`血管 ${e.id}：${e.a} → ${e.b}。命名端点保持原坐标；${r.positionChanged?'中间走向已调整。':'曲线位置保留。'}`));
    const box=document.createElement('div');box.className='hidden-list';for(const hid of r.hiddenSegments){const seg=data.occlusions.find(h=>h.id===hid),b=document.createElement('button');b.textContent=`${hid} · ${ownerName(seg)} · (${fmt(seg.startSource)}) → (${fmt(seg.endSource)})`;b.onclick=()=>showHidden(hid);box.append(b);}detail.append(box);if(!r.hiddenSegments.length)detail.append(para('本器官重合已通过外缘绕行消除。'));list();draw();fit(bounds(e.samples));}
  function chooseGate(id){const g=data.gates.find(g=>g.id===id);gate=id;selected='';hidden='';$('showFood').checked=true;center=g.pipeCenterSource;zoom=.15;const detail=$('caseDetail');detail.replaceChildren();const h=document.createElement('h2');h.textContent=id.includes('.inner')?'胃壁内侧组织出口':'胃壁外侧组织出口';detail.append(h,para('供血口 stomach.a → 你画的胃壁曲线 → 回流口 stomach.v。原曲线形状没有重画；两个组织出口已重新落到管壁。'),para(`管腔锚点 (${fmt(g.pipeCenterSource)})；管壁口 (${fmt(g.wallSource)})；组织侧 (${fmt(g.tissueTargetSource)})。`),para(`沿管线距最近接头 ${g.distanceToJunctionSource.toFixed(2)} 原图像素，管壁口距食物投影 ${g.foodClearanceSource.toFixed(2)} 原图像素。朝向与管线切线垂直。`),para('淡金色是食物通路；绿色短箭头进入胃壁组织。这里确定入口位置，实际单位移动会在接入游戏时重测。'));draw();list();}
  async function start(){const [d,c]=await Promise.all([fetch('final-reference-data.json',{cache:'no-store'}),fetch('final-reference-checks.json',{cache:'no-store'})]);if(!d.ok||!c.ok)throw Error('定稿数据加载失败');data=await d.json();checks=await c.json();edges=new Map(data.edges.map(e=>[e.id,e]));if(data.edges.length!==202||data.coordinates.width!==1024)throw Error('坐标基准不匹配');const n=data.counts;
    $('summary').textContent=`48 项重合处理已确定 · ${n.hiddenSegments} 个精确遮挡段（含腔道与新交叉） · 13 组循环连接保留 · 本轮未生图`;
    for(const [id,value] of [['statNetwork',n.vessels],['statFrozen',n.protectedEdges],['statRouted',n.routedEdges],['statGates',n.stomachExits]])$(id).textContent=value;
    $('checkStatus').textContent=`结构复核：${String(checks.status).startsWith('PASS')?'通过':'待核对'}。116 条脑部和四肢曲线、404 个端点、13 组循环、48 项处理和两个胃壁出口均已检查。`;
    $('occlusionSummary').textContent=`${n.hiddenSegments} 个精确遮挡段；${n.newRouteCrossings} 个新增无连接血管交叉已确定上下层。黄色圆点标遮挡开始，浅蓝圆点标结束。`;
    for(const h of data.occlusions)$('hiddenSelect').add(new Option(`${h.id} · ${h.edgeId} · ${ownerName(h)}`,h.id));
    for(const text of data.limits){const li=document.createElement('li');li.textContent=text;$('limits').append(li);}
    for(const id of ['showDeep','showChanges','showOld','showOrgans','showPorts','showFood'])$(id).onchange=draw;
    $('decisionFilter').onchange=list;$('hiddenSelect').onchange=()=>showHidden($('hiddenSelect').value);
    $('fitBody').onclick=()=>{selected='';hidden='';gate='';draw();fit([0,0,1024,1536]);};
    for(const [id,b] of [['fitTorso',[350,270,680,825]],['fitHead',[405,5,615,280]],['fitArms',[125,260,895,925]],['fitLegs',[310,765,710,1520]],['fitStomach',[455,455,635,579]]])$(id).onclick=()=>{selected='';hidden='';gate=id==='fitStomach'?data.gates[0].id:'';if(gate)$('showFood').checked=true;$('hiddenSelect').value='';draw();fit(b);};
    $('zoom015').onclick=()=>chooseGate(data.gates.find(g=>g.id.includes('.inner')).id);$('outer015').onclick=()=>chooseGate(data.gates.find(g=>g.id.includes('.outer')).id);
    $('zoomPlus').onclick=()=>setZoom(zoom*1.5);$('zoomMinus').onclick=()=>setZoom(zoom/1.5);
    map.addEventListener('wheel',e=>{e.preventDefault();setZoom(zoom*Math.exp(-Math.max(-100,Math.min(100,e.deltaY))*.004),source(e));},{passive:false});
    map.addEventListener('pointerdown',e=>{if(e.target.closest('[data-port],[data-gate]'))return;gesture={x:e.clientX,y:e.clientY,center:[...center],scale:64*zoom};map.setPointerCapture(e.pointerId);});
    map.addEventListener('pointermove',e=>{if(!gesture)return;center=[gesture.center[0]-(e.clientX-gesture.x)/gesture.scale,gesture.center[1]-(e.clientY-gesture.y)/gesture.scale];if(!frame)frame=requestAnimationFrame(()=>{frame=0;view();});});for(const name of ['pointerup','pointercancel','lostpointercapture'])map.addEventListener(name,()=>{gesture=null;});
    new ResizeObserver(view).observe(map);list();draw();fit([0,0,1024,1536]);
  }
  start().catch(e=>{$('error').textContent=e.message;console.error(e);});
})();
