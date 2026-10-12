"""Authorized exact-window capture, with verified terminal-frame handshake.

Derived from capture-movement-003.py; never starts/refreshes a preview or changes
runtime/main/art. All four final PNGs must show the production driver's accepted
arrival before its state can advance. --self-test performs no computer control.
"""
import argparse
import copy
import datetime
import hashlib
import json
import math
import re
import subprocess
import sys
import time
from pathlib import Path

for dependency in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0, dependency)
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BATCH = '004'
BASE = ROOT / 'docs/body-life/vascular-art-study/fullbody-015'
STORAGE = Path('/Users/jitian/.taptap-maker/preview/c77d76c39450447ca7bafe38d059fd9c2a3ad04a7b223daa29b3b681ffd63caa/storage')
CLI = ['/opt/homebrew/Cellar/node/25.8.1_1/bin/node',
       '/Users/jitian/.taptap-maker/mcp-runtime/0.0.36/dist/maker.js', 'preview']
WINDOW_TOOL = ROOT / '.tmp/vessel-material-pilot/window-all'
MAX_GOAL_DISTANCE = .075


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_bytes().rstrip(b'\x00').decode())


def write_json(path, value, single_line=False):
    # Native File:ReadLine consumes the terminal acknowledgement's single line.
    text = json.dumps(value, ensure_ascii=False, allow_nan=False,
                      separators=(',', ':') if single_line else None,
                      indent=None if single_line else 2) + '\n'
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(text)
    temporary.replace(path)


def phase_ready(phase, now):
    return (phase.get('stage') == 'record' and phase.get('recording') is True and
            phase.get('worldReady') is True and phase.get('uiReady') is True and
            bool(phase.get('stateRunId')) and phase.get('total') == 4 and
            abs(phase.get('zoom', 0) - .15) <= 1e-12 and
            abs(now - phase.get('wallTime', 0)) <= 2.1)


def case_for(driver, phase):
    return next((c for c in driver.get('cases', [])
                 if c.get('stateRunId') == phase.get('stateRunId') and
                 c.get('id') == phase.get('id') and c.get('index') == phase.get('index')), None)


def terminal_errors(case, phase):
    errors, checks = [], []
    if not case:
        return ['matching completed driver case is absent'], checks
    if not (phase.get('terminal') is True and phase.get('terminalReady') is True and
            phase.get('terminalRenderedFrames', 0) >= 2 and phase.get('complete') is True and
            phase.get('driverArrivalVerified') is True and case.get('completed') is True):
        errors.append('terminal arrival/second rendered frame is not explicitly verified')
    if case.get('stateRunId') != phase.get('stateRunId') or case.get('index') != phase.get('index') or case.get('id') != phase.get('id'):
        errors.append('case identity differs from current state')
    commands = case.get('commands', [])
    if not commands or phase.get('goals') != commands or not all(c.get('accepted') is True and c.get('resolved') for c in commands):
        errors.append('phase goals do not equal actual accepted driver commands')
    arrivals = case.get('arrivals', [])
    if len(arrivals) != len(commands) or not all(a.get('distanceWorld', math.inf) <= MAX_GOAL_DISTANCE and
                                                a.get('laneMatches') is True and a.get('organMatches') is True for a in arrivals):
        errors.append('driver arrivals do not validate every actor')
    if not case.get('recordingUsesNormalMainLoop') or not case.get('movedDistanceWorld') or not all(v > 0 for v in case['movedDistanceWorld']):
        errors.append('no complete actual normal-main-loop movement evidence')
    positions = phase.get('positions', [])
    by_id = {p.get('id'): p for p in positions}
    if len(by_id) != len(positions) or len(positions) != len(commands):
        errors.append('terminal position list omits or duplicates actors')
    for command in commands:
        position, goal = by_id.get(command.get('id')), command.get('resolved')
        if not position or not goal:
            errors.append('terminal actor/goal missing')
            continue
        distance = math.hypot(position['x'] - goal['x'], position['y'] - goal['y'])
        good = (distance <= MAX_GOAL_DISTANCE and position.get('lane') == goal.get('lane') and
                position.get('orders') == 0 and not position.get('transit'))
        checks.append({'id': command['id'], 'distanceWorld': distance,
                       'laneMatches': position.get('lane') == goal.get('lane'),
                       'orders': position.get('orders'), 'noTransit': not position.get('transit'),
                       'capturedAtAcceptedGoal': good})
        if not good:
            errors.append('actor ' + str(command['id']) + ' is not at its accepted terminal goal')
    return errors, checks


