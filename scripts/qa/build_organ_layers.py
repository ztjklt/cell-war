"""Explicit candidate collision ownership from existing organ-local graph edges.
No coordinate or canonical network changes; not a claim of anatomical depth.
"""
from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
n=json.loads((D/'network.json').read_text());p=json.loads((D/'passages-data.json').read_text())
alias={'brain':['brain_r','brain_l'],'large_intestine':['colon_proximal','colon_distal'],'heart':['coronary']}
contract=json.loads((D/'interface-contract.json').read_text())
zones=[]
for z in p['zones']:
 prefixes=alias.get(z['id'],[z['id']])
 belongs=lambda node:any(node.startswith(a+'.') for a in prefixes)
 owned=[e['id'] for e in n['edges'] if belongs(e['a']) and belongs(e['b'])]
 for region in contract['regions']:
  if region['id'] in prefixes:
   owned.extend(port['edge'] for port in region['ports'] if port.get('exitToTissue') and port['edge'] not in owned)
 assert owned,z['id']
 zones.append({'id':z['id'],'nodeNamespaces':prefixes,'tissueWallEdges':owned,'extraStudyEdges':['study.stomach.wall_service'] if z['id']=='stomach' else [],'rule':'Only explicitly organ-owned vessels bound this tissue plane; every blood lane retains the complete original graph. Foreign projected vessels cannot become tissue entrances.'})
r={'status':'candidate_gameplay_depth_contract','productionInstalled':False,'nativeConfirmed':False,'basis':'Existing graph node namespaces; original coordinates, original gates and original organ targets unchanged. Requires gameplay and visual review; not inferred physical anatomy.','zones':zones,'sourceHashes':{f:sha(D/f) for f in ['network.json','passages-data.json','interface-contract.json']},'scriptSha256':sha(Path(__file__))}
(D/'organ-layers.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print('12 explicit candidate tissue planes; no canonical edits')
