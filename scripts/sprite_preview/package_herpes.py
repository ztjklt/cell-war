#!/usr/bin/env python3
"""Package approved ImageGen artwork as aligned animation frames, preserving sources.

The generator sometimes varies row spacing. Connected body bounds identify the
sixteen poses before slicing. No frames are interpolated or invented. Burst
frames are scaled about their core to remove the generator's camera-size jump.
Death retains a fixed cell-space anchor so fading fragments do not recenter.
"""
from pathlib import Path
import hashlib
import json
import statistics
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets/image/herpes-ambusher-20261020"
CANVAS, AX, AY = 768, 384, 512
SPECS = {
    "move": ("移动", 16, True),
    "burrow": ("缩成膜囊", 16, False),
    "emerge": ("从膜囊恢复", 16, False),
    "burst": ("范围爆发攻击", 20, False),
    "hit": ("受击", 20, False),
    "death": ("慢慢消散死亡", 8, False),
}


def components(im, threshold=240, min_area=400):
    width, height = im.size
    mask = bytearray(v >= threshold for v in im.getchannel("A").tobytes())
    output = []
    for start in range(len(mask)):
        if not mask[start]:
            continue
        mask[start] = 0
        queue = [start]
        count = 0
        left, top, right, bottom = width, height, 0, 0
        while queue:
            pt = queue.pop()
            x, y = pt % width, pt // width
            count += 1
            left, top = min(left, x), min(top, y)
            right, bottom = max(right, x + 1), max(bottom, y + 1)
            for neighbor in ((pt - 1 if x else -1),
                             (pt + 1 if x + 1 < width else -1),
                             (pt - width if y else -1),
                             (pt + width if y + 1 < height else -1)):
                if neighbor >= 0 and mask[neighbor]:
                    mask[neighbor] = 0
                    queue.append(neighbor)
        if count >= min_area:
            output.append({"area": count, "box": [left, top, right, bottom]})
    return output


def body_rows(im, kind):
    candidates = components(im)
    # All non-effect body silhouettes are the sixteen largest opaque islands.
    if kind != "burst":
        candidates = sorted(candidates, key=lambda c: c["area"], reverse=True)[:16]
        if len(candidates) != 16:
            raise ValueError(f"{kind}: expected 16 body silhouettes")
        candidates.sort(key=lambda c: c["box"][3])
        return [sorted(candidates[r * 4:(r + 1) * 4],
                       key=lambda c: c["box"][0]) for r in range(4)]
    # The continuous ring is a separate island; choose the opaque filled core
    # nearest each slot center, excluding thin off-center effect fragments.
    rows = []
    for row in range(4):
        entries = []
        for col in range(4):
            cx, cy = (col + .5) * im.width / 4, (row + .56) * im.height / 4
            near = []
            for c in candidates:
                l, t, r, b = c["box"]
                x, y = (l + r) / 2, (t + b) / 2
                if abs(x - cx) < im.width / 4 * .27 and abs(y - cy) < im.height / 4 * .43:
                    near.append(c)
            if not near:
                raise ValueError(f"Missing burst core {row},{col}")
            entries.append(max(near, key=lambda c: c["area"]))
        rows.append(entries)
    return rows


def cell_boxes(im, rows, kind):
    if kind in ("burst", "death"):
        # Effects require the whole slot, including detached translucent pixels.
        # Four pixels separate edge-touching fragments from neighboring burst
        # slots. This trims the source slot; it does not repaint the effects.
        inset = 4 if kind == "burst" else 0
        return [[round(c * im.width / 4) + inset, round(r * im.height / 4) + inset,
                 round((c + 1) * im.width / 4) - inset, round((r + 1) * im.height / 4) - inset]
                for r in range(4) for c in range(4)]
    ys = [0]
    for r in range(3):
        upper = max(c["box"][3] for c in rows[r])
        lower = min(c["box"][1] for c in rows[r + 1])
        if lower <= upper:
            raise ValueError("Artwork rows overlap")
        ys.append(round((upper + lower) / 2))
    ys.append(im.height)
    boxes = []
    for row, entries in enumerate(rows):
        xs = [0]
        for col in range(3):
            a, b = entries[col]["box"][2], entries[col + 1]["box"][0]
            if b <= a:
                raise ValueError("Artwork columns overlap")
            xs.append(round((a + b) / 2))
        xs.append(im.width)
        boxes.extend([[xs[c], ys[row], xs[c + 1], ys[row + 1]] for c in range(4)])
    return boxes


