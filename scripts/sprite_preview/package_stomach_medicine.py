#!/usr/bin/env python3
"""Package sixteen GPT-painted poses per action without redrawing/interpolation.

Keep originals; find transparent gutters, group alpha components, register whole
painted poses, then create PNG frames, 4x4 atlases, JSON and animated WebP files.
"""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_antibiotic import component_list
from package_macrophage import grid_borders

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/image/stomach-medicine-character-20261022"
SIZE = 512
DISPLAY = "胃药 · 护胃盾卫"
SPECS = {
    "move": dict(version=1, label="轻跳移动 · 16帧", loop=True,
                 durations=[80] * 16,
                 lift=[0, 0, 0, 18, 30, 17, 0, 0, 0, 0, 0, 19, 29, 15, 0, 0]),
    "release": dict(version=2, label="朝左全身举盾 · 16帧", loop=False,
                    durations=[95, 85, 95, 100, 105, 110, 110, 120, 120, 120, 120, 120, 135, 150, 170, 360],
                    metadata=dict(fullBodyCoverage=True, coverage="all_directions", facing="left",
                                  enclosedObjects=["tablet_body", "both_hands", "held_shield"],
                                  visualClosedShellFromFrame=8, finalPose="closed_shell_held",
                                  gameplayNote="Confirmed full-body all-direction protection; finite capacity and duration. Preview only; no runtime combat events.")),
    "hit": dict(version=1, label="受击回弹 · 16帧", loop=False,
                durations=[75, 60, 60, 65, 75, 80, 85, 75, 65, 65, 70, 75, 80, 85, 100, 155],
                x=[256, 258, 261, 267, 272, 271, 268, 264, 258, 251, 253, 255, 256, 256, 256, 256]),
    "death": dict(version=1, label="药片碎裂死亡 · 16帧", loop=False,
                  durations=[90, 85, 95, 95, 105, 105, 100, 110, 100, 105, 120, 140, 160, 180, 230, 500],
                  metadata=dict(twitchFrames=[], settledFromFrame=13,
                                deathState="Tablet breaks into large solid fragments; shield falls separately; final pile stays down, no resurrection.")),
}
SPECS["release-right"] = {
    **SPECS["release"], "version": 1, "label": "朝右全身举盾 · 16帧",
    "metadata": {**SPECS["release"]["metadata"], "facing": "right",
                 "phaseReference": "../release-16/animation.json", "mirroredByCode": False},
}
SPECS = {key: SPECS[key] for key in ("release", "release-right", "move", "hit", "death")}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def body_bounds(image):
    """Measure the large cream tablet face, excluding the smaller shield facets."""
    a = np.asarray(image)
    r, g, b = [a[:, :, i].astype(float) for i in range(3)]
    mask = (a[:, :, 3] >= 160) & (r > 185) & (g > 135) & (g > b * 1.05)
    _, parts = component_list(mask)
    if not parts or max(p["area"] for p in parts) < 500:
        raise ValueError("Missing large cream tablet face")
    return max(parts, key=lambda p: p["area"])["box"]


def extract(source, action):
    rgba = np.asarray(Image.open(source).convert("RGBA"))
    alpha = rgba[:, :, 3]
    if alpha.min() != 0:
        raise ValueError("Source must retain true transparency")
    yedges = grid_borders((alpha >= 160).sum(axis=1), 4)
    poses, first_face_x = [], None
    for row in range(4):
        top, bottom = yedges[row:row + 2]
        strip = rgba[top:bottom]
        xedges = grid_borders((strip[:, :, 3] >= 160).sum(axis=0), 4)
        for col in range(4):
            left, right = xedges[col:col + 2]
            pixels = strip[:, left:right].copy()
            labels, parts = component_list(pixels[:, :, 3] >= 96)
            # Retain separated shield, foam arcs, death fragments and crumbs.
            # Discard only detached tiny alpha speckles, never paint new pixels.
            ids = [p["id"] for p in parts if p["area"] >= (16 if action == "death" else 32)]
            if not ids or max(p["area"] for p in parts) < 5000:
                raise ValueError(f"Missing complete painted cell {action}:{row * 4 + col + 1}")
            keep = ndimage.binary_dilation(np.isin(labels, ids), iterations=2)
            pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
            pixels[pixels[:, :, 3] == 0, :3] = 0
            painted = Image.fromarray(pixels)
            bounds = painted.getchannel("A").point(lambda a: 255 if a >= 32 else 0).getbbox()
            l, t, r, b = bounds
            crop = (max(0, l - 2), max(0, t - 2), min(painted.width, r + 2), min(painted.height, b + 2))
            painted = painted.crop(crop)
            face = body_bounds(painted)
            anchor = [(face[0] + face[2]) / 2, face[3]]
            if action == "death":
                # Fixed horizontal source-cell anchor and common ground retain
                # the actual fragment fall; do not center each fallen fragment.
                if first_face_x is None:
                    first_face_x = (face[0] + face[2]) / 2 + crop[0] + left - (col + .5) * rgba.shape[1] / 4
                anchor = [(col + .5) * rgba.shape[1] / 4 + first_face_x - left - crop[0], b - crop[1]]
            poses.append(dict(image=painted, body=face, anchor=anchor,
                              sourceBox=[left + crop[0], top + crop[1], left + crop[2], top + crop[3]],
                              sourceCell=[left, top, right, bottom], sourceFrame=row * 4 + col + 1))
    return poses


