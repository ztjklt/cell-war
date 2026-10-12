"""Publish only the matching stomach artwork/union/real-Lua evidence set."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/body-life/vascular-art-study';PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((DOC/'stomach-evidence/report.json').read_text());data=json.loads((DOC/'stomach-pilot.json').read_text());union=json.loads((DOC/'stomach-food-union.json').read_text())
assert report['sourcePilotSha256']==union['sourcePilotSha256']==sha(DOC/'stomach-pilot.json'),'stale pilot evidence'
assert report['sourceNetworkSha256']==data['sourceNetworkSha256']==sha(DOC/'network.json'),'stale vascular network'
for name,digest in report['testedModuleHashes'].items():assert sha(ROOT/'scripts/war'/name)==digest,'stale module '+name
for name in ['stomach.html','stomach.js','stomach-pilot.json','stomach-food-union.json','limb-v14.html','generation-round4.json','stomach-base.svg','stomach-old-vessels.svg','stomach-handover.json']:
    shutil.copy2(DOC/name,PUB/name)
shutil.copytree(DOC/'stomach-evidence',PUB/'stomach-evidence',dirs_exist_ok=True)
for name in ['inspection.html','index.html']:
    p=DOC/name;s=p.read_text()
    link='<p><a href="stomach.html">下一步：胃壁战场试点与新图层实测 →</a></p>'
    if 'href="stomach.html"' not in s:s=s.replace('<footer>',link+'<footer>') if '<footer>' in s else s.replace('</body>',link+'</body>')
    p.write_text(s);shutil.copy2(p,PUB/name)
print('Published matched stomach study and actual Lua evidence; production unchanged')
