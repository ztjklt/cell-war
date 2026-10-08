from pathlib import Path
from lupa.lua54 import LuaRuntime
import html,math,time,json,sys,hashlib
import cairosvg
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
G=l.globals();svg=[];path=[];fill='#ffffff';stroke='#ffffff';sw=1;fs=12;defs=[];stack=[]
def num(n):return f'{n:.3f}'
def color(r,g,b,a=255):return f'rgba({max(0,min(255,int(r)))},{max(0,min(255,int(g)))},{max(0,min(255,int(b)))},{a/255:.4f})'
def begin(*_):path.clear()
def command(cmd,args):path.append(cmd+' '.join(num(x) for x in args))
def ellipse(_,x,y,rx,ry):
 path.append(f'M {num(x-rx)} {num(y)} a {num(rx)} {num(ry)} 0 1 0 {num(rx*2)} 0 a {num(rx)} {num(ry)} 0 1 0 {num(-rx*2)} 0 Z')
def arc(_,x,y,r,start,end,direction):
 for i in range(17):
  a=start+(end-start)*i/16
  command('M' if i==0 and not path else 'L',(x+math.cos(a)*r,y+math.sin(a)*r))
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
'nvgArc':arc,'nvgBeginPath':begin,'nvgMoveTo':lambda _,*a:command('M',a),'nvgLineTo':lambda _,*a:command('L',a),'nvgBezierTo':lambda _,*a:command('C',a),'nvgQuadTo':lambda _,*a:command('Q',a),'nvgClosePath':lambda *_:path.append('Z'),'nvgRect':rect,'nvgEllipse':ellipse,'nvgCircle':lambda _,x,y,r:ellipse(_,x,y,r,r),'nvgRGBA':color,'nvgFillColor':setfill,'nvgFillPaint':setfill,'nvgStrokeColor':setstroke,'nvgStrokePaint':setstroke,'nvgStrokeWidth':width,
'nvgFill':lambda *_:svg.append('<path d="'+' '.join(path)+f'" fill="{fill}" fill-rule="evenodd"/>'),'nvgStroke':lambda *_:svg.append('<path d="'+' '.join(path)+f'" fill="none" stroke="{stroke}" stroke-width="{num(sw)}" stroke-linecap="round" stroke-linejoin="round"/>'),
'nvgFontSize':font,'nvgText':lambda _,x,y,text,*a:svg.append(f'<text x="{x}" y="{y}" fill="{fill}" font-size="{fs}" font-family="sans-serif" text-anchor="middle" dominant-baseline="middle">{html.escape(str(text))}</text>'),
'nvgSave':save2,'nvgRestore':restore2,'nvgTranslate':lambda _,x,y:transform2('translate',x,y),'nvgScale':lambda _,x,y:transform2('scale',x,y),'nvgRotate':lambda _,angle:transform2('rotate',angle*180/math.pi),
'nvgRadialGradient':lambda _,*a:gradient('radial',a),'nvgLinearGradient':lambda _,*a:gradient('linear',a),'nvgCreateImage':lambda _,path,*a:1 if path=='image/anatomy-reference/reference.png' else 0}
for n,f in functions.items():G[n]=f
for n in ['nvgBeginFrame','nvgEndFrame','nvgLineCap','nvgLineJoin','nvgPathWinding','nvgFontFaceId','nvgTextAlign','nvgIntersectScissor']:G[n]=lambda *_:None
for i,n in enumerate(['NVG_SOLID','NVG_HOLE','NVG_ROUND','NVG_ALIGN_CENTER','NVG_ALIGN_MIDDLE','NVG_IMAGE_GENERATE_MIPMAPS','NVG_IMAGE_REPEATX','NVG_IMAGE_REPEATY']):G[n]=1<<i

# This backend evaluates the actual Lua renderer; PNG delivery and native GPU work differ.
import base64
source_png=Path('assets/image/anatomy-reference/reference.png').read_bytes()
encoded=base64.b64encode(source_png).decode()
def image_pattern(_,x,y,w,h,angle,ident,alpha):
    key=f'i{len(defs)}'
    defs.append(f'<pattern id="{key}" patternUnits="userSpaceOnUse" x="{x}" y="{y}" width="{w}" height="{h}"><image x="0" y="0" width="{w}" height="{h}" opacity="{alpha}" href="data:image/png;base64,{encoded}"/></pattern>')
    return f'url(#{key})'
G['nvgImagePattern']=image_pattern
G['nvgDeleteImage']=lambda *_:None
# Clip native scissor commands, including minimap rectangles.
def scissor(_,x,y,w,h):
    global depth
    key=f'clip{len(defs)}'
    defs.append(f'<clipPath id="{key}"><rect x="{x}" y="{y}" width="{w}" height="{h}"/></clipPath>')
    svg.append(f'<g clip-path="url(#{key})">');depth+=1
