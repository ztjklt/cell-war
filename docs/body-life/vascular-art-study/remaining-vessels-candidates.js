'use strict';
const $=s=>document.querySelector(s), NS='http://www.w3.org/2000/svg';
let records,reference,audit,region='lower-abdomen',paint='generated';
const path=points=>'M '+points.map(p=>p.join(' ')).join(' L ');
function addPath(parent,attrs){const node=document.createElementNS(NS,'path');for(const[k,v]of Object.entries(attrs))node.setAttribute(k,v);parent.appendChild(node);}
function show(){
 if(!records||!reference)return;
 const record=records.regions.find(r=>r.region===region),[x,y,x1,y1]=record.sourceBox;
 $('#artScene').setAttribute('viewBox',`${x} ${y} ${x1-x} ${y1-y}`);
 const image=$('#artImage');for(const[k,v]of Object.entries({x,y,width:x1-x,height:y1-y,href:paint==='generated'?record.previewAsset:record.originalPreview}))image.setAttribute(k,v);
 $('#artScene').setAttribute('aria-label',region==='chest'?'胸部血管生图':'下腹血管生图');
 $('#artScene').dataset.region=region;$('#artScene').dataset.paint=paint;
 $('#download').href=record.previewAsset;
 $('#caption').textContent=(region==='chest'?'胸部：心脏、肺部供回路及胸腔主干。':'下腹：肠道供回路、膀胱壁血管与骨盆接续。')+'原图坐标 '+record.sourceBox.join('，')+'。';
 $('#wallNote').hidden=region!=='lower-abdomen';
 for(const[id,value]of [['chest','chest'],['lower','lower-abdomen']])$('#'+id).setAttribute('aria-pressed',String(region===value));
 for(const[id,value]of [['generated','generated'],['original','original']])$('#'+id).setAttribute('aria-pressed',String(paint===value));
 const lines=$('#referenceLines');lines.replaceChildren();
 for(const e of reference.edges.filter(e=>record.editableEdgeIds.includes(e.id))){for(const p of e.visibleSegments)addPath(lines,{d:path(p),fill:'none',stroke:'#344d45','stroke-width':.48,'stroke-dasharray':'1.7 1.4',opacity:.85,'data-edge':e.id});}
 lines.style.display=$('#guide').checked?'':'none';
 const organs=$('#organLines');organs.replaceChildren();
 for(const o of reference.organs){if(o.bounds[0]>=x1||o.bounds[2]<=x||o.bounds[1]>=y1||o.bounds[3]<=y)continue;for(const p of o.outlines)addPath(organs,{d:path(p.points)+' Z',fill:'none',stroke:'#5b6663','stroke-width':.42,'stroke-dasharray':'2 1.8',opacity:.8});}
 organs.style.display=$('#organs').checked?'':'none';
 $('#review').textContent=audit?.pageSummary||'局部绘画已生成，正在核对固定接口与遮挡；不计作已安装的最终血管。';
}
$('#chest').onclick=()=>{region='chest';show();};$('#lower').onclick=()=>{region='lower-abdomen';show();};
$('#generated').onclick=()=>{paint='generated';show();};$('#original').onclick=()=>{paint='original';show();};
$('#guide').onchange=show;$('#organs').onchange=show;
(async()=>{
 [records,reference]=await Promise.all(['remaining-vessels-generation.json','final-reference-data.json'].map(async url=>{const r=await fetch(url);if(!r.ok)throw Error(url+' 加载失败');return r.json();}));
 const r=await fetch('remaining-vessels-art-audit-current.json');if(r.ok)audit=await r.json();show();
})().catch(e=>{$('#error').textContent=e.message;console.error(e);});
