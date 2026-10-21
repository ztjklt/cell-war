#!/usr/bin/env python3
"""Package vaccine poses, retaining independent antibody drops and broken glass.

The death clip groups fragments by source grid position instead of discarding all
but the largest connected shape. The original painted sheets remain untouched.
"""
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_antibiotic import component_list, pack_action
from package_macrophage import grid_borders

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/image/vaccine-character-20261021"
SPECS = {
    "move": {
        "source": "source-move-16-v1.png", "label": "移动 · 16帧", "loop": True,
        "durations": [80] * 16,
        "lift": [0, 0, 10, 24, 34, 20, 0, 0, 0, 10, 24, 34, 20, 0, 0, 0],
    },
    "hit": {
        "source": "source-hit-16-v1.png", "label": "受击 · 16帧", "loop": False,
        "durations": [65, 60, 55, 80, 75, 65, 55, 55, 60, 60, 65, 70, 70, 75, 85, 150],
        "x": [256, 254, 246, 237, 234, 243, 250, 263, 256, 251, 260, 256, 256, 256, 256, 256],
    },
    "release": {
        "source": "source-release-16-v1.png", "label": "受击后释放抗体 · 16帧", "loop": False,
        "durations": [85, 75, 85, 85, 85, 85, 90, 90, 100, 100, 110, 100, 100, 100, 120, 200],
        "metadata": {"antibodyVisibleFromFrame": 4, "secondAntibodyVisibleFromFrame": 8,
                     "antibodyAsset": "../antibody/antibody-v1.png",
                     "gameplayNote": "User-defined passive trigger: hostile hit drops ground antibodies; virus contact causes damage. Two visual drops are illustrative; gameplay quantities and damage remain unspecified."},
    },
    "death": {
        "source": "source-death-16-v1.png", "label": "瓶身破碎死亡 · 16帧", "loop": False,
        "durations": [90, 85, 95, 100, 105, 85, 80, 75, 80, 85, 100, 140, 180, 200, 220, 450],
        "metadata": {"twitchFrames": [], "shatterFrame": 8, "debrisSettledFromFrame": 13,
                     "processing": "Preserve all substantive painted fragments in each grid pose; one fixed scale; ground registration with common source horizontal pivot. No synthetic shattering, pose redraw or interpolation.",
                     "sourceBodyBoundsMeaning": "Intact vial color bounds in first frame; complete fragment/prop bounds after fracture.",
                     "deathState": "Only shattered glass, detached stopper, spilled liquid, fallen flag and handbook remain."},
    },
}


def vial_bounds(image):
    rgba = np.asarray(image)
    red, green, blue = [rgba[:, :, i].astype(float) for i in range(3)]
    warm = ((rgba[:, :, 3] >= 96) & (red > 150) & (green > 80)
            & (red > blue * 1.1) & (green > blue * 1.025))
    _, components = component_list(warm)
    if not components:
        raise ValueError("Could not find honey-gold vial body")
    largest = max(components, key=lambda item: item["area"])
    if largest["area"] < 2000:
        raise ValueError("Vial body detector found only a small prop")
    return largest["box"]


def extract_shatter(source):
    rgba = np.asarray(Image.open(source).convert("RGBA"))
    alpha = rgba[:, :, 3]
    yedges = grid_borders((alpha >= 96).sum(axis=1), 4)
    nominal_width = rgba.shape[1] / 4
    poses = []
    reference_center_delta = None
    for row in range(4):
        top, bottom = yedges[row:row + 2]
        strip = rgba[top:bottom]
        labels, components = component_list(strip[:, :, 3] >= 64)
        groups = [set() for _ in range(4)]
        for item in components:
            left, _, right, _ = item["box"]
            col = min(3, max(0, int((left + right) / 2 / nominal_width)))
            groups[col].add(item["id"])
        for col, ids in enumerate(groups):
            if not ids:
                raise ValueError("Missing shattered pose")
            keep = ndimage.binary_dilation(np.isin(labels, list(ids)), iterations=2)
            pixels = strip.copy()
            pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
            pixels[pixels[:, :, 3] == 0, :3] = 0
            full = Image.fromarray(pixels)
            bounds = full.getchannel("A").point(lambda value: 255 if value >= 32 else 0).getbbox()
            left, local_top, right, local_bottom = bounds
            crop = (max(0, left - 2), max(0, local_top - 2),
                    min(full.width, right + 2), min(full.height, local_bottom + 2))
            painted = full.crop(crop)
            if not poses:
                body = vial_bounds(painted)
                reference_center_delta = (body[0] + body[2]) / 2 + crop[0] - nominal_width / 2
            else:
                body = painted.getchannel("A").point(lambda value: 255 if value >= 64 else 0).getbbox()
            anchor_x = (col + .5) * nominal_width + reference_center_delta - crop[0]
            anchor_y = local_bottom - crop[1]
            poses.append({"image": painted, "body": body,
                          "registrationAnchor": [anchor_x, anchor_y],
                          "sourceBox": [crop[0], top + crop[1], crop[2], top + crop[3]],
                          "sourceFrame": row * 4 + col + 1})
    return poses


def main():
    manifest = {"character": "vaccine", "displayName": "疫苗 · 免疫教官",
                "portrait": "vaccine-concept-v1.png"}
    validation = {}
    contact = Image.new("RGB", (16 * 160, 4 * 180), "#1a2733")
    draw = ImageDraw.Draw(contact)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames, validation[key] = pack_action(key, spec, output_dir=OUT,
                                               body_bounds=vial_bounds, display_name="疫苗",
                                               extractor=extract_shatter if key == "death" else None)
        manifest[spec["label"]] = f"{key}-16/animation.json"
        for index, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            contact.paste(thumb, (index * 160, row * 180), thumb)
            draw.text((index * 160 + 5, row * 180 + 160), f"{key} {index + 1:02}", fill="white")
    (OUT / "animations.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (OUT / "animation-validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n")
    contact.save(OUT / "animation-contact-sheet.jpg", quality=95)


if __name__ == "__main__":
    main()
