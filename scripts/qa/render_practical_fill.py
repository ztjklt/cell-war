"""Inspect actual Lua map fills together with actual game units, in fixed scenarios.

--baseline loads the saved pre-change ReferenceArt only, never restores workspace files.
Output is offline NanoVG/SVG/Cairo evidence, not native GPU frame-time evidence.
"""
from pathlib import Path
import argparse, json, hashlib
import render_body_life as r

SCENARIOS=[('brain','脑沟回',512,72),('lung','肺与支气管',450,368),
           ('heart','心肌与血管',516,416),('liver','肝与胆囊',455,528),
           ('stomach','胃壁',565,530),('intestine','肠袢',507,697),
           ('kidney','肾与连接处',420,615),('muscle','腿部肌肉',410,884),
           ('trachea','气管作战区',509,242)]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',action='store_true');parser.add_argument('--output',required=True)
    parser.add_argument('--zooms',default='.15,.4,.9,2.8');args=parser.parse_args()
    out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
    b=r.b
    if args.baseline:
        b.l.execute("package.loaded['war.ReferenceArt']=assert(loadfile('docs/body-life/practical-fill/baseline/ReferenceArt.lua'))()")
    r.initialise()
    b.l.execute("require('war.Cells').init(R.vg);game.fogDisabled=true;game.flowTime=.6;C=require('war.Commands');U=require('war.Util')")
    records=[]
    for ident,label,sx,sy in SCENARIOS:
        for zoom in map(float,args.zooms.split(',')):
            w,h=800,540; cy=sy*2+512-.03*h/(32*zoom)
            b.l.execute(f"game.camera={{x={sx*2},y={cy}}};game.zoom={zoom};game.realTime=1.92;state.entities={{}};state.nextId=1;game.contactKey=nil;state.resources={{}};game.selection={{}};state.factions[1].visible={{}};state.factions[1].seen={{}};require('war.World').rebuild(state)")
            b.l.execute(f"""
            local kinds={{'scout','spear','archer','heavy','worker','virus'}}
            for row=-1,1 do for col=-2,2 do
              local kind=kinds[(row+1)*5+col+3];kind=kind or kinds[(col+2)%6+1]
              local e=C.spawn(state,'unit',kind,kind=='virus' and 2 or 1,{sx*2}+col*95/(32*{zoom}),{sy*2+512}+row*95/(32*{zoom}),true)
              if e then
                state.factions[1].visible[U.key(e.x,e.y)]=true
                state.factions[1].seen[U.key(e.x,e.y)]=true
                if e.faction==1 and col==0 then game.selection[e.id]=true;e.hp=e.maxHp*.65 end
              end
            end end
            game.marker={{x={sx*2}+150/(32*{zoom}),y={sy*2+512}+150/(32*{zoom}),born=1.65,kind='move'}}
            """)
            b.reset();b.l.execute(f"graphics={{GetWidth=function() return {w} end,GetHeight=function() return {h} end,GetDPR=function() return 1 end}};R.draw(game)")
            filename=f'{ident}-z{zoom:g}.png';(out/filename).write_bytes(b.png(w,h))
            art=b.l.eval("require('war.ReferenceArt')")
            count=b.l.eval("(function() local n=0;for _ in pairs(state.entities) do n=n+1 end;return n end)()")
            records.append(dict(id=f'{ident}-z{zoom:g}',label=label,zoom=zoom,file=filename,units=count,regions=art.last.regions,details=art.last.details))
        print(ident,'complete',flush=True)
    manifest=dict(baseline=args.baseline,records=records,nativeEvidence=False,referenceSha256=hashlib.sha256((b.ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest())
    (out/'catalog.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
