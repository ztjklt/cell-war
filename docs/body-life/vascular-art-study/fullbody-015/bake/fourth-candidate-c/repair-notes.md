# Two-foot antialias ownership repair — candidate C

Status: frozen for root promotion and Native007; offline visual review completed. This document does not claim native or performance acceptance.

The right-foot blue return had a thin brown vertical line at source `[376.0625,1437.9375]`. In the node RGB replacement, the lower artery node `r.toe3.a` was clipped with a raster of `higher footprint ∩ own node region`. At the antialiased boundary this raster was only 183/255 even though the blue foreign tube was opaque. The remaining 72/255 lower red material blended into the blue lumen. The equivalent lower-node leftovers also appeared in the left foot.

The compiler now uses the complete higher foreign visible footprint for its priority mask. The RGB repair remains limited to the same own-node region and the same fixed incident-layer ownership. It preserves independent artery/vein crossings, every named node and the physical alpha footprint. It does not union unrelated routes.

Only `external-0256-1280.png` and `external-0512-1280.png` were rebuilt. Their alpha channels are byte-identical to B; only 482 and 429 RGB pixels changed. The source probe changed from `[161,126,167,255]` to `[153,142,198,255]`. Enlarged before/after crops and full native-camera static composites were actually read; the red vertical residue is absent in both feet. Static composites remain offline evidence.

The other 39 image specifications directly reference immutable B files. The accepted source SVG, 16× foreground raster, narrow-band AA raster/contracts, 202 edge samples/widths/systems, original 135 logical intervals and all 107 visual intervals are unchanged. The budget remains 42 specifications and 265,055,880 decoded RGBA bytes per NanoVG context including the quiet base. GPU/mips and native P95 are separate root checks.

`manifest.json` is frozen at SHA256 `fb0bb1a3fd70a7d69cdf53d534a715a519ea48822bd6a9665fa1e639d0e8f693`.
Compiler SHA256 is `0efacdc4e4edc562b76e39f9aedecfe38a6597d355f1161c710460a92da70bc8`. The original B compiler is archived in `inputs/compiler-b-before-foot-aa.py` at its original SHA256 `8a3139691f087ede9d708a78bacefd3b35dfb031714ffeaf8edb839da647d8e3`.

`diagnostics/repair-review.json` records exact asset hashes, pixel counts and source probes. `freeze.json` records the immutable promotion contract. Do not rebake into this candidate directory after promotion. For reproduction use the same command in `reproduce-command.txt`, changing both output directories to new private paths. Incremental mode directly reuses the original B foreground/AA masks and retains all unselected resources; it no longer emits replacement masks or temporary guides.

Native-only low-contrast slanted lines in chest/portal screenshots were absent from the exact frozen static composite and are being independently diagnosed by root. This two-foot patch does not pretend to fix those separate runtime observations.