def same_capture_state(before, after, terminal=False):
    names = ['stateRunId', 'index', 'id', 'camera', 'zoom', 'stage', 'recording', 'worldReady', 'uiReady']
    if not all(before.get(k) == after.get(k) for k in names):
        return False
    if terminal:
        return (before.get('terminal') is True and after.get('terminal') is True and
                before.get('terminalReady') is True and after.get('terminalReady') is True and
                before.get('positions') == after.get('positions') and before.get('goals') == after.get('goals'))
    return True


def exact_window(identity, pid, previous=None):
    assert identity.get('ownerPid') == pid and identity.get('screenCaptureAccess') is True, 'PID or capture authorization differs'
    rows = [w for w in identity.get('windows', [])
            if w.get('title') == '细胞战争' and w.get('owner') == 'UrhoXRuntime' and w.get('layer') == 0]
    assert len(rows) == 1, 'Exactly one matching game window is required'
    window = rows[0]
    if previous is not None:
        assert window.get('id') == previous.get('id') and window.get('bounds') == previous.get('bounds'), 'Window identity/bounds changed'
    return window


def command_json(argv):
    return json.loads(subprocess.run(argv, capture_output=True, text=True, check=True, timeout=10).stdout)


def status():
    result = command_json(CLI + ['status', '--target-dir', str(ROOT), '--json'])
    assert result.get('process_alive') is True, 'Stopped preview is not restarted by this helper'
    return result


def discover_current():
    paths = [p for p in STORAGE.glob('**/fullbody-movement-' + BATCH + '/current.json')
             if abs(time.time() - p.stat().st_mtime) < 5]
    return max(paths, key=lambda p: p.stat().st_mtime) if paths else None


def binding():
    paths = [Path(__file__).resolve(), ROOT / 'scripts/qa/FullBodyMapNativeMovement.lua',
             ROOT / 'scripts/qa/FullBodyMapNativeMovementData.lua', ROOT / 'scripts/main.lua',
             ROOT / 'scripts/war/FullBodyMapArt.lua', ROOT / 'scripts/war/FullBodyMapArtData.lua',
             BASE / 'bake/manifest.json']
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in paths}
    data = (ROOT / 'scripts/war/FullBodyMapArtData.lua').read_text()
    found = re.search(r'\["manifestSha256"\]\s*=\s*"([0-9a-f]{64})"', data)
    manifest = hashes[str((BASE / 'bake/manifest.json').relative_to(ROOT))]
    assert found and found[1] == manifest, 'Runtime resource Data is not bound to active manifest'
    return hashes, manifest


def finalize(record, driver, out):
    record['driverCompleted'] = driver.get('completed') is True
    record['driverErrors'] = driver.get('errors', [])
    record['caseCoverage'] = []
    for case in driver.get('cases', []):
        shots = [x for x in record['captures'] if x['phase']['stateRunId'] == case.get('stateRunId')]
        gaps = [shots[i + 1]['captureStartedUnix'] - shots[i]['captureStartedUnix'] for i in range(len(shots) - 1)]
        span = shots[-1]['captureStartedUnix'] - shots[0]['captureStartedUnix'] if len(shots) > 1 else 0
        terminal = [x for x in shots if x.get('terminal')]
        terminal_error, checks = terminal_errors(case, terminal[-1]['phase']) if terminal else (['no terminal PNG captured'], [])
        if terminal and (case.get('terminalScreenshot', {}).get('pngSha256') != terminal[-1]['sha256'] or
                         case.get('terminalScreenshot', {}).get('pngPath') != str((out / terminal[-1]['path']).resolve())):
            terminal_error.append('driver did not acknowledge this exact terminal PNG')
        coverage = {'id': case.get('id'), 'stateRunId': case.get('stateRunId'), 'frames': len(shots),
                    'captureSpanSeconds': span,
                    'simulationSpanSeconds': shots[-1]['phase']['simulationElapsed'] - shots[0]['phase']['simulationElapsed'] if len(shots) > 1 else 0,
                    'capturedContinuously': span >= 15 and bool(gaps) and max(gaps) <= 2.5,
                    'maximumCaptureGapSeconds': max(gaps, default=0), 'completed': case.get('completed') is True,
                    'terminalCaptured': bool(terminal) and not terminal_error,
                    'terminalErrors': terminal_error, 'terminalGoalChecks': checks,
                    'terminalPath': terminal[-1]['path'] if terminal else None,
                    'terminalHoldSeconds': max(0, terminal[-1]['phase']['visualElapsed'] - case.get('durationSeconds', 0)) if terminal else None}
        record['caseCoverage'].append(coverage)
        if shots:
            images = []
            for shot in shots:
                with Image.open(out / shot['path']) as source:
                    im = source.convert('RGB'); im.thumbnail((1249, 734)); images.append(im)
            durations = [max(1, round(g * 1000)) for g in gaps] + [750]
            target = out / ('case-' + f"{case['index']:02d}" + '.webp')
            images[0].save(target, save_all=True, append_images=images[1:], duration=durations, loop=0, quality=78)
            coverage['animationSha256'] = sha(target)
    record['changedDuringCapture'] = [p for p, h in record['inputHashes'].items() if sha(ROOT / p) != h]
    record['completed'] = (record['driverCompleted'] and not record['driverErrors'] and not record['errors'] and
                           not record['changedDuringCapture'] and len(record['caseCoverage']) == 4 and
                           all(c['capturedContinuously'] and c['frames'] >= 2 and c['completed'] and c['terminalCaptured']
                               for c in record['caseCoverage']))
    write_json(out / 'system-movement.json', record)


