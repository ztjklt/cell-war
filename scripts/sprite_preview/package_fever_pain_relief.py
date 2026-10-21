#!/usr/bin/env python3
"""Extract the painted cooling-firefighter poses and independent bubble effect.

No pose redraw, interpolation or gameplay integration. The generated originals
are retained; only alpha grouping, registration and atlas packing happen here.
"""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_antibiotic import bbox_distance, component_list, pack_action
from package_macrophage import grid_borders

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/image/fever-pain-relief-character-20261021"
DISPLAY = "退烧止痛药 · 降温消防员"
SPECS = {
    "move": {
        "source": "source-move-16-v1.png", "label": "轻跳移动 · 16帧", "loop": True,
        "durations": [80] * 16,
        "lift": [0, 0, 12, 25, 35, 20, 0, 0, 0, 12, 25, 35, 20, 0, 0, 0],
    },
    "attack": {
        "source": "source-attack-16-v1.png", "label": "远程泡泡射击 · 16帧", "loop": False,
        "durations": [95, 85, 80, 90, 100, 115, 70, 75, 85, 85, 85, 90, 95, 100, 110, 160],
        "x": [256, 256, 256, 254, 252, 250, 258, 269, 265, 260, 256, 256, 256, 256, 256, 256],
        "metadata": {"impactFrames": [], "projectileSpawnFrames": [7],
                     "projectileAsset": "../projectile-16/asset.json",
                     "reviewProjectile": {"animation": "../projectile-16/animation.json",
                                          "startFrame": 7, "endFlightFrame": 10,
                                          "from": [55, 315], "to": [-135, 315], "drawSize": 150,
                                          "frameMap": [1, 2, 3, 4, 5, 7, 9, 11, 13, 16]},
                     "gameplayNote": "Independent ranged projectile: light damage plus a brief fixed slow; re-hit refreshes slow duration. All numerical balance values remain unspecified."},
    },
    "hit": {
        "source": "source-hit-16-v1.png", "label": "受击回弹 · 16帧", "loop": False,
        "durations": [75, 60, 55, 75, 85, 65, 60, 65, 65, 65, 75, 75, 80, 85, 100, 150],
        "x": [256, 256, 260, 269, 274, 270, 264, 251, 248, 253, 260, 256, 256, 256, 256, 256],
    },
    "death": {
        "source": "source-death-16-v1.png", "label": "倒地死亡 · 16帧", "loop": False,
        "durations": [90, 85, 90, 95, 95, 95, 85, 110, 90, 120, 140, 90, 140, 180, 230, 500],
        "metadata": {"twitchFrames": [[9, 10], [12, 13]], "settledFromFrame": 14,
                     "deathState": "Intact tablet lies on its side with fallen helmet, tank, nozzle and connected hose; no resurrection."},
    },
}


def tablet_bounds(image):
    rgba = np.asarray(image)
    r, g, b = [rgba[:, :, i].astype(float) for i in range(3)]
    pale = ((rgba[:, :, 3] >= 96) & (r > 120) & (g > 160) & (b > 150)
            & (g > r * .95) & (b > r * .94))
    _, parts = component_list(pale)
    if not parts:
        raise ValueError("Missing icy-white tablet body")
    body = max(parts, key=lambda part: part["area"])
    if body["area"] < 2500:
        raise ValueError("Body detector selected a small highlight")
    return body["box"]


def extract_character(source):
    rgba = np.asarray(Image.open(source).convert("RGBA"))
    alpha = rgba[:, :, 3]
    edges = grid_borders((alpha >= 96).sum(axis=1), 4)
    poses = []
    for row in range(4):
        top, bottom = edges[row:row + 2]
        strip = rgba[top:bottom]
        labels, components = component_list(strip[:, :, 3] >= 64)
        mains = sorted(components, key=lambda part: part["area"], reverse=True)[:4]
        mains.sort(key=lambda part: part["box"][0] + part["box"][2])
        if len(mains) != 4 or min(part["area"] for part in mains) < 8000:
            raise ValueError("Expected four complete character drawings per source row")
        groups = [{part["id"]} for part in mains]
        for part in components:
            if any(part["id"] in ids for ids in groups):
                continue
            l, t, r, b = part["box"]
            # The painted attack source has a 1px scratch at the lower left edge.
            # It is neither attached art nor an action effect; retain the original.
            if part["area"] < 128 and (l == 0 or r == strip.shape[1]):
                continue
            distances = []
            for main in mains:
                first, second = part["box"], main["box"]
                center = ((first[0] + first[2] - second[0] - second[2]) / 2) ** 2
                distances.append(bbox_distance(first, second) + center * .08)
            groups[int(np.argmin(distances))].add(part["id"])
        for col, ids in enumerate(groups):
            keep = ndimage.binary_dilation(np.isin(labels, list(ids)), iterations=2)
            pixels = strip.copy()
            pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
            pixels[pixels[:, :, 3] == 0, :3] = 0
            image = Image.fromarray(pixels)
            l, t, r, b = image.getchannel("A").point(lambda v: 255 if v >= 32 else 0).getbbox()
            crop = (max(0, l - 2), max(0, t - 2), min(image.width, r + 2), min(image.height, b + 2))
            image = image.crop(crop)
            poses.append({"image": image, "body": tablet_bounds(image),
                          "sourceBox": [crop[0], top + crop[1], crop[2], top + crop[3]],
                          "sourceFrame": row * 4 + col + 1})
    return poses


