"""Apply the user-requested influenza fortress gameplay/art registration."""
from pathlib import Path
import hashlib,json,shutil

ROOT=Path(__file__).resolve().parents[2]
GAME=ROOT/'godot'
ART=ROOT/'assets/image/influenza-fortress-20261020'

def write(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

def main():
    data=json.loads((ART/'fortress.json').read_text())
    config_path=GAME/'data/config.json'
    config=json.loads(config_path.read_text())
    config['Data']['buildings']['flu_fortress']={'name':'流感要塞','hp':data['rules']['hp'],
        'size':data['rules']['size'],'time':data['rules']['buildSeconds'],'vision':10,
        'desc':'10 个流感病毒共同施工；建成每 30 秒孵化 1 个流感病毒；施工者保留并继续作战。'}
    write(config_path,config)
    path=GAME/'data/asset_manifest.json'
    rows=json.loads(path.read_text());rows={row['path']:row for row in rows}
    texture=Path(data['texture']).name
    for name,dest in [(texture,'assets/'+data['texture']),('fortress.json','data/influenza_fortress.json')]:
        source=ART/name;target=GAME/dest;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
        rows[dest]={'source':source.relative_to(ROOT).as_posix(),'path':dest,'bytes':target.stat().st_size,
                    'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    rows=list(rows.values());write(path,rows)
    path=GAME/'data/source_manifest.json';baseline=json.loads(path.read_text())
    baseline['assets']=len(rows);baseline['assetBytes']=sum(row['bytes'] for row in rows)
    write(path,baseline)
    print('Registered 流感要塞: 10 builders retained, 30-second reproduction')

if __name__=='__main__':main()
