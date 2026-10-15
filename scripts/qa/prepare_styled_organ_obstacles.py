"""Bake reviewed raised-prop footprints into radius-aware organ navigation.

These semantic annotations refer to the approved standalone previews (normalised
image coordinates). Pink floor mottling and painted shadows are NOT obstacles.
No artwork is edited. The overlay makes every annotation reviewable.
"""
from pathlib import Path
import sys,json,hashlib,math,copy
sys.path.insert(0,str(Path(__file__).parent))
from check_gastric_battlefield import runtime,convert
from prepare_organ_battlefield_runtime import grid
from prepare_vessel_channels_runtime import rings,lua
from shapely.geometry import Point,Polygon
from shapely.affinity import scale
from shapely.ops import unary_union,nearest_points
import cairosvg
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/styled-organ-obstacles-20261015'
ART=ROOT/'assets/image/anatomy-reference/organ-style-20261015'

# Ellipses describe the solid base of a single prop or tightly packed cluster;
# C-shaped brain props use concave polygons to retain their open courtyards.
ELLIPSES={
 'kidney_r':[(.70,.20,.135,.066),(.44,.325,.13,.075),(.275,.55,.105,.066),(.68,.685,.115,.060),(.43,.815,.125,.068)],
 'kidney_l':[(.43,.19,.11,.070),(.285,.32,.105,.068),(.64,.32,.125,.072),(.735,.475,.12,.055),(.79,.592,.105,.072),(.43,.75,.13,.071)],
 'pancreas':[(.095,.51,.043,.082),(.15,.735,.06,.11),(.185,.29,.06,.12),(.296,.206,.020,.029),(.317,.177,.014,.027),(.345,.316,.036,.061),(.318,.383,.013,.027),(.257,.608,.017,.025),(.273,.654,.012,.022),(.249,.823,.015,.024),(.231,.86,.012,.022),(.425,.283,.035,.068),(.49,.402,.05,.090),(.606,.433,.036,.07),(.445,.65,.04,.084),(.503,.68,.018,.034),(.482,.735,.014,.026),(.73,.536,.04,.07),(.782,.563,.018,.031),(.758,.610,.015,.024),(.812,.361,.036,.065)],
 'brain':[(.25,.274,.036,.047),(.433,.467,.036,.048),(.682,.465,.036,.047),(.22,.648,.033,.044),(.385,.187,.013,.019),(.426,.279,.013,.018),(.228,.354,.014,.019),(.321,.397,.010,.016),(.383,.632,.013,.017),(.367,.731,.014,.020),(.588,.56,.015,.021),(.807,.516,.011,.019)],
 'lung_r':[(.822,.128,.086,.082),(.552,.172,.083,.047),(.379,.271,.064,.046),(.894,.315,.076,.038),(.502,.506,.081,.041),(.20,.531,.075,.052),(.19,.768,.081,.045),(.704,.815,.095,.058),(.256,.899,.113,.045),(.681,.151,.023,.014),(.603,.229,.020,.014),(.92,.239,.023,.014),(.879,.36,.021,.014),(.832,.599,.042,.025),(.17,.68,.035,.024),(.436,.827,.040,.026),(.321,.411,.038,.020)],
 'lung_l':[(.244,.105,.091,.063),(.52,.17,.102,.049),(.14,.267,.066,.059),(.676,.258,.066,.037),(.841,.469,.067,.040),(.302,.606,.067,.048),(.502,.786,.086,.034),(.865,.748,.05,.041),(.79,.883,.108,.050)],
 'liver':[(.354,.248,.033,.050),(.389,.184,.038,.047),(.457,.15,.042,.045),(.515,.195,.037,.05),(.550,.272,.035,.050),(.321,.478,.068,.095),(.133,.624,.035,.043),(.19,.584,.037,.044),(.117,.703,.033,.048),(.145,.773,.034,.044),(.215,.792,.043,.047),(.42,.632,.026,.035),(.449,.68,.023,.036),(.386,.768,.030,.037),(.349,.725,.026,.035),(.359,.664,.025,.033)],
 'stomach':[(.541,.206,.034,.048),(.563,.438,.035,.048),(.853,.335,.041,.059),(.868,.578,.038,.048),(.61,.831,.052,.064)],
 'small_intestine':[(.132,.28,.060,.078),(.182,.245,.026,.035),(.147,.187,.018,.021),(.474,.267,.074,.049),(.603,.279,.032,.039),(.738,.282,.082,.082),(.913,.206,.017,.023),(.126,.399,.018,.023),(.402,.465,.112,.063),(.593,.477,.036,.045),(.862,.524,.017,.027),(.241,.645,.068,.058),(.338,.665,.017,.022),(.663,.677,.092,.068),(.418,.88,.083,.058),(.329,.825,.017,.022),(.533,.89,.026,.043)],
 'large_intestine':[(.13,.252,.035,.039),(.168,.217,.030,.033),(.64,.187,.031,.032),(.688,.148,.034,.036),(.733,.12,.029,.032),(.777,.308,.066,.067),(.505,.331,.057,.034),(.277,.309,.052,.027),(.151,.445,.035,.055),(.086,.6,.042,.066),(.197,.845,.036,.042),(.238,.88,.036,.039),(.291,.865,.036,.045),(.682,.884,.037,.038),(.776,.836,.036,.036),(.814,.804,.031,.034),(.879,.649,.054,.062),(.86,.494,.035,.051)],
 'bladder':[(.214,.269,.060,.068),(.4,.145,.079,.071),(.865,.397,.063,.074)],
 'heart':[], # Existing four-cavity/valve geometry remains authoritative.
}
POLYGONS={'brain':[
 [[.263,.174],[.321,.163],[.371,.229],[.383,.284],[.356,.355],[.321,.38],[.269,.365],[.263,.329],[.306,.312],[.319,.274],[.300,.225],[.264,.215]],
 [[.455,.365],[.505,.380],[.553,.437],[.561,.493],[.541,.551],[.499,.586],[.454,.581],[.446,.545],[.493,.53],[.507,.484],[.492,.435],[.447,.407]],
 [[.685,.367],[.733,.370],[.785,.422],[.800,.473],[.782,.534],[.749,.574],[.694,.579],[.687,.548],[.731,.525],[.746,.478],[.725,.429],[.684,.405]],
 [[.239,.558],[.288,.556],[.332,.609],[.350,.669],[.329,.728],[.293,.759],[.246,.758],[.242,.721],[.284,.704],[.295,.655],[.277,.61],[.236,.594]],
]}

