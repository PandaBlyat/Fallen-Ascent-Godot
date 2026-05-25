# Top Resource Strip (`top_strip.png`)

Top-of-screen status bar showing resource counts, time of day, alerts, etc.
Built in `scripts/ui/ColonyHud.gd` (`top_strip`, around line 180).

- Anchored: top-center.
- Width: spans most of the top edge; height ~44 px (`TOP_STRIP_HEIGHT`).
- Tone: dark/industrial; should fade into the world without grabbing focus.
- Often layered over chips (`resource_chip.png`) and a wisdom badge
  (`wisdom_badge.png`).
