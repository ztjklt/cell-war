#!/usr/bin/env python3
"""Pack GPT-painted sachet poses and a separate healing drop; never redraw poses."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_antibiotic import bbox_distance, component_list
from package_macrophage import grid_borders

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/image/rehydration-salts-character-20261023"
DISPLAY = "补液盐 · 水盐补给员"
SPECS = {
    "move": dict(label="轻跳移动 · 16帧", loop=True, durations=[80] * 16,
                 lift=[0, 0, 0, 18, 30, 15, 0, 0, 0, 18, 28, 12, 0, 0, 0, 0]),
    "release": dict(label="举壶补给 · 16帧", loop=False,
                    durations=[90, 85, 85, 95, 100, 110, 110, 85, 95, 100, 105, 105, 100, 100, 110, 160]),
    "hit": dict(label="受击回弹 · 16帧", loop=False,
                durations=[75, 60, 60, 65, 75, 80, 85, 75, 65, 65, 70, 75, 80, 85, 100, 155],
                x=[256, 258, 261, 268, 273, 272, 268, 264, 258, 251, 253, 255, 256, 256, 256, 256]),
    "death": dict(label="瘪袋倒地 · 16帧", loop=False,
                  durations=[90, 85, 95, 95, 105, 105, 100, 110, 100, 105, 120, 140, 160, 180, 230, 500]),
    "drop": dict(label="独立补给滴 · 飞行与散开16帧", loop=False,
                 durations=[85] * 6 + [65, 65, 70, 75, 75, 80, 85, 90, 100, 140]),
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def body_bounds(image):
    a = np.asarray(image)
    r, g, b = [a[:, :, i].astype(float) for i in range(3)]
    mask = (a[:, :, 3] >= 128) & (r > 165) & (g > 170) & (b > 170)
    _, parts = component_list(mask)
    if not parts or max(p["area"] for p in parts) < 500:
        raise ValueError("Missing white sachet face panel")
    return max(parts, key=lambda p: p["area"])["box"]


def extract(source, action):
    rgba = np.asarray(Image.open(source).convert("RGBA"))
    if rgba[:, :, 3].min() != 0:
        raise ValueError("Source lacks actual transparency")
    labels, components = component_list(rgba[:, :, 3] >= 96)
    mains = [p for p in components if p["area"] > 5000]
    if len(mains) != 16:
        raise ValueError(f"{action}: expected16 whole painted characters, got{len(mains)}")
    row_of = lambda p: int((p["box"][1] + p["box"][3]) / 2 / rgba.shape[0] * 4)
    mains.sort(key=lambda p: (row_of(p), p["box"][0] + p["box"][2]))
    if any(sum(row_of(p) == row for p in mains) != 4 for row in range(4)):
        raise ValueError("Expected four painted characters per source row")
    groups = [{p["id"]} for p in mains]
    for part in components:
        if part["area"] < 16 or any(part["id"] in ids for ids in groups):
            continue
        scores = []
        for main in mains:
            a, b = part["box"], main["box"]
            dx = (a[0] + a[2] - b[0] - b[2]) / 2
            dy = (a[1] + a[3] - b[1] - b[3]) / 2
            scores.append(bbox_distance(a, b) + (dx * dx + dy * dy) * .08)
        groups[int(np.argmin(scores))].add(part["id"])
    poses, reference_x = [], None
    for i, ids in enumerate(groups):
        owned = np.isin(labels, list(ids))
        # Include antialiasing around owned artwork without borrowing pixels
        # from a different pose whose silhouette crosses a nominal grid line.
        keep = ndimage.binary_dilation(owned, iterations=2) & ((labels == 0) | owned)
        pixels = rgba.copy()
        pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
        pixels[pixels[:, :, 3] == 0, :3] = 0
        full = Image.fromarray(pixels)
        box = full.getchannel("A").point(lambda a: 255 if a >= 32 else 0).getbbox()
        l, t, r, b = box
        if min(l, t, full.width - r, full.height - b) < 2:
            raise ValueError(f"{action}:{i + 1}: source silhouette touches sheet edge")
        crop = [max(0, l - 2), max(0, t - 2), min(full.width, r + 2), min(full.height, b + 2)]
        image = full.crop(crop)
        face = body_bounds(image)
        anchor = [(face[0] + face[2]) / 2, face[3]]
        if action == "death":
            source_center = (i % 4 + .5) * rgba.shape[1] / 4
            if reference_x is None:
                reference_x = anchor[0] + crop[0] - source_center
            anchor = [source_center + reference_x - crop[0], b - crop[1]]
        poses.append(dict(image=image, body=face, anchor=anchor, sourceBox=crop, sourceFrame=i + 1))
    return poses


def save_clip(action, spec, frames, records, scale, source):
    folder = OUT / f"{action}-16"
    folder.mkdir(exist_ok=True)
    shutil.copy2(source, folder / "source-painted-sheet.png")
    size = frames[0].width
    atlas = Image.new("RGBA", (size * 4, size * 4))
    for i, frame in enumerate(frames):
        name = f"frame-{i + 1:03}.png"
        frame.save(folder / name)
        atlas.paste(frame, (i % 4 * size, i // 4 * size))
        records[i].update(name=name, duration=spec["durations"][i],
                          rect=dict(x=i % 4 * size, y=i // 4 * size, w=size, h=size))
    atlas.save(folder / "spritesheet.png")
    frames[0].save(folder / "preview.webp", save_all=True, append_images=frames[1:],
                   duration=spec["durations"], loop=0 if spec["loop"] else 1, lossless=True, method=3)
    doc = dict(name="补液盐 · " + spec["label"], animation=action, width=size, height=size,
               columns=4, rows=4, frameCount=16, durationMs=sum(spec["durations"]),
               loop=spec["loop"], spritesheet="spritesheet.png", preview="preview.webp",
               generatedBy="Built-in image_gen.imagegen", fixedScale=scale,
               sourceSHA256=digest(source), frames=records,
               processing="Extract complete painted source silhouettes and attached details; remove tiny detached alpha speckles; fixed scale per clip; whole-pose registration. No redraw, replacement copies or synthetic in-between frames.")
    if action == "release":
        doc.update(projectileSpawnFrames=[8], projectileAsset="../drop-16/asset.json",
                   gameplayNote="One friendly healing drop per cast. Character animation playback does not install treatment or spawn game entities.",
                   reviewProjectile=dict(animation="../drop-16/animation.json", startFrame=8,
                                         endFlightFrame=11, from_=[68, 242], to=[-140, 230], drawSize=180,
                                         frameMap=[1, 2, 4, 6, 7, 9, 11, 14, 16]))
        doc["reviewProjectile"]["from"] = doc["reviewProjectile"].pop("from_")
    if action == "death":
        doc.update(settledFromFrame=13, deathState="Deflated folded sachet and separate intact fallen pitcher; small water/salt spill; remains down.")
    if action == "drop":
        doc.update(flightLoopFrames=list(range(1, 7)), impactFrames=list(range(7, 17)),
                   type="independent_friendly_healing_drop", runtimeImplemented=False)
        frames[0].save(folder / "sprite.png")
        write(folder / "asset.json", dict(schema=1, type="independent_friendly_healing_drop",
                                          name="水盐补给滴", image="sprite.png", animation="animation.json",
                                          flightLoopFrames=list(range(1, 7)), impactFrames=list(range(7, 17)),
                                          friendlyOnly=True, runtimeImplemented=False, mechanics="../mechanics.json"))
    write(folder / "animation.json", doc)
    return doc


def package(action, spec):
    source = OUT / f"source-{action}-16-v1.png"
    poses = extract(source, action)
    scale = 200 / (poses[0]["body"][3] - poses[0]["body"][1])
    def offset(pose, i):
        x = spec.get("x", [256] * 16)[i]
        y = 430 if action == "death" else 365 - spec.get("lift", [0] * 16)[i]
        return [round(x - pose["anchor"][0] * scale), round(y - pose["anchor"][1] * scale)]
    for _ in range(60):
        if all(min(offset(p, i)) >= 12 and offset(p, i)[0] + round(p["image"].width * scale) <= 500
               and offset(p, i)[1] + round(p["image"].height * scale) <= 500 for i, p in enumerate(poses)):
            break
        scale *= .98
    else:
        raise ValueError(f"Cannot fit {action} frames")
    frames, records = [], []
    for i, p in enumerate(poses):
        off = offset(p, i)
        resized = p["image"].resize((round(p["image"].width * scale), round(p["image"].height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (512, 512)); frame.paste(resized, off)
        frames.append(frame)
        records.append(dict(anchor=dict(x=.5, y=430 / 512), sourceFrame=p["sourceFrame"],
                            sourceBox=p["sourceBox"], sourceBodyBounds=list(p["body"]),
                            sourceRegistrationAnchor=p["anchor"], registrationOffset=off))
    save_clip(action, spec, frames, records, scale, source)
    return frames


def package_drop():
    source = OUT / "source-drop-16-v1.png"
    rgba = np.asarray(Image.open(source).convert("RGBA"))
    ye = grid_borders((rgba[:, :, 3] >= 96).sum(axis=1), 4)
    poses = []
    for row in range(4):
        strip = rgba[ye[row]:ye[row + 1]]
        xe = grid_borders((strip[:, :, 3] >= 96).sum(axis=0), 4)
        for col in range(4):
            p = strip[:, xe[col]:xe[col + 1]].copy()
            labels, components = component_list(p[:, :, 3] >= 64)
            ids = [c["id"] for c in components if c["area"] >= 12]
            if not ids:
                raise ValueError("Missing drawn healing effect cell")
            owned = np.isin(labels, ids)
            keep = ndimage.binary_dilation(owned, iterations=2) & ((labels == 0) | owned)
            p[:, :, 3] = np.where(keep, p[:, :, 3], 0)
            p[p[:, :, 3] == 0, :3] = 0
            poses.append(dict(image=Image.fromarray(p), sourceBox=[xe[col], ye[row], xe[col + 1], ye[row + 1]]))
    # Whole cells preserve the spread and fade around a fixed source-cell pivot.
    first_box = poses[0]["image"].getchannel("A").point(lambda a: 255 if a >= 64 else 0).getbbox()
    scale = 112 / (first_box[2] - first_box[0])
    frames, records = [], []
    for i, p in enumerate(poses):
        im = p["image"]
        offset = [round(128 - im.width * scale / 2), round(128 - im.height * scale / 2)]
        resized = im.resize((round(im.width * scale), round(im.height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (256, 256)); frame.paste(resized, offset)
        frames.append(frame)
        records.append(dict(anchor=dict(x=.5, y=.5), sourceFrame=i + 1,
                            sourceBox=p["sourceBox"], registrationOffset=offset))
    save_clip("drop", SPECS["drop"], frames, records, scale, source)
    return frames


def audit():
    report = dict(characterFrames=0, independentEffectFrames=0, totalFrames=0, runtimeImplemented=False, clips={})
    for key in SPECS:
        folder = OUT / f"{key}-16"
        d = json.loads((folder / "animation.json").read_text())
        paths = sorted(folder.glob("frame-*.png"))
        assert len(paths) == d["frameCount"] == 16
        assert sum(x["duration"] for x in d["frames"]) == d["durationMs"]
        atlas = Image.open(folder / "spritesheet.png")
        assert atlas.mode == "RGBA" and atlas.size == (d["width"] * 4, d["height"] * 4)
        hashes, margins = [], []
        for p, record in zip(paths, d["frames"]):
            im = Image.open(p)
            assert im.mode == "RGBA" and im.size == (d["width"], d["height"])
            assert im.getchannel("A").getextrema()[0] == 0
            b = im.getchannel("A").point(lambda a: 255 if a >= 32 else 0).getbbox()
            assert b
            margin = min(b[0], b[1], im.width - b[2], im.height - b[3]); assert margin >= 8
            rr = record["rect"]
            assert atlas.crop((rr["x"], rr["y"], rr["x"] + rr["w"], rr["y"] + rr["h"])).tobytes() == im.tobytes()
            hashes.append(hashlib.sha256(im.tobytes()).hexdigest()); margins.append(margin)
        assert len(set(hashes)) == 16
        assert Image.open(folder / "preview.webp").n_frames == 16
        assert digest(folder / "source-painted-sheet.png") == d["sourceSHA256"]
        report["independentEffectFrames" if key == "drop" else "characterFrames"] += 16
        report["totalFrames"] += 16
        report["clips"][key] = dict(frameCount=16, uniqueFrames=16, allTransparent=True,
                                   atlasMatchesFrames=True, minimumMargin=min(margins),
                                   durationMs=d["durationMs"], sourceSHA256=d["sourceSHA256"])
    assert report["characterFrames"] == 64 and report["independentEffectFrames"] == 16
    release = json.loads((OUT / "release-16/animation.json").read_text())["reviewProjectile"]
    assert release["startFrame"] == 8 and len(release["frameMap"]) == 9
    assert release["startFrame"] + len(release["frameMap"]) - 1 == 16
    assert all(1 <= i <= 16 for i in release["frameMap"])
    write(OUT / "packaging-validation.json", report)
    return report


def main():
    manifest = dict(character="rehydration_salts", displayName=DISPLAY, portrait="rehydration-salts-concept-v1.png")
    contact = Image.new("RGB", (2560, 900), "#1d2937"); draw = ImageDraw.Draw(contact)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames = package_drop() if key == "drop" else package(key, spec)
        manifest[spec["label"]] = f"{key}-16/animation.json"
        for i, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            contact.paste(thumb, (i * 160, row * 180), thumb)
            draw.text((i * 160 + 5, row * 180 + 161), f"{key} {i + 1:02}", fill="white")
    write(OUT / "animations.json", manifest)
    contact.save(OUT / "animation-contact-sheet.jpg", quality=95)
    print(json.dumps(audit(), ensure_ascii=False))


if __name__ == "__main__":
    main()
