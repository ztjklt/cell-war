"""Split only the SVG vessel groups taken over by the stomach study. Raster inputs are unchanged."""
from pathlib import Path
import copy,hashlib,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/body-life/vascular-art-study'
ET.register_namespace('','http://www.w3.org/2000/svg')
source=DOC/'candidate-v10.svg';root=ET.fromstring(source.read_bytes());base=copy.deepcopy(root);ids={e['edgeId'] for e in json.loads((DOC/'stomach-pilot.json').read_text())['vessels']};removed=[]
for parent in base.iter():
 for e in list(parent):
  if e.get('data-edge') in ids:removed.append(e.get('data-edge'));parent.remove(e)
assert sorted(removed)==['e123','e164'],'v10 takeover set changed; review required'
def retain(e):
 tag=e.tag.split('}')[-1]
 if tag=='defs' or e.get('data-edge') in ids:return copy.deepcopy(e)
 if tag not in ['svg','g']:return None
 result=ET.Element(e.tag,e.attrib)
 for child in e:
  kept=retain(child)
  if kept is not None:result.append(kept)
 return result if len(result) else None
old=retain(root)
for name,tree in [('stomach-base.svg',base),('stomach-old-vessels.svg',old)]:
 (DOC/name).write_bytes(ET.tostring(tree,encoding='utf-8',xml_declaration=True))
(DOC/'stomach-handover.json').write_text(json.dumps(dict(sourceSha256=hashlib.sha256(source.read_bytes()).hexdigest(),removedSvgEdges=removed,rasterEdited=False,oldRouteAlpha='1-smoothstep(.085,.15,zoom)',newLayerAlpha='per drawing primitive; same rule as Lua',backgroundScope='Browser uses the v10 authoring artwork; Lua evidence uses existing ReferenceArt. These backgrounds are separately evaluated, not pixel-identical.'),ensure_ascii=False,indent=2)+'\n')
print('Split 2 legacy vector groups; no legacy takeover group remains in base')
