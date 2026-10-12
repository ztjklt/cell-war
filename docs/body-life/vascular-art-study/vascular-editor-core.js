/* Shared source-image geometry; independent of the simulation and browser storage. */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.VascularEditorCore = factory();
})(typeof window === "undefined" ? this : window, function () {
  "use strict";
  const clone = value => JSON.parse(JSON.stringify(value));
  const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  function segmentDistance(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy || 1)));
    return distance(p, [a[0]+dx*t, a[1]+dy*t]);
  }
  function simplify(points, tolerance) {
    if (points.length < 3) return clone(points);
    let max = 0, index = 0;
    for (let i=1; i<points.length-1; i++) {
      const d = segmentDistance(points[i], points[0], points.at(-1));
      if (d > max) { max=d; index=i; }
    }
    return max > tolerance
      ? [...simplify(points.slice(0,index+1),tolerance).slice(0,-1), ...simplify(points.slice(index),tolerance)]
      : [clone(points[0]), clone(points.at(-1))];
  }
  function validate(document, baselineId) {
    if (!document || document.schema !== "vascular-draft/v1" || document.baselineId !== baselineId)
      throw Error("草稿版本或血管基准不同，请使用此页面导出的 JSON。");
    if (document.coordinateSystem?.width !== 1024 || document.coordinateSystem?.height !== 1536)
      throw Error("草稿必须使用 1024×1536 原图坐标。");
    if (!Array.isArray(document.edges) || document.edges.length > 2000) throw Error("草稿线条数量无效。");
    const ids = new Set();
    for (const e of document.edges) {
      if (typeof e.id !== "string" || ids.has(e.id) || !["artery","vein"].includes(e.kind)) throw Error("线条编号或类型无效。");
      ids.add(e.id);
      if (!Number.isFinite(e.lumenWidthSource) || e.lumenWidthSource < .1 || e.lumenWidthSource > 40) throw Error("管径须为 0.1–40 原图像素。");
      if (!Array.isArray(e.points) || e.points.length < 2 || e.points.length > 4096) throw Error("每条线须有 2–4096 个节点。");
      for (const p of e.points) if (!Array.isArray(p) || p.length !== 2 || !p.every(Number.isFinite) || p[0]<0 || p[0]>1024 || p[1]<0 || p[1]>1536) throw Error("节点超出原图坐标范围。");
      if (!e.points.some(p=>distance(p,e.points[0])>.01)) throw Error("线条长度为零。");
    }
    return clone(document);
  }
  function changes(edges, baseline) {
    const old = new Map(baseline.map(e=>[e.id,e])), now = new Map(edges.map(e=>[e.id,e]));
    return {added:edges.filter(e=>!old.has(e.id)).map(e=>e.id),
      deleted:baseline.filter(e=>!now.has(e.id)).map(e=>e.id),
      modified:edges.filter(e=>old.has(e.id) && JSON.stringify(e)!==JSON.stringify(old.get(e.id))).map(e=>e.id)};
  }
  function anchorsUnchanged(edges, baseline) {
    const old=new Map(baseline.map(e=>[e.id,e.points]));
    return edges.length===baseline.length&&edges.every(e=>old.has(e.id)&&JSON.stringify(e.points)===JSON.stringify(old.get(e.id)));
  }
  // A visual snap is not a named graph connection, and moving a lane does not move its gates.
  function inspectDraft(edges, baseline, gates, curves) {
    const nodes=new Map(),now=new Map(edges.map(e=>[e.id,e]));
    for(const e of baseline){if(e.a)nodes.set(e.a,e.points[0]);if(e.b)nodes.set(e.b,e.points.at(-1));}
    const endpoints=[];
    for(const e of edges)for(const [end,p] of [["a",e.points[0]],["b",e.points.at(-1)]]){
      const assigned=e[end],expected=nodes.get(assigned);
      if(!expected||distance(p,expected)>.001)endpoints.push({edgeId:e.id,end,assigned:assigned||null,
        point:clone(p),expected:expected?clone(expected):null,
        matches:[...nodes].filter(([,v])=>distance(p,v)<.001).map(([id])=>id)});
    }
    const delta=changes(edges,baseline),edited=new Set([...delta.added,...delta.modified]),gateIssues=[];
    for(const gate of gates||[]){const e=now.get(gate.edgeId);if(!e){gateIssues.push({id:gate.id,edgeId:gate.edgeId,reason:"deleted_lane"});continue;}
      if(!edited.has(e.id))continue;
      const p=[gate.px,gate.py],points=curves?.get(e.id)?.samples||e.points;
      if(!p.every(Number.isFinite))continue;
      let d=Infinity;for(let i=1;i<points.length;i++)d=Math.min(d,segmentDistance(p,points[i-1],points[i]));
      // Anchor distance is a preliminary warning, never a clearance certificate.
      if(d>.25)gateIssues.push({id:gate.id,edgeId:e.id,reason:"moved_lane",anchor:p,distanceSource:d});
    }
    return {anchorsUnchanged:anchorsUnchanged(edges,baseline),endpoints,gateIssues};
  }
  // Rendering only. Exact endpoints stay fixed; rounding remains inside the lumen.
  function vesselPath(points, radius) {
    const commands=[`M ${points[0].join(" ")}`];
    for(let i=1;i<points.length-1;i++){
      const a=points[i-1],b=points[i],c=points[i+1],la=distance(a,b),lb=distance(b,c);
      if(la<.001||lb<.001)continue;
      const r=Math.min(radius,la/3,lb/3),p=b.map((v,j)=>v+(a[j]-v)*r/la),q=b.map((v,j)=>v+(c[j]-v)*r/lb);
      commands.push(`L ${p.join(" ")} Q ${b.join(" ")} ${q.join(" ")}`);
    }
    commands.push(`L ${points.at(-1).join(" ")}`);return commands.join(" ");
  }
  function curvedNetwork(edges, strength=.8) {
    strength=Math.max(0,Math.min(1,strength));
    const joints=new Map(),unit=v=>{const d=Math.hypot(...v);return d>.000001?v.map(n=>n/d):[0,0];};
    const key=p=>p.map(n=>n.toFixed(5)).join(",");
    for(const e of edges){
      if(e.points.length<2)continue;
      for(const start of [true,false]){const p=start?e.points[0]:e.points.at(-1),near=start?e.points[1]:e.points.at(-2),k=key(p);if(!joints.has(k))joints.set(k,[]);joints.get(k).push({id:e.id,near});}
    }
    function endpoint(e,start){const p=start?e.points[0]:e.points.at(-1),near=start?e.points[1]:e.points.at(-2),own=unit(p.map((v,j)=>start?near[j]-v:v-near[j]));
      let best=null,alignment=-.95;for(const other of joints.get(key(p))||[]){if(other.id===e.id)continue;const continuation=unit(p.map((v,j)=>start?v-other.near[j]:other.near[j]-v)),dot=own[0]*continuation[0]+own[1]*continuation[1];if(dot>alignment){best=continuation;alignment=dot;}}
      return best?unit(own.map((v,j)=>v+best[j])):own;
    }
    function at(seg,t){const u=1-t;return seg[0].map((_,j)=>u*u*u*seg[0][j]+3*u*u*t*seg[1][j]+3*u*t*t*seg[2][j]+t*t*t*seg[3][j]);}
    const result=new Map();
    for(const e of edges){const points=e.points,segments=[],samples=[clone(points[0])],commands=[`M ${points[0].join(" ")}`];
      for(let i=0;i<points.length-1;i++){const a=points[i],b=points[i+1],dir=unit(b.map((v,j)=>v-a[j])),length=distance(a,b);
        const t0=i===0?endpoint(e,true):unit(points[i+1].map((v,j)=>v-points[i-1][j]));
        const t1=i===points.length-2?endpoint(e,false):unit(points[i+2].map((v,j)=>v-points[i][j]));
        // Clamp handles to point forward along each span; no decorative loops.
        const forward=t=>t[0]*dir[0]+t[1]*dir[1]>.08?t:dir;
        const handle=Math.min(18,length*.3)*strength,c0=a.map((v,j)=>v+forward(t0)[j]*handle),c1=b.map((v,j)=>v-forward(t1)[j]*handle),segment=[clone(a),c0,c1,clone(b)];
        segments.push(segment);commands.push(`C ${c0.join(" ")} ${c1.join(" ")} ${b.join(" ")}`);
        const count=Math.max(8,Math.ceil(length/2));for(let step=1;step<=count;step++)samples.push(at(segment,step/count));
      }
      result.set(e.id,{d:commands.join(" "),segments,samples});
    }
    return result;
  }
  return {clone,distance,segmentDistance,simplify,validate,changes,anchorsUnchanged,inspectDraft,vesselPath,curvedNetwork};
});
