"""Publish the registered underlay and previews of the actual layered assets."""
from pathlib import Path
import hashlib,json,shutil,sys
from PIL import Image
sys.path.insert(0,str(Path(__file__).parent))
from prepare_anatomy_foundation import VectorIndex

ROOT=Path(__file__).resolve().parents[2]
ASSETS=ROOT/'assets'
ART=ASSETS/'image/anatomy-reference'
DOC=ROOT/'docs/organ-underlay-style-20261015'
CHANNELS=ART/'vascular-study/standalone-vessels-20261015/channels-v3'
DELIVERY=CHANNELS.parent/'anatomy-v2'

def main():
    DELIVERY.mkdir(exist_ok=True)
    shutil.copy2(DOC/'viewer.html',DELIVERY/'viewer.html')
    shutil.copy2(ART/'organ-underlay-style-20261015/organ-underlay.svg',DELIVERY/'organ-underlay.svg')
    indexes=[VectorIndex(ART/'body-base-style-20261015/body-base.svg'),
             VectorIndex(ART/'organ-underlay-style-20261015/organ-underlay.svg'),
             VectorIndex(ART/'organ-style-20261015/organs-styled.svg')]
    channel=json.loads((CHANNELS/'manifest.json').read_text())
    for name,b,density in [('torso-composite',[340,255,675,845],4),('digestive-composite',[385,440,640,770],6)]:
        image=indexes[0].render(b,density)
        image.alpha_composite(indexes[1].render(b,density))
        image.alpha_composite(indexes[2].render(b,density))
        image.save(DOC/(name+'-no-blood.png'))
        for tile in channel['tiles']:
            if tile['x']>b[2]or tile['x']+tile['w']<b[0]or tile['y']>b[3]or tile['y']+tile['h']<b[1]:continue
            source=4 if density==4 else 8
            raster=Image.open(CHANNELS/f'l{source}'/tile['name']).convert('RGBA')
            if source!=density:raster=raster.resize((tile['w']*density,tile['h']*density),Image.Resampling.LANCZOS)
            image.alpha_composite(raster,(round((tile['x']-b[0])*density),round((tile['y']-b[1])*density)))
        image.save(DOC/(name+'.png'));print(name,image.size,flush=True)
    protected=json.loads((DOC/'protected-inputs.json').read_text())
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==sha for p,sha in protected.items()),'Protected gameplay or approved art changed'
    (DOC/'review.json').write_text(json.dumps(dict(preview='http://127.0.0.1:52483/anatomy-v2/viewer.html',
        layerOrder=['body','continuous organ support underlay','approved organ floors','blood channels'],
        generatedWith='built-in imagegen',registeredVector='assets/image/anatomy-reference/organ-underlay-style-20261015/organ-underlay.svg',
        nativeVector=True,rectangularImageBackground=False,protectedInputsUnchanged=len(protected),
        oldConnectionRibbonsShown=False,oldBloodBridgeDraftShown=False,navigationChanged=False,nativePreviewVerified=False),indent=2)+'\n')

if __name__=='__main__':main()
