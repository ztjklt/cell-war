"""Deterministic NanoVG -> SVG/Cairo inspection backend (not a native GPU oracle).

Coordinates are logical pixels. Raster output applies DPR only at the final surface.
Image handles follow create/delete lifetime, while decoded files are cached by path.
NanoVG triangle anti-aliasing and filtering are only approximated by Cairo.
"""
from pathlib import Path
from dataclasses import dataclass
import base64
import html
import io
import math
import re

import cairosvg
from cairosvg import surface as svg_surface
from cairosvg import defs as svg_defs
from lupa.lua54 import LuaRuntime
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
l = LuaRuntime(unpack_returned_tuples=True)
l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
G = l.globals()
svg, path, defs, saved = [], [], [], []
fill, stroke, sw, fs, alpha, antialias, depth = '#ffffff', '#ffffff', 1, 12, 1, True, 0
line_cap, line_join = 'butt', 'miter'
image_handles, decoded_images, tinted_images, frame_images = {}, {}, {}, set()
image_flags, image_patterns = {}, {}
next_handle = 1
frame_size = (0, 0, 1)


class Color(str):
    def __new__(cls, r, g, b, a):
        rgba = tuple(max(0, min(255, float(v))) for v in (r, g, b, a))
        obj = str.__new__(cls, f'rgba({rgba[0]:.6f},{rgba[1]:.6f},{rgba[2]:.6f},{rgba[3]/255:.8f})')
        obj.rgba = rgba
        return obj


@dataclass
class Texture:
    key: str
    pixels: Image.Image
    surface: object
    encoded: str


def num(n):
    return f'{n:.6f}'


def color(r, g, b, a=255):
    return Color(r, g, b, a)


def reset():
    global fill, stroke, sw, fs, alpha, antialias, depth, line_cap, line_join
    svg.clear(); path.clear(); defs.clear(); saved.clear(); frame_images.clear(); image_patterns.clear()
    fill, stroke, sw, fs, alpha, antialias, depth = '#ffffff', '#ffffff', 1, 12, 1, True, 0
    line_cap, line_join = 'butt', 'miter'


def begin(*_):
    path.clear()


def command(cmd, args):
    path.append(cmd + ' '.join(num(x) for x in args))


def ellipse(_, x, y, rx, ry):
    path.append(f'M {num(x-rx)} {num(y)} a {num(rx)} {num(ry)} 0 1 0 {num(rx*2)} 0 a {num(rx)} {num(ry)} 0 1 0 {num(-rx*2)} 0 Z')


def arc(_, x, y, r, start, end, direction):
    for i in range(17):
        a = start + (end-start)*i/16
        command('M' if i == 0 and not path else 'L', (x+math.cos(a)*r, y+math.sin(a)*r))


def rect(_, x, y, w, h):
    path.append(f'M {num(x)} {num(y)} h {num(w)} v {num(h)} h {num(-w)} Z')


def setfill(_, c):
    global fill
    fill = c


def setstroke(_, c):
    global stroke
    stroke = c


def width(_, w):
    global sw
    sw = w


def font(_, size):
    global fs
    fs = size


def global_alpha(_, value):
    global alpha
    alpha = max(0, min(1, value))


def shape_antialias(_, value):
    global antialias
    antialias = bool(value)


def set_line_cap(_, value):
    global line_cap
    line_cap = 'round' if value == G.NVG_ROUND else 'butt' if value == 0 else 'square'


def set_line_join(_, value):
    global line_join
    line_join = 'round' if value == G.NVG_ROUND else 'miter'


def save(*_):
    saved.append((depth, fill, stroke, sw, fs, alpha, antialias, line_cap, line_join))


def transform(kind, *args):
    global depth
    svg.append(f'<g transform="{kind}('+','.join(num(x) for x in args)+')">')
    depth += 1


