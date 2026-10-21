#!/usr/bin/env python3
"""Offline metadata for existing approved vaccine art; never enables runtime sales."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/image/vaccine-character-20261021"
GAME = ROOT / "godot"


def main():
    clips = {}
    sources = []
    for key in ["move", "hit", "release", "death"]:
        doc_path = ART / f"{key}-16/animation.json"
        doc = json.loads(doc_path.read_text())
        source = doc_path.parent / doc["spritesheet"]
        relative = source.relative_to(ROOT / "assets").as_posix()
        installed = GAME / "assets" / relative
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        assert hashlib.sha256(installed.read_bytes()).hexdigest() == digest
        assert Image.open(source).size == (2048, 2048) and len(doc["frames"]) == 16
        first = doc["frames"][0]
        x0, y0, x1, y1 = first["sourceBodyBounds"]
        dx, dy = first["registrationOffset"]
        scale = doc["fixedScale"]
        durations = [f["duration"] / 1000 for f in doc["frames"]]
        clips[key] = dict(path=relative, columns=4, rows=4, frameSize=512,
                          anchorX=(x0+x1)*scale/2+dx, anchorY=(y0+y1)*scale/2+dy,
                          occupancy=max(x1-x0, y1-y0)*scale/512,
                          durations=durations, duration=sum(durations), loop=key == "move")
        if key == "release":
            clips[key].update(embeddedAntibodyIllustrationCount=2,
                              worldRenderingStatus="body isolation needed before battlefield wiring; illustrated antibodies must not appear as extra persistent drops")
        sources.append(dict(path=str(source.relative_to(ROOT)), sha256=digest,
                            metadata=str(doc_path.relative_to(ROOT))))
    antibody = ART / "antibody/sprite.png"
    relative = antibody.relative_to(ROOT / "assets").as_posix()
    digest = hashlib.sha256(antibody.read_bytes()).hexdigest()
    assert Image.open(antibody).size == (256, 256)
    assert hashlib.sha256((GAME / "assets" / relative).read_bytes()).hexdigest() == digest
    data = dict(schema=1, medicineId="vaccine", releaseEnabled=False,
        runtimeStage="independent_candidate_only", tuningStatus="first_pass_adjustable",
        helperProposal=dict(price=120, health=90, moveSpeed=2.0, helperLifetimeSeconds=90),
        rules=dict(dropCooldownSeconds=1.0, antibodyLifetimeSeconds=12.0,
                   contactRadius=.45, damage=8.0, searchRadius=1.25, searchStep=.25,
                   searchDirections=16, maxPerHelper=12, maxAntibodies=128,
                   maxSourceRecords=256, maxTrackedActors=8192, maxSegmentsPerActor=128,
                   maxEvents=256),
        activeAttackCauses=["attack", "projectile", "collision"],
        classification=dict(currentVirusKinds=["virus", "herpes"],
                            extension="Host is_virus callback explicitly opts future virus kinds in; never use all pathogens."),
        clips=clips,
        antibodyVisual=dict(path=relative, frameSize=256, columns=1, rows=1,
                            anchorX=128, anchorY=128, spriteSide=.9, fixedWorldPosition=True),
        provenance=dict(method="Metadata only. Bottle body center from authored registration; existing atlases and antibody copied byte-for-byte; no new images.",
                        clips=sources, antibody=dict(path=str(antibody.relative_to(ROOT)), sha256=digest)))
    (GAME / "data/vaccine_antibodies.json").write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n")
    print("Prepared 4x16 vaccine samples and existing independent antibody; release remains closed.")


if __name__ == "__main__":
    main()
