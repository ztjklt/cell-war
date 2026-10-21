"""Build and verify a source-only Godot handoff from the current workspace."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import stat
from zoneinfo import ZoneInfo
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
SKIP = {'.godot', 'test-output', 'exports', '__pycache__', '.git', '.DS_Store'}

README = '''# 细胞战争 · Godot 源码交接包

生成时间：{timestamp}（Asia/Shanghai）。包含生成时工作区的未提交修改。

## 运行

使用 Godot 4.6+ 标准版导入 `godot/project.godot`，按 F5 运行。
macOS/Linux 也可执行 `bash godot/run.sh`；可通过 GODOT_BIN 指定引擎路径。
游戏使用原生 GDScript，运行资源完整保存在 godot/ 内。

## 内容与来源

- godot/：源码、场景、{asset_count} 个登记素材、测试与文档。
- godot/tests/fixtures/：已冻结的原版绘制基准，测试无需启动 Lua。
- scripts/godot_tools/：独立 Godot 素材、校验与交接工具。
- qa/evidence/：本机已有的紧凑检查报告，属于历史证据。
- handoff-manifest.json、verify_package.py：本次快照的文件与 SHA-256 校验。

Lua 旧版已于 2026-10-20 归档清理。来源清单保留旧 Lua 哈希作为迁移记录；
包中不携带 Lua、原版 QA 或迁移导出器。美术安装工具另需原始素材与图像依赖。
validation.json 记录其生成时的检查，不能代替对本次快照重新运行测试。

## 校验

```sh
python3 verify_package.py
python3 scripts/godot_tools/audit_integrity.py
godot --headless --path godot --editor --import --quit
godot --headless --path godot --script res://tests/run_tests.gd
```

verify_package.py 检查本次包内所有文件与运行素材；Godot 检查当前规则。
更多测试入口及已有验收边界见 godot/README.md 与 godot/PARITY.md。
归档清理不代表已通过全量玩法一致性、移动设备或发行验收。
'''

VERIFY = '''"""Verify an unmodified extracted source handoff using Python stdlib."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
manifest = json.loads((root/'handoff-manifest.json').read_text(encoding='utf-8'))
failures = []
def check(path, expected, size=None):
    file = root/path
    if not file.is_file():
        failures.append('missing: '+path)
    elif (size is not None and file.stat().st_size != size) or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
        failures.append('changed: '+path)
for row in manifest['files']:
    check(row['path'],row['sha256'],row['bytes'])
for row in json.loads((root/'godot/data/asset_manifest.json').read_text(encoding='utf-8')):
    check('godot/'+row['path'],row['sha256'],row['bytes'])
print(json.dumps({'filesChecked':len(manifest['files']),'failures':failures},ensure_ascii=False,indent=2))
raise SystemExit(bool(failures))
'''


def sha(content):
    return hashlib.sha256(content).hexdigest()


def build(output):
    timestamp = datetime.now(ZoneInfo('Asia/Shanghai'))
    name = 'cell-war-godot-gdscript-'+timestamp.strftime('%Y%m%d-%H%M%S')
    output.mkdir(parents=True, exist_ok=True)
    archive = output/(name+'.zip')
    files = {}
    for p in sorted((ROOT/'godot').rglob('*')):
        relative = p.relative_to(ROOT/'godot')
        if p.is_file() and not set(relative.parts) & SKIP:
            if p.is_symlink(): raise ValueError('Unexpected symlink: '+str(relative))
            files['godot/'+relative.as_posix()] = p.read_bytes()
    for p in sorted((ROOT/'scripts/godot_tools').glob('*.py')):
        files[p.relative_to(ROOT).as_posix()] = p.read_bytes()
    files['godot/test-output/.gdignore'] = b''
    for p in sorted((ROOT/'godot/test-output').glob('*.json')):
        files['qa/evidence/'+p.name] = p.read_bytes()
    for row in json.loads(files['godot/data/asset_manifest.json']):
        content = files['godot/'+row['path']]
        if len(content) != row['bytes'] or sha(content) != row['sha256']:
            raise ValueError('Asset mismatch: '+row['path'])
    files['README.md'] = README.format(timestamp=timestamp.isoformat(timespec='seconds'),
        asset_count=len(json.loads(files['godot/data/asset_manifest.json']))).encode()
    files['verify_package.py'] = VERIFY.encode()
    manifest = {'schema':'cell-war-godot-handoff/1','createdAt':timestamp.isoformat(),
                'runtime':'Godot 4.6+ / native GDScript / Compatibility',
                'fullOriginalParityAccepted':False,
                'files':[{'path':p,'bytes':len(v),'sha256':sha(v)} for p,v in sorted(files.items())]}
    files['handoff-manifest.json'] = (json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    with ZipFile(archive,'x',compression=ZIP_DEFLATED,compresslevel=6) as z:
        for path, content in sorted(files.items()):
            z.writestr(name+'/'+path,content)
        # run.sh can also be invoked with bash on systems that ignore ZIP permissions.
        z.getinfo(name+'/godot/run.sh').external_attr = (stat.S_IFREG | 0o755) << 16
    with ZipFile(archive) as z:
        if z.testzip() is not None: raise ValueError('ZIP CRC verification failed')
        for path, content in files.items():
            if sha(z.read(name+'/'+path)) != sha(content): raise ValueError('ZIP readback failed: '+path)
    digest = sha(archive.read_bytes())
    archive.with_suffix('.zip.sha256.txt').write_text(digest+'  '+archive.name+'\n')
    report = {'archive':str(archive),'rootFolder':name,'files':len(files),
              'bytes':archive.stat().st_size,'sha256':digest,
              'crcAndSha256Readback':'PASS','fullOriginalParityAccepted':False}
    archive.with_suffix('.package.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=ROOT/'dist/handoffs')
    build(parser.parse_args().output)