def restore(*_):
    global depth, fill, stroke, sw, fs, alpha, antialias, line_cap, line_join
    target, fill, stroke, sw, fs, alpha, antialias, line_cap, line_join = saved.pop()
    while depth > target:
        svg.append('</g>'); depth -= 1


def path_winding(_, winding):
    # All reference contours are outer rings or their nested holes. SVG evenodd
    # expresses this topology irrespective of contour vertex orientation.
    # Self-intersecting/overlapping solids are outside this inspection backend.
    if winding not in (G.NVG_SOLID, G.NVG_HOLE):
        raise ValueError(f'Unsupported path winding: {winding}')


def fill_path(*_):
    # crispEdges disables coverage AA for mesh interiors, but is not the native rasterizer.
    aa = '' if antialias else ' shape-rendering="crispEdges"'
    svg.append('<path d="'+' '.join(path)+f'" fill="{fill}" fill-rule="evenodd" opacity="{alpha}"{aa}/>')


def stroke_path(*_):
    svg.append('<path d="'+' '.join(path)+f'" fill="none" stroke="{stroke}" stroke-width="{num(sw)}" stroke-linecap="{line_cap}" stroke-linejoin="{line_join}" opacity="{alpha}"/>')


def gradient(kind, args):
    ident = f'g{len(defs)}'; a, b = args[-2:]
    if kind == 'linear':
        x1, y1, x2, y2 = args[:4]
        head = f'<linearGradient id="{ident}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
        stops = f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/>'
        tail = '</linearGradient>'
    else:
        x, y, inner, outer = args[:4]
        head = f'<radialGradient id="{ident}" gradientUnits="userSpaceOnUse" cx="{x}" cy="{y}" r="{outer}">'
        stops = f'<stop offset="{max(0,min(1,inner/max(outer,1e-8)))}" stop-color="{a}"/><stop offset="1" stop-color="{b}"/>'
        tail = '</radialGradient>'
    defs.append(head+stops+tail)
    return f'url(#{ident})'


def texture(key, pixels):
    data = io.BytesIO(); pixels.save(data, format='PNG'); raw = data.getvalue()
    return Texture(key, pixels, svg_surface.cairo.ImageSurface.create_from_png(io.BytesIO(raw)), base64.b64encode(raw).decode())


def create_image(_, resource, flags=0):
    global next_handle
    file = ROOT / 'assets' / resource
    if not file.is_file():
        return 0
    key = str(file.resolve())
    if key not in decoded_images:
        with Image.open(file) as im:
            decoded_images[key] = texture(f'body-source-{len(decoded_images)}', im.convert('RGBA'))
    ident = next_handle; next_handle += 1
    image_handles[ident] = decoded_images[key]
    image_flags[ident] = int(flags or 0)
    return ident


def delete_image(_, ident):
    image_handles.pop(ident, None)
    image_flags.pop(ident, None)


original_image_draw = svg_surface.TAGS['image']


def cached_image_draw(surface, node):
    tex = next((t for t in decoded_images.values() if t.key == node.get('id')), None)
    if tex is None:
        tex = next((t for t in tinted_images.values() if t.key == node.get('id')), None)
    if tex is None:
        return original_image_draw(surface, node)
    surface.context.set_source_surface(tex.surface, 0, 0)
    surface.context.paint_with_alpha(float(node.get('opacity', 1)))


svg_surface.TAGS['image'] = cached_image_draw
original_pattern_draw = svg_defs.draw_pattern


