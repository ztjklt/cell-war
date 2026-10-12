# Fourth-round compile and registration notes

This is a private candidate. Root alone promotes it and records native acceptance. The third-round active PNGs, manifest, gameplay geometry, Save data and original artwork remain unchanged.

The native-inspection candidate was frozen at manifest SHA `a90d1edccd8b1e14ab29fed03647c206430bef528d88985ac2e46dad0f3ffaaa`. Its 41 output PNG SHA values were read back and matched; adding the immutable quiet PNG gives 42 resources and 218281320 decoded RGBA bytes per context. The 202 sampled-route SHA values and widths, and all original135 logical foreground intervals, exactly match the third-round baseline. Accepted v7 display foreground yields111 separate visual intervals. This is a resource/geometry freeze, not a native visual PASS.

## Reproduction

```sh
python3 scripts/qa/build_fullbody_vascular_material.py --pipe-materials docs/body-life/vascular-art-study/fullbody-015/bake/fourth-repair/root/pipe-materials-v4.json --foreground-guides docs/body-life/vascular-art-study/fullbody-015/bake/fourth-guides/manifest-v7.json --junctions docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate/gpt-patches-v4.json --asset-dir assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v4 --out docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate
python3 scripts/qa/prepare_fullbody_v4_guides.py --preview-candidate docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate/manifest.json
```

Do not re-run the original guide generator after generation: its original nine guides are immutable generation inputs. Original `manifest.json` and root arch guide-v4 remain the actual generation history. Accepted v7 foreground SVG is a separate reviewed display contract. Every output PNG/size/registration and raw source SHA is recorded in the material manifest.

## Complete pipes

All 202 frozen sampled routes keep their widths and original systems. Their three independent GPT source images include both banks and a flat lumen. The compositor normalizes each source column within near-opaque texture bounds, applies area filtering at the target UV density, and samples fixed graph arclength plus signed transverse distance. Source alpha never defines navigation. Bank distance is measured against fixed geometric segments, independent of image/tile/foreground cuts.

Real named nodes are composed once with the union exterior bank and a central flat GPT lumen. Regional GPT art can replace both correctly placed outside banks. Obvious terrain/other material colors are rejected according to the frozen paint owner, never a global artery/vein OR. A raw wall drifting into the fixed flat lumen falls back to the same generated strip; quiet matching regional floor texture can mix at 30 percent, while a true-node core uses the complete open strip floor. Projected crossings retain the authored over/under cut and never change graph adjacency.

Owned blood previously disappeared from the deep plane because it was already baked into the organ image. At a cross-organ projection, that split could overpaint a high-layer owned tube with a low-layer foreign trunk: at source(549,666.2), e188's blue layer60 was covered by e134's red layer25, leaving a blue crescent. The final compiler restores fixed owned footprints only within the pre-existing deep blood domain (0.22-source filtering gutter, always clipped inside each original full vessel footprint). The deep render then sorts all participants by the frozen layer/id. The 60 restored intersection records are explicit in `deepPlaneOwnershipRepairs`; no extra tile or route is added. The source point now has full-width blue material in the later deep image. Native filtering must still verify that duplicate complementary AA at a plane handoff causes no double bank.

## One visible foreground contract

The accepted SVG drives the gray-L 16-pixels/source mask, blood alpha, open mouths, the 0.025-source unit-center guard and nine high-density foreground textures. Actual organ normal floor cannot become an opaque roof solely because it resembles cream pigment. Canonical airway Y uses frozen passages with cap_style=1, join_style=1, quad_segs=24.

The v7 correction protects the actual gastric cavity (foodRings intersect stomachOuter) in full. Gastric-outside abstract esophageal/duodenal reservations require real cream from the accepted quiet+12-floor composition, preserving other real organ lumens and the canonical airway roof. This removes the false roof at source (517,618), where an arterial main previously ended visibly on ordinary orange ground. Original135 protectedForegroundIntervals remain the historical audit; visualForegroundIntervals are the separate display record.

## Intentional route details and limits

The apparent red hook next to the heart is frozen e152 (aortic_root→coronary.entry), which goes from (533,375) down near (540,390) and back to (541.7692308,384.1538462), joining e199. It is distinct from the nearby wide e009 aortic main. Its two-sided pipe must remain visible; painting it away or joining an unrelated projected artery is forbidden. True coronary.entry floor is open. The blue pipe near (549.4,665.6) is the real e188→e166 venous connection crossing e134, not automatically an arterial pixel.

Older accepted organ floors outside the nine fixed high-density edits still include quarter-source-pixel foreground rim contours. Native inspection must assess their actual .15-size edge quality; offline composition is not native evidence. Quiet bitmap and all accepted source floor/organ silhouettes remain immutable. Resource limit is42 specs/context including quiet,288MiB decoded RGBA/context; mip/GPU actual consumption is separately measured by root.

All13 final offline compositions were opened for review. The false gastric-exterior mouth at(517,618), raw orange arch triangle and blue half-crescent were absent after the fixes. Remaining points for native inspection include stepped original cream rims near small-gut(511,716)/(482,713), kidney(447,635)/(558,633), and the long return near(572,685); subtle floor/bank handoff tones; and same-system projected small tubes over large tubes whose walls must not be mistaken for closed node floors. Accepted source-organ textures outside the frozen replacement area are not repainted to hide those questions. `previews-v4/manifest.json` SHA `2ba33d73a24ca18e5db3dee606c259e46ef0a9499e98bb7a120b8e8e753cbbbe` binds those actual13 offline images to the frozen candidate.
