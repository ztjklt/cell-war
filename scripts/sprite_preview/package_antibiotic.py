#!/usr/bin/env python3
"""Extract and register the approved antibiotic's sixteen painted poses per action.

The source images remain untouched. This script groups connected artwork instead
of cutting vertical lines through overlapping hammer silhouettes. It only cleans
small alpha speckles, scales, translates and packs the generated poses.
"""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_macrophage import grid_borders

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/image/antibiotic-character-20261021"
CANVAS = 512
SPECS = {
    "move": {
        "source": "source-move-16-v1.png", "label": "轻跳移动 · 16帧", "loop": True,
        "durations": [80] * 16,
        "lift": [0, 0, 10, 25, 36, 22, 0, 0, 0, 10, 25, 36, 22, 0, 0, 0],
    },
    "hit": {
        "source": "source-hit-16-v1.png", "label": "受击回弹 · 16帧", "loop": False,
        "durations": [65, 55, 55, 75, 70, 60, 55, 55, 60, 55, 55, 65, 65, 70, 75, 130],
        "x": [256, 254, 246, 238, 234, 240, 248, 260, 254, 250, 259, 256, 256, 256, 256, 256],
    },
    "attack": {
        "source": "source-attack-16-v2.png", "label": "提锤重敲 · 16帧", "loop": False,
        "durations": [100, 100, 90, 110, 120, 150, 55, 55, 95, 90, 75, 85, 95, 105, 100, 150],
        "x": [256, 256, 256, 254, 252, 248, 254, 265, 268, 266, 260, 256, 254, 256, 256, 256],
    },
    "death": {
        "source": "source-death-16-v1.png", "label": "倒地甩动两下 · 16帧", "loop": False,
        "durations": [95, 85, 85, 85, 80, 80, 90, 130, 85, 100, 130, 85, 100, 180, 200, 420],
        "x": [256, 256, 258, 262, 268, 280, 300, 300, 300, 300, 300, 300, 300, 300, 300, 300],
        "lift": [0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 6, 0, 0, 0, 0],
    },
}


def bbox_distance(first, second):
    dx = max(first[0] - second[2], second[0] - first[2], 0)
    dy = max(first[1] - second[3], second[1] - first[3], 0)
    return dx * dx + dy * dy


def component_list(mask):
    labels, count = ndimage.label(mask)
    sizes = np.bincount(labels.ravel())
    found = []
    for number, slices in enumerate(ndimage.find_objects(labels), 1):
        if slices is None or sizes[number] < 12:
            continue
        ys, xs = slices
        found.append({"id": number, "area": int(sizes[number]),
                      "box": (xs.start, ys.start, xs.stop, ys.stop)})
    return labels, found


def colored_body_bounds(image):
    a = np.asarray(image)
    rgb = a[:, :, :3].astype(float)
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    opaque = a[:, :, 3] >= 96
    aqua = opaque & (green > 95) & (blue > 90) & (green > red * 1.35) & (blue > red * 1.15)
    yellow = opaque & (red > 155) & (green > 140) & (red > blue * 1.06) & (green > blue * 1.04)
    _, ac = component_list(aqua)
    _, yc = component_list(yellow)
    ac = sorted(ac, key=lambda x: x["area"], reverse=True)[:5]
    yc = sorted(yc, key=lambda x: x["area"], reverse=True)[:5]
    candidates = []
    for first in ac:
        for second in yc:
            distance = bbox_distance(first["box"], second["box"])
            if distance > max(image.size) ** 2 * .025:
                continue
            score = first["area"] + second["area"] - distance * 3
            candidates.append((score, first["box"], second["box"]))
    if not candidates:
        raise ValueError("Could not locate aqua/yellow capsule body")
    _, first, second = max(candidates)
    return (min(first[0], second[0]), min(first[1], second[1]),
            max(first[2], second[2]), max(first[3], second[3]))


def extract(source, body_bounds=colored_body_bounds):
    rgba = np.array(Image.open(source).convert("RGBA"))
    alpha = rgba[:, :, 3]
    if alpha.min() != 0:
        raise ValueError("Painted source must have a transparent background")
    yedges = grid_borders((alpha >= 96).sum(axis=1), 4)
    frames = []
    for row in range(4):
        top, bottom = yedges[row:row + 2]
        strip = rgba[top:bottom]
        labels, components = component_list(strip[:, :, 3] >= 64)
        mains = sorted(components, key=lambda item: item["area"], reverse=True)[:4]
        mains.sort(key=lambda item: item["box"][0] + item["box"][2])
        if len(mains) != 4 or min(item["area"] for item in mains) < 4000:
            raise ValueError("Source row does not contain four complete painted poses")
        groups = [{item["id"]} for item in mains]
        for item in components:
            if any(item["id"] in ids for ids in groups):
                continue
            distances = []
            for main in mains:
                first, second = item["box"], main["box"]
                center_distance = ((first[0] + first[2] - second[0] - second[2]) / 2) ** 2
                distances.append(bbox_distance(first, second) + center_distance * .08)
            groups[int(np.argmin(distances))].add(item["id"])
        for col, ids in enumerate(groups):
            keep = ndimage.binary_dilation(np.isin(labels, list(ids)), iterations=2)
            cell = strip.copy()
            cell[:, :, 3] = np.where(keep, cell[:, :, 3], 0)
            cell[cell[:, :, 3] == 0, :3] = 0
            painted = Image.fromarray(cell)
            bounds = painted.getchannel("A").point(lambda value: 255 if value >= 32 else 0).getbbox()
            if bounds is None:
                raise ValueError("Extracted empty frame")
            left, local_top, right, local_bottom = bounds
            crop = (max(0, left - 2), max(0, local_top - 2),
                    min(painted.width, right + 2), min(painted.height, local_bottom + 2))
            painted = painted.crop(crop)
            body = body_bounds(painted)
            frames.append({"image": painted, "body": body,
                           "sourceBox": [crop[0], top + crop[1], crop[2], top + crop[3]],
                           "sourceFrame": row * 4 + col + 1})
    return frames