def native_surface_pattern(surface, node, name, opacity):
    """Sample the decoded image with an inverse affine; never rasterize at zoom size.

    CairoSVG's normal SVG pattern path creates a 26k/59k bitmap for near-view
    source images. A SurfacePattern keeps the original texture dimensions.
    Translucent paint uses a viewport-bounded group, preserving alpha semantics.
    """
    item = image_patterns.get(name)
    if item is None:
        return original_pattern_draw(surface, node, name, opacity)
    tex, x, y, w, h, angle, paint_alpha, flags = item
    if not w or not h:
        surface.context.set_source_rgba(0, 0, 0, 0)
        return True
    cairo = svg_surface.cairo
    co, si = math.cos(angle), math.sin(angle)
    sx, sy = w/tex.pixels.width, h/tex.pixels.height
    matrix = cairo.Matrix(co*sx, si*sx, -si*sy, co*sy, x, y)
    matrix.invert()
    pattern = cairo.SurfacePattern(tex.surface)
    repeat = flags & (G.NVG_IMAGE_REPEATX | G.NVG_IMAGE_REPEATY)
    pattern.set_extend(cairo.EXTEND_REPEAT if repeat else cairo.EXTEND_PAD)
    pattern.set_filter(cairo.FILTER_BILINEAR)
    pattern.set_matrix(matrix)
    context = surface.context
    combined_alpha = max(0, min(1, paint_alpha*opacity))
    if combined_alpha < 1:
        # Restrict temporary alpha compositing to this patch's bounds. A full
        # viewport group per atlas patch is bounded but needlessly expensive.
        # Use a padded rectangle, not the shape itself: clipping the shape here
        # would apply edge coverage twice when Cairo subsequently fills it.
        original_path = context.copy_path()
        x1, y1, x2, y2 = context.path_extents()
        ux, uy = context.device_to_user_distance(2, 2)
        padding = max(abs(ux), abs(uy), 1e-6)
        context.save()
        context.new_path()
        context.rectangle(x1-padding, y1-padding, x2-x1+2*padding, y2-y1+2*padding)
        context.clip()
        context.append_path(original_path)
        context.push_group()
        context.set_source(pattern)
        context.paint_with_alpha(combined_alpha)
        pattern = context.pop_group()
        context.restore()
    context.set_source(pattern)
    return True


svg_defs.draw_pattern = native_surface_pattern


def image_pattern(_, x, y, w, h, angle, ident, opacity, tint=None):
    tex = image_handles.get(ident)
    if tex is None:
        return 'rgba(0,0,0,0)'
    if tint and tint != (255, 255, 255):
        key = (tex.key, tint)
        if key not in tinted_images:
            pixels = ImageChops.multiply(tex.pixels, Image.new('RGBA', tex.pixels.size, (*(round(v) for v in tint), 255)))
            tinted_images[key] = texture(f'body-tinted-{len(tinted_images)}', pixels)
        tex = tinted_images[key]
    if tex.key not in frame_images:
        defs.append(f'<image id="{tex.key}" width="{tex.pixels.width}" height="{tex.pixels.height}" href="data:image/png;base64,{tex.encoded}"/>')
        frame_images.add(tex.key)
    key = f'i{len(defs)}'
    image_patterns[key] = (tex, x, y, w, h, angle, opacity, image_flags.get(ident, 0))
    # Keep exported SVG valid while the Cairo hook uses the cached native surface.
    transform_attr = f'translate({x} {y}) rotate({angle*180/math.pi}) scale({w/tex.pixels.width} {h/tex.pixels.height})'
    defs.append(f'<pattern id="{key}" patternUnits="userSpaceOnUse" width="{tex.pixels.width}" height="{tex.pixels.height}" patternTransform="{transform_attr}"><g opacity="{opacity}"><use href="#{tex.key}"/></g></pattern>')
    return f'url(#{key})'


def tinted_pattern(ctx, x, y, w, h, angle, ident, c):
    # UrhoX multiplies RGB and alpha: engine-docs/lua-scripting-guide.md § NanoVG.
    if hasattr(c, 'rgba'):
        r, g, b, a = c.rgba
    else:
        # Lua round-trips string subclasses as plain strings. Actual Cells.draw
        # passes its local nvgRGBA through this boundary, unlike direct Python QA.
        match = re.fullmatch(r'rgba\(([^)]+)\)', str(c))
        if not match: raise ValueError(f'Unsupported texture tint: {c}')
        r, g, b, opacity = map(float, match.group(1).split(','))
        a = opacity * 255
    return image_pattern(ctx, x, y, w, h, angle, ident, a/255, (r, g, b))


