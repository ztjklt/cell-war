"""Reproduce the reference's vector colour regions and silhouette, without editing its PNG.

Offline authoring dependency: Pillow, numpy, opencv-python-headless. Runtime uses Lua only.
"""
from pathlib import Path
import json
import cv2
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[2]
source = root / 'assets/image/anatomy-reference/reference.png'
image = Image.open(source).convert('RGB')
assert image.size == (1024, 1536)
rgb = np.asarray(image)
mask = ((rgb.max(2).astype(int) - rgb.min(2).astype(int) > 25) & (rgb.min(2) < 220)).astype('uint8') * 255
contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
body = max(contours, key=cv2.contourArea)
silhouette = np.zeros(mask.shape, dtype='uint8')
cv2.drawContours(silhouette, [body], -1, 255, cv2.FILLED)

def points(contour, error=.55):
    return cv2.approxPolyDP(contour, error, True).reshape(-1, 2).tolist()

def lua(value):
    if isinstance(value, list): return '{' + ','.join(lua(x) for x in value) + '}'
    if isinstance(value, dict): return '{' + ','.join(k+'='+lua(v) for k,v in value.items()) + '}'
    return str(value)

# Median-cut colours retain the source's exact warm palette and drawn structures.
quantized = image.quantize(colors=48, dither=Image.Dither.NONE)
indexed = np.asarray(quantized)
palette = np.array(quantized.getpalette()).reshape(-1, 3)
regions = []
for index, color in enumerate(palette[:48]):
    layer = ((indexed == index) & (silhouette > 0)).astype('uint8') * 255
    paths, hierarchy = cv2.findContours(layer, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    if hierarchy is None: continue
    for i, contour in enumerate(paths):
        if hierarchy[0][i][3] != -1 or cv2.contourArea(contour) < 2: continue
        outer = points(contour)
        if len(outer) < 3: continue
        holes = []
        child = hierarchy[0][i][2]
        while child != -1:
            p = points(paths[child])
            if len(p) >= 3: holes.append(p)
            child = hierarchy[0][child][0]
        x,y,w,h = cv2.boundingRect(contour)
        regions.append(dict(color=color.tolist(), points=outer, holes=holes, x1=x,y1=y,x2=x+w,y2=y+h))
data = '-- Generated from the unchanged reference.png; run scripts/qa/trace_reference.py to reproduce.\nreturn ' + lua(dict(outline=points(body), regions=regions)) + '\n'
(root / 'scripts/war/ReferenceTrace.lua').write_text(data)
print(json.dumps(dict(regions=len(regions), outlinePoints=len(points(body)), bytes=len(data))))
