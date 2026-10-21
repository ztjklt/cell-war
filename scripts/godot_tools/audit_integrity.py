"""Verify Godot assets; optionally compare an extracted legacy source archive."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'godot'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path,
                        help='Extracted legacy workspace to compare with the frozen Lua hashes')
    parser.add_argument('--asset-source-root', type=Path,
                        help='Original artwork workspace to compare with asset provenance')
    args = parser.parse_args()
    manifest = json.loads((OUT/'data/asset_manifest.json').read_text())
    baseline = json.loads((OUT/'data/source_manifest.json').read_text())
    missing, mismatches = [], []
    source_mismatches = [] if args.asset_source_root is not None else None
    for row in manifest:
        path = OUT/row['path']
        if not path.exists():
            missing.append(row['path'])
        elif digest(path) != row['sha256'] or path.stat().st_size != row['bytes']:
            mismatches.append(row['path'])
        if args.asset_source_root is not None and row['source'].startswith('assets/'):
            source = args.asset_source_root/row['source']
            if not source.is_file() or digest(source) != row['sha256']:
                source_mismatches.append(row['source'])
    lua_mismatches = None
    if args.source_root is not None:
        lua_mismatches = [name for name, sha in baseline['sources'].items()
                          if not (args.source_root/name).is_file() or digest(args.source_root/name) != sha]
    result = {'files':len(manifest), 'bytes':sum(row['bytes'] for row in manifest),
              'missing':missing, 'mismatches':mismatches,
              'sourceAssetMismatches':source_mismatches,
              'sourceAssetStatus':'checked' if args.asset_source_root is not None else 'not checked',
              'sourceLuaFiles':len(baseline['sources']), 'sourceLuaMismatches':lua_mismatches,
              'sourceLuaStatus':'checked' if args.source_root is not None else 'archived; not checked',
              'manifestTotalsMatch':baseline['assets'] == len(manifest) and
                  baseline['assetBytes'] == sum(row['bytes'] for row in manifest)}
    (OUT/'test-output').mkdir(exist_ok=True)
    (OUT/'test-output/integrity.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))
    raise SystemExit(bool(missing or mismatches or source_mismatches or lua_mismatches or not result['manifestTotalsMatch']))


if __name__ == '__main__':
    main()