def package_projectile():
    source = OUT / "source-projectile-16-v1.png"
    rgba = np.asarray(Image.open(source).convert("RGBA"))
    yedges = grid_borders((rgba[:, :, 3] >= 96).sum(axis=1), 4)
    xedges = [0, 319, 630, 940, rgba.shape[1]]
    # Pivots follow the intact first-row bubble centers and the source row layout.
    # Shrinking mist fragments must not be individually recentered or enlarged.
    pivots_x = [181, 477, 777, 1077]
    pivots_y = [204, 514, 810, 1094]
    target = OUT / "projectile-16"
    target.mkdir(exist_ok=True)
    shutil.copy2(source, target / "source-painted-sheet.png")
    durations = [85] * 4 + [65, 65, 65, 70, 75, 75, 80, 85, 90, 95, 110, 140]
    frames, records = [], []
    for row in range(4):
        for col in range(4):
            index = row * 4 + col
            crop = (xedges[col], yedges[row], xedges[col + 1], yedges[row + 1])
            pixels = rgba[crop[1]:crop[3], crop[0]:crop[2]].copy()
            labels, components = component_list(pixels[:, :, 3] >= 32)
            if not components:
                raise ValueError(f"Missing projectile drawing {index + 1}")
            keep = ndimage.binary_dilation(np.isin(labels, [part["id"] for part in components]), iterations=2)
            pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
            pixels[pixels[:, :, 3] == 0, :3] = 0
            frame = Image.new("RGBA", (512, 512))
            offset = (256 - pivots_x[col] + crop[0], 256 - pivots_y[row] + crop[1])
            frame.paste(Image.fromarray(pixels), offset)
            name = f"frame-{index + 1:03}.png"
            frame.save(target / name)
            frames.append(frame)
            records.append({"name": name, "duration": durations[index],
                            "rect": {"x": col * 512, "y": row * 512, "w": 512, "h": 512},
                            "anchor": {"x": .5, "y": .5}, "sourceFrame": index + 1,
                            "sourceGridCell": list(crop), "sourcePivot": [pivots_x[col], pivots_y[row]],
                            "registrationOffset": list(offset)})
    atlas = Image.new("RGBA", (2048, 2048))
    for index, frame in enumerate(frames):
        atlas.paste(frame, (index % 4 * 512, index // 4 * 512))
    atlas.save(target / "spritesheet.png")
    frames[0].save(target / "sprite.png")
    frames[0].save(target / "preview.webp", save_all=True, append_images=frames[1:],
                   duration=durations, loop=1, lossless=True)
    document = {"name": "降温泡泡弹 · 独立飞行与破裂", "animation": "projectile",
                "width": 512, "height": 512, "columns": 4, "rows": 4, "frameCount": 16,
                "loop": False, "durationMs": sum(durations), "spritesheet": "spritesheet.png",
                "preview": "preview.webp", "frames": records,
                "flightLoopFrames": [1, 2, 3, 4], "impactFrames": list(range(5, 17)),
                "generatedBy": "Built-in image_gen.imagegen", "fixedScale": 1,
                "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "processing": "Extract original painted effect cells; retain fixed-scale pivot while fragments disperse and fade. No redraw or interpolated effect poses."}
    (target / "animation.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n")
    asset = {"schema": 1, "name": "降温泡泡弹", "type": "independent_projectile", "image": "sprite.png",
             "animation": "animation.json", "flightLoopFrames": [1, 2, 3, 4], "impactFrames": list(range(5, 17)),
             "mechanics": "../mechanics.json", "runtimeImplemented": False}
    (target / "asset.json").write_text(json.dumps(asset, ensure_ascii=False, indent=2) + "\n")
    return frames, {"frames": 16, "uniquePixelHashes": len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames}),
                    "allTransparent": all(f.getchannel("A").getextrema()[0] == 0 for f in frames),
                    "bounds": [f.getchannel("A").point(lambda v: 255 if v >= 64 else 0).getbbox() for f in frames],
                    "fixedScale": 1}


def main():
    manifest = {"character": "fever_pain_relief", "displayName": DISPLAY,
                "portrait": "fever-pain-relief-concept-v1.png"}
    validation = {}
    contact = Image.new("RGB", (16 * 160, 5 * 180), "#1a2733")
    draw = ImageDraw.Draw(contact)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames, validation[key] = pack_action(key, spec, output_dir=OUT, body_bounds=tablet_bounds,
                                              display_name="退烧止痛药", extractor=extract_character)
        path = OUT / f"{key}-16/animation.json"
        doc = json.loads(path.read_text())
        doc["processing"] = "Connected-alpha extraction of painted poses; tiny boundary-scratch cleanup; one fixed scale per action; tablet-body registration. No pose redraw or interpolated replacement frames."
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
        manifest[spec["label"]] = f"{key}-16/animation.json"
        for index, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            contact.paste(thumb, (index * 160, row * 180), thumb)
            draw.text((index * 160 + 5, row * 180 + 160), f"{key} {index + 1:02}", fill="white")
    frames, validation["projectile"] = package_projectile()
    manifest["独立泡泡弹 · 16帧"] = "projectile-16/animation.json"
    for index, frame in enumerate(frames):
        thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
        contact.paste(thumb, (index * 160, 4 * 180), thumb)
        draw.text((index * 160 + 5, 4 * 180 + 160), f"bubble {index + 1:02}", fill="white")
    (OUT / "animations.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (OUT / "animation-validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n")
    contact.save(OUT / "animation-contact-sheet.jpg", quality=95)


if __name__ == "__main__":
    main()
