(function () {
  "use strict";
  window.initializeVascularEditor = function (network, regions, central) {
    const C=window.VascularEditorCore, q=id=>document.getElementById(id), ns="http://www.w3.org/2000/svg";
    const svg=q("editScene"), group=q("editLines"), overlay=q("editHandles");
    const make=(tag,attrs)=>{const n=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs)) n.setAttribute(k,v);return n;};
    const baseline=C.clone(network.edges);
    // Fingerprint distinguishes coordinate/width changes without touching the simulation.
    let hash=2166136261;for(const ch of JSON.stringify(baseline)) hash=Math.imul(hash^ch.charCodeAt(0),16777619);
    const baselineId=`navigation-${(hash>>>0).toString(16)}`, key=`vascular-draft/v1/${baselineId}`;
    let edges=C.clone(baseline), selected=null, tool="select", draft=[], gesture=null, view=[0,0,1024,1536];
    let history=[C.clone(edges)], cursor=0, sequence=Date.now(), saveMessage="尚无修改", notice="", curves=new Map();
    const colors={artery:"#b44c48",vein:"#397ca6"};
    const centralIds=new Set(central.centralEdges), protectedIds=new Set(central.preservedEdges);
    const nodePoints=new Map();for(const e of baseline){if(e.a)nodePoints.set(e.a,e.points[0]);if(e.b)nodePoints.set(e.b,e.points.at(-1));}
    function connectionPath(from,to,systems){const graph=new Map();for(const e of edges){
      if(!systems.includes(e.system)||!e.a||!e.b||!nodePoints.has(e.a)||!nodePoints.has(e.b))continue;
      if(C.distance(e.points[0],nodePoints.get(e.a)||[])>.001||C.distance(e.points.at(-1),nodePoints.get(e.b)||[])>.001)continue;
      if(!graph.has(e.a))graph.set(e.a,[]);graph.get(e.a).push(e);
    }const queue=[[from,[]]],seen=new Set([from]);for(let i=0;i<queue.length;i++){const [n,path]=queue[i];if(n===to)return path;for(const e of graph.get(n)||[])if(!seen.has(e.b)){seen.add(e.b);queue.push([e.b,[...path,e.id]]);}}return null;}
    function connectionState(organ){return {
      supply:connectionPath(organ.supplyRoot,organ.entry,["artery"]),
      exchange:connectionPath(organ.entry,organ.exit,["artery","vein","capillary"]),
      back:connectionPath(organ.exit,organ.returnRoot,["vein","capillary"])};}
    function connectionDetail(){
      const audit=C.inspectDraft(edges,baseline,network.gates,curves);
      q("editDraftReview").textContent=audit.endpoints.length||audit.gateIssues.length
        ? `草稿待复核：${audit.endpoints.length} 个端点的连接标记未匹配，${audit.gateIssues.length} 个旧出口锚点已偏离修改后的管线。画面相接不能代替通行验收。`
        : "草稿端点标记未发现偏移；移动、净空与会车仍以原基准回放为准。";
      q("editDraftReview").classList.toggle("bad",!!(audit.endpoints.length||audit.gateIssues.length));
      const id=q("editRegion").value,organs=central.organs.filter(o=>o.region===id),ports=q("editPorts");ports.replaceChildren();
      if(!organs.length){const count=central.organs.filter(o=>{const c=connectionState(o);return c.supply&&c.exchange&&c.back;}).length;
        q("editConnection").textContent=`现有主通路 ${count}/13 组器官供血、交换、回流连通；此数量不包含新增或修改支线的通行验收。选择器官查看接口。`;return;}
      const details=[];for(const organ of organs){const c=connectionState(organ);
        details.push(`${organ.name}：供血 ${c.supply?"已连接":"需要复核"} · 内部交换 ${c.exchange?"已连接":"需要复核"} · 回流 ${c.back?"已连接":"需要复核"}。${organ.portal?"消化回流经门静脉汇入肝内交换区。":""}`);
        const scale=pixelScale();for(const [node,label,color] of [[organ.entry,"供血口",colors.artery],[organ.exit,"回流口",colors.vein],...(organ.portalEntry?[[organ.portalEntry,"门静脉口","#886f98"]]:[])]){
          const p=nodePoints.get(node);if(!p)continue;ports.append(make("circle",{cx:p[0],cy:p[1],r:4/scale,fill:"#fff8d3",stroke:color,"stroke-width":2,"vector-effect":"non-scaling-stroke","pointer-events":"none"}));
          const text=make("text",{x:p[0]+6/scale,y:p[1]-6/scale,fill:"#334039","font-size":12/scale,"paint-order":"stroke",stroke:"#edf0e3","stroke-width":3/scale,"pointer-events":"none"});text.textContent=label;ports.append(text);
        }
      }q("editConnection").textContent=details.join(" ")+" 检查依据是共同节点与端点坐标。";
    }
    function locked(){return q("editLock").checked&&protectedIds.has(selected);}
    function lockedPoint(e,i){return q("editLock").checked&&Object.values(central.lockedNodes).some(p=>C.distance(p,e.points[i])<.001);}
    function payload(){return {schema:"vascular-draft/v1",baselineId,coordinateSystem:{width:1024,height:1536,worldScale:2,worldOffset:[0,512]},status:"draft_requires_navigation_recheck",edges:C.clone(edges),changes:C.changes(edges,baseline),logicalGates:C.clone(network.gates),preservedSections:{edges:central.preservedEdges,lockedNodes:central.lockedNodes},rendering:{centralTubePreview:q("editTube").checked,curvedPreview:q("editCurve").checked,curveStrength:Number(q("editCurveStrength").value),curveAlgorithm:"bounded-cubic-v1",sourceAnchorsUnchanged:C.anchorsUnchanged(edges,baseline),curvePreservesAuthoredAnchors:true,collisionGeometryRemainsBaseline:true},note:"Logical gates retain baseline coordinates and require reassignment after vessel edits. Line crossings alone do not create connected junctions."};}
    try {const saved=localStorage.getItem(key);if(saved){const stored=C.validate(JSON.parse(saved),baselineId);edges=stored.edges;if(typeof stored.rendering?.curvedPreview==="boolean")q("editCurve").checked=stored.rendering.curvedPreview;if(stored.rendering?.curveStrength!=null)q("editCurveStrength").value=stored.rendering.curveStrength;history=[C.clone(edges)];saveMessage="已恢复浏览器草稿";}} catch(e){saveMessage="草稿未读取："+e.message;}
    function save(){try{localStorage.setItem(key,JSON.stringify(payload()));saveMessage="已自动保存到此浏览器";}catch(e){saveMessage="浏览器保存失败，请导出 JSON 备份";}}
    function commit(){history=history.slice(0,cursor+1);history.push(C.clone(edges));if(history.length>80)history.shift();cursor=history.length-1;save();render();}
    function active(){return edges.find(e=>e.id===selected);}
    function point(event){const p=svg.createSVGPoint();p.x=event.clientX;p.y=event.clientY;const matrix=svg.getScreenCTM();if(!matrix)return null;const v=p.matrixTransform(matrix.inverse());return [v.x,v.y];}
    function bounded(p){return [Math.max(0,Math.min(1024,p[0])),Math.max(0,Math.min(1536,p[1]))];}
    function pixelScale(){const m=svg.getScreenCTM();return m?Math.max(.001,Math.hypot(m.a,m.b)):1;}
    function snap(p,exclude){if(!q("editSnap").checked)return bounded(p);let best=bounded(p),d=10/pixelScale();for(const e of edges){if(e.id===exclude)continue;for(const v of e.points){const n=C.distance(p,v);if(n<d){d=n;best=C.clone(v);}}}return best;}
    function applyView(){svg.setAttribute("viewBox",view.join(" "));q("editZoomLabel").textContent=`${(1024/view[2]).toFixed(1)}×`;renderHandles();connectionDetail();}
    function zoom(factor,p=[view[0]+view[2]/2,view[1]+view[3]/2]){const w=Math.max(12,Math.min(2048,view[2]/factor)),ratio=w/view[2];view=[p[0]-(p[0]-view[0])*ratio,p[1]-(p[1]-view[1])*ratio,w,view[3]*ratio];applyView();}
    function fit(points){if(!points?.length){view=[0,0,1024,1536];applyView();return;}const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]),x=Math.min(...xs),y=Math.min(...ys),w=Math.max(20,Math.max(...xs)-x),h=Math.max(20,Math.max(...ys)-y);view=[x-w*.15,y-h*.15,w*1.3,h*1.3];applyView();}
    function renderHandles(){overlay.replaceChildren();const e=active(),r=5/pixelScale();if(e&&tool==="select"&&!locked())for(let i=0;i<e.points.length;i++){const p=e.points[i];if(lockedPoint(e,i))continue;overlay.append(make("circle",{cx:p[0],cy:p[1],r,fill:"#fff8d3",stroke:"#554724","stroke-width":1.5,"vector-effect":"non-scaling-stroke","data-point":i,"aria-label":`节点 ${i+1}`}));}
      if(draft.length){overlay.append(make("path",{d:C.curvedNetwork([{id:"preview",points:draft}],q("editCurve").checked?Number(q("editCurveStrength").value):0).get("preview").d,fill:"none",stroke:colors[q("editType").value],"stroke-width":Number(q("editWidth").value),"stroke-linecap":"round","stroke-linejoin":"round","pointer-events":"none"}));for(const p of draft)overlay.append(make("circle",{cx:p[0],cy:p[1],r:r*.7,fill:"#fff8d3","pointer-events":"none"}));}}
    function render(){curves=C.curvedNetwork(edges,q("editCurve").checked?Number(q("editCurveStrength").value):0);q("editCurveValue").textContent=Math.round(Number(q("editCurveStrength").value)*100)+"%";group.replaceChildren();for(const e of edges){
      if(q("editTube").checked&&centralIds.has(e.id)){
        const g=make("g",{"data-edge":e.id,"aria-label":`血管 ${e.id}`}),d=curves.get(e.id).d,w=e.lumenWidthSource;
        const color=e.id===selected?"#b79a51":e.system==="capillary"?"#b88870":colors[e.kind];
        for(const [stroke,width,opacity] of [[e.kind==="vein"?"#456275":"#754943",w+1.1,1],[color,w,1],["#e6c5aa",w*.23,.3]])g.append(make("path",{d,fill:"none",stroke,"stroke-width":width,"stroke-opacity":opacity,"stroke-linecap":"round","stroke-linejoin":"round"}));group.append(g);
      }else{const line=make("path",{d:curves.get(e.id).d,fill:"none",stroke:e.id===selected?"#c79c3f":colors[e.kind],"stroke-width":e.lumenWidthSource,"stroke-linecap":"round","stroke-linejoin":"round","data-edge":e.id,"aria-label":`血管 ${e.id}`});group.append(line);}}
      const e=active(),delta=C.changes(edges,baseline);q("editSelection").textContent=e?`${e.id} · ${e.kind==="vein"?"静脉":"动脉"} · ${e.points.length} 个节点 · 管径 ${e.lumenWidthSource} 原图像素`:"未选中血管";
      q("editStatus").textContent=`${edges.length} 段 · 新增 ${delta.added.length} / 修改 ${delta.modified.length} / 删除 ${delta.deleted.length} · ${saveMessage}${notice?" · "+notice:""}`;
      q("editDelete").disabled=!e||locked();q("editFitLine").disabled=!e;q("editUndo").disabled=cursor===0;q("editRedo").disabled=cursor===history.length-1;q("editFinish").disabled=draft.length<2;
      q("editType").disabled=locked();q("editWidth").disabled=locked();if(locked())q("editSelection").textContent+=" · 头部 / 四肢已锁定";
      renderHandles();connectionDetail();}
    function setTool(next){if(draft.length){draft=[];notice="未完成线条已取消";}tool=next;if(tool==="draw"||tool==="free")selected=null;for(const b of document.querySelectorAll("[data-edit-tool]"))b.setAttribute("aria-pressed",b.dataset.editTool===tool);svg.style.cursor=tool==="pan"?"grab":tool==="select"?"default":"crosshair";q("editHint").textContent={select:"点击线条选中；拖动浅色节点调整位置。空白处拖动可平移。",pan:"拖动画布平移；滚轮或 + / − 缩放。",draw:"依次点击设置转折点；点「完成线条」或按 Enter 完成，Esc 取消。",free:"按住拖动画线；松手完成，自动减少多余节点。"}[tool];render();}
    function addLine(points){points=points.filter((p,i)=>!i||C.distance(p,points[i-1])>.01);if(points.length<2)return;points[0]=snap(points[0]);points[points.length-1]=snap(points.at(-1));if(!points.some(p=>C.distance(p,points[0])>.01))return;
      const kind=q("editType").value;selected="draft-"+(++sequence);edges.push({id:selected,kind,system:kind,lumenWidthSource:Number(q("editWidth").value),points:C.clone(points),origin:"manual"});notice="新线已加入草稿；接入寻路前需复核";draft=[];commit();}
    function finish(){if(draft.length>=2)addLine(draft);}
    function undo(step){if(gesture)return;const n=cursor+step;if(n<0||n>=history.length)return;cursor=n;edges=C.clone(history[cursor]);selected=null;draft=[];notice="";save();render();}
    function remove(){if(!active()||locked())return;edges=edges.filter(e=>e.id!==selected);selected=null;notice="已删除草稿线；底图像素仍保留";commit();}
    function hit(p){let found=null,best=8/pixelScale();for(const e of edges){const samples=curves.get(e.id)?.samples||e.points;for(let i=1;i<samples.length;i++){const d=C.segmentDistance(p,samples[i-1],samples[i])-e.lumenWidthSource/2;if(d<best){best=d;found=e.id;}}}return found;}
    svg.addEventListener("wheel",e=>{e.preventDefault();if(gesture)return;zoom(Math.exp(-Math.max(-100,Math.min(100,e.deltaY))*.004),point(e));},{passive:false});
    svg.addEventListener("pointerdown",e=>{
      if(e.button!==0&&e.button!==1&&e.button!==2)return;svg.focus({preventScroll:true});const p=point(e);if(!p)return;notice="";
      const forcePan=e.button!==0||e.shiftKey;
      if(tool==="draw"&&!forcePan){if(p[0]<0||p[0]>1024||p[1]<0||p[1]>1536)return;const v=snap(p);if(!draft.length||C.distance(v,draft.at(-1))>.01)draft.push(v);render();return;}
      svg.setPointerCapture(e.pointerId);
      if(forcePan||tool==="pan"){gesture={type:"pan",p,view:C.clone(view),pointer:e.pointerId};return;}
      if(tool==="free"){draft=[bounded(p)];gesture={type:"free",pointer:e.pointerId};render();return;}
      const index=e.target.getAttribute("data-point");
      if(index!==null&&active()&&!locked()&&!lockedPoint(active(),Number(index))){gesture={type:"node",index:Number(index),before:C.clone(edges),pointer:e.pointerId};return;}
      selected=hit(p);const a=active();if(a){q("editType").value=a.kind;q("editWidth").value=a.lumenWidthSource;}
      else gesture={type:"pan",p,view:C.clone(view),pointer:e.pointerId};render();
    });
    svg.addEventListener("pointermove",e=>{if(!gesture||gesture.pointer!==e.pointerId)return;const p=point(e);if(gesture.type==="pan"){const dx=p[0]-gesture.p[0],dy=p[1]-gesture.p[1];view=[view[0]-dx,view[1]-dy,view[2],view[3]];applyView();}
      if(gesture.type==="node"){active().points[gesture.index]=bounded(p);render();}
      if(gesture.type==="free"&&C.distance(p,draft.at(-1))>2/pixelScale()){draft.push(bounded(p));if(draft.length>4096)draft=C.simplify(draft,1/pixelScale());renderHandles();}});
    function endGesture(e,cancel=false){if(!gesture||e.pointerId!==gesture.pointer)return;const g=gesture;gesture=null;
      if(g.type==="node"){if(cancel)edges=g.before;else{active().points[g.index]=snap(active().points[g.index],selected);if(JSON.stringify(edges)!==JSON.stringify(g.before))commit();}render();}
      if(g.type==="free"){if(cancel){draft=[];render();}else{draft.push(bounded(point(e)));addLine(C.simplify(draft,1.2/pixelScale()));}}
      if(svg.hasPointerCapture(e.pointerId))svg.releasePointerCapture(e.pointerId);}
    svg.addEventListener("pointerup",e=>endGesture(e));svg.addEventListener("pointercancel",e=>endGesture(e,true));svg.addEventListener("lostpointercapture",e=>endGesture(e,true));svg.addEventListener("contextmenu",e=>e.preventDefault());
    svg.addEventListener("keydown",e=>{if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==="z"){e.preventDefault();undo(e.shiftKey?1:-1);}else if(e.key==="Delete"||e.key==="Backspace"){e.preventDefault();remove();}else if(e.key==="Enter"){e.preventDefault();finish();}else if(e.key==="Escape"){draft=[];if(gesture){const g=gesture;gesture=null;if(g.type==="node")edges=g.before;}render();}});
    for(const b of document.querySelectorAll("[data-edit-tool]"))b.onclick=()=>setTool(b.dataset.editTool);
    q("editFinish").onclick=finish;q("editDelete").onclick=remove;q("editUndo").onclick=()=>undo(-1);q("editRedo").onclick=()=>undo(1);
    q("editPlus").onclick=()=>zoom(1.5);q("editMinus").onclick=()=>zoom(1/1.5);q("editFit").onclick=()=>fit();q("editTorso").onclick=()=>fit([[340,280],[680,820]]);q("editFitLine").onclick=()=>fit(active()?.points);
    q("editType").onchange=()=>{if(active()){active().kind=q("editType").value;active().system=active().kind;commit();}};
    q("editWidth").onchange=()=>{const width=Number(q("editWidth").value);if(!Number.isFinite(width)||width<.1||width>40){q("editWidth").value=active()?.lumenWidthSource||3;return;}if(active()){active().lumenWidthSource=width;commit();}else renderHandles();};
    q("editReference").oninput=()=>q("editImage").setAttribute("opacity",q("editReference").value);
    q("editShowLines").onchange=()=>{group.style.visibility=q("editShowLines").checked?"visible":"hidden";};
    q("editTube").onchange=render;q("editLock").onchange=render;q("editCurve").onchange=()=>{save();render();};q("editCurveStrength").oninput=()=>{render();};q("editCurveStrength").onchange=()=>{save();render();};
    for(const region of regions){const points=region.outlines?.flatMap(r=>r.points)||region.boundaryRings?.flatMap(r=>r.points);if(!points?.length)continue;const option=new Option(region.name||region.id,region.id);q("editRegion").add(option);option._points=points;}
    q("editRegion").onchange=()=>fit(q("editRegion").selectedOptions[0]._points);
    function download(text,name,type){const url=URL.createObjectURL(new Blob([text],{type})),a=document.createElement("a");a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
    q("editExport").onclick=()=>{download(JSON.stringify(payload(),null,2),"vascular-draft.json","application/json");notice="已导出原图坐标与修改清单";render();};
    q("editExportSvg").onclick=()=>{const out=make("svg",{xmlns:ns,viewBox:"0 0 1024 1536",width:1024,height:1536});out.append(make("rect",{width:1024,height:1536,fill:"white"}));const title=make("title",{});title.textContent="血管草稿 · 1024×1536 原图坐标";out.append(title);for(const e of edges)out.append(make("path",{d:curves.get(e.id).d,fill:"none",stroke:colors[e.kind],"stroke-width":e.lumenWidthSource,"stroke-linecap":"round","stroke-linejoin":"round","data-edge":e.id}));download(new XMLSerializer().serializeToString(out),"vascular-guide.svg","image/svg+xml");};
    q("editImport").onclick=()=>{q("editJson").value="";q("editImportError").textContent="";q("editImportDialog").showModal();};
    q("editImportCancel").onclick=()=>q("editImportDialog").close();
    q("editImportApply").onclick=()=>{try{edges=C.validate(JSON.parse(q("editJson").value),baselineId).edges;selected=null;draft=[];notice="已导入草稿";commit();q("editImportDialog").close();}catch(e){q("editImportError").textContent=e.message;}};
    q("editRestore").onclick=()=>{edges=C.clone(baseline);selected=null;draft=[];notice="已恢复基准，可撤销";commit();};
    new ResizeObserver(()=>renderHandles()).observe(svg);
    applyView();setTool("select");
  };
})();
