#!/usr/bin/env python3
"""Slice a generated grid into registered frames, an atlas and an animated preview.

This packages the original painted poses; it never interpolates or redraws them.
Requires Pillow. Original generation is preserved alongside the output.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image


def main_bounds(image):
    """Find the main opaque connected shape for a stable bottom-center pivot."""
    alpha = image.getchannel("A")
    width, height = image.size
    pixels = bytearray(value >= 128 for value in alpha.tobytes())
    largest, bounds = 0, None
    for origin in range(len(pixels)):
        if not pixels[origin]:
            continue
        pixels[origin] = 0
        queue = [origin]
        count = 0
        left, top, right, bottom = width, height, 0, 0
        while queue:
            point = queue.pop()
            x, y = point % width, point // width
            count += 1
            left, top = min(left, x), min(top, y)
            right, bottom = max(right, x + 1), max(bottom, y + 1)
            neighbors = []
            if x: neighbors.append(point - 1)
            if x + 1 < width: neighbors.append(point + 1)
            if y: neighbors.append(point - width)
            if y + 1 < height: neighbors.append(point + width)
            for neighbor in neighbors:
                if pixels[neighbor]:
                    pixels[neighbor] = 0
                    queue.append(neighbor)
        if count > largest:
            largest, bounds = count, (left, top, right, bottom)
    if bounds is None:
        raise ValueError("An animation cell has no opaque artwork")
    return bounds


def package(source, output, columns, rows, fps, name, canvas=320):
    output.mkdir(parents=True, exist_ok=False)
    original = Image.open(source).convert("RGBA")
    if original.getchannel("A").getextrema()[0] != 0:
        raise ValueError("Source needs a transparent background")
    shutil.copy2(source, output / "gpt-source-grid.png")
    frames, metadata = [], []
    anchor_x, anchor_y = canvas // 2, round(canvas * .85)
    for index in range(columns * rows):
        col, row = index % columns, index // columns
        box = (round(col * original.width / columns), round(row * original.height / rows),
               round((col + 1) * original.width / columns), round((row + 1) * original.height / rows))
        cell = original.crop(box)
        left, top, right, bottom = main_bounds(cell)
        # Four pixels retain the generated antialiased contour around the opaque body.
        crop_box = (max(0, left - 4), max(0, top - 4), min(cell.width, right + 4), min(cell.height, bottom + 4))
        painted = cell.crop(crop_box)
        offset = (round(anchor_x - (left + right) / 2 + crop_box[0]), anchor_y - bottom + crop_box[1])
        if min(offset) < 0 or offset[0] + painted.width > canvas or offset[1] + painted.height > canvas:
            raise ValueError("Canvas too small; increase --canvas rather than resizing the artwork")
        frame = Image.new("RGBA", (canvas, canvas))
        frame.paste(painted, offset)
        filename = f"frame-{index + 1:03}.png"
        frame.save(output / filename)
        duration = round((index + 1) * 1000 / fps) - round(index * 1000 / fps)
        frames.append(frame)
        metadata.append({"name": filename, "duration": duration,
                         "rect": {"x": col * canvas, "y": row * canvas, "w": canvas, "h": canvas},
                         "anchor": {"x": anchor_x / canvas, "y": anchor_y / canvas},
                         "sourceGridCell": list(box), "sourceBodyBounds": [left, top, right, bottom],
                         "registrationOffset": list(offset), "sourceFrame": index + 1})
    atlas = Image.new("RGBA", (columns * canvas, rows * canvas))
    for index, frame in enumerate(frames):
        atlas.paste(frame, ((index % columns) * canvas, (index // columns) * canvas))
    atlas.save(output / "spritesheet.png")
    frames[0].save(output / "preview.webp", save_all=True, append_images=frames[1:],
                   duration=[entry["duration"] for entry in metadata], loop=0, lossless=True, method=6)
    animation = {"name": name, "animation": "idle", "fps": fps, "loop": True,
                 "durationMs": sum(entry["duration"] for entry in metadata),
                 "frameCount": len(frames), "width": canvas, "height": canvas,
                 "columns": columns, "rows": rows, "spritesheet": "spritesheet.png", "preview": "preview.webp",
                 "generatedBy": "OpenAI built-in image generation; eighteen distinct painted source poses",
                 "processing": "Grid slicing, tight crop and bottom-center translation only; no resizing, interpolation or synthetic motion.",
                 "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(), "frames": metadata}
    (output / "animation.json").write_text(json.dumps(animation, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"frames": len(frames), "durationMs": animation["durationMs"], "atlas": str(output / "spritesheet.png"),
                      "preview": str(output / "preview.webp")}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--canvas", type=int, default=320)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    if min(args.columns, args.rows, args.fps, args.canvas) < 1:
        parser.error("Grid, frame rate and canvas must be positive")
    package(args.source, args.output, args.columns, args.rows, args.fps, args.name, args.canvas)
