#!/usr/bin/env python3
"""Project authoritative medicine design/release data into the gallery.

The standalone command updates only medicine entries. It does not install new
art, change gameplay or enable purchases. Released metadata is copied only after
the runtime definition enables the individual implemented medicine. The full catalogue installer may pass
its existing byte-for-byte asset installer to build_entries().
"""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "godot"
DEFINITION = GAME / "data/medicines.json"


def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_size(path):
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path.relative_to(ROOT)}")
    return struct.unpack(">II", data[16:24])


def installed(source):
    relative = source.relative_to(ROOT)
    target = GAME / relative
    if not source.is_file() or not target.is_file() or digest(source) != digest(target):
        raise ValueError(f"Missing or stale gallery art: {relative}")
    return "res://" + relative.as_posix()


def build_entries(install=installed):
    definition = read(DEFINITION)
    enabled = set(definition["runtime"].get("enabledMedicineIds", []))
    assert enabled <= {"fever_pain_relief"}, "Only the validated first medicine has a runtime implementation"
    entries = []
    for item in definition["entries"]:
        can_sell = bool(item["purchase"]["canSell"])
        can_deploy = bool(item["purchase"]["canDeploy"])
        if can_sell or can_deploy:
            assert item["id"] in enabled and item["actualEffect"]["runtimeImplemented"]
        art = item["assets"]
        authoring = art["authoring"]
        mechanics_source = ROOT / authoring["mechanics"]
        assert mechanics_source.is_file(), mechanics_source
        mechanism = read(mechanics_source)
        assert mechanism["id"] == item["id"]
        assert mechanism["character"] == item["displayName"]
        entry = dict(id=item["id"], name=item["name"], category="medicines", role=item["role"],
                     status=item["gallery"]["status"], summary=item["gallery"]["summary"],
                     mechanics=item["gallery"]["mechanics"], note=item["gallery"]["note"],
                     kind=item["id"] if can_deploy else "", portrait=install(ROOT / authoring["portrait"]), actions=[],
                     sources=["godot/data/medicines.json", authoring["mechanics"]],
                     medicineDefinition="res://data/medicines.json", medicineDefinitionId=item["id"],
                     confirmation=item["confirmation"], canPurchase=can_sell, canDeploy=can_deploy)
        assert entry["portrait"] == art["runtimePortrait"]
        if authoring["manifest"]:
            manifest_path = ROOT / authoring["manifest"]
            manifest = read(manifest_path)
            assert manifest["displayName"] == item["displayName"]
            assert manifest["character"] == item["id"]
            assert (manifest_path.parent / manifest["portrait"]).resolve() == (ROOT / authoring["portrait"]).resolve()
            entry["sources"].append(authoring["manifest"])
        for action in art["animations"]:
            doc_path = ROOT / action["authoringAnimation"]
            doc = read(doc_path)
            assert doc["animation"] == action["id"]
            assert len(doc["frames"]) == doc["frameCount"] == action["frameCount"] == 16
            atlas = doc_path.parent / doc["spritesheet"]
            width, height = png_size(atlas)
            frames = []
            for frame in doc["frames"]:
                r = frame["rect"]
                assert 0 <= r["x"] < r["x"] + r["w"] <= width
                assert 0 <= r["y"] < r["y"] + r["h"] <= height
                assert frame["duration"] > 0
                assert (doc_path.parent / frame["name"]).is_file()
                frames.append(dict(rect=[r[key] for key in ["x", "y", "w", "h"]],
                                   duration=frame["duration"] / 1000.0))
            path = install(atlas)
            assert path == action["runtimeAtlas"]
            label = next(label for label, value in manifest.items()
                         if isinstance(value, str) and value.endswith(".json")
                         and (manifest_path.parent / value).resolve() == doc_path.resolve())
            entry["actions"].append(dict(name=label.split(" · ")[0], path=path, frames=frames,
                                          duration=sum(f["duration"] for f in frames),
                                          sourceLoop=doc.get("loop", False)))
            entry["sources"].append(action["authoringAnimation"])
        for still in art["stills"]:
            assert (ROOT / still["authoringAsset"]).is_file()
            source = ROOT / still["authoringImage"]
            assert list(png_size(source)) == still["size"]
            path = install(source)
            assert path == still["runtimeImage"]
            w, h = still["size"]
            # 1.5s is a read-only display hold, not the ground object's lifetime.
            entry["actions"].append(dict(name=still["name"], path=path,
                frames=[dict(rect=[0, 0, w, h], duration=1.5)], duration=1.5, sourceLoop=True))
            entry["sources"].append(still["authoringAsset"])
        entries.append(entry)
    assert len({entry["id"] for entry in entries}) == len(entries)
    return entries


def main():
    path = GAME / "data/character_catalogue.json"
    document = read(path)
    original_other = [entry for entry in document["entries"] if entry.get("category") != "medicines"]
    medicines = {entry["id"]: entry for entry in build_entries()}
    seen = set()
    merged = []
    for entry in document["entries"]:
        if entry.get("category") == "medicines" and entry["id"] in medicines:
            merged.append(medicines[entry["id"]]); seen.add(entry["id"])
        else:
            merged.append(entry)
    merged.extend(entry for key, entry in medicines.items() if key not in seen)
    assert original_other == [entry for entry in merged if entry.get("category") != "medicines"]
    document["entries"] = merged
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(dict(medicines=len(medicines), actions=sum(len(e["actions"]) for e in medicines.values()),
                          nonMedicineEntriesPreserved=len(original_other), runtimeEnabled=sorted(e["id"] for e in medicines.values() if e["canPurchase"])), ensure_ascii=False))


if __name__ == "__main__":
    main()
