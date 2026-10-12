"""Author quiet, source-derived curved fills without changing gameplay geometry.

Offline dependencies: vtracer==0.6.12, numpy, OpenCV, scipy. Runtime uses only the generated Lua curves.
Keep ReferenceTrace (silhouette and vessel visibility) and the source PNG untouched.
"""
from pathlib import Path
import hashlib, json, re, xml.etree.ElementTree as ET
import vtracer
import numpy as np
import cv2
from scipy.ndimage import gaussian_filter1d

ROOT = Path(__file__).resolve().parents[2]
source = ROOT / 'assets/image/anatomy-reference/reference.png'
settings = dict(img_format='png', colormode='color', hierarchical='stacked',
                mode='spline', filter_speckle=10, color_precision=7,
                layer_difference=12, corner_threshold=90, length_threshold=6,
                max_iterations=10, splice_threshold=45, path_precision=2)
svg = vtracer.convert_raw_image_to_svg(source.read_bytes(), **settings)
def smooth_path(commands):
    # Sample splines in source pixels, then remove staircase noise without inventing
    # organ features. All preprocessing happens once, outside the game runtime.
    points=[]; last=None
    for q in commands:
        op=q[0]; args=np.asarray(q[1:],float).reshape(-1,2)
        if op==0: last=args[0]; points.append(last); continue
        length=sum(np.linalg.norm(b-a) for a,b in zip([last,*args],args))
        for t in np.linspace(0,1,max(2,int(length/.4)+1))[1:]:
            v=(1-t)*last+t*args[0] if op==1 else (1-t)**3*last+3*(1-t)**2*t*args[0]+3*(1-t)*t*t*args[1]+t**3*args[2]
            points.append(v)
        last=args[-1]
    p=np.asarray(points)
    if np.linalg.norm(p[0]-p[-1])<.001: p=p[:-1]
    lengths=np.linalg.norm(np.roll(p,-1,axis=0)-p,axis=1)
    distances=np.r_[0,np.cumsum(lengths)]
    sample=np.linspace(0,distances[-1],max(8,int(distances[-1]/.4)),endpoint=False)
    closed=np.vstack([p,p[0]])
    even=np.column_stack([np.interp(sample,distances,closed[:,axis]) for axis in (0,1)])
    smooth=gaussian_filter1d(even,1.25,axis=0,mode='wrap')
    result=cv2.approxPolyDP(smooth.astype(np.float32),.15,True).reshape(-1,2)
    return [[round(float(x),2),round(float(y),2)] for x,y in result]

regions = []
for element in ET.fromstring(svg):
    if not element.tag.endswith('path'): continue
    tx, ty = map(float, re.findall(r'-?\d+(?:\.\d+)?', element.attrib['transform']))
    color = [int(element.attrib['fill'][i:i+2], 16) for i in (1, 3, 5)]
    # Omit the full-canvas paper layer; world/UI already supplies the white backdrop.
    if min(color) > 245: continue
    tokens = re.findall(r'[MCZL]|-?\d+(?:\.\d+)?', element.attrib['d'])
    paths, commands, endpoints, bounds = [], [], [], []
    i = 0
    while i < len(tokens):
        command = tokens[i]; i += 1
        n = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}[command]
        args = [round(float(tokens[i+j]) + (tx if j % 2 == 0 else ty), 2) for j in range(n)]
        i += n
        if command == 'Z':
            area = sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(endpoints, endpoints[1:]+endpoints[:1]))
            paths.append(dict(commands=commands, area=area)); commands=[]; endpoints=[]
            continue
        bounds.extend(zip(args[::2], args[1::2]))
        endpoints.append(args[-2:])
        # Store command opcodes as numbers: move=0, line=1, cubic=2.
        commands.append([{'M':0, 'L':1, 'C':2}[command], *args])
    assert paths and not commands
    # Nonzero SVG winding: opposite-direction child contours are holes.
    direction = max(paths, key=lambda p: abs(p['area']))['area']
    for p in paths:
        p['hole'] = p.pop('area')*direction < 0
        p['points'] = smooth_path(p.pop('commands'))
    xs, ys = zip(*bounds)
    regions.append(dict(color=color, paths=paths, x1=min(xs), y1=min(ys), x2=max(xs), y2=max(ys)))

def lua(value):
    if isinstance(value, bool): return 'true' if value else 'false'
    if isinstance(value, list): return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value, dict): return '{'+','.join(k+'='+lua(v) for k,v in value.items())+'}'
    return f'{value:g}'

result = '-- Source-derived display curves; regenerate with scripts/qa/prepare_reference_fill.py.\nreturn '+lua(dict(regions=regions))+'\n'
output = ROOT/'scripts/war/ReferenceFill.lua'
output.write_text(result)
report = dict(sourceSha256=hashlib.sha256(source.read_bytes()).hexdigest(), generator='vtracer 0.6.12', settings=settings,
              regions=len(regions), points=sum(len(p['points']) for r in regions for p in r['paths']), smoothingSourcePixels=.5, approximationSourcePixels=.15,
              bytes=len(result), dataSha256=hashlib.sha256(output.read_bytes()).hexdigest(), gameplayTraceChanged=False)
folder=ROOT/'docs/body-life/practical-fill'; folder.mkdir(parents=True,exist_ok=True)
(folder/'authoring.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
