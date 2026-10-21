"""Collect actual local reports; deliberately does not grant full parity acceptance."""
import hashlib
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]/'godot'


def read(name):
    return json.loads((ROOT/'test-output'/name).read_text())


def main():
    routes = read('route-oracle.json')
    result = {
        'schema':'cell-war-godot-validation/2',
        'recordedAt':datetime.now().astimezone().isoformat(),
        'tested_engine':'4.6.3-stable (official)', 'platform':'macOS arm64',
        'acceptance':'audit revision; full original parity NOT accepted',
        'rules':read('rules.json'), 'mode_start_and_save_checks':read('modes.json'),
        'presentation_point_oracle':read('presentation-parity.json'),
        'layer_compositor':read('layer-compositor.json'),
        'route_oracle':{
            'passed':sum(bool(r['pass']) for r in routes), 'total':len(routes),
            'segments':sum(r['segments'] for r in routes),
            'max_float32_normalization_world_units':max(r['maxFloat32Snap'] for r in routes)},
        'systemic_encounter':read('encounter.json'), 'ui':read('ui-flow.json'),
        'teammate_alignment_checks':read('alignment.json'),
        'legacy_static_art_checks':read('legacy-art.json'),
        'sandbox_progress_checks':read('progress.json'),
        'underlay_repair_checks':read('underlay-repair.json'),
        'cell_entry_checks':read('cell-entry.json'),
        'asset_integrity':read('integrity.json'),
        'native_visual_checks':[
            'Seven 512x768 fullbody captures inspected against original Lua compositor with approved native underlay correction',
            'Native 1280x800 liver-notch and bladder-fringe closeups inspected after full underlay repair',
            'Live native right-lung entry inspected: three selected allied cells and three viruses visible',
            'Four independent native anatomy layer captures inspected after Node2D separation',
            '1280x800 gastric/organ trial static captures inspected against original Lua painter',
            '360x780 sandbox tutorial panel capture inspected',
            '1280x800 systemic window and original home inspected',
            '1280x800 and 360x780 trachea campaign inspected'],
        'legacy_lua_matches_export_baseline':(
            not read('integrity.json')['sourceLuaMismatches']
            if read('integrity.json').get('sourceLuaStatus') == 'checked' else None),
        'legacy_lua_status':read('integrity.json').get('sourceLuaStatus', 'historical report'),
        'full_original_parity_accepted':False,
        'limits':[
            'Legacy perfusion/heart shading and cell-test terrain details still differ',
            'Full sidebar, production/build previews and campaign warning animations incomplete',
            'Sandbox tutorial conditions tested; complete natural economy/tutorial replay not accepted',
            'Decorative circulation, minimap deformation and baked background animation differ',
            'Full sweep/slide, idle yielding and OrganTraffic not aligned',
            'No complete original/native replay acceptance for AI, combat and long-term economy',
            'No Maker cloud-save migration; independent native saves',
            'No Android/iOS hardware acceptance or release package export'],
        'native_source_sha256':{
            str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
            for directory in ['scripts','scenes','tests']
            for p in sorted((ROOT/directory).rglob('*'))
            if p.is_file() and p.suffix in ['.gd','.gdshader','.tscn']}
    }
    (ROOT/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(result['acceptance'])


if __name__ == '__main__':
    main()
