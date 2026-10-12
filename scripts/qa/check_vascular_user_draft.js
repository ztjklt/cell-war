// Preserve and review an editor export without changing the simulation or the user's geometry.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),dir=path.join(root,'docs/body-life/vascular-art-study');
const C=require(path.join(dir,'vascular-editor-core.js'));
const baseline=JSON.parse(fs.readFileSync(path.join(dir,'navigation-review-data.json'),'utf8')).network;
const central=JSON.parse(fs.readFileSync(path.join(dir,'central-vessel-connections.json'),'utf8'));
const passages=JSON.parse(fs.readFileSync(path.join(dir,'passages-data.json'),'utf8'));
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
let fingerprint=2166136261;for(const ch of JSON.stringify(baseline.edges))fingerprint=Math.imul(fingerprint^ch.charCodeAt(0),16777619);
const baselineId=`navigation-${(fingerprint>>>0).toString(16)}`;
const saved=path.join(dir,'user-drafts/stomach-20261010-original.json');
const input=process.argv[2]||saved,bytes=fs.readFileSync(input),doc=C.validate(JSON.parse(bytes),baselineId);
const delta=C.changes(doc.edges,baseline.edges),curves=C.curvedNetwork(doc.edges,doc.rendering?.curvedPreview===false?0:doc.rendering?.curveStrength??.8);
const audit=C.inspectDraft(doc.edges,baseline.edges,baseline.gates,curves);
const original=baseline.edges.find(e=>e.id==='study.stomach.wall_service'),edited=doc.edges.find(e=>e.id===original.id);
// This review describes the supplied single stomach edit, not arbitrary imported geometry.
assert.deepEqual(delta,{added:[],deleted:[],modified:[original.id]});
assert.equal(doc.edges.length,202);
for(const id of central.preservedEdges)assert.deepEqual(doc.edges.find(e=>e.id===id),baseline.edges.find(e=>e.id===id));
assert.deepEqual(doc.logicalGates,baseline.gates);
assert.equal(C.inspectDraft(baseline.edges,baseline.edges,baseline.gates).endpoints.length,0);
assert.equal(C.anchorsUnchanged(baseline.edges,baseline.edges),true);
assert.equal(audit.anchorsUnchanged,false);
assert.equal(audit.endpoints.length,1);
assert.deepEqual(audit.endpoints[0].matches,['stomach.a']);
const serialized=JSON.stringify(doc.edges);
assert.equal(curves.get(edited.id).samples[0][0],edited.points[0][0]);
assert.deepEqual(curves.get(edited.id).samples.at(-1),edited.points.at(-1));
assert.equal(JSON.stringify(doc.edges),serialized);

function inside(p,poly){let yes=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){
  const a=poly[i],b=poly[j];if((a[1]>p[1])!==(b[1]>p[1])&&p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])yes=!yes;
}return yes;}
function dense(curve){const points=[];for(const s of curve.segments){
  const length=C.distance(s[0],s[1])+C.distance(s[1],s[2])+C.distance(s[2],s[3]),n=Math.max(8,Math.ceil(length/.15));
  for(let i=0;i<n;i++){const t=i/n,u=1-t;points.push(s[0].map((_,j)=>u*u*u*s[0][j]+3*u*u*t*s[1][j]+3*u*t*t*s[2][j]+t*t*t*s[3][j]));}
}points.push(curve.samples.at(-1));return points;}
const samples=dense(curves.get(edited.id)),food=passages.foodUnion,stomach=passages.zones.find(z=>z.id==='stomach');
const overlap=[];let active=null;
for(let i=0;i<samples.length;i++){
  if(food.some(poly=>inside(samples[i],poly))){if(!active){active={startIndex:i,points:[]};overlap.push(active);}active.points.push(samples[i]);active.endIndex=i;}
  else active=null;
}
const outside=samples.filter(p=>!stomach.outlines.some(o=>inside(p,o.points))).length;
assert.equal(outside,0);assert.equal(overlap.length,2);
const nodes=new Map();for(const e of baseline.edges){nodes.set(e.a,e.points[0]);nodes.set(e.b,e.points.at(-1));}
function reach(from,to,systems){const todo=[from],seen=new Set(todo);for(let i=0;i<todo.length;i++){
  if(todo[i]===to)return true;for(const e of doc.edges){if(e.a!==todo[i]||!systems.includes(e.system)||!nodes.has(e.a)||!nodes.has(e.b))continue;
    if(C.distance(e.points[0],nodes.get(e.a))>.001||C.distance(e.points.at(-1),nodes.get(e.b))>.001)continue;
    if(!seen.has(e.b)){seen.add(e.b);todo.push(e.b);}}
}return false;}
const mainLoops=central.organs.map(o=>({id:o.id,
  supply:reach(o.supplyRoot,o.entry,['artery']),exchange:reach(o.entry,o.exit,['artery','vein','capillary']),
  back:reach(o.exit,o.returnRoot,['vein','capillary'])}));