def placement(item, spec, index, scale):
    left, top, right, bottom = item["body"]
    anchor_x, anchor_y = item.get("registrationAnchor", ((left + right) / 2, bottom))
    target_x = spec.get("x", [256] * 16)[index]
    target_y = 438 - spec.get("lift", [0] * 16)[index]
    return (round(target_x - anchor_x * scale), round(target_y - anchor_y * scale))


def pack_action(key, spec, output_dir=OUT, body_bounds=colored_body_bounds,
                display_name="抗生素", target_body_height=232, extractor=None):
    source = output_dir / spec["source"]
    poses = extractor(source) if extractor else extract(source, body_bounds)
    scale = target_body_height / (poses[0]["body"][3] - poses[0]["body"][1])
    # One fixed scale for the entire action preserves deformations and weapon size.
    for _ in range(50):
        fits = True
        for index, item in enumerate(poses):
            ox, oy = placement(item, spec, index, scale)
            w, h = item["image"].size
            fits &= ox >= 10 and oy >= 10 and ox + w * scale <= 502 and oy + h * scale <= 502
        if fits:
            break
        scale *= .97
    else:
        raise ValueError("Could not fit all painted poses without clipping")
    target = output_dir / f"{key}-16"
    target.mkdir(exist_ok=True)
    shutil.copy2(source, target / "source-painted-sheet.png")
    frames, records = [], []
    for index, item in enumerate(poses):
        ox, oy = placement(item, spec, index, scale)
        painted = item["image"].resize((round(item["image"].width * scale),
                                         round(item["image"].height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (CANVAS, CANVAS))
        frame.paste(painted, (ox, oy))
        name = f"frame-{index + 1:03}.png"
        frame.save(target / name)
        frames.append(frame)
        records.append({"name": name, "duration": spec["durations"][index],
                        "rect": {"x": index % 4 * CANVAS, "y": index // 4 * CANVAS,
                                 "w": CANVAS, "h": CANVAS},
                        "anchor": {"x": .5, "y": 438 / CANVAS},
                        "sourceFrame": item["sourceFrame"], "sourceGridCell": item["sourceBox"],
                        "sourceBodyBounds": list(item["body"]), "registrationOffset": [ox, oy]})
        if "registrationAnchor" in item:
            records[-1]["sourceRegistrationAnchor"] = list(item["registrationAnchor"])
    atlas = Image.new("RGBA", (CANVAS * 4, CANVAS * 4))
    for index, frame in enumerate(frames):
        atlas.paste(frame, (index % 4 * CANVAS, index // 4 * CANVAS))
    atlas.save(target / "spritesheet.png")
    frames[0].save(target / "preview.webp", save_all=True, append_images=frames[1:],
                   duration=spec["durations"], loop=0 if spec["loop"] else 1, lossless=True, method=3)
    doc = {"name": display_name + " · " + spec["label"], "animation": key, "width": CANVAS,
           "height": CANVAS, "columns": 4, "rows": 4, "frameCount": 16,
           "durationMs": sum(spec["durations"]), "loop": spec["loop"],
           "spritesheet": "spritesheet.png", "preview": "preview.webp",
           "generatedBy": "Built-in image_gen.imagegen", "fixedScale": scale,
           "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
           "processing": "Connected-alpha grouping; speckle cleanup; one fixed scale per action; capsule-body registration with action anchor offsets. No pose redraw or interpolated replacement frames.",
           "frames": records}
    if key == "attack":
        doc["impactFrames"] = [8, 9]
        doc["gameplayNote"] = "Heavy high-damage attack direction only; no damage value configured."
    if key == "death":
        doc["twitchFrames"] = [[9, 10], [12, 13]]
    doc.update(spec.get("metadata", {}))
    (target / "animation.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    validation = {"frames": len(frames), "uniquePixelHashes": len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames}),
                  "allTransparent": all(frame.getchannel("A").getextrema()[0] == 0 for frame in frames),
                  "bounds": [frame.getchannel("A").point(lambda value: 255 if value >= 64 else 0).getbbox() for frame in frames],
                  "bodyBounds": [list(item["body"]) for item in poses], "fixedScale": scale}
    print(key, json.dumps({"frames": 16, "scale": scale, "unique": validation["uniquePixelHashes"], "durationMs": doc["durationMs"]}))
    return frames, validation


def main():
    manifest = {"character": "antibiotic", "displayName": "抗生素 · 胶囊重锤兵",
                "portrait": "antibiotic-concept-v4-hand-grip.png"}
    validation = {}
    debug = Image.new("RGB", (16 * 160, 4 * 180), "#1a2733")
    draw = ImageDraw.Draw(debug)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames, validation[key] = pack_action(key, spec)
        manifest[spec["label"]] = f"{key}-16/animation.json"
        for index, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            debug.paste(thumb, (index * 160, row * 180), thumb)
            draw.text((index * 160 + 5, row * 180 + 160), f"{key} {index + 1:02}", fill="white")
    (OUT / "animations.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (OUT / "animation-validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n")
    debug.save(OUT / "animation-contact-sheet.jpg", quality=95)


if __name__ == "__main__":
    main()
