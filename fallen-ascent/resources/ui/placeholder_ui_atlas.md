# Placeholder UI Atlas

`placeholder_ui_atlas.png` is an append-only UI icon atlas.

- Cell size: 32x32 px.
- Current used cells are x 0-10 on row 0.
- Add new icons by expanding canvas right or down and drawing into new 32x32 cells.
- Do not reshuffle existing cells unless `scripts/ui/ColonyHud.gd` icon coordinates are updated in the same change.
- Keep this atlas separate from terrain/object placeholder atlases so adding UI icons does not rewrite gameplay tile atlases.
