"""Register built-in GPT crop outputs against frozen guide coordinates."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'docs/body-life/vascular-art-study/fullbody-015'
GUIDES = BASE / 'bake/fourth-guides/manifest.json'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--display-guides', type=Path,
                    default=BASE / 'bake/fourth-guides/manifest-v6.json',
                    help='Exact reviewed semantic foreground contract, separate from generation history')
parser.add_argument('--output', type=Path,
                    default=BASE / 'bake/fourth-repair/root/junctions-v4.json',
                    help='Separate registration output for a later display revision; preserves historical inputs')
args = parser.parse_args()
DISPLAY_GUIDES = args.display_guides.resolve()
ASSET = ROOT / 'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fourth/root'
VERSIONS = {'arch-roof-and-junction': 2, 'celiac-stomach-complete-junction': 3,
            'pancreas-duct-and-crossings': 2, 'heart-venous-junction': 1}
guides = json.loads(GUIDES.read_text())
display_guides = json.loads(DISPLAY_GUIDES.read_text())
display_svg = ROOT / display_guides['sharedForegroundSvgPath']
assert hashlib.sha256(display_svg.read_bytes()).hexdigest() == display_guides['sharedForegroundSvgSha256']
data = {'schema': 'fullbody-registered-gpt-junctions/v1',
        'model': 'GPT built-in image_gen', 'status': 'CANDIDATE_NOT_ACCEPTED',
        'sourceGeometryEdited': False,
        'guideManifestSha256': hashlib.sha256(GUIDES.read_bytes()).hexdigest(),
        # Original generation references and the reviewed display geometry are
        # distinct evidence. Later semantic corrections must not rewrite the
        # recorded inputs of an already generated image.
        'generationGuideManifestPath': str(GUIDES.relative_to(ROOT)),
        'displayForegroundContract': {
            'path': str(DISPLAY_GUIDES.relative_to(ROOT)),
            'sha256': hashlib.sha256(DISPLAY_GUIDES.read_bytes()).hexdigest(),
            'geometrySvgPath': display_guides['sharedForegroundSvgPath'],
            'geometrySvgSha256': display_guides['sharedForegroundSvgSha256'],
            'generatedPixelsDefineNavigation': False,
        },
        'humanAuthorization': 'Continue fixes until accepted without per-round questions.',
        'patches': []}
for g in guides['patches']:
    key = g['id']
    if key not in VERSIONS:
        continue
    raw = ASSET / f'{key}-raw-v{VERSIONS[key]}.png'
    im = Image.open(raw)
    assert im.mode == 'RGBA'
    norm = g['guideContentRectNormalized']
    # The heart edit returned the portrait content without the square guide's
    # transparent side margins. Register its full portrait, not square margins.
    if key == 'heart-venous-junction':
        assert im.size == (1024, 1536)
        norm = [0, 0, 1, 1]
    content = [norm[0]*im.width, norm[1]*im.height, norm[2]*im.width, norm[3]*im.height]
    pp = min((content[2]-content[0])/(g['sourceBox'][2]-g['sourceBox'][0]),
             (content[3]-content[1])/(g['sourceBox'][3]-g['sourceBox'][1]))
    assert pp >= 16
    generation_guide = ROOT / g['guidePath']
    if key == 'arch-roof-and-junction':
        generation_guide = BASE / 'bake/fourth-guides/arch-roof-and-junction-pipe-guide-v4.png'
    assert generation_guide.exists()
    edit_chain = []
    for version in range(1, VERSIONS[key] + 1):
        previous_raw = ASSET / f'{key}-raw-v{version}.png'
        prompt = BASE / f'bake/fourth-repair/root/{key}-prompt-v{version}.txt'
        assert previous_raw.exists() and prompt.exists()
        edit_chain.append({
            'version': version,
            'path': str(previous_raw.relative_to(ROOT)),
            'sha256': hashlib.sha256(previous_raw.read_bytes()).hexdigest(),
            'promptPath': str(prompt.relative_to(ROOT)),
            'promptSha256': hashlib.sha256(prompt.read_bytes()).hexdigest(),
        })
    data['patches'].append({
        'id': key, 'path': str(raw.relative_to(ROOT)),
        'sha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
        'pixelSize': list(im.size), 'contentBox': content,
        'sourceBox': g['sourceBox'], 'edgeIds': g['edgeIds'],
        'compositionMode': 'whole-pipe-and-foreground',
        'foregroundSvgPath': g['foregroundSvgPath'],
        'foregroundSvgSha256': g['foregroundSvgSha256'],
        'foregroundSvgRole': 'Original generation guide; display uses shared displayForegroundContract.',
        'selectedGenerationGuidePath': str(generation_guide.relative_to(ROOT)),
        'selectedGenerationGuideSha256': hashlib.sha256(generation_guide.read_bytes()).hexdigest(),
        'editChain': edit_chain,
        'priority': g['artOwnershipPriority'],
        'effectivePixelsPerSource': pp,
        'promptPath': str((BASE / f'bake/fourth-repair/root/{key}-prompt-v{VERSIONS[key]}.txt').relative_to(ROOT)),
        'registrationRequiresCompiledVisualReview': True,
    })
out = args.output.resolve()
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
print(out)
print(hashlib.sha256(out.read_bytes()).hexdigest())