def offset(pose, spec, i, scale, action):
    x = spec.get("x", [256] * 16)[i]
    y = 430 if action == "death" else 360 - spec.get("lift", [0] * 16)[i]
    return [round(x - pose["anchor"][0] * scale), round(y - pose["anchor"][1] * scale)]


def package(action, spec):
    source = OUT / f"source-{action}-16-v{spec['version']}.png"
    poses = extract(source, action)
    scale = 208 / (poses[0]["body"][3] - poses[0]["body"][1])
    for _ in range(60):
        fits = True
        for i, p in enumerate(poses):
            ox, oy = offset(p, spec, i, scale, action)
            w, h = p["image"].size
            fits &= min(ox, oy) >= 12 and ox + round(w * scale) <= 500 and oy + round(h * scale) <= 500
        if fits:
            break
        scale *= .98
    else:
        raise ValueError(f"Cannot fit {action} poses without clipping")
    folder = OUT / f"{action}-16"
    folder.mkdir(exist_ok=True)
    shutil.copy2(source, folder / "source-painted-sheet.png")
    frames, records = [], []
    for i, pose in enumerate(poses):
        ox, oy = offset(pose, spec, i, scale, action)
        resized = pose["image"].resize((round(pose["image"].width * scale), round(pose["image"].height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (SIZE, SIZE))
        frame.paste(resized, (ox, oy))
        name = f"frame-{i + 1:03}.png"
        frame.save(folder / name)
        frames.append(frame)
        records.append(dict(name=name, duration=spec["durations"][i],
                            rect=dict(x=i % 4 * SIZE, y=i // 4 * SIZE, w=SIZE, h=SIZE),
                            anchor=dict(x=.5, y=430 / SIZE), sourceFrame=pose["sourceFrame"],
                            sourceGridCell=pose["sourceCell"], sourceBox=pose["sourceBox"],
                            sourceBodyBounds=list(pose["body"]), sourceRegistrationAnchor=pose["anchor"],
                            registrationOffset=[ox, oy]))
    atlas = Image.new("RGBA", (SIZE * 4, SIZE * 4))
    for i, frame in enumerate(frames):
        atlas.paste(frame, (i % 4 * SIZE, i // 4 * SIZE))
    atlas.save(folder / "spritesheet.png")
    frames[0].save(folder / "preview.webp", save_all=True, append_images=frames[1:],
                   duration=spec["durations"], loop=0 if spec["loop"] else 1, lossless=True, method=3)
    record = dict(name="胃药 · " + spec["label"], animation=action, width=SIZE, height=SIZE,
                  columns=4, rows=4, frameCount=16, durationMs=sum(spec["durations"]),
                  loop=spec["loop"], spritesheet="spritesheet.png", preview="preview.webp",
                  generatedBy="Built-in image_gen.imagegen", fixedScale=scale,
                  sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  processing="Preserve sixteen distinct painted cells; transparent-gutter extraction and tiny detached alpha-speckle cleanup only; fixed scale per action and whole-pose registration; no redraw, synthetic poses or interpolation.",
                  frames=records)
    record.update(spec.get("metadata", {}))
    write(folder / "animation.json", record)
    bounds = [f.getchannel("A").point(lambda a: 255 if a >= 64 else 0).getbbox() for f in frames]
    result = dict(frames=len(frames), uniquePixelHashes=len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames}),
                  allTransparent=all(f.getchannel("A").getextrema()[0] == 0 for f in frames),
                  noClipping=all(b and min(b[:2]) >= 10 and max(b[2:]) <= 502 for b in bounds),
                  bounds=bounds, fixedScale=scale, durationMs=record["durationMs"])
    if result["uniquePixelHashes"] != 16 or not result["noClipping"]:
        raise ValueError(f"Invalid painted frame set {action}: {result}")
    print(action, json.dumps({k: v for k, v in result.items() if k != "bounds"}))
    return frames, result


def main():
    manifest = dict(character="stomach_medicine", displayName=DISPLAY, portrait="stomach-medicine-concept-v1.png")
    validation = {}
    contact = Image.new("RGB", (2560, len(SPECS) * 180), "#241e29")
    draw = ImageDraw.Draw(contact)
    for row, (action, spec) in enumerate(SPECS.items()):
        frames, validation[action] = package(action, spec)
        manifest[spec["label"]] = f"{action}-16/animation.json"
        for i, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            contact.paste(thumb, (i * 160, row * 180), thumb)
            draw.text((i * 160 + 5, row * 180 + 161), f"{action} {i + 1:02}", fill="white")
    write(OUT / "animations.json", manifest)
    write(OUT / "animation-validation.json", validation)
    contact.save(OUT / "animation-contact-sheet.jpg", quality=95)


if __name__ == "__main__":
    main()
