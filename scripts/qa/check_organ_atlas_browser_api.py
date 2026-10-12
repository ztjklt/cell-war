"""Check the local HTTP adapter against current production Lua without UI mocks."""
from pathlib import Path
import hashlib
import json
import math
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/body-life/vascular-art-study/organ-atlas'


def call(action, session=None, **kwargs):
    request = Request('http://127.0.0.1:57918/api/organs',
                      data=json.dumps(dict(action=action, session=session, **kwargs)).encode(),
                      headers={'Content-Type': 'application/json'})
    with urlopen(request, timeout=30) as response:
        value = json.load(response)
    assert 'error' not in value, value
    return value


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads((DOCS / 'art.json').read_text())
    cases = []
    for organ in manifest['organs']:
        initial = call('reset', organs=[organ['organId']])
        token = initial['session']
        unit = initial['units'][0]
        target = organ['rooms'][0]['approachSource']
        moving = call('command', token, kind='move', ids=[unit['id']],
                      x=target[0]*2, y=target[1]*2+512, plane='0')
        assert moving['accepted'], organ['organId']
        for _ in range(12):
            moving = call('tick', token, dt=.5)
        current = next(x for x in moving['units'] if x['id'] == unit['id'])
        distance = math.hypot(current['x']-unit['x'], current['y']-unit['y'])
        assert distance > .01, organ['organId']
        restored = call('save_restore', token)
        # Save deliberately discards the route cache; position, layer and the
        # active command survive, then the real planner reconstructs the path.
        persistent = ['id','kind','x','y','vesselLane','radius','moving']
        assert [{k:u[k] for k in persistent} for u in restored['units']] == [
            {k:u[k] for k in persistent} for u in moving['units']], organ['organId']
        resumed = call('tick', token, dt=.5)
        resumed_unit = next(x for x in resumed['units'] if x['id'] == unit['id'])
        if current['moving']:
            continued = math.hypot(resumed_unit['x']-current['x'], resumed_unit['y']-current['y']) > .001
            arrived = not resumed_unit['moving'] and math.hypot(
                resumed_unit['x']-target[0]*2, resumed_unit['y']-(target[1]*2+512)) <= .05
            assert continued or arrived, organ['organId']
        stopped = call('command', token, kind='stop', ids=[unit['id']])
        # C.execute's legacy return counts newly queued orders. Stop clears
        # orders and returns false; verify its state effect rather than count.
        assert not next(x for x in stopped['units'] if x['id'] == unit['id'])['moving']
        rejected = call('command', token, kind='move', ids=[unit['id']], x=-2, y=-2, plane='0')
        assert rejected['accepted'] is False and rejected['units'] == stopped['units']
        assert initial['native'] is False and initial['networkEdges'] == 202
        cases.append(dict(organId=organ['organId'], status='PASS',
                          displacementWorld=distance, saveRestorePersistentStateUnchanged=True,
                          stopClearsOrders=True,
                          invalidClickPreservesStoppedState=True))
        print('HTTP production adapter:', organ['organId'], flush=True)
    report = dict(schema='organ-atlas-browser-adapter-check/v1', status='PASS',
                  passed=len(cases), total=12, nativeEvidence=False, cases=cases,
                  inputHashes={str(p.relative_to(ROOT)): sha(p) for p in [
                      ROOT / 'scripts/qa/organ_play_server.py',
                      ROOT / 'scripts/war/Commands.lua', ROOT / 'scripts/war/OrganTrial.lua',
                      ROOT / 'scripts/war/Simulation.lua', ROOT / 'scripts/war/Save.lua',
                      ROOT / 'scripts/war/OrganBattlefield.lua',
                      ROOT / 'scripts/war/OrganBattlefieldData.lua',
                      ROOT / 'scripts/war/OrganTraffic.lua', DOCS / 'art.json']})
    (DOCS / 'browser-api-final.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')


if __name__ == '__main__':
    main()
