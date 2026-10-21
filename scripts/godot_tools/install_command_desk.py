#!/usr/bin/env python3
"""Install the approved overhead flat desk art and register runtime hashes."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "godot"
ART = Path("assets/image/command-desk-20261021")

def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")

def main():
    names = ("command-desk-balanced-wide-v6.png", "command-desk-balanced-portrait-v6.png")
    for name in names:
        if not (ROOT / ART / name).is_file():
            raise SystemExit(f"Missing selected art: {ART / name}")
    path = GAME / "data/asset_manifest.json"
    entries = {entry["path"]: entry for entry in json.loads(path.read_text())}
    delivered = []
    for old in ("command-desk-wide-v2.png", "command-desk-portrait-v2.png", "command-desk-flat-base-v3.png", "command-desk-flat-wide-v4.png", "command-desk-flat-portrait-v4.png", "command-desk-research-wide-v5.png", "command-desk-research-portrait-v5.png"):
        relative = (ART / old).as_posix()
        entries.pop(relative, None)
        (GAME / relative).unlink(missing_ok=True)
        (GAME / (relative + ".import")).unlink(missing_ok=True)
    for name in names:
        relative = (ART / name).as_posix()
        target = GAME / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)
        entries[relative] = {"source": relative, "path": relative,
                             "bytes": target.stat().st_size,
                             "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}
        delivered.append(relative)
    write(path, list(entries.values()))
    path = GAME / "data/source_manifest.json"
    baseline = json.loads(path.read_text())
    baseline["assets"] = len(entries)
    baseline["assetBytes"] = sum(entry["bytes"] for entry in entries.values())
    write(path, baseline)
    print(json.dumps({"runtimeAssets": delivered}, ensure_ascii=False))

if __name__ == "__main__":
    main()