assert(mainLoops.every(o=>o.supply&&o.exchange&&o.back));
fs.mkdirSync(path.dirname(saved),{recursive:true});
if(fs.existsSync(saved))assert.equal(hash(fs.readFileSync(saved)),hash(bytes),'Existing user snapshot differs; never overwrite it.');
else fs.writeFileSync(saved,bytes);
assert.equal(hash(fs.readFileSync(saved)),hash(bytes));
const report={status:'USER_DRAFT_RETAINED_REQUIRES_CONNECTION_AND_GATE_RECHECK',
  originalFile:path.basename(input),savedDraft:path.relative(dir,saved),originalSha256:hash(bytes),baselineId,
  baselineSha256:hash(fs.readFileSync(path.join(dir,'navigation-review-data.json'))),
  passagesSha256:hash(fs.readFileSync(path.join(dir,'passages-data.json'))),
  changes:delta,sourceGeometryPreservedExactly:true,headAndLimbEdgesUnchanged:116,
  before:original,after:edited,endpointAudit:audit.endpoints,gateAudit:audit.gateIssues,mainLoops,
  foodProjection:{intervals:overlap.map(o=>({start:o.points[0],end:o.points.at(-1)})),
    curveSamplingMaxStepSource:.15,classification:'different-depth projected overlap, not a food-to-blood connection',
    bloodLayer:edited.layer,foodLayer:passages.edges.find(e=>e.id==='food.stomach').layer,
    required:'Retain independent blood and food layers and recalculate visible occlusion segments.'},
  outline:{outsideSampleCount:outside},flowDirectionConfirmed:false,navigationOnEditedDraftTested:false,
  productionInstalled:false,
  nextRequirements:['Resolve the new endpoint node and choose supply-to-return flow for the added loop.',
    'Reassign both stomach wall-service gates and normals against this new curve.',
    'Rebuild food occlusion and run actual cell movement, gate clearance and passing tests.'],
  staleExportMetadata:{sourceAnchorsUnchanged:doc.rendering?.sourceAnchorsUnchanged,actualSourceAnchorsUnchanged:false},
  scope:'Single user-authored stomach branch; passing baseline main loops does not certify the new branch.'};
