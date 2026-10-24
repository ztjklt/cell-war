#!/usr/bin/env python3
"""Pack the sixteen painted expectorant poses per action, without pose redraw.

Preserves generated originals; only crop/alpha speckle grouping, fixed per-action
scale, body registration and deterministic atlas/WebP packaging happen here.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_antibiotic import bbox_distance, component_list, pack_action
from package_macrophage import grid_borders

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/image/expectorant-character-20261021"
DISPLAY = "化痰药 · 清痰清道夫"
SPECS = {
    "move": dict(source="source-move-16-v1.png", label="轻跳移动 · 16帧", loop=True,
                 durations=[80] * 16,
                 lift=[0, 0, 8, 22, 34, 20, 0, 0, 0, 8, 22, 34, 20, 0, 0, 0]),
    "attack": dict(source="source-attack-16-v2.png", label="向前吸痰 · 16帧", loop=False,
                   durations=[95, 85, 85, 95, 100, 110, 100, 95, 100, 100, 110, 100, 95, 90, 95, 150],
                   x=[256, 256, 254, 252, 250, 246, 243, 241, 242, 244, 248, 250, 252, 254, 256, 256],
                   metadata=dict(impactFrames=[], suctionFrames=[6, 7, 8, 9, 10, 11],
                                 attachedSuctionVfx=True, independentProjectile=False,
                                 gameplayNote="Visual intake only: particles move toward funnel. Mucus cleanup/shield/status rules remain a design proposal; no runtime effect is installed by playback.")),
    "hit": dict(source="source-hit-16-v1.png", label="受击回弹 · 16帧", loop=False,
                durations=[75, 60, 55, 75, 85, 65, 60, 65, 65, 65, 75, 75, 80, 85, 100, 150],
                x=[256, 256, 261, 269, 274, 270, 264, 252, 248, 252, 260, 256, 256, 256, 256, 256]),
    "death": dict(source="source-death-16-v1.png", label="瘪倒死亡 · 16帧", loop=False,
                  durations=[90, 85, 90, 95, 95, 95, 90, 120, 100, 110, 140, 100, 140, 200, 240, 500],
                  metadata=dict(twitchFrames=[[9, 10], [12, 13]], settledFromFrame=14,
                                deathState="Green droplet remains down/deflated; visor and funnel settle, hose stays connected to intact collection jar. No glass shatter or resurrection.")),
}


def green_body_bounds(image):
    rgba = np.asarray(image)
    r, g, b = [rgba[:, :, i].astype(float) for i in range(3)]
    mask = ((rgba[:, :, 3] >= 96) & (g > 80) & (g > r * 1.10) & (g > b * 1.18))
    _, components = component_list(mask)
    if not components:
        raise ValueError("Missing painted green droplet body")
    main = max(components, key=lambda item: item["area"])
    if main["area"] < 500:
        raise ValueError("Body detection found only a small green accent")
    # Gold visor separates the curled tip from the main body; the brown belt
    # also separates its lower green belly. Include belly facets below the face,
    # excluding the side jar's green liquid and the springy top tip.
    left, top, right, bottom = main["box"]
    middle_left = left + (right - left) * .15
    middle_right = right - (right - left) * .15
    body_parts = [main]
    for part in components:
        l, t, r, b = part["box"]
        if part["area"] >= 200 and t >= top and b > bottom and middle_left <= (l + r) / 2 <= middle_right:
            body_parts.append(part)
    return (min(p["box"][0] for p in body_parts), min(p["box"][1] for p in body_parts),
            max(p["box"][2] for p in body_parts), max(p["box"][3] for p in body_parts))


def extract(source, death=False):
    rgba = np.asarray(Image.open(source).convert("RGBA"))
    alpha = rgba[:, :, 3]
    if alpha.min() != 0:
        raise ValueError("Generated sheet lacks true transparency")
    yedges = grid_borders((alpha >= 64).sum(axis=1), 4)
    poses = []
    reference_center_delta = None
    reference_floor_delta = None
    for row in range(4):
        top, bottom = yedges[row:row + 2]
        strip = rgba[top:bottom]
        labels, components = component_list(strip[:, :, 3] >= 32)
        mains = sorted(components, key=lambda part: part["area"], reverse=True)[:4]
        mains.sort(key=lambda part: part["box"][0] + part["box"][2])
        if len(mains) != 4 or min(part["area"] for part in mains) < 4000:
            raise ValueError("Each painted source row must contain four complete characters")
        groups = [{part["id"]} for part in mains]
        for part in components:
            if any(part["id"] in ids for ids in groups) or part["area"] < 16:
                continue
            scores = []
            for main in mains:
                a, b = part["box"], main["box"]
                center = ((a[0] + a[2] - b[0] - b[2]) / 2) ** 2
                scores.append(bbox_distance(a, b) + center * .08)
            groups[int(np.argmin(scores))].add(part["id"])
        for col in range(4):
            # Group connected silhouettes rather than cutting through a jar or
            # intake fleck that slightly crosses a nominal vertical cell line.
            pixels = strip.copy()
            keep = ndimage.binary_dilation(np.isin(labels, list(groups[col])), iterations=2)
            pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
            pixels[pixels[:, :, 3] == 0, :3] = 0
            edge = pixels[:, :, 3] >= 64
            if edge[0].any() or edge[-1].any() or edge[:, 0].any() or edge[:, -1].any():
                raise ValueError(f"Painted pose touches outer row/image boundary: {row * 4 + col + 1}")
            full = Image.fromarray(pixels)
            bounds = full.getchannel("A").point(lambda v: 255 if v >= 16 else 0).getbbox()
            l, t, r, b = bounds
            crop = (max(0, l - 2), max(0, t - 2), min(full.width, r + 2), min(full.height, b + 2))
            image = full.crop(crop)
            body = green_body_bounds(image)
            item = dict(image=image, body=body,
                        sourceBox=[crop[0], top + crop[1], crop[2], top + crop[3]],
                        sourceFrame=row * 4 + col + 1)
            if death:
                center = (col + .5) * rgba.shape[1] / 4
                if reference_center_delta is None:
                    reference_center_delta = (body[0] + body[2]) / 2 + crop[0] - center
                    reference_floor_delta = image.height - body[3]
                item["registrationAnchor"] = [center + reference_center_delta - crop[0],
                                               image.height - reference_floor_delta]
            poses.append(item)
    return poses


def main():
    manifest = dict(character="expectorant", displayName=DISPLAY, portrait="expectorant-concept-v2.png")
    validation = {}
    contact = Image.new("RGB", (16 * 160, 4 * 180), "#1a2733")
    draw = ImageDraw.Draw(contact)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames, validation[key] = pack_action(
            key, spec, output_dir=OUT, body_bounds=green_body_bounds, display_name="化痰药",
            target_body_height=228, extractor=lambda p, dead=key == "death": extract(p, dead))
        path = OUT / f"{key}-16/animation.json"
        doc = json.loads(path.read_text())
        doc["processing"] = "Preserve sixteen painted source cells, including equipment and intake effects; remove tiny detached alpha speckles only; one fixed scale per action and green-body registration. No synthetic pose redraw or interpolation."
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
        manifest[spec["label"]] = f"{key}-16/animation.json"
        if validation[key]["frames"] != 16 or validation[key]["uniquePixelHashes"] != 16:
            raise ValueError("Each action must retain sixteen genuinely distinct painted frames")
        for index, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            contact.paste(thumb, (index * 160, row * 180), thumb)
            draw.text((index * 160 + 5, row * 180 + 160), f"{key} {index + 1:02}", fill="white")
    (OUT / "animations.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (OUT / "animation-validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n")
    contact.save(OUT / "animation-contact-sheet.jpg", quality=95)


if __name__ == "__main__":
    main()
