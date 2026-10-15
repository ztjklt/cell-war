"""Verify exact route ownership and continuous high-resolution tile rendering."""
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, binary_erosion
import build_standalone_vessel_channels as c


def main():
    c.ASSET=c.BASE/'channels-v3'
    b,source,paths,materials=c.prepare()
    registered=json.loads((c.ASSET/'manifest.json').read_text())
    assert registered['geometrySourceSha256']==c.sha(c.BASE/'vessels-geometry.svg')
    assert registered['geometryPaths']==paths
    assert len(paths)==203
    assert all(p['originalPathSha256']==p['paintPathSha256']for p in paths)
    assert registered['organInterfaces']==source['organInterfaces']
    assert registered['terminalNodes']==source['terminalNodes']
    checks=[]
    for bounds in [[508,572,516,580],[476,636,484,644],[700,956,708,964]]:
        expected=np.asarray(c.render_cropped_tile(b,bounds,32))
        mosaic=Image.new('RGBA',((bounds[2]-bounds[0])*32,(bounds[3]-bounds[1])*32))
        for y in range(bounds[1]//64*64,bounds[3],64):
            for x in range(bounds[0]//64*64,bounds[2],64):
                p=c.ASSET/'l32'/f'{x:04}-{y:04}.png'
                if p.exists():mosaic.paste(Image.open(p),((x-bounds[0])*32,(y-bounds[1])*32))
        # Ignore the separate ROI's outer antialias boundary, checking the
        # interior across the actual horizontal and vertical grid seams.
        crop=(slice(8,-8),slice(8,-8));e=expected[crop];a=np.asarray(mosaic)[crop]
        valid=(e[:,:,3]>240)&(a[:,:,3]>240)
        difference=np.abs(e[:,:,:3].astype(int)-a[:,:,:3].astype(int))
        max_rgb=int(difference[valid].max())if valid.any()else 0
        mismatch=int(np.sum((e[:,:,3]>127)!=(a[:,:,3]>127)))
        silhouette=e[:,:,3]>127
        band=binary_dilation(silhouette)^binary_erosion(silhouette)
        interior_mismatch=int(np.sum(((e[:,:,3]>127)!=(a[:,:,3]>127))&~band))
        # Cairo can quantize an edge alpha either side of 127 after a
        # different exact rectangle crop. A one-pixel AA band is allowed;
        # no interior gap or color seam is allowed.
        row=dict(sourceBox=bounds,opaqueRGBMaxDifference=max_rgb,alphaMaskMismatchPixels=mismatch,alphaMismatchesAwayFromAntialiasEdge=interior_mismatch)
        assert max_rgb<=2 and interior_mismatch==0,row
        checks.append(row)
    report=dict(status='PASS',sourcePathCount=len(paths),allSourcePathHashesIdentical=True,
                organInterfacesRetained=len(source['organInterfaces']),tileSeams=checks,materialSources=materials,
                highResolutionTileCount=len(registered['tiles']),sourceDensity=32,fullPNGPixelSize=[8192,12288])
    output=c.ROOT/'docs/standalone-vessels-20261015/channels-v3/registration-and-seams.json'
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items()if k!='materialSources'}),flush=True)


if __name__=='__main__':main()
