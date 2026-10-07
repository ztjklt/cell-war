from pathlib import Path
from lupa.lua54 import LuaRuntime
import html,math,time,json
import cairosvg
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
G=l.globals();svg=[];path=[];fill='#ffffff';stroke='#ffffff';sw=1;fs=12;defs=[];stack=[]
def num(n):return f'{n:.3f}'
def color(r,g,b,a=255):return f'rgba({max(0,min(255,int(r)))},{max(0,min(255,int(g)))},{max(0,min(255,int(b)))},{a/255:.4f})'
def begin(*_):path.clear()
def command(cmd,args):path.append(cmd+' '.join(num(x) for x in args))
def ellipse(_,x,y,rx,ry):
 path.append(f'M {num(x-rx)} {num(y)} a {num(rx)} {num(ry)} 0 1 0 {num(rx*2)} 0 a {num(rx)} {num(ry)} 0 1 0 {num(-rx*2)} 0 Z')
def rect(_,x,y,w,h):path.append(f'M {num(x)} {num(y)} h {num(w)} v {num(h)} h {num(-w)} Z')
def setfill(_,c):
 global fill
 fill=c
 defnone=None

def setstroke(_,c):
 global stroke
 stroke=c

def width(_,w):
 global sw
 sw=w

def font(_,s):
 global fs
 fs=s

def save(*_):stack.append((fill,stroke,sw,fs));svg.append('<g>')
def restore(*_):
 global fill,stroke,sw,fs
 fill,stroke,sw,fs=stack.pop();svg.append('</g>')
def transform(kind,*args):svg.append(f'<g transform="{kind}('+','.join(num(x) for x in args)+')">');stack.append((fill,stroke,sw,fs))
# NanoVG transform modifies the current state; use transform attributes in a nested SVG group
# and close all groups belonging to the saved state on restore.
saved=[];depth=0
def save2(*_):
 global depth
 saved.append((depth,fill,stroke,sw,fs))
def transform2(kind,*args):
 global depth
 svg.append(f'<g transform="{kind}('+','.join(num(x) for x in args)+')">');depth+=1

def restore2(*_):
 global depth,fill,stroke,sw,fs
 target,fill,stroke,sw,fs=saved.pop()
 while depth>target:svg.append('</g>');depth-=1

def gradient(kind,args):
 ident=f'g{len(defs)}';a,b=args[-2:]
 if kind=='linear':x1,y1,x2,y2=args[:4];head=f'<linearGradient id="{ident}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">';tail='</linearGradient>'
 else:x,y,inner,outer=args[:4];head=f'<radialGradient id="{ident}" gradientUnits="userSpaceOnUse" cx="{x}" cy="{y}" r="{outer}">';tail='</radialGradient>'
 defs.append(head+f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/>'+tail);return f'url(#{ident})'
functions={
'nvgBeginPath':begin,'nvgMoveTo':lambda _,*a:command('M',a),'nvgLineTo':lambda _,*a:command('L',a),'nvgBezierTo':lambda _,*a:command('C',a),'nvgQuadTo':lambda _,*a:command('Q',a),'nvgClosePath':lambda *_:path.append('Z'),'nvgRect':rect,'nvgEllipse':ellipse,'nvgCircle':lambda _,x,y,r:ellipse(_,x,y,r,r),'nvgRGBA':color,'nvgFillColor':setfill,'nvgFillPaint':setfill,'nvgStrokeColor':setstroke,'nvgStrokePaint':setstroke,'nvgStrokeWidth':width,
'nvgFill':lambda *_:svg.append('<path d="'+' '.join(path)+f'" fill="{fill}" fill-rule="evenodd"/>'),'nvgStroke':lambda *_:svg.append('<path d="'+' '.join(path)+f'" fill="none" stroke="{stroke}" stroke-width="{num(sw)}" stroke-linecap="round" stroke-linejoin="round"/>'),
'nvgFontSize':font,'nvgText':lambda _,x,y,text,*a:svg.append(f'<text x="{x}" y="{y}" fill="{fill}" font-size="{fs}" font-family="sans-serif" text-anchor="middle" dominant-baseline="middle">{html.escape(str(text))}</text>'),
'nvgSave':save2,'nvgRestore':restore2,'nvgTranslate':lambda _,x,y:transform2('translate',x,y),'nvgScale':lambda _,x,y:transform2('scale',x,y),'nvgRotate':lambda _,angle:transform2('rotate',angle*180/math.pi),
'nvgRadialGradient':lambda _,*a:gradient('radial',a),'nvgLinearGradient':lambda _,*a:gradient('linear',a),'nvgCreateImage':lambda *_:0}
for n,f in functions.items():G[n]=f
for n in ['nvgBeginFrame','nvgEndFrame','nvgLineCap','nvgLineJoin','nvgPathWinding','nvgFontFaceId','nvgTextAlign','nvgIntersectScissor']:G[n]=lambda *_:None
for i,n in enumerate(['NVG_SOLID','NVG_HOLE','NVG_ROUND','NVG_ALIGN_CENTER','NVG_ALIGN_MIDDLE','NVG_IMAGE_GENERATE_MIPMAPS','NVG_IMAGE_REPEATX','NVG_IMAGE_REPEATY']):G[n]=1<<i
l.execute("state=require('war.World').generate(73);require('war.World').rebuild(state);R=require('war.Render');R.vg={};R.font=1;game={state=state,selection={},camera={x=1024,y=2048},zoom=.006,accumulator=0,realTime=0,fogDisabled=true,vesselSurvey=true};require('war.Render').prepare(state)")
targets=[('full',1280,1000,1024,2048,.0064),('chest',1280,800,1080,1430,.026),('abdomen',1280,800,1090,2260,.028),('heart',1000,800,1105,1400,.05),('wall',1000,800,1215,1670,.8),('phone',844,390,1024,2048,.00265),('portrait',430,932,1024,2048,.0058)]
report=[]
base_targets=targets
targets=[(name,w,h,x,y,z,dpr) for name,w,h,x,y,z in base_targets for dpr in ([1,2,3] if name in ['full','phone','portrait'] else [1])]
for name,w,h,x,y,z,dpr in targets:
 svg.clear();defs.clear();saved.clear();depth=0
 l.execute(f'graphics={{GetWidth=function() return {w*dpr} end,GetHeight=function() return {h*dpr} end,GetDPR=function() return {dpr} end}};game.camera={{x={x},y={y}}};game.zoom={z}')
 t=time.time();l.execute('R.draw(game)');elapsed=time.time()-t
 text='<svg xmlns="http://www.w3.org/2000/svg" width="'+str(w)+'" height="'+str(h)+'"><defs>'+''.join(defs)+'</defs>'+''.join(svg)+'</svg>'
 dest=Path('docs/previews/anatomy-v2')/f'{name}{"" if dpr==1 else "-dpr"+str(dpr)}.svg';dest.write_text(text)
 if dpr>1:assert text==dest.with_name(name+'.svg').read_text(),'DPR changes logical geometry'
 cairosvg.svg2png(bytestring=text.encode(),write_to=str(dest.with_suffix('.png')))
 report.append({'view':name,'logicalSize':[w,h],'dpr':dpr,'zoom':z,'svgElements':len(svg),'pythonBridgeSeconds':round(elapsed,5),'native':False,'image2Loaded':False})
Path('docs/anatomy-v2-offline-render-results.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
