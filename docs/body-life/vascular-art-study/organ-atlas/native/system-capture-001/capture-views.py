import subprocess,json,time,hashlib,datetime
from pathlib import Path
root=Path('/Users/jitian/Documents/ChatGPT/细胞战争真')
out=root/'docs/body-life/vascular-art-study/organ-atlas/native/system-capture-001'
base=['/opt/homebrew/Cellar/node/25.8.1_1/bin/node','/Users/jitian/.taptap-maker/mcp-runtime/0.0.36/dist/maker.js','preview']
s=json.loads(subprocess.run(base+['status','--target-dir',str(root),'--json'],capture_output=True,text=True,check=True).stdout)
assert s.get('process_alive') is True
# Exact game process, title and owner only; no desktop capture.
pid=s['runtime_pid']; identity=json.loads(subprocess.run(['/tmp/cell-war-window-identity',str(pid)],capture_output=True,text=True,check=True).stdout)
rows=[w for w in identity['windows'] if w['title']=='细胞战争' and w['owner']=='UrhoXRuntime' and w['layer']==0]
assert identity['ownerPid']==pid and identity['screenCaptureAccess'] and len(rows)==1
window=rows[0]
record={'timestamp':datetime.datetime.now().astimezone().isoformat(),'session_id':s['session_id'],'reload_id':s['reload_id'],'ownerPid':pid,'window':window,'captures':[],'errors':[]}
(out/'system-views.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
storage=Path('/Users/jitian/.taptap-maker/preview/c77d76c39450447ca7bafe38d059fd9c2a3ad04a7b223daa29b3b681ffd63caa/storage')
current=None; last=0;deadline=time.monotonic()+150
while time.monotonic()<deadline:
 if current is None:
  matches=list(storage.glob('**/system-capture-001/current.json'))
  if matches:current=max(matches,key=lambda p:p.stat().st_mtime)
 if current is None:time.sleep(.25);continue
 try:phase=json.loads(current.read_bytes().rstrip(b'\x00').decode())
 except (ValueError,OSError):time.sleep(.1);continue
 if phase['index']<=last:time.sleep(.15);continue
 assert phase['worldReady'] and phase['uiReady'] and phase['snapshotUnchanged'] and phase['visibilityUnchanged']
 time.sleep(.15)
 dest=out/f"{phase['index']:02d}-{phase['label']}.png"
 result=subprocess.run(['/usr/sbin/screencapture','-x','-o','-l',str(window['id']),str(dest)],capture_output=True,text=True)
 if result.returncode or not dest.exists():
  record['errors'].append({'phase':phase['label'],'returncode':result.returncode,'stderr':result.stderr});break
 row={'path':dest.name,'phase':phase,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'bytes':dest.stat().st_size,'timestamp':datetime.datetime.now().astimezone().isoformat()}
 record['captures'].append(row);last=phase['index']
 (out/'system-views.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
 (current.parent/'ack.txt').write_text(str(last)+'\n')
 print(f"CAPTURED {last}/{phase['total']} {phase['label']} {dest.stat().st_size} bytes",flush=True)
 if last==phase['total']:
  time.sleep(.5);break
if current:
 for name in ['report.json','current.json']:
  p=current.parent/name
  if p.exists(): (out/('driver-'+name)).write_bytes(p.read_bytes().rstrip(b'\x00')+b'\n')
record['complete']=bool(record['captures']) and last==record['captures'][-1]['phase']['total'] and not record['errors']
(out/'system-views.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print('COMPLETE',record['complete'],'count',len(record['captures']),flush=True)
