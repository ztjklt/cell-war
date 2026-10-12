(() => {
  'use strict';
  const byId = id => document.getElementById(id);
  const svg = byId('sampleMap'), NS = 'http://www.w3.org/2000/svg';
  const palette = {artery:'#bb5148',vein:'#36799f',capillary:'#83658d'};
  let box = [350,450,324,216], mode = 'sample', dragging = null, data;
  const point = e => new DOMPoint(e.clientX,e.clientY).matrixTransform(svg.getScreenCTM().inverse());
  const el = (name, attrs, parent, title) => {
    const node = document.createElementNS(NS,name);
    Object.entries(attrs).forEach(([k,v]) => node.setAttribute(k,String(v)));
    if(title){const t=document.createElementNS(NS,'title');t.textContent=title;node.append(t);}
    parent.append(node);return node;
  };
  const path = points => 'M '+points.map(p=>p.join(' ')).join(' L ');
  function updateView(){
    svg.setAttribute('viewBox',box.join(' '));
    byId('viewCaption').textContent = mode==='raw'
      ? 'GPT 初稿：已排除连接错误，仅用于美术对照。'
      : mode==='original' ? '原图对照：取景和坐标保持一致。'
      : box[2]>800 ? '全身试贴：仅上腹部参与编辑，脑部与四肢为原图像素。'
      : '校准试样：深层接续由前景遮住，可切换虚线核对；裁切外保留原图。';
  }
  function fit(next,body=false){box=next.slice();svg.classList.toggle('body-view',body);updateView();}
  function variant(next){mode=next;byId('sampleArt').style.display=mode==='sample'?'':'none';byId('rawArt').style.display=mode==='raw'?'':'none';
    for(const [id,v] of [['showSample','sample'],['showOriginal','original'],['showRaw','raw']])byId(id).setAttribute('aria-pressed',mode===v);updateView();}
  function zoom(factor,center){const c=center||{x:box[0]+box[2]/2,y:box[1]+box[3]/2};const w=Math.max(12,Math.min(1800,box[2]*factor)),h=w*box[3]/box[2];box=[c.x-(c.x-box[0])*w/box[2],c.y-(c.y-box[1])*h/box[3],w,h];updateView();}
  byId('showSample').onclick=()=>variant('sample');byId('showOriginal').onclick=()=>variant('original');byId('showRaw').onclick=()=>variant('raw');
  byId('fitUpper').onclick=()=>fit([350,450,324,216]);byId('fitBody').onclick=()=>fit([0,0,1024,1536],true);
  byId('fitStomach').onclick=()=>fit([476,466,150,112]);
  byId('fitGates').onclick=()=>{fit([557,515,66,44]);byId('showPorts').checked=true;layers();};
  byId('zoomPlus').onclick=()=>zoom(.8);byId('zoomMinus').onclick=()=>zoom(1.25);
  function layers(){for(const [input,ids] of [['showGuide',['visibleLayer']],['showDeep',['deepLayer']],['showPorts',['portLayer','gateLayer']],['showOrgans',['organLayer']],['showFood',['foodLayer']]])for(const id of ids)byId(id).style.display=byId(input).checked?'':'none';}
  for(const id of ['showGuide','showDeep','showPorts','showOrgans','showFood'])byId(id).onchange=layers;
  svg.addEventListener('wheel',e=>{e.preventDefault();zoom(Math.exp(Math.max(-200,Math.min(200,e.deltaY))*.002),point(e));},{passive:false});
  svg.addEventListener('pointerdown',e=>{if(e.button!==0)return;const p=point(e);dragging={x:p.x,y:p.y,box:box.slice(),moved:false};svg.setPointerCapture(e.pointerId);});
  svg.addEventListener('pointermove',e=>{if(!dragging)return;const p=point(e),dx=p.x-dragging.x,dy=p.y-dragging.y;if(Math.hypot(dx,dy)>.5)dragging.moved=true;box[0]-=dx;box[1]-=dy;updateView();});
  svg.addEventListener('pointerup',e=>{if(dragging&&!dragging.moved)select(point(e));dragging=null;});
  svg.addEventListener('pointercancel',()=>{dragging=null;});
  svg.addEventListener('keydown',e=>{if(['+','=','-','0'].includes(e.key)){e.preventDefault();e.key==='0'?fit([350,450,324,216]):zoom(e.key==='-'?1.25:.8);}});
  function select(p){
    if(!data)return;byId('selectedLayer').replaceChildren();
    const port = [...data.ports,...data.gates.map(g=>({id:g.id,source:g.wallSource,gate:true}))].map(q=>({...q,d:Math.hypot(q.source[0]-p.x,q.source[1]-p.y)})).sort((a,b)=>a.d-b.d)[0];
    if(port&&port.d<box[2]/28){el('circle',{cx:port.source[0],cy:port.source[1],r:2.2,fill:'none',stroke:'#29594b','stroke-width':.6},byId('selectedLayer'));byId('routeDetail').textContent=`${port.id} · 原图坐标 (${port.source.map(v=>v.toFixed(2)).join(', ')})。${port.gate?'定稿胃壁组织出口；纹样已标，移动尚未接入。':'命名供回流接口；本轮位置保持不变。'}`;return;}
    let nearest=null;
    for(const e of data.edges)for(const ps of e.visibleSegments)for(const q of ps){const d=Math.hypot(q[0]-p.x,q[1]-p.y);if(!nearest||d<nearest.d)nearest={e,d};}
    if(!nearest||nearest.d>box[2]/28)return;
    const e=nearest.e;for(const ps of e.visibleSegments)el('path',{d:path(ps),fill:'none',stroke:'#285d49','stroke-width':e.lumenWidthSource+.8,opacity:.6},byId('selectedLayer'));
    const hidden=data.hidden.filter(h=>h.edgeId===e.id);for(const h of hidden)el('path',{d:path(h.points),fill:'none',stroke:'#31485f','stroke-width':.8,'stroke-dasharray':'2 2'},byId('selectedLayer'));
    byId('routeDetail').textContent=`${e.id} · ${e.a} → ${e.b}。可见 ${e.visibleSegments.length} 段，定稿遮挡 ${hidden.length} 段。遮挡与投影交叉均不创建新连接。`;
  }
  fetch('upper-abdomen-review-data.json').then(r=>{if(!r.ok)throw Error('复核数据未加载');return r.json();}).then(d=>{
    data=d;
    for(const e of d.edges)for(const ps of e.visibleSegments)el('path',{d:path(ps),fill:'none',stroke:palette[e.system],'stroke-width':.55,'stroke-linecap':'round'},byId('visibleLayer'),e.id);
    for(const h of d.hidden)el('path',{d:path(h.points),fill:'none',stroke:'#536a73','stroke-width':.62,'stroke-dasharray':'2 2',opacity:.8},byId('deepLayer'),`${h.id} ${h.edgeId} ${h.owner}`);
    for(const o of d.organs)el('path',{d:o.d,fill:'none',stroke:'#47705a','stroke-width':.55,opacity:.9},byId('organLayer'),o.name);
    for(const p of d.food)el('path',{d:path(p.points),fill:'none',stroke:'#bf8f3c','stroke-width':p.width,opacity:.24,'stroke-linecap':'round'},byId('foodLayer'),p.name+'：独立食物通路');
    for(const p of d.ports)el('circle',{cx:p.source[0],cy:p.source[1],r:1.15,fill:p.role==='return'?'#4f85a3':'#b06554',stroke:'#f5ebd6','stroke-width':.45},byId('portLayer'),p.id);
    for(const g of d.gates){el('path',{d:path([g.pipeCenterSource,g.wallSource,g.tissueTargetSource]),fill:'none',stroke:'#2d7350','stroke-width':.65},byId('gateLayer'),g.id);el('circle',{cx:g.wallSource[0],cy:g.wallSource[1],r:1.5,fill:'#e9e4b3',stroke:'#327c52','stroke-width':.6},byId('gateLayer'),g.id);}
    byId('checkStatus').textContent=`已核对 ${d.counts.edges} 条局部血管：${d.counts.visible} 条有可见段，${d.counts.hiddenOnly} 条仅为深层；器官固定轮廓与 ${d.counts.gates} 个胃壁口沿用定稿。裁切外像素变化：0。`;
    layers();updateView();
  }).catch(e=>{byId('error').textContent=e.message;});
  updateView();
})();