def scissor(_, x, y, w, h):
    global depth
    key = f'clip{len(defs)}'
    defs.append(f'<clipPath id="{key}"><rect x="{x}" y="{y}" width="{w}" height="{h}"/></clipPath>')
    svg.append(f'<g clip-path="url(#{key})">'); depth += 1


def begin_frame(_, w, h, dpr):
    global frame_size
    frame_size = (w, h, dpr)


def document(w, h):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs>'+''.join(defs)+'</defs>'+''.join(svg)+'</g>'*depth+'</svg>'


def png(w, h, dpr=1):
    return cairosvg.svg2png(bytestring=document(w, h).encode(), output_width=round(w*dpr), output_height=round(h*dpr))


functions = {
    'nvgArc': arc, 'nvgBeginPath': begin, 'nvgMoveTo': lambda _, *a: command('M', a),
    'nvgLineTo': lambda _, *a: command('L', a), 'nvgBezierTo': lambda _, *a: command('C', a),
    'nvgQuadTo': lambda _, *a: command('Q', a), 'nvgClosePath': lambda *_: path.append('Z'),
    'nvgRect': rect, 'nvgEllipse': ellipse, 'nvgCircle': lambda _, x, y, r: ellipse(_, x, y, r, r),
    'nvgRGBA': color, 'nvgRGBAf': lambda r,g,b,a: color(r*255,g*255,b*255,a*255), 'nvgFillColor': setfill, 'nvgFillPaint': setfill,
    'nvgStrokeColor': setstroke, 'nvgStrokePaint': setstroke, 'nvgStrokeWidth': width,
    'nvgLineCap': set_line_cap, 'nvgLineJoin': set_line_join,
    'nvgFill': fill_path, 'nvgStroke': stroke_path, 'nvgFontSize': font,
    'nvgText': lambda _, x, y, text, *a: svg.append(f'<text x="{x}" y="{y}" fill="{fill}" font-size="{fs}" font-family="sans-serif" text-anchor="middle" dominant-baseline="middle" opacity="{alpha}">{html.escape(str(text))}</text>'),
    'nvgSave': save, 'nvgRestore': restore, 'nvgTranslate': lambda _, x, y: transform('translate', x, y),
    'nvgScale': lambda _, x, y: transform('scale', x, y), 'nvgRotate': lambda _, angle: transform('rotate', angle*180/math.pi),
    'nvgTransform': lambda _, *a: transform('matrix', *a), 'nvgGlobalAlpha': global_alpha,
    'nvgShapeAntiAlias': shape_antialias, 'nvgBeginFrame': begin_frame, 'nvgPathWinding': path_winding,
    'nvgRadialGradient': lambda _, *a: gradient('radial', a), 'nvgLinearGradient': lambda _, *a: gradient('linear', a),
    'nvgCreateImage': create_image, 'nvgDeleteImage': delete_image,
    'nvgImageSize': lambda _, handle: image_handles[handle].pixels.size if handle in image_handles else (0, 0),
    'nvgImagePattern': image_pattern, 'nvgImagePatternTinted': tinted_pattern,
    'nvgIntersectScissor': scissor, 'nvgScissor': scissor,
}
for name, function in functions.items():
    G[name] = function
for name in ['nvgEndFrame', 'nvgFontFaceId', 'nvgTextAlign']:
    G[name] = lambda *_: None
for i, name in enumerate(['NVG_SOLID', 'NVG_HOLE', 'NVG_ROUND', 'NVG_ALIGN_CENTER', 'NVG_ALIGN_MIDDLE', 'NVG_IMAGE_GENERATE_MIPMAPS', 'NVG_IMAGE_REPEATX', 'NVG_IMAGE_REPEATY']):
    G[name] = 1 << i