G['nvgIntersectScissor']=scissor
l.execute("state=require('war.World').generate(73);require('war.World').rebuild(state);R=require('war.Render');R.vg={};R.font=1;game={state=state,selection={},camera={x=1024,y=2048},zoom=.0074,accumulator=0,realTime=0,started=true,fogDisabled=false,vesselSurvey=false};R.prepare(state)")
# World-space cameras follow the specified source x*2, y*2+512 transform.
targets=[('full',1280,1000,1024,2048,.0074),('chest',1280,900,1024,1252,.032),('abdomen',1280,900,1024,1832,.038),('arms',1280,850,500,1760,.042),('legs',1100,900,1024,2880,.021),('hand',1000,800,460,2182,.14),('foot',1000,800,736,3412,.14),('brain-detail',1100,800,970,682,.6),('marrow-detail',1100,800,812,2672,.6),('heart-detail',1100,800,1040,1352,.6),('lung-detail',1100,800,852,1292,.6),('liver-detail',1100,800,900,1592,.6),('gut-detail',1100,800,1004,1942,.6),('kidney-detail',1100,800,826,1792,.6),('max-detail',1100,800,1004,1942,2.8),('trachea-max',1100,800,1023,1050,2.8),('phone',844,390,1024,2048,.003),('portrait',430,932,1024,2048,.006)]
report=[];canonical={}
for name,w,h,x,y,z in targets:
 for dpr in ([1,2,3] if name in ['full','phone','portrait','max-detail'] else [1]):
  svg.clear();defs.clear();saved.clear();depth=0
  l.execute(f"graphics={{GetWidth=function() return {w*dpr} end,GetHeight=function() return {h*dpr} end,GetDPR=function() return {dpr} end}};game.camera={{x={x},y={y}}};game.zoom={z}")
  t=time.time();l.execute('R.draw(game)');elapsed=time.time()-t
  while depth>0:svg.append('</g>');depth-=1
  xml='<svg xmlns="http://www.w3.org/2000/svg" width="'+str(w)+'" height="'+str(h)+'"><defs>'+''.join(defs)+'</defs>'+''.join(svg)+'</svg>'
  dest=Path('docs/previews/reference-map')/f'{name}{"" if dpr==1 else "-dpr"+str(dpr)}.svg';dest.parent.mkdir(parents=True,exist_ok=True)
  if '--svg' in sys.argv:dest.write_text(xml)
  if dpr>1:assert xml==canonical[name],'DPR changes logical geometry'
  else:canonical[name]=xml
  if dpr==1:cairosvg.svg2png(bytestring=xml.encode(),write_to=str(dest.with_suffix('.png')))
  stat=l.eval("require('war.ReferenceArt').last")
  report.append({'view':name,'logicalSize':[w,h],'dpr':dpr,'zoom':z,'regions':stat.regions,'details':stat.details,'svgElements':len(svg),'bridgeSeconds':round(elapsed,5),'native':False,'geometrySha256':hashlib.sha256(xml.encode()).hexdigest()})
  print(name,dpr,stat.regions,stat.details,round(elapsed,3),flush=True)
# Render playable trachea overview and the same whole-body atlas during the campaign.
l.execute("game.state=require('war.Simulation').new(73);R.prepare(game.state)")
for name,w,h in [('trachea',1280,900),('trachea-phone',430,932),('trachea-landscape',844,390),('trachea-home',1280,900),('trachea-home-phone',430,932),('campaign-body',1280,1000)]:
 svg.clear();defs.clear();saved.clear();depth=0
 l.execute(f"graphics={{GetWidth=function() return {w} end,GetHeight=function() return {h} end,GetDPR=function() return 1 end}};R.w={w};R.h={h}")
 if name=='campaign-body':l.execute('game.camera={x=1024,y=2048};game.zoom=.0074')
 elif 'home' in name:l.execute('R.home(game)')
 else:l.execute('R.nasalOverview(game)')
 l.execute('R.draw(game)')
 while depth>0:svg.append('</g>');depth-=1
 xml=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}"><defs>'+''.join(defs)+'</defs>'+''.join(svg)+'</svg>'
 dest=Path('docs/previews/reference-map')/f'{name}.svg';
 if '--svg' in sys.argv:dest.write_text(xml)
 cairosvg.svg2png(bytestring=xml.encode(),write_to=str(dest.with_suffix('.png')))
Path('docs/reference-map-render-results.json').write_text(json.dumps(report,indent=2))
# Overlay authored geometry on the unmodified source to expose registration mistakes.
M=l.eval("require('war.ReferenceMap')");net=l.eval("require('war.Vessels').forDisplay(state)");Gair=l.eval("require('war.TracheaTerrain').airways")
def line_points(points):
 return ' '.join(f'{p[1]/2:.2f},{(p[2]-512)/2:.2f}' for p in points.values())
overlay=[f'<image width="1024" height="1536" href="data:image/png;base64,{encoded}"/>']
overlay.append(f'<polygon points="{line_points(M.outline)}" fill="none" stroke="#95501b" stroke-width="1"/>')
for organ in M.organs.values():
 overlay.append(f'<polygon points="{line_points(organ.points)}" fill="none" stroke="#2e958e" stroke-width="1" opacity=".75"/>')
for edge in net.edges.values():
 if edge.hidden:continue
 c='#126cb8' if edge.system=='vein' else '#a32b31' if edge.system=='artery' else '#9d6227'
 overlay.append(f'<polyline points="{line_points(edge.points)}" fill="none" stroke="{c}" stroke-width="1" opacity=".85"/>')
for branch in Gair.values():
 overlay.append(f'<polyline points="{line_points(branch.points)}" fill="none" stroke="#f9f2bc" stroke-width="1" opacity=".9"/>')
xml='<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1536">'+''.join(overlay)+'</svg>'
dest=Path('docs/previews/reference-map/source-overlay.svg')
if '--svg' in sys.argv:dest.write_text(xml)
cairosvg.svg2png(bytestring=xml.encode(),write_to=str(dest.with_suffix('.png')))