def save_clip(kind):
    label, fps, loop = SPECS[kind]
    path = DEST / f"{kind}-source.png"
    im = Image.open(path).convert("RGBA")
    if im.getchannel("A").getextrema()[0] != 0:
        raise ValueError("Source must have genuine alpha")
    rows = body_rows(im, kind) if kind != "death" else None
    bodies = [c["box"] for row in rows for c in row] if rows else None
    boxes = cell_boxes(im, rows, kind)
    reference = 15 if kind == "emerge" else 0
    if kind == "death":
        core = max(components(im.crop(tuple(boxes[0]))), key=lambda c: c["area"])["box"]
    else:
        core = bodies[reference]
    scale = 300 / (core[2] - core[0])
    folder = DEST / kind
    folder.mkdir(exist_ok=True)
    frames, entries = [], []
    for i, box in enumerate(boxes):
        cell = im.crop(tuple(box))
        if kind == "death":
            cx = (core[0] + core[2]) / 2
            bottom = core[3]
            factor = scale
        else:
            l, t, r, b = bodies[i]
            cx, bottom = (l + r) / 2 - box[0], b - box[1]
            if kind == "burst":
                sizes = [300, 304, 308, 312, 314, 320, 325, 330,
                         315, 304, 300, 300, 300, 300, 300, 300]
                factor = sizes[i] / (r - l)
            else:
                factor = scale
        resized = cell.resize((round(cell.width * factor), round(cell.height * factor)), Image.Resampling.LANCZOS)
        ox, oy = round(AX - cx * factor), round(AY - bottom * factor)
        frame = Image.new("RGBA", (CANVAS, CANVAS))
        # Compositing a full transparent source slot preserves detached effects.
        frame.alpha_composite(resized, (ox, oy))
        name = f"frame-{i + 1:03}.png"
        frame.save(folder / name)
        duration = round((i + 1) * 1000 / fps) - round(i * 1000 / fps)
        entries.append({"name": name, "duration": duration,
                        "rect": {"x": i % 4 * CANVAS, "y": i // 4 * CANVAS, "w": CANVAS, "h": CANVAS},
                        "anchor": {"x": AX / CANVAS, "y": AY / CANVAS},
                        "sourceFrame": i + 1, "sourceBox": box,
                        "registrationOffset": [ox, oy], "registrationScale": factor,
                        "sourceCoreBounds": bodies[i] if bodies else None})
        frames.append(frame)
    atlas = Image.new("RGBA", (CANVAS * 4, CANVAS * 4))
    for i, frame in enumerate(frames):
        atlas.paste(frame, (i % 4 * CANVAS, i // 4 * CANVAS))
    atlas.save(folder / "spritesheet.png")
    # Animated-file previews loop for easy review; runtime metadata remains once.
    frames[0].save(folder / "preview.webp", save_all=True, append_images=frames[1:],
                   duration=[f["duration"] for f in entries], loop=0, lossless=True, method=4)
    data = {"name": label, "animation": kind, "fps": fps, "loop": loop,
            "durationMs": sum(f["duration"] for f in entries), "frameCount": 16,
            "width": CANVAS, "height": CANVAS, "columns": 4, "rows": 4,
            "spritesheet": "spritesheet.png", "preview": "preview.webp",
            "source": f"../{kind}-source.png", "sourceSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "generatedBy": "OpenAI built-in image_gen; sixteen painted source slots",
            "processing": "Source slot extraction, spatial registration and resampling only; no interpolation or synthetic poses. Burst core size registered per frame; death uses fixed original cell space.",
            "frames": entries}
    (folder / "animation.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return frames, data


def main():
    clips, summary = {}, {}
    for kind in SPECS:
        frames, data = save_clip(kind)
        clips[kind] = frames
        hashes = [hashlib.sha256(f.tobytes()).hexdigest() for f in frames]
        counts = [sum(v > 8 for v in f.getchannel("A").tobytes()) for f in frames]
        summary[kind] = {"frameCount": 16, "uniqueFrames": len(set(hashes)),
                         "durationMs": data["durationMs"], "loop": data["loop"],
                         "nontransparentPixelCounts": counts}
        assert len(set(hashes)) == 16, (kind, "duplicated poses")
        print(kind, summary[kind], flush=True)
    assert summary["death"]["nontransparentPixelCounts"][-1] == 0, "Death must end transparent"
    still = Image.open(DEST / "dormant-cyst.png").convert("RGBA")
    l, t, r, b = still.getchannel("A").getbbox()
    factor = 300 / (r - l)
    paint = still.resize((round(still.width * factor), round(still.height * factor)), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", (CANVAS, CANVAS))
    frame.alpha_composite(paint, (round(AX - (l + r) / 2 * factor), round(AY - b * factor)))
    frame.save(DEST / "dormant-preview.png")
    static = {"name": "休眠膜囊", "animation": "dormant", "loop": True,
              "width": CANVAS, "height": CANVAS, "frameCount": 1, "fps": 1,
              "spritesheet": "dormant-preview.png", "frames": [{"name": "休眠膜囊", "duration": 1000,
                "rect": {"x": 0, "y": 0, "w": CANVAS, "h": CANVAS},
                "anchor": {"x": AX / CANVAS, "y": AY / CANVAS}}]}
    (DEST / "dormant.json").write_text(json.dumps(static, ensure_ascii=False, indent=2) + "\n")
    manifest = {"character": "herpes_ambusher", "displayName": "疱疹病毒 · 埋伏兵", "portrait": "character.png"}
    manifest.update({label: f"{kind}/animation.json" for kind, (label, _, _) in SPECS.items()})
    manifest["休眠膜囊（静态）"] = "dormant.json"
    manifest["generation"] = "OpenAI built-in image_gen; six sets of sixteen poses and one dormant cyst illustration"
    manifest["runtimeIntegrated"] = False
    (DEST / "animations.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (DEST / "validation.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    # Six-panel animated review; each action plays then holds its last frame.
    # Movement repeats; a short hold at the cycle end makes death readable.
    order = list(SPECS)
    composites = []
    font_path = Path("/System/Library/Fonts/STHeiti Medium.ttc")
    font = ImageFont.truetype(str(font_path), 20) if font_path.exists() else None
    for tick in range(42):
        sheet = Image.new("RGB", (1140, 820), (242, 235, 244))
        draw = ImageDraw.Draw(sheet)
        for panel, kind in enumerate(order):
            x, y = panel % 3 * 380, panel // 3 * 410
            draw.rounded_rectangle((x + 8, y + 8, x + 372, y + 402), radius=18, fill=(255, 252, 255))
            title = f"{SPECS[kind][0]} · 16 帧" if font else f"{kind.upper()} / 16 FRAMES"
            draw.text((x + 24, y + 24), title, fill=(70, 34, 80), font=font)
            fps = SPECS[kind][1]
            idx = (int(tick / 16 * fps) % 16 if kind == "move" else min(15, int(tick / 16 * fps)))
            art = clips[kind][idx].resize((360, 360), Image.Resampling.LANCZOS)
            sheet.paste(art, (x + 10, y + 40), art)
        composites.append(sheet)
    composites[0].save(DEST / "six-actions-preview.webp", save_all=True, append_images=composites[1:],
                       duration=[62 if i % 2 == 0 else 63 for i in range(42)], loop=0, lossless=True, method=4)
    composites[9].save(DEST / "six-actions-overview.png")


if __name__ == "__main__":
    main()