def shape(rs):return unary_union([Polygon(q['outer'],q.get('holes')or[])for q in rs])
def main():
 DOC.mkdir(exist_ok=True)
 baseline=DOC/'baseline.json'
 if not baseline.exists():
  l=runtime();data=convert(l.execute("local O=require('war.OrganBattlefield');local s=require('war.FullBodyBattlefield').new(73);local out={};for _,id in ipairs(O.activeOrgans(s))do out[id]=O.organ(id)end;return out"))
  baseline.write_text(json.dumps(data,separators=(',',':')))
 data=json.loads(baseline.read_text());manifest=json.loads((ART/'manifest.json').read_text());source={q['id']:q for q in json.loads((ROOT/'docs/organ-style-20261015/source-manifest.json').read_text())['organs']}
 out={};annotations=[];report=[]
 for m in manifest['organs']:
  oid=m['id'];d=data[oid];b=m['sourceBox'];x,y,x1,y1=b;w,h=x1-x,y1-y
  pieces=[]
  for cx,cy,rx,ry in ELLIPSES[oid]:pieces.append(scale(Point(x+cx*w,y+cy*h).buffer(1,quad_segs=10),rx*w,ry*h))
  for ps in POLYGONS.get(oid,[]):pieces.append(Polygon([(x+u*w,y+v*h)for u,v in ps]))
  obstacles=unary_union(pieces).intersection(shape(d['outerRings'])).buffer(0)
  profiles={};stats={}
  for kind,radius in [('scout',.21875),('siege',.53125)]:
   old=d['grids'][kind];floor=shape(old['safeRings']);safe=floor.difference(obstacles.buffer(radius+.025,quad_segs=6)).buffer(0)
   step=.125 if oid=='small_intestine'and kind=='scout'else .25 if oid in ('brain','small_intestine','large_intestine')else old['step']
   profiles[kind]=grid(rings(safe),d['sourceBox'],step);profiles[kind]['radiusSource']=radius
   stats[kind]=dict(beforeArea=floor.area,afterArea=safe.area,valid=profiles[kind]['validGridPoints'])
  rooms=copy.deepcopy(d['rooms'])
  safe=shape(profiles['siege']['safeRings']).buffer(-.08)
  for room in rooms:
   for key in ['centerSource','approachSource','rallySource','doorSource']:
    if room.get(key)and not safe.covers(Point(room[key])):
     p=nearest_points(safe,Point(room[key]))[0];room[key]=[p.x,p.y]
  raw=rings(obstacles)
  out[oid]=dict(grids=profiles,rooms=rooms,obstacleRings=raw)
  annotations.append(dict(id=oid,sourceBox=b,obstacleRings=raw))
  # QA overlay only: approved vector artwork plus transparent collision outlines.
  import xml.etree.ElementTree as ET
  tree=ET.parse(ART/m['registeredVector']).getroot();body=''.join(ET.tostring(q,encoding='unicode')for q in tree)
  def path(p):return'M '+' L '.join(f'{a:.4f},{v:.4f}'for a,v in p)+' Z'
  overlay=''.join(f'<path d="{path(q["outer"])}" fill="#754dde" fill-opacity=".28" stroke="#5431af" stroke-width=".18"/>'for q in raw)
  svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x} {y} {w} {h}" width="{w*8}" height="{h*8}">{body}{overlay}</svg>'
  (DOC/(oid+'-overlay.svg')).write_text(svg)
  cairosvg.svg2png(bytestring=svg.encode(),write_to=str(DOC/(oid+'-overlay.png')))
  report.append(dict(organ=oid,annotatedProps=len(pieces),components=len(raw),profiles=stats))
 record=dict(version=1,organs=out,artSha256=hashlib.sha256((ART/'organs-styled.svg').read_bytes()).hexdigest())
 (ROOT/'scripts/war/StyledOrganObstaclesData.lua').write_text('-- Baked reviewed prop footprints; generated by prepare_styled_organ_obstacles.py.\nreturn '+lua(record)+'\n')
 (DOC/'obstacles.json').write_text(json.dumps(annotations,separators=(',',':')))
 (DOC/'geometry-checks.json').write_text(json.dumps(dict(organs=report,annotatedProps=sum(q['annotatedProps']for q in report),annotationMethod='vision-reviewed solid prop bases; floor texture excluded; approximate conservative footprints',nativeEvidence=False),indent=2)+'\n')
 print(json.dumps(report),flush=True)
if __name__=='__main__':main()