def capture(args):
    out = args.output_dir.resolve()
    assert not out.exists() or not any(out.glob('*.png')) and not (out / 'system-movement.json').exists(), 'Refusing to overwrite an existing capture batch'
    hashes, manifest = binding()
    if args.manifest_sha256:
        assert manifest == args.manifest_sha256, 'Requested material manifest differs from active Data'
    preview = status(); pid = preview['runtime_pid']
    if args.pid is not None:
        assert args.pid == pid, 'Requested PID is not the alive preview process'
    window, deadline = None, time.monotonic() + 20
    while time.monotonic() < deadline:
        identity = command_json([str(WINDOW_TOOL), str(pid)])
        try:
            window = exact_window(identity, pid); break
        except AssertionError:
            time.sleep(.25)
    assert window is not None, 'Exact game window did not become ready'
    out.mkdir(parents=True, exist_ok=True)
    record = {'schema': 'fullbody-native-movement-capture/v2', 'batch': BATCH, 'captures': [], 'errors': [],
              'window': window, 'ownerPid': pid, 'session_id': preview['session_id'], 'reload_id': preview['reload_id'],
              'timeCompression': 1, 'targetCaptureIntervalSeconds': .75, 'inputHashes': hashes,
              'manifestSha256': manifest, 'terminalHandshakeRequired': True,
              'sourceHistory': {'helper003Path': '.tmp/fullbody-015/capture-movement-003.py',
                                'helper003Sha256': sha(ROOT / '.tmp/fullbody-015/capture-movement-003.py')},
              'captureScope': 'Exact verified game window only; no preview start/refresh or desktop capture.'}
    current, driver, next_shot, last_status = args.current, {}, 0, 0
    counts, acknowledged = {}, set()
    deadline = time.monotonic() + args.wait_seconds
    try:
        while time.monotonic() < deadline:
            if current is None:
                current = discover_current()
            if current is None:
                time.sleep(.1); continue
            try:
                phase = read_json(current)
            except (ValueError, OSError):
                time.sleep(.1); continue
            if phase.get('stage') == 'finished':
                driver = read_json(current.parent / 'report.json'); break
            if not phase_ready(phase, time.time()) or phase['stateRunId'] in acknowledged:
                time.sleep(.05); continue
            terminal = phase.get('terminal') is True
            if terminal and not phase.get('terminalReady'):
                time.sleep(.05); continue
            if not terminal and time.monotonic() < next_shot:
                time.sleep(.05); continue
            driver = read_json(current.parent / 'report.json')
            case = case_for(driver, phase)
            if not case:
                time.sleep(.05); continue
            if terminal:
                errors, goals = terminal_errors(case, phase)
                assert not errors, '; '.join(errors)
            if time.monotonic() - last_status >= 10:
                latest = status()
                assert all(latest.get(k) == preview.get(k) for k in ['runtime_pid', 'session_id', 'reload_id']), 'Preview session changed during capture'
                last_status = time.monotonic()
            exact_window(command_json([str(WINDOW_TOOL), str(pid)]), pid, window)
            index = phase['index']; number = counts.get(index, 0) + 1
            dest = out / f'case-{index:02d}-frame-{number:03d}.png'
            start = time.time()
            result = subprocess.run(['/usr/sbin/screencapture', '-x', '-o', '-l', str(window['id']), str(dest)],
                                    capture_output=True, text=True, timeout=10)
            end = time.time()
            assert result.returncode == 0 and dest.is_file(), result.stderr or 'No PNG returned'
            with Image.open(dest) as image:
                assert image.format == 'PNG'; dimensions = list(image.size); image.verify()
            after = read_json(current)
            exact_window(command_json([str(WINDOW_TOOL), str(pid)]), pid, window)
            if not phase_ready(after, end) or not same_capture_state(phase, after, terminal):
                dest.unlink(); time.sleep(.05); continue
            if terminal:
                newer = read_json(current.parent / 'report.json'); case = case_for(newer, after)
                errors, goals = terminal_errors(case, after)
                assert not errors, '; '.join(errors)
            row = {'path': dest.name, 'phase': phase, 'phaseAfter': after, 'terminal': terminal,
                   'sha256': sha(dest), 'pixelSize': dimensions, 'captureStartedUnix': start, 'captureEndedUnix': end,
                   'timestamp': datetime.datetime.now().astimezone().isoformat()}
            if terminal:
                row['terminalGoalChecks'] = goals
            record['captures'].append(row); counts[index] = number
            record['sourceCurrentPath'] = str(current)
            write_json(out / 'system-movement.json', record)
            if terminal:
                ack = {'schema': 'fullbody-native-terminal-capture-ack/v1', 'stateRunId': phase['stateRunId'],
                       'index': index, 'terminal': True, 'pngSha256': row['sha256'], 'pngPath': str(dest.resolve()),
                       'ownerPid': pid, 'windowId': window['id'], 'manifestSha256': manifest,
                       'captureStartedUnix': start, 'captureEndedUnix': end}
                write_json(current.parent / 'terminal-ack.json', ack, single_line=True)
                row['terminalAcknowledgement'] = ack
                acknowledged.add(phase['stateRunId'])
                write_json(out / 'system-movement.json', record)
            next_shot = time.monotonic() + .75
            print('CAPTURED', index, number, 'terminal' if terminal else 'moving', round(phase['visualElapsed'], 2), flush=True)
        else:
            record['errors'].append({'reason': 'capture-deadline', 'seconds': args.wait_seconds})
    except Exception as error:
        record['errors'].append({'reason': type(error).__name__, 'message': str(error)})
    if current and (current.parent / 'report.json').exists():
        driver = read_json(current.parent / 'report.json')
    write_json(out / 'driver-report.json', driver)
    finalize(record, driver, out)
    print(json.dumps({'completed': record['completed'], 'captures': len(record['captures']),
                      'terminalCases': sum(c['terminalCaptured'] for c in record['caseCoverage']),
                      'errors': record['errors'], 'report': str(out / 'system-movement.json')}, ensure_ascii=False), flush=True)
    return 0 if record['completed'] else 1


