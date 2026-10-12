// Verify display curves against frozen authoring points; no gameplay simulation.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),dir=path.join(root,'docs/body-life/vascular-art-study');
const C=require(path.join(dir,'vascular-editor-core.js'));
const network=JSON.parse(fs.readFileSync(path.join(dir,'navigation-review-data.json'),'utf8')).network;
const frozen=JSON.stringify(network.edges),curves=C.curvedNetwork(network.edges,.8);
let spans=0,curvedSpans=0,maxControlDeviation=0;
for(const e of network.edges){
  const curve=curves.get(e.id);
  assert.deepEqual(curve.samples[0],e.points[0]);assert.deepEqual(curve.samples.at(-1),e.points.at(-1));
  assert.equal(curve.segments.length,e.points.length-1);
  for(let i=0;i<curve.segments.length;i++){
    const [a,b,c,d]=curve.segments[i],length=C.distance(a,d),axis=d.map((v,j)=>v-a[j]);
    assert.deepEqual(a,e.points[i]);assert.deepEqual(d,e.points[i+1]);
    assert(C.distance(a,b)<=Math.min(18,length*.3)*.8+1e-8);
    assert(C.distance(d,c)<=Math.min(18,length*.3)*.8+1e-8);
    for(const p of [a,b,c,d])assert(p.every(Number.isFinite));
    if(length>.001){const projection=p=>p.reduce((sum,v,j)=>sum+(v-a[j])*axis[j],0)/(length*length);
      // Ordered projected controls prevent a span from doubling back.
      assert(projection(b)>=-1e-8);assert(projection(c)<=1+1e-8);assert(projection(b)<=projection(c)+1e-8);
    }
    const dev=Math.max(C.segmentDistance(b,a,d),C.segmentDistance(c,a,d));
    if(dev>.01)curvedSpans++;maxControlDeviation=Math.max(maxControlDeviation,dev);spans++;
  }
}
assert.equal(curves.size,202);assert(curvedSpans>250);assert.equal(frozen,JSON.stringify(network.edges));
for(const curve of C.curvedNetwork(network.edges,0).values())for(const [a,b,c,d] of curve.segments){assert.deepEqual(a,b);assert.deepEqual(c,d);}
const edited=C.clone(network.edges);edited[0].points[1][0]+=7;
assert.notEqual(C.curvedNetwork(edited,.8).get(edited[0].id).d,curves.get(edited[0].id).d);
let exportedPaths=null;
if(process.argv[2]){
  const text=fs.readFileSync(process.argv[2],'utf8'),paths=[...text.matchAll(/<path\s+[^>]*>/g)];
  assert.equal(paths.length,202);
  for(const [tag] of paths){const id=tag.match(/data-edge="([^"]+)"/)[1],d=tag.match(/\bd="([^"]+)"/)[1];assert.equal(d,curves.get(id).d);}
  exportedPaths=paths.length;
}
const result={pass:true,edges:202,spans,visiblyCurvedSpans:curvedSpans,maxControlDeviationSource:maxControlDeviation,
  allEndpointsExact:true,allAuthoringNodesExact:true,sourceEdgesUnchanged:true,
  spanControlsForward:true,zeroStrengthReturnsOriginalSegments:true,matchingSVGExportPaths:exportedPaths,
  scope:'Display cubic curves; baseline gameplay collision remains polyline. Curved collision requires retest.'};
fs.writeFileSync(path.join(dir,'vascular-curve-evidence.json'),JSON.stringify(result,null,2)+'\n');
console.log(`PASS: ${curvedSpans}/${spans} curved spans, 202 exact anchored paths; SVG ${exportedPaths??'not supplied'}.`);
