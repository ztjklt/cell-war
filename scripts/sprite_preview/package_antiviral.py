#!/usr/bin/env python3
"""Pack the antiviral's generated sixteen-pose movement/combat animation sheets."""
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw

from package_antibiotic import component_list, pack_action

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/image/antiviral-character-20261021"
SPECS = {
    "move": {
        "source": "source-move-16-v1.png", "label": "移动 · 16帧", "loop": True,
        "durations": [80] * 16, "x": [316] * 16,
        "lift": [0, 0, 10, 23, 32, 20, 0, 0, 0, 10, 23, 32, 20, 0, 0, 0],
    },
    "attack": {
        "source": "source-attack-16-v1.png", "label": "前伸夹击 · 16帧", "loop": False,
        "durations": [100, 85, 90, 90, 85, 115, 60, 55, 120, 100, 70, 75, 85, 90, 100, 140],
        "x": [316, 316, 316, 312, 308, 302, 300, 298, 298, 298, 304, 310, 314, 316, 316, 316],
        "metadata": {"impactFrames": [8, 9, 10],
                     "gameplayNote": "Forward clamp attack visual; no gameplay damage or antiviral mechanics configured."},
    },
    "hit": {
        "source": "source-hit-16-v1.png", "label": "受击 · 16帧", "loop": False,
        "durations": [65, 60, 55, 80, 75, 65, 55, 55, 60, 60, 65, 70, 70, 75, 85, 150],
        "x": [316, 318, 326, 338, 340, 333, 320, 311, 318, 323, 315, 316, 316, 316, 316, 316],
    },
    "death": {
        "source": "source-death-16-v1.png", "label": "倒地死亡 · 16帧", "loop": False,
        "durations": [90, 80, 80, 80, 80, 90, 100, 140, 90, 140, 90, 140, 160, 180, 200, 400],
        "x": [316, 316, 318, 321, 326, 332, 336, 336, 336, 336, 336, 336, 336, 336, 336, 336],
        "lift": [0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 5, 0, 0, 0, 0, 0],
        "metadata": {"twitchFrames": [[9, 10], [11, 12]]},
    },
}


def tablet_bounds(image):
    rgba = np.asarray(image)
    red, green, blue = [rgba[:, :, index].astype(float) for index in range(3)]
    purple = ((rgba[:, :, 3] >= 96) & (red > 90) & (blue > 120)
              & (blue > green * 1.06) & (red > green * 1.04) & (blue > red * .95))
    _, components = component_list(purple)
    if not components:
        raise ValueError("Could not find the lavender medicine tablet")
    largest = max(components, key=lambda item: item["area"])
    if largest["area"] < 2500:
        raise ValueError("Detected body is too small to be the medicine tablet")
    return largest["box"]


def main():
    manifest = {"character": "antiviral", "displayName": "抗病毒药 · 病毒封锁员",
                "portrait": "antiviral-concept-v1.png"}
    validation = {}
    contact = Image.new("RGB", (16 * 160, 4 * 180), "#1a2733")
    draw = ImageDraw.Draw(contact)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames, validation[key] = pack_action(key, spec, output_dir=OUT,
                                               body_bounds=tablet_bounds, display_name="抗病毒药")
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
