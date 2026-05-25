# Inspect Card (`inspect_card.png`)

Compact card at the bottom-center above the command palette, showing
quick-inspect info for whatever the cursor is hovering (tile / bot /
structure). Built in `scripts/ui/ColonyHud.gd` (`InspectCard`, around
line 354).

- Anchored: bottom-center, above the command palette.
- Width ~`INSPECT_CARD_WIDTH` (300), height ~`INSPECT_CARD_HEIGHT` (150).
- Tone: brief tooltip-like surface; thin border, low contrast.
