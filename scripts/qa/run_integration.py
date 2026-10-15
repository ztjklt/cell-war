"""Validate the shared integration without a native window or cloud writes.

Run from the repository root with Python and lupa (Lua 5.4).
Historical route failures remain documented in TEAM_HANDOVER.md; their original
tests are retained in run_reference.py, rather than silently waived here.
"""
from pathlib import Path
import json
import os
import re
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;'..package.path;"
                "package.loaded['urhox-libs/UI']={};print=function()end")
    return lua


def main():
    report = {}
    suites = ['ResourceAcceptance', 'CombatAcceptance', 'GameplayUpdateAcceptance',
              'BattleHUDAcceptance', 'ReferenceAcceptance',
              'ReferenceRenderAcceptance', 'BodyLifeAcceptance',
              'BodyLifeFlowAcceptance', 'BodyLifeMotionAcceptance',
              'OrganBoundariesAcceptance', 'OrganForegroundAcceptance']
    for name in suites:
        result = runtime().eval("require('war." + name + "').run()")
        rows = list((result['results'] or result).values())
        failures = [{'name': row['name'], 'error': row['error']}
                    for row in rows if not row['pass']]
        report[name] = {'passed': len(rows) - len(failures),
                        'total': len(rows), 'failures': failures}
        print(name, report[name]['passed'], '/', len(rows), flush=True)

    lua = runtime()
    compile_lua = lua.eval('function(text,name) local fn,err=load(text,name);'
                          'return fn~=nil,err end')
    errors = []
    files = list(Path('scripts').rglob('*.lua'))
    for file in files:
        ok, error = compile_lua(file.read_text(), str(file))
        if not ok:
            errors.append({'file': str(file), 'error': error})
    report['syntax'] = {'files': len(files), 'errors': errors}

    missing = []
    for file in Path('scripts/war').glob('*.lua'):
        text = file.read_text()
        for module in re.findall(r"require\s*\(?\s*['\"](war\.[\w.]+)['\"]", text):
            if not (Path('scripts') / (module.replace('.', '/') + '.lua')).is_file():
                missing.append({'file': str(file), 'module': module})
        for asset in re.findall(r"['\"](image/[^'\"\n]+\.(?:png|jpg|webp))['\"]", text):
            if '%' not in asset and not (Path('assets') / asset).is_file():
                missing.append({'file': str(file), 'asset': asset})
    report['staticResources'] = {'missing': missing}

    lua.execute("""
        local S=require('war.Simulation');local F=require('war.FullBodyBattlefield')
        local Status=require('war.CombatStatus');local Save=require('war.Save')
        local s=F.new(73);local e
        for _,u in pairs(s.entities)do
            if u.faction==1 and u.kind=='scout'then e=u;break end
        end
        assert(e,'starter cell missing')
        Status.apply(s,e,'slow',{duration=.2})
        S.step(s,.1);assert(e.statuses.slow)
        S.step(s,.2);assert(not e.statuses.slow,'fullbody status expiry')
        local q=Save.restore(Save.snapshot(s))
        assert(q.fullbodyBattlefieldVersion==1 and q.heartBattlefieldVersion==1)
        assert(q.anatomyVersion==4)
        assert(#require('war.OrganBattlefield').net(q).edges==
               #require('war.OrganBattlefield').net(s).edges)
        local old=S.new(73,'campaign',3)
        assert(Save.restore(Save.snapshot(old)).anatomyVersion==3)
        local latest=S.new(73)
        local lung,why=S.changeMap(latest,'lungs_01');assert(lung,why)
        assert(lung.anatomyVersion==4 and lung.campaign.terrainVersion==4)
        local saved=Save.restore(Save.snapshot(lung))
        assert(saved.campaign.map_id=='lungs_01' and saved.anatomyVersion==4)
    """)
    report['IntegrationSmoke'] = {'passed': 6, 'total': 6,
        'checks': ['fullbody starters', 'fullbody status expiry',
                   'fullbody/heart save', 'vascular graph retained',
                   'v3 campaign save', 'v4 lung transition/save']}
    report['nativePreviewVerified'] = False
    Path('docs/integration-regression-results.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    assert not errors and not missing, 'Syntax or dependency failures'
    assert all(report[name]['passed'] == report[name]['total'] for name in suites)
    print('PASS', sum(report[name]['passed'] for name in suites) + 6,
          'checks;', len(files), 'Lua files', flush=True)


if __name__ == '__main__':
    main()
