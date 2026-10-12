"""Register GPT outputs as texture inputs; never author navigation or pixels."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fourth/root'
OUT = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/bake/fourth-repair/root'
SPECS = {
    'artery': {'crop': [0, 242, 1536, 778], 'floorRangeNormalized': [.14, .86]},
    'vein': {'crop': [0, 325, 1536, 699], 'floorRangeNormalized': [.18, .82]},
    'capillary': {'crop': [0, 288, 1536, 734], 'floorRangeNormalized': [.14, .86]},
}
data = {
    'schema': 'fullbody-complete-gpt-pipe-materials/v1',
    'model': 'GPT built-in image_gen',
    'purpose': 'Continuous two sidewalls plus flat lumen, sampled by frozen arc length and signed transverse coordinate.',
    'sourceGeometryEdited': False,
    'greenAllowed': False,
    'materials': {},
}
for key, spec in SPECS.items():
    path = ASSET / (key + '-strip-raw-v1.png')
    im = Image.open(path)
    assert im.mode == 'RGBA' and im.size == (1536, 1024)
    data['materials'][key] = {
        'path': str(path.relative_to(ROOT)),
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'pixelSize': list(im.size),
        'repeatSourceLength': 18,
        'normaliseTextureColumnsByAlpha': True,
        'alphaIsOnlyTextureBoundary': True,
        **spec,
    }
path = OUT / 'pipe-materials-v4.json'
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(path)
print(hashlib.sha256(path.read_bytes()).hexdigest())
