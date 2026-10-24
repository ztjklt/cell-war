# Rehydration Salts Animation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to execute locally in this conversation. The user already chose direct painted frames and right-side playback; no additional planning approval is needed.

**Goal:** Produce move, supply release, hit and death as sixteen painted frames each, plus an independent sixteen-frame healing-drop effect, and show connected playback on the right.

**Architecture:** Built-in imagegen creates reference-guided transparent 4×4 sheets. Offline Python only extracts source cells, removes tiny detached alpha speckles, registers complete poses and packages PNG/JSON/WebP. Existing local viewer composes the independent drop with release playback.

**Tech Stack:** Built-in image_gen; existing Pillow, NumPy and SciPy in `.tmp/godot-tools/venv`; existing local sprite preview.

**Spec:** `assets/image/rehydration-salts-character-20261023/mechanics.json`, approved by user: “可以，这个机制很好，然后根据这个机制做那个动作图吧。”

## Global Constraints

- Preserve approved blue/white sachet, exactly two hands, orange-handled pitcher, polygon 2D style and no feet.
- Four character actions ×16; independent drop is an additional asset; retain prompts, source images and hashes.
- No Godot runtime, sales, balance-value or navigation changes. Do not commit or push.

## Review Focus

- Pitcher grip remains attached to exactly two hands during living poses.
- Release has one launch, not a damaging spray or repeated drops.
- Independent drop and in-pitcher liquid share blue/ivory palette.
- Death stays crumpled down with a separate fallen intact pitcher.
- Transparent margins, scale and anchors preserve whole silhouettes without cross-cell clipping.

### Task 1: Painted source sheets

**Files:** `assets/image/rehydration-salts-character-20261023/prompt-*-16.txt`, `source-*-16-v1.png`, `generation-animations-v1.json`.

- [x] Record approval, create prompts and generate move/release/hit/death/drop sheets, one built-in call per asset.
- [x] Inspect all source poses and revise any identity, count, grip or effect-direction failure.

### Task 2: Packaging and validation

**Files:** `scripts/sprite_preview/package_rehydration_salts.py`; per-action `*-16/` folders; `animations.json`; `packaging-validation.json`.

**Interfaces:** `extract(source: Path, action: str) -> list[dict]` returns whole painted poses with source boxes and registration measurements. `package(action: str, spec: dict) -> tuple[list[Image], dict]` creates frames and metadata. `audit() -> dict` verifies counts, alpha, unique hashes, atlas equality, duration sums, source hashes and effect composition.

- [x] Reuse the established sprite packaging pattern, preserving real painted poses with fixed clip scale.
- [x] Bind the independent drop through existing `reviewProjectile` metadata at the actual release frame.
- [x] Run the packager and audit; inspect contact sheet, release/drop transition and final death frame.

### Task 3: Delivery

- [x] Register four character clips and independent drop in the existing local preview; update authoring records only.
- [x] Verify browser title, expected clip/frame counts and live playback, capture proof and retain right-side tab.
- [x] Create and validate a ZIP containing art, prompts and records; report it with the preview.

## Execution record

- Five generated source sheets retained with SHA256 and prompts; four character clips and one effect clip inspected.
- Asset audit:64 character frames +16 independent effect frames; all clips16 unique frames, transparent margins≥38px for characters and64px for effect, atlas pixels equal individual frames, duration sums and original hashes match.
- Browser:5 clips /80 frames, live frame counters advance, independent drop appears during release; pause used for inspection then all playback resumed.
- No gameplay integration, balance changes, commits, pushes or remote builds.