fs.writeFileSync(path.join(dir,'stomach-user-edit-review.json'),JSON.stringify(report,null,2)+'\n');
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const polyPath=polys=>polys.map(p=>'M '+p.map(v=>v.join(' ')).join(' L ')+' Z').join(' ');
const pointsPath=points=>'M '+points.map(p=>p.join(' ')).join(' L ');
const baseCurves=C.curvedNetwork(baseline.edges,.8);
function svg(after){const edge=after?edited:original,curve=after?curves.get(edge.id):baseCurves.get(edge.id);
  const vessels=baseline.edges.filter(e=>e.id!==edge.id&&e.points.some(p=>p[0]>485&&p[0]<625&&p[1]>475&&p[1]<573));
  return `<svg viewBox="480 466 145 110" role="img" aria-label="${after?'用户修改':'原短支线'}与胃部固定坐标"><image href="coverage-reference.png" width="1024" height="1536" opacity=".3"/><path d="${polyPath(stomach.outlines.map(o=>o.points))}" fill="none" stroke="#8d8371" stroke-width=".5"/>${vessels.map(e=>`<path d="${baseCurves.get(e.id).d}" fill="none" stroke="${e.system==='capillary'?'#a77d61':e.kind==='vein'?'#517e96':'#b26357'}" stroke-width="${e.lumenWidthSource}" opacity=".5"/>`).join('')}<path d="${polyPath(food)}" fill="#ddc99b" stroke="#aa9270" stroke-width=".4" opacity=".6"/><path d="${curve.d}" fill="none" stroke="#796051" stroke-width="2.6" stroke-linejoin="round"/><path d="${curve.d}" fill="none" stroke="#d4a47c" stroke-width="1.5"/>${after?overlap.map(o=>`<path d="${pointsPath(o.points)}" fill="none" stroke="#7d649e" stroke-width="2.3" stroke-dasharray="1.2 1.1"/>`).join(''):''}${baseline.gates.filter(g=>g.edgeId===edge.id).map((g,i)=>`<circle cx="${g.px}" cy="${g.py}" r="1.6" fill="#e6eddd" stroke="#58785e" stroke-width=".5"/><text x="${g.px+2}" y="${g.py-2}" font-size="3.4" fill="#334634">旧出口 ${i+1}</text>`).join('')}${edge.points.map((p,i)=>`<circle cx="${p[0]}" cy="${p[1]}" r=".8" fill="#493f38"/>`).join('')}<text x="563" y="499" font-size="3.3" fill="#69463f">供血侧节点 A</text><text x="550" y="532" font-size="3.3" fill="#385769">回流侧节点 V</text></svg>`;
}
const rows=audit.gateIssues.map(g=>`<tr><td>${esc(g.id)}</td><td>${g.distanceSource.toFixed(2)} 原图像素</td><td>需重设锚点、法线并实测</td></tr>`).join('');
const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>胃部手动修改复核</title><style>*{box-sizing:border-box}body{margin:0;background:#1d302e;color:#e3e8dd;font:15px/1.7 system-ui}main{max-width:1080px;margin:24px auto;padding:0 18px}h1{font-size:25px}h2{font-size:19px}a{color:#bbd6bd}.views{display:grid;grid-template-columns:1fr 1fr;gap:16px}figure{margin:0;background:#2a403a;padding:14px;border-radius:8px}svg{width:100%;display:block;background:#e6e8df;border-radius:5px}figcaption{margin-top:10px}.notice{border-left:3px solid #c6ac79;padding:10px 14px;background:#2c4036}table{width:100%;border-collapse:collapse;font-size:13px}td,th{padding:8px;text-align:left;border-bottom:1px solid #5b6d60;overflow-wrap:anywhere}.foot{font-size:13px;color:#b9c9b9}@media(max-width:700px){.views{grid-template-columns:1fr}main{margin-top:16px}}</style><main><a href="organ-routes.html">返回可编辑的全身草稿</a><h1>你的胃部修改已原样保存</h1><p>只修改了胃壁服务支线，202 条线中的其余 201 条保持原样。头部、四肢、胃轮廓与主供血、门静脉回流接口均未移动。以下是固定坐标对照。</p><div class="views"><figure>${svg(false)}<figcaption>原短支线：从回流侧节点 V 延伸到外壁死端。</figcaption></figure><figure>${svg(true)}<figcaption>你的新线：沿下缘、外侧绕回供血侧节点 A。浅褐色为食物区域；紫色虚线是两段屏幕投影重合；绿圈仍是旧出口。</figcaption></figure></div><p class="notice">形状已保留，尚未认证为可通行新地图。现有 13 组器官主循环继续连通，这不代表这条修改支线与旧出口已经通过。</p><h2>需要衔接的三件事</h2><p>末端现在是 (${edited.points.at(-1).join(', ')})，正好落在胃供血侧节点 <code>stomach.a</code>，但草稿连接标记仍是旧外壁死端。后续应明确它是胃壁交换环，并确定从供血侧通往回流侧的流向；本次没有替你改变画线顺序或形状。</p><table><thead><tr><th>原出口</th><th>距新弧线中心</th><th>结论</th></tr></thead><tbody>${rows}</tbody></table><p>两处食物投影重合需要重新算遮挡。原支线定义为深层血管（layer 35），食物在前层（layer 60），因此它们可以在画面投影交叉，但不能成为相通的通道。正式美术应遮住前层食物下的血管；细胞是否能进出则必须使用重新配置的膜口进行测试。</p><p><a href="${esc(report.savedDraft)}" download>下载原样保存的 JSON</a> · <a href="stomach-user-edit-review.json">查看复核记录与坐标</a></p><p class="foot">所有新弧线采样仍在胃轮廓内。本轮没有替换生产血管、旧存档或原通行回放；后续生图使用这份坐标草稿，先完成连接与出口配置。复现：node scripts/qa/check_vascular_user_draft.js</p></main></html>`;
fs.writeFileSync(path.join(dir,'stomach-user-edit-review.html'),html+'\n');
console.log(`Saved exact user draft; 1 endpoint mismatch, ${audit.gateIssues.length} displaced gate anchors, ${overlap.length} food projection overlaps. Original 13 main loops retained.`);
for(const g of audit.gateIssues)console.log(`${g.id}: ${g.distanceSource.toFixed(3)} source px from new curve`);