def self_test():
    old_path = BASE / 'native-movement-003/driver-report.json'
    old_helper = ROOT / '.tmp/fullbody-015/capture-movement-003.py'
    before = {str(p.relative_to(ROOT)): sha(p) for p in [old_path, old_helper]}
    driver = read_json(old_path); old_system = read_json(BASE / 'native-movement-003/system-movement.json')
    checks = []
    def check(name, passed):
        checks.append({'name': name, 'pass': bool(passed)})
    for case in driver['cases']:
        phase = copy.deepcopy(case['frames'][-1])
        phase.update(terminal=True, terminalReady=True, terminalRenderedFrames=2,
                     driverArrivalVerified=True, goals=copy.deepcopy(case['commands']))
        errors, goals = terminal_errors(case, phase)
        check('historical actual final driver positions accept terminal contract: ' + case['id'], not errors and len(goals) == len(case['commands']))
        for key, value in [('terminal', False), ('terminalReady', False), ('terminalRenderedFrames', 1),
                           ('driverArrivalVerified', False), ('complete', False), ('stateRunId', 'other-state'), ('goals', [])]:
            bad = copy.deepcopy(phase); bad[key] = value
            check('reject invalid terminal ' + key + ': ' + case['id'], bool(terminal_errors(case, bad)[0]))
        for actor in range(len(phase['positions'])):
            bad = copy.deepcopy(phase); bad['positions'][actor]['x'] += 1
            check('reject any actor short of its goal: ' + case['id'] + '/' + str(actor), bool(terminal_errors(case, bad)[0]))
            bad = copy.deepcopy(phase); bad['positions'][actor]['orders'] = 1
            check('reject remaining order: ' + case['id'] + '/' + str(actor), bool(terminal_errors(case, bad)[0]))
            bad = copy.deepcopy(phase); bad['positions'][actor]['lane'] += 1
            check('reject wrong terminal plane: ' + case['id'] + '/' + str(actor), bool(terminal_errors(case, bad)[0]))
        after = copy.deepcopy(phase)
        check('same terminal state accepts', same_capture_state(phase, after, True))
        after['positions'][0]['x'] += .001
        check('movement during terminal screenshot rejects', not same_capture_state(phase, after, True))
        check('fresh .15 phase accepts', phase_ready(phase, phase['wallTime'] + .5))
        check('stale phase rejects', not phase_ready(phase, phase['wallTime'] + 3))
        shots = [s for s in old_system['captures'] if s['phase']['stateRunId'] == case['stateRunId']]
        check('old unacknowledged PNG cannot become new terminal evidence', bool(terminal_errors(case, shots[-1]['phase'])[0]))
    identity = {'ownerPid': 123, 'screenCaptureAccess': True, 'windows': [
        {'id': 9, 'title': '细胞战争', 'owner': 'UrhoXRuntime', 'layer': 0, 'bounds': {'Width': 1249, 'Height': 734}}]}
    window = exact_window(identity, 123)
    check('exact PID/title/owner/window accepts', window['id'] == 9)
    for key, value in [('ownerPid', 124), ('screenCaptureAccess', False)]:
        bad = copy.deepcopy(identity); bad[key] = value
        try:
            exact_window(bad, 123); rejected = False
        except AssertionError:
            rejected = True
        check('wrong identity rejects: ' + key, rejected)
    for key, value in [('title', 'Other app'), ('owner', 'OtherRuntime'), ('layer', 1), ('id', 10)]:
        bad = copy.deepcopy(identity); bad['windows'][0][key] = value
        try:
            exact_window(bad, 123, window); rejected = False
        except AssertionError:
            rejected = True
        check('wrong exact window rejects: ' + key, rejected)
    changed = [p for p, h in before.items() if sha(ROOT / p) != h]
    result = {'schema': 'fullbody-native-terminal-helper-contract-test/v1',
              'status': 'PASS' if all(c['pass'] for c in checks) and not changed else 'FAIL',
              'passed': sum(c['pass'] for c in checks), 'total': len(checks), 'checks': checks,
              'helperSha256': sha(Path(__file__).resolve()), 'inputHashes': before,
              'driverSha256': sha(ROOT / 'scripts/qa/FullBodyMapNativeMovement.lua'),
              'changedHistoricalInputs': changed, 'nativeEvidence': False,
              'scope': 'Pure helper predicates with historical actual arrival-coordinate fixtures; terminal flags are synthetic, no screenshots/preview/status/native access.'}
    output = BASE / 'qa/fourth-repair/terminal-helper-contract-test.json'
    write_json(output, result)
    print(json.dumps({'status': result['status'], 'passed': result['passed'], 'total': result['total'],
                      'report': str(output), 'sha256': sha(output)}))
    return 0 if result['status'] == 'PASS' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--current', type=Path, help='Exact active fullbody-movement-004/current.json')
    parser.add_argument('--output-dir', type=Path, default=BASE / 'native-movement-004')
    parser.add_argument('--pid', type=int, help='Optional expected alive preview PID')
    parser.add_argument('--manifest-sha256', help='Optional expected frozen current art manifest')
    parser.add_argument('--wait-seconds', type=float, default=600)
    args = parser.parse_args()
    return self_test() if args.self_test else capture(args)


if __name__ == '__main__':
    raise SystemExit(main())
