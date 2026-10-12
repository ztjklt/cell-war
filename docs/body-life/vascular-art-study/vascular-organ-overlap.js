/* Read-only annotated atlas. Generated artwork and gameplay routing are not installed here. */
(function () {
  'use strict';
  const $=id=>document.getElementById(id),ns='http://www.w3.org/2000/svg';
  const colors={connect:'#288665',reroute:'#dc852e',occlude:'#467ab8',pending:'#9e61ba'};
  const vesselColors={artery:'#b85350',vein:'#3b77a6',capillary:'#726877'};
  const labels={connect:'已有连接',reroute:'建议绕开',occlude:'可以遮挡',pending:'待接入'};
  const roles={supply:'供血',return:'回流',portalSupply:'门静脉供血',controlledTissueAccess:'组织膜口'};
  const make=(tag,attrs={})=>{const el=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))el.setAttribute(k,v);return el;};
  const path=points=>'M '+points.map(p=>p.join(' ')).join(' L ');
  const ringPath=rings=>rings.map(r=>path(r.points)+' Z').join(' ');
  let data,organ='all',selected=null,channel=null,zoom=.006,center=[512,768],gesture=null,frame=0;
  const map=$('overlapMap'),mapLayers=['organOutlines','baseVessels','passageAreas','overlapLines','passageLines','channelLines','portMarkers','annotationLabels','selectionMarker'];
  const visible=r=>organ==='all'||r.organ===organ;
  const region=()=>data.organs.find(o=>o.id===organ);
  const round=p=>p.map(n=>n.toFixed(2)).join(', ');
  function view(){
    if(!data)return;const rect=map.getBoundingClientRect(),scale=64*zoom,w=rect.width/scale,h=rect.height/scale;
    map.setAttribute('viewBox',[center[0]-w/2,center[1]-h/2,w,h].join(' '));
    $('mapZoom').textContent=`zoom ${zoom.toFixed(4)} · ${scale.toFixed(2)} 逻辑像素 / 原图像素`;
    $('mapCaption').textContent=zoom>=.149&&zoom<=.151?'当前为 0.15 比例：1 原图像素 = 9.6 逻辑像素。通道沿现有血管，未重测细胞通行。':'滚轮缩放，拖动画布平移。点击器官名称或彩色线段，查看具体连接依据。';
    // Preserve each source lumen; use a small screen minimum so distal branches remain legible.
    for(const line of $('baseVessels').children)line.setAttribute('stroke-width',Math.max(Number(line.dataset.lumen),1.4/scale));
    drawLabels();drawPorts();drawSelection();
  }
  function fit(bounds){const rect=map.getBoundingClientRect(),w=bounds[2]-bounds[0],h=bounds[3]-bounds[1];
    center=[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2];zoom=Math.min(rect.width/(w*1.15),rect.height/(h*1.15))/64;view();}
  function setZoom(value,p=center){const previous=zoom;zoom=Math.max(.002,Math.min(.45,value));const ratio=previous/zoom;center=p.map((v,i)=>v+(center[i]-v)*ratio);view();}
  function source(event){const rect=map.getBoundingClientRect(),scale=64*zoom;return [center[0]+(event.clientX-rect.left-rect.width/2)/scale,center[1]+(event.clientY-rect.top-rect.height/2)/scale];}
  function chooseOrgan(id,focus=true){organ=id;selected=null;channel=null;$('organSelect').value=id;
    $('regionTitle').textContent=id==='all'?'全身标注台账':region().name+' · 连接与重合';
    const own=data.records.filter(visible),counts=Object.fromEntries(Object.keys(labels).map(k=>[k,own.filter(r=>r.category===k).length]));
    $('regionSummary').textContent=`${own.length} 组血管—器官重合 · 连接 ${counts.connect} · 绕开 ${counts.reroute} · 遮挡 ${counts.occlude} · 待接入 ${counts.pending}`;
    $('caseDetail').replaceChildren();const p=document.createElement('p');p.textContent='点击一条彩色标注，查看对应血管、命名关系和处理建议。';$('caseDetail').append(p);
    for(const b of $('regionButtons').children)b.setAttribute('aria-pressed',b.dataset.organ===id);
    channelButtons();caseList();draw();if(focus)fit(id==='all'?[0,0,1024,1536]:region().bounds);
  }
  function draw(){
    if(!data)return;for(const id of mapLayers)$(id).replaceChildren();
    for(const o of data.organs){if(organ!=='all'&&o.id!==organ)continue;
      $('organOutlines').append(make('path',{d:ringPath(o.outlines),fill:'none',stroke:'#626b62','stroke-width':1,'stroke-opacity':.65,'stroke-dasharray':'4 3','vector-effect':'non-scaling-stroke','pointer-events':'none'}));}
    if($('showNetwork').checked)for(const e of data.edges)$('baseVessels').append(make('path',{d:e.d,fill:'none',stroke:vesselColors[e.system]||vesselColors.capillary,'stroke-width':e.lumenWidthSource,'stroke-opacity':.88,'stroke-linecap':'round','stroke-linejoin':'round','data-base-edge':e.id,'data-system':e.system,'data-lumen':e.lumenWidthSource,'pointer-events':'none'}));
    if($('showPassages').checked){
      for(const p of data.protectedPassages){if(organ!=='all'&&!p.owners.includes(organ))continue;
        const color={food:'#cbb080',air:'#b5bac4',urine:'#c1b1cf'}[p.system];
        $('passageAreas').append(make('path',p.id==='food.stomach'?{d:data.stomachFoodUnion.map(points=>path(points)+' Z').join(' '),fill:color,'fill-opacity':.33,stroke:'none','pointer-events':'none'}:{d:path(p.points),fill:'none',stroke:color,'stroke-width':p.width,'stroke-opacity':.5,'stroke-linecap':'round','pointer-events':'none'}));}
    }
    for(const r of data.records){if(!visible(r)||!$('show'+{connect:'Connect',reroute:'Reroute',occlude:'Occlude',pending:'Pending'}[r.category]).checked)continue;
      for(const points of r.segments){const line=make('path',{d:path(points),fill:'none',stroke:colors[r.category],'stroke-width':selected===r.id?5:2.6,'stroke-linecap':'round','stroke-dasharray':r.category==='occlude'?'5 3':r.category==='pending'?'3 2':'none','vector-effect':'non-scaling-stroke','data-record':r.id,role:'button','aria-label':r.id+' '+r.label+' '+labels[r.category],tabindex:0});
        line.onclick=()=>selectCase(r.id);line.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();selectCase(r.id);}};$('overlapLines').append(line);}}
    if($('showPassages').checked)for(const r of passageCases())for(const points of r.segments){
      const line=make('path',{d:path(points),fill:'none',stroke:'#b85124','stroke-width':selected===r.id?5:3,'stroke-dasharray':'2 2','vector-effect':'non-scaling-stroke','data-passage-record':r.id,role:'button','aria-label':r.id+' '+r.edgeId+' '+r.passageName,tabindex:0});line.onclick=()=>selectCase(r.id);$('passageLines').append(line);}
    if($('showChannels').checked)for(const c of data.channels.filter(c=>organ==='all'||c.organ===organ)){
      const edge=data.edges.find(e=>e.id===c.edgeId),w=edge.lumenWidthSource;
      const g=make('g',{'data-channel':c.id,role:'button','aria-label':c.id+' '+c.organName+' '+roles[c.role]+'接入通道',tabindex:0});
      g.append(make('path',{d:path(c.points),fill:'none',stroke:channel===c.id?'#58406d':'#776180','stroke-width':w+1,'stroke-linecap':'round'}),make('path',{d:path(c.points),fill:'none',stroke:'#d7c7e6','stroke-width':w,'stroke-linecap':'round'}));g.onclick=()=>selectChannel(c.id,false);$('channelLines').append(g);}
    view();
  }
  function drawLabels(){
    $('annotationLabels').replaceChildren();if(!data)return;
    const scale=64*zoom,size=11/scale;
    const callouts={brain:[640,65],lung_r:[245,340],lung_l:[755,343],heart:[755,417],liver:[228,500],stomach:[755,520],pancreas:[755,585],kidney_r:[228,600],kidney_l:[755,635],large_intestine:[755,690],small_intestine:[228,697],bladder:[755,781]};
    if(organ==='all'&&zoom<.015)for(const o of data.organs){const anchor=callouts[o.id],mid=[(o.bounds[0]+o.bounds[2])/2,(o.bounds[1]+o.bounds[3])/2];
      const g=make('g',{'data-organ-label':o.id,role:'button','aria-label':'查看'+o.name,tabindex:0});g.append(make('path',{d:path([mid,anchor]),fill:'none',stroke:'#526d5b','stroke-width':.8,'vector-effect':'non-scaling-stroke','stroke-opacity':.75}));
      const text=make('text',{x:anchor[0],y:anchor[1],fill:'#253f32','font-size':size,'text-anchor':anchor[0]<512?'end':'start','paint-order':'stroke',stroke:'#f5f4ed','stroke-width':3/scale});text.textContent=o.name;g.append(text);g.onclick=()=>chooseOrgan(o.id);g.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();chooseOrgan(o.id);}};$('annotationLabels').append(g);}
    if(organ!=='all'&&zoom<.06)for(const r of data.records.filter(visible)){
      const p=r.sourceMidpoint,text=make('text',{x:p[0]+3/scale,y:p[1]-3/scale,fill:colors[r.category],'font-size':9/scale,'paint-order':'stroke',stroke:'#fff9e9','stroke-width':2.5/scale,'pointer-events':'none'});text.textContent=r.id;$('annotationLabels').append(text);}
  }
  function drawPorts(){
    $('portMarkers').replaceChildren();if(!data)return;const scale=64*zoom;
    for(const p of data.ports){if(!visible(p))continue;const named=p.kind==='named_port',r=(named?3.4:2.6)/scale;
      const g=make('g',{'data-port':p.id,role:'button','aria-label':p.organName+' '+roles[p.role]+'固定接口',tabindex:0});
      g.append(make(named?'circle':'rect',named?{cx:p.source[0],cy:p.source[1],r,fill:'#eef3dd',stroke:'#2c6a51','stroke-width':1.3,'vector-effect':'non-scaling-stroke'}:{x:p.source[0]-r,y:p.source[1]-r,width:r*2,height:r*2,fill:'#526d52',stroke:'#e9f0dc','stroke-width':1,'vector-effect':'non-scaling-stroke'}));
      g.onclick=()=>{if(named){const c=data.channels.find(c=>c.portId===p.id);selectChannel(c.id,true);}else{chooseOrgan(p.organ,false);center=p.source;setZoom(.15);$('channelDetail').textContent=p.organName+'组织膜口 '+p.id+'：这是指定的血管—组织交换口，不是血管交叉自动开口。';}};
      $('portMarkers').append(g);
    }
    for(const mismatch of data.draftAudit.endpoints){const p=mismatch.point,scale=64*zoom,r=6/scale;
      if(organ!=='all'&&organ!=='stomach')continue;
      $('portMarkers').append(make('path',{d:`M ${p[0]} ${p[1]-r} L ${p[0]+r} ${p[1]+r} L ${p[0]-r} ${p[1]+r} Z`,fill:'#d9c2e6',stroke:colors.pending,'stroke-width':1.5,'vector-effect':'non-scaling-stroke','pointer-events':'none'}));}
  }
  function drawSelection(){
    $('selectionMarker').replaceChildren();const r=data?.records.find(r=>r.id===selected)||data?.passageConflicts.find(r=>r.id===selected);
    if(r){const scale=64*zoom,p=r.sourceMidpoint;$('selectionMarker').append(make('circle',{cx:p[0],cy:p[1],r:8/scale,fill:'none',stroke:'#363d29','stroke-width':1.5,'vector-effect':'non-scaling-stroke','pointer-events':'none'}));}
  }
  function passageCases(){return data.passageConflicts.filter(r=>organ==='all'||r.owners.includes(organ)||data.records.some(o=>o.organ===organ&&o.edgeId===r.edgeId));}
  function caseList(){
    const filter=$('caseFilter').value,list=$('caseList');list.replaceChildren();
    const rows=filter==='passages'?passageCases():data.records.filter(r=>visible(r)&&(filter==='all'||filter===r.category));
    for(const r of rows){const b=document.createElement('button');b.className='case'+(selected===r.id?' active':'');b.style.borderLeftColor=colors[r.category]||'#b85124';b.dataset.record=r.id;
      b.textContent=r.id+' · '+(r.label||r.edgeId+' × '+r.passageName)+' · '+(labels[r.category]||'独立腔道冲突');
      const small=document.createElement('small');small.textContent=r.reason;b.append(small);b.onclick=()=>selectCase(r.id,true);list.append(b);}
  }
  function paragraph(text){const p=document.createElement('p');p.textContent=text;return p;}
  function selectCase(id,focus=false){
    const r=data.records.find(r=>r.id===id)||data.passageConflicts.find(r=>r.id===id);if(!r)return;selected=id;
    if(r.passageId)$('showPassages').checked=true;
    const detail=$('caseDetail');detail.replaceChildren();const h=document.createElement('h2');h.textContent=id+' · '+(r.label||r.edgeId+' × '+r.passageName);detail.append(h);
    const label=document.createElement('span');label.className='tag';label.textContent=labels[r.category]||'独立腔道冲突';detail.append(label,paragraph(r.reason));
    const e=data.edges.find(e=>e.id===r.edgeId);detail.append(paragraph(`血管关系：${e.a||'未命名'} → ${e.b||'未命名'}；${e.system==='capillary'?'交换血管':e.system==='vein'?'静脉回流':'动脉供血'}。`));
    if(r.category==='pending')detail.append(paragraph('新末端 (566, 503) 对齐 stomach.a，但 b 仍标旧外壁死端。需要补命名接入、流向和膜口；当前未改原稿。'));
    const conflicts=data.passageConflicts.filter(p=>p.edgeId===r.edgeId);if(conflicts.length)detail.append(paragraph('此血管另有 '+conflicts.length+' 组食物／气道／尿路投影重合，可勾选冲突层查看；已有连接不等于局部净空通过。'));
    detail.append(paragraph('标注位置（原图坐标）：'+round(r.sourceMidpoint)+'。'));
    if(r.boundaryKind==='coarse_locator')detail.append(paragraph('此器官仍使用定位轮廓，贴边重合保留待精细复核状态。'));
    if(focus){center=r.sourceMidpoint;zoom=Math.max(zoom,.035);}caseList();draw();
  }
  function channelButtons(){
    $('channelButtons').replaceChildren();for(const c of data.channels.filter(c=>organ==='all'||c.organ===organ)){
      const b=document.createElement('button');b.className=channel===c.id?'active':'';b.dataset.channel=c.id;b.textContent=c.id+' '+c.organName+' '+roles[c.role];b.onclick=()=>selectChannel(c.id,true);$('channelButtons').append(b);}
    $('channelDetail').textContent='圆点是冻结的血管供回口，方点是组织膜口。选一个通道可按0.15查看；通道沿现有血管延伸，不移动接口。';
  }
  function selectChannel(id,focus){const c=data.channels.find(c=>c.id===id);if(!c)return;
    if(organ!==c.organ)chooseOrgan(c.organ,false);channel=id;$('showChannels').checked=true;
    for(const b of $('channelButtons').children)b.classList.toggle('active',b.dataset.channel===id);
    const foreign=c.crossedOrgans.map(o=>o.name).join('、'),special=c.crossedPassages.map(p=>p.name).join('、');
    $('channelDetail').textContent=`${id} · ${c.portId} · 沿 ${c.edgeId} · 冻结接口 (${round(c.frozenSource)}) → 器官内侧 (${round(c.targetSource)})。${c.startsInsideOutline?'接口已在轮廓内。':'接口在视觉轮廓外，保留短接入段。'}${foreign?'需核对跨 '+foreign+' 的深度接续。':''}${special?'另与 '+special+' 投影重合，须保留独立通路。':''}细胞移动与出口净空未验收。`;
    if(focus){center=c.points[Math.floor(c.points.length/2)];zoom=.15;}draw();
  }
  async function start(){
    const response=await fetch('vascular-organ-overlap-data.json',{cache:'no-store'});if(!response.ok)throw Error('标注数据加载失败');data=await response.json();
    if(data.coordinates.width!==1024||data.coordinates.height!==1536||data.edges.length!==202)throw Error('原图坐标基准不匹配');
    const c=data.counts;$('summary').textContent=`已检查全身 ${c.vessels} 条设计血管与 ${c.organs} 个器官：${c.organVesselPairs} 组重合，${c.channels015} 个0.15接入通道候选。独立腔道另列 ${c.passageConflictPairs} 组投影重合。未生图、未替换生产地图。`;
    for(const o of data.organs){$('organSelect').add(new Option(o.name,o.id));const b=document.createElement('button');b.textContent=o.name;b.dataset.organ=o.id;b.onclick=()=>chooseOrgan(o.id);$('regionButtons').append(b);
      const counts=Object.keys(labels).map(k=>data.records.filter(r=>r.organ===o.id&&r.category===k).length),tr=document.createElement('tr'),td=document.createElement('td'),button=document.createElement('button');button.textContent=o.name;button.onclick=()=>chooseOrgan(o.id);td.append(button);tr.append(td);for(const n of counts){const cell=document.createElement('td');cell.textContent=n;tr.append(cell);}$('organRows').append(tr);}
    for(const text of data.limitations){const li=document.createElement('li');li.textContent=text;$('limitations').append(li);}
    $('organSelect').onchange=()=>chooseOrgan($('organSelect').value);$('caseFilter').onchange=()=>{if($('caseFilter').value==='passages')$('showPassages').checked=true;caseList();draw();};
    for(const id of ['showNetwork','showConnect','showReroute','showOcclude','showPending','showPassages','showChannels'])$(id).onchange=draw;
    $('fitBody').onclick=()=>chooseOrgan('all');$('fitTorso').onclick=()=>fit([350,275,680,835]);$('zoomPlus').onclick=()=>setZoom(zoom*1.5);$('zoomMinus').onclick=()=>setZoom(zoom/1.5);
    for(const [id,bounds] of [['fitHead',[405,5,615,280]],['fitArms',[125,260,895,925]],['fitLegs',[310,765,710,1520]]])$(id).onclick=()=>{chooseOrgan('all',false);fit(bounds);};
    $('zoom015').onclick=()=>{const c=data.channels.find(c=>c.id===channel)||data.channels.find(c=>c.organ===(organ==='all'?'stomach':organ));selectChannel(c.id,true);};
    map.addEventListener('wheel',e=>{e.preventDefault();setZoom(zoom*Math.exp(-Math.max(-100,Math.min(100,e.deltaY))*.004),source(e));},{passive:false});
    map.addEventListener('pointerdown',e=>{if(e.target.closest('[data-record],[data-passage-record],[data-channel],[data-organ-label],[data-port]'))return;gesture={x:e.clientX,y:e.clientY,center:[...center],scale:64*zoom};map.setPointerCapture(e.pointerId);});
    map.addEventListener('pointermove',e=>{if(!gesture)return;center=[gesture.center[0]-(e.clientX-gesture.x)/gesture.scale,gesture.center[1]-(e.clientY-gesture.y)/gesture.scale];if(!frame)frame=requestAnimationFrame(()=>{frame=0;view();});});
    const end=()=>{gesture=null;};map.addEventListener('pointerup',end);map.addEventListener('pointercancel',end);map.addEventListener('lostpointercapture',end);
    new ResizeObserver(view).observe(map);chooseOrgan('all');
  }
  start().catch(e=>{$('error').textContent=e.message;console.error(e);});
})();
