"""Mock engine events/Files to test the actual native QA driver's handshake.

No preview, screenshots, real navigation, images, or native APIs are used. The
actual driver and four actual configs are loaded. Motion/resource/engine mocks
exercise terminal state transitions only; they never certify gameplay movement.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import sys

for dependency in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0, dependency)
from lupa.lua54 import LuaRuntime, lua_type

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/qa/fourth-repair/native-terminal-protocol-005-test.json'
HELPER = ROOT / '.tmp/fullbody-015/capture-movement-005.py'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def to_python(value):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if not keys or sorted(keys, key=str) == sorted(range(1, len(keys) + 1), key=str):
        return [to_python(value[i]) for i in range(1, len(keys) + 1)]
    return {k: to_python(value[k]) for k in keys}


def to_lua(lua, value):
    if isinstance(value, dict):
        return lua.table_from({k: to_lua(lua, v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([to_lua(lua, v) for v in value])
    return value


MODEL = r'''
package.path='scripts/?.lua;'..package.path
cjson={encode=encodeJson,decode=decodeJson};FILE_WRITE=1;FILE_READ=0
virtualFiles={};virtualPNGs={};callbacks={};factoryCount=0;nextId=0
outputDir='qa/organ-atlas-native/fullbody-movement-005'
fileSystem={DirExists=function()return true end,CreateDir=function()return true end,
 FileExists=function(_,path)return virtualFiles[path]~=nil or virtualPNGs[path]==true end}
function File(path,mode)
 return{IsOpen=function()return true end,WriteString=function(_,text)virtualFiles[path]=text end,
 ReadLine=function()return virtualFiles[path]end,Close=function()end}
end
graphics={GetDPR=function()return 2 end,GetWidth=function()return 2498 end,GetHeight=function()return 1468 end,Raise=function()end}
function ScriptObject()return{}end
local receiver={SubscribeToEvent=function(_,event,cb)callbacks[event]=cb end,
 UnsubscribeFromAllEvents=function()callbacks={}end}
function Node()return{CreateScriptObject=function()return receiver end}end
local configs=require('qa.FullBodyMapNativeMovementData')
local F={new=function()
 factoryCount=factoryCount+1;return{entities={},commands={},time=0,tick=0,caseIndex=factoryCount,spawnCount=0}
end}
local C={spawn=function(s,category,kind,faction,x,y)
 s.spawnCount=s.spawnCount+1;local config=configs[s.caseIndex].actors[s.spawnCount];nextId=nextId+1
 local e={id=nextId,kind=kind,faction=faction,x=x,y=y,hp=10,orders={},
 vesselLane=config.setupSource and 0 or config.lane,mockTargetOrgan=config.targetOrgan}
 s.entities[e.id]=e;return e
end,execute=function(s,command)
 local e=s.entities[command.ids[1]];e.orders={{x=command.x,y=command.y,lane=command.lane}};return true
end}
local M={record=function()end,reset=function()end};originalRecord=M.record
local function move(s,dt)
 s.time=s.time+dt;s.tick=s.tick+1
 for _,e in pairs(s.entities)do local goal=e.orders[1]
  if goal then
   local dx,dy=goal.x-e.x,goal.y-e.y;local distance=math.sqrt(dx*dx+dy*dy)
   local amount=dt==.1 and distance or math.min(distance,.25)
   if distance>0 then e.x=e.x+dx*amount/distance;e.y=e.y+dy*amount/distance end
   if amount>=distance then e.x,e.y,e.vesselLane=goal.x,goal.y,goal.lane;e.orders={}end
  end
  M.record(e)
 end
end
package.loaded['war.FullBodyBattlefield']=F
package.loaded['war.Commands']=C
package.loaded['war.World']={rebuild=function()end}
package.loaded['war.Simulation']={step=move}
package.loaded['war.Data']={STEP=.1}
package.loaded['war.Motion']=M
package.loaded['war.FullBodyMapArt']={ready=function()return true end,stats=function()return{contexts=2,images=84}end}
package.loaded['war.FullBodyMapArtData']={manifestSha256=string.rep('a',64)}
package.loaded['urhox-libs/UI']={GetNVGContext=function()return{}end}
package.loaded['war.OrganBattlefield']={organAt=function(_,e)return e.mockTargetOrgan end,pointAllowed=function()return true end}
g={realTime=0,state={},paused=true,selection={}}
g.replaceState=function(s)g.state=s end
R={vg={}};H={closeModal=function()end,sidebar=function()end}
result=require('qa.FullBodyMapNativeMovement').start(g,R,H,{outputDir=outputDir})
function updateOnly()
 g.realTime=g.realTime+1/60
 if not g.paused then move(g.state,1/60)end
 if callbacks.Update then callbacks.Update()end
end
function renderOnly()if callbacks.NanoVGRender then callbacks.NanoVGRender()end end
function stepFrame()updateOnly();renderOnly()end
function phaseText()return virtualFiles[outputDir..'/current.json']end
function reportText()return virtualFiles[outputDir..'/report.json']end
function ackText(text)virtualFiles[outputDir..'/terminal-ack.json']=text end
function armText(text)virtualFiles[outputDir..'/capture-ready.json']=text end
function stateText()return encodeJson(g.state)end
function recordRestored()return M.record==originalRecord end
'''


def model():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().encodeJson = lambda v: json.dumps(to_python(v), ensure_ascii=False, allow_nan=False, separators=(',', ':'))
    lua.globals().decodeJson = lambda text: to_lua(lua, json.loads(text))
    lua.execute(MODEL)
    return lua


def phase(lua):
    return json.loads(lua.eval('phaseText()'))


def arm(lua, current):
    lua.eval('armText')(json.dumps({'schema': 'fullbody-native-capture-ready/v1', 'stateRunId': current['stateRunId'], 'index': current['index'], 'manifestSha256': 'a' * 64, 'nonce': 'b' * 32, 'ownerPid': 123}))


def terminal(lua):
    for _ in range(2500):
        lua.eval('stepFrame()')
        current = phase(lua)
        if current.get('stage') == 'ready' and current.get('stateRunId'):
            arm(lua, current)
        if current.get('terminal'):
            return current
        assert current.get('stage') != 'finished', json.loads(lua.eval('reportText()'))
    raise AssertionError('mock case failed to enter terminal stage')


def main():
    os.chdir(ROOT)
    paths = [Path(__file__).resolve(), HELPER, ROOT / 'scripts/qa/FullBodyMapNativeMovement.lua',
             ROOT / 'scripts/qa/FullBodyMapNativeMovementData.lua']
    bindings = {str(p.relative_to(ROOT)): sha(p) for p in paths}
    spec = importlib.util.spec_from_file_location('capture_movement_005', HELPER)
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    checks = []
    def check(name, passed, **facts):
        checks.append({'name': name, 'pass': bool(passed), **facts})
    render_gate = model()
    for _ in range(140): render_gate.eval('updateOnly()')
    current = phase(render_gate); arm(render_gate, current)
    render_gate.eval('updateOnly()')
    check('collector arm without completed render cannot start setup', phase(render_gate).get('stage') == 'ready')
    render_gate.eval('renderOnly()'); render_gate.eval('updateOnly()')
    check('collector arm and only one ready render cannot start setup', phase(render_gate).get('stage') == 'ready')
    render_gate.eval('renderOnly()'); render_gate.eval('updateOnly()')
    check('collector arm and two ready renders allow paused setup', phase(render_gate).get('stage') == 'setup' and render_gate.eval('g.paused'))
    waiting = model()
    for _ in range(140): waiting.eval('stepFrame()')
    ready = phase(waiting)
    check('driver stays paused in ready without collector arm', ready.get('stage') == 'ready' and waiting.eval('g.paused') and waiting.eval('g.state.time') == 0)
    valid_arm = {'schema': 'fullbody-native-capture-ready/v1', 'stateRunId': ready['stateRunId'], 'index': ready['index'], 'manifestSha256': 'a' * 64, 'nonce': 'b' * 32, 'ownerPid': 123}
    for key, value in [('schema', 'other'), ('stateRunId', 'oldrun'), ('index', 2), ('manifestSha256', 'b' * 64), ('nonce', ''), ('nonce', 'z' * 32), ('ownerPid', 0)]:
        waiting.eval('armText')(json.dumps({**valid_arm, key: value})); waiting.eval('stepFrame()')
        check('wrong pre-record arm cannot start: ' + key, phase(waiting).get('stage') == 'ready' and waiting.eval('g.paused'))
    waiting.eval('armText')(json.dumps(valid_arm)); waiting.eval('stepFrame()')
    check('exact collector run/index/manifest arms setup before movement', phase(waiting).get('stage') == 'setup' and waiting.eval('g.paused'))
    lua = model()
    for index in range(1, 5):
        current = terminal(lua); factory = lua.globals().factoryCount
        check(f'case{index}: first arrival waits for terminal renders', current['index'] == index and current['terminalReady'] is False and lua.eval('g.paused'))
        state = lua.eval('stateText()')
        lua.eval('updateOnly()'); current = phase(lua)
        check(f'case{index}: one completed render is insufficient', current['terminalRenderedFrames'] == 1 and not current['terminalReady'])
        lua.eval('renderOnly()'); lua.eval('updateOnly()'); current = phase(lua)
        check(f'case{index}: second completed render becomes terminal-ready', current['terminalRenderedFrames'] >= 2 and current['terminalReady'])
        case = helper.case_for(json.loads(lua.eval('reportText()')), current)
        check(f'case{index}: actual final QA positions validate all helper goals', not helper.terminal_errors(case, current)[0])
        path = '/mock/original-capture-case-' + str(index) + '-terminal.png'
        runtime_path = 'qa/organ-atlas-native/fullbody-movement-005/terminal-case-' + str(index) + '.png'
        lua.globals().virtualPNGs[runtime_path] = True
        check(f'case{index}: engine mock does not recognize original absolute workspace path', not lua.eval('function(path)return fileSystem:FileExists(path)end')(path))
        ack = {'stateRunId': current['stateRunId'], 'index': index, 'terminal': True,
               'pngSha256': 'a' * 64, 'pngPath': path, 'pngRuntimePath': runtime_path,
               'captureNonce': 'b' * 32, 'ownerPid': 123, 'runtimeMirrorSha256': 'a' * 64}
        for key, value in [('stateRunId', 'stale-other-case'), ('index', index + 1), ('terminal', False),
                           ('pngSha256', 'a' * 63), ('pngPath', 12), ('pngRuntimePath', path),
                           ('pngRuntimePath', 'qa/organ-atlas-native/fullbody-movement-004/terminal-case-' + str(index) + '.png'),
                           ('pngRuntimePath', 'qa/organ-atlas-native/fullbody-movement-005/terminal-case-0' + str(index) + '.png'),
                           ('captureNonce', 'c' * 32), ('ownerPid', 124), ('runtimeMirrorSha256', 'd' * 64)]:
            bad = {**ack, key: value}; lua.eval('ackText')(json.dumps(bad))
            lua.eval('stepFrame()')
            check(f'case{index}: wrong ACK {key} cannot advance', lua.globals().factoryCount == factory and phase(lua)['stateRunId'] == current['stateRunId'])
        lua.globals().virtualPNGs[runtime_path] = None
        lua.eval('ackText')(json.dumps(ack)); lua.eval('stepFrame()')
        check(f'case{index}: absent virtual mirror cannot advance even with matching runtime path', lua.globals().factoryCount == factory and phase(lua)['stateRunId'] == current['stateRunId'])
        lua.globals().virtualPNGs[runtime_path] = True
        check(f'case{index}: paused terminal preserves simulation/entities/commands', lua.eval('stateText()') == state)
        lua.eval('ackText')(json.dumps(ack)); lua.eval('updateOnly()')
        report = json.loads(lua.eval('reportText()'))
        check(f'case{index}: driver recorded collector arm before record', report['cases'][index - 1].get('recordingCaptureArmed') is True)
        check(f'case{index}: exact PNG acknowledgement persisted before advance', report['cases'][index - 1].get('terminalScreenshot') == ack)
        check(f'case{index}: only acknowledged case advances', phase(lua).get('stage') == 'finished' if index == 4 else lua.globals().factoryCount == factory + 1)
    report = json.loads(lua.eval('reportText()'))
    check('all four actual QA configurations finish only with four terminal ACKs', report.get('completed') and len(report['cases']) == 4 and all(c.get('terminalScreenshot') for c in report['cases']))
    check('normal speed is retained', report['speed'] == report['timeCompression'] == 1)
    check('Motion.record and event subscriptions restored on finish', lua.eval('recordRestored()') and not list(lua.globals().callbacks.keys()))
    timeout_lua = model(); terminal(timeout_lua)
    timeout_lua.execute('g.realTime=g.realTime+121;updateOnly()')
    report = json.loads(timeout_lua.eval('reportText()'))
    check('missing terminal ACK fails explicitly after bounded wait', not report.get('completed') and report.get('reason') == 'driver-error' and any('terminal screenshot acknowledgement timeout' in e for e in report.get('errors', [])))
    check('timeout restores Motion.record/subscriptions', timeout_lua.eval('recordRestored()') and not list(timeout_lua.globals().callbacks.keys()))
    hex_lua = model(); current = terminal(hex_lua)
    hex_lua.eval('stepFrame()'); hex_lua.eval('stepFrame()'); current = phase(hex_lua)
    hex_lua.globals().virtualPNGs['qa/organ-atlas-native/fullbody-movement-005/terminal-case-1.png'] = True
    ack = {'stateRunId': current['stateRunId'], 'index': current['index'], 'terminal': True,
           'pngSha256': 'z' * 64, 'pngPath': '/mock/nonhex.png',
           'pngRuntimePath': 'qa/organ-atlas-native/fullbody-movement-005/terminal-case-1.png',
           'captureNonce': 'b' * 32, 'ownerPid': 123, 'runtimeMirrorSha256': 'z' * 64}
    factory = hex_lua.globals().factoryCount
    hex_lua.eval('ackText')(json.dumps(ack)); hex_lua.eval('stepFrame()')
    check('64 characters without hexadecimal content do not count as PNG SHA', hex_lua.globals().factoryCount == factory and phase(hex_lua).get('stateRunId') == current['stateRunId'])
    changed = [p for p, h in bindings.items() if sha(ROOT / p) != h]
    result = {'schema': 'fullbody-native-terminal-protocol-test/v2', 'batch': '005', 'status': 'PASS' if all(c['pass'] for c in checks) and not changed else 'FAIL',
              'passed': sum(c['pass'] for c in checks), 'total': len(checks), 'checks': checks,
              'inputHashes': bindings, 'changedDuringChecks': changed, 'nativeEvidence': False,
              'scope': 'Actual QA Lua driver and four actual configs with mocked event/File/resource/motion engine; strict virtual storage PNG path plus collector-arming protocol.',
              'limits': ['No actual screenshots, native UI, preview status/refresh, production path planning or GPU resources were used.',
                         'Four final real PNGs plus current material bindings must still be captured and independently viewed after candidate freeze.']}
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps({'status': result['status'], 'passed': result['passed'], 'total': result['total'], 'report': str(OUT.relative_to(ROOT)), 'sha256': sha(OUT)}))
    for c in checks:
        if not c['pass']:
            print('FAIL:', c['name'])
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
