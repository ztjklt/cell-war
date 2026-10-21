#!/usr/bin/env python3
"""Package new dendritic poses and preserve the original six-frame lamp scan."""
from pathlib import Path
import json
from package_t_cell import package

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/dendritic-cell-cartoon-20261021'
SPECS={
 'move':{'name':'移动 · 16帧','displayName':'树突状细胞','grid':(4,4),'durations':[90]*16,'loop':True},
 'hit':{'name':'受击 · 12帧','displayName':'树突状细胞','grid':(4,3),'durations':[65,55,45,45,55,75,75,75,80,85,90,100],'loop':False},
 'death':{'name':'侧倒死亡 · 12帧','displayName':'树突状细胞','grid':(4,3),'durations':[120]*12,'loop':False},
}

def main():
    for action in SPECS:
        SPECS[action]['processing']='Painted-pose extraction and alpha-speckle cleanup; six branching arms retained; fixed scale per action and ground/body registration; no interpolation.'
        package(action,ART,SPECS)
    manifest={'character':'dendritic_cell','displayName':'树突状细胞','portrait':'character-refined-v1.png',
              '移动 · 16帧':'move-16/animation.json','侦察标记 · 原版6帧':'original-skill1-6/animation.json',
              '受击 · 12帧':'hit-12/animation.json','侧倒死亡 · 12帧':'death-12/animation.json'}
    (ART/'animations.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__': main()
