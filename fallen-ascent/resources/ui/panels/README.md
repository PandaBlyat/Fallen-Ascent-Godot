# Placeholder UI Panel Atlas

`resources/ui/panels/` is the append-only library of per-panel background
textures. Each PNG is a 48x48 9-slice tile (16px corners → 16x16 stretchable
center) that the UI code loads through `StyleBoxTexture` so panels swap in
art the moment you replace the PNG on disk.

- Cell size: 48x48 px.
- 9-slice content margins: 16px on every side (top/bottom/left/right).
- Keep alpha enabled — panels composite over the world.
- Replace any PNG with real art at the same size and the panel will pick
  it up automatically on next reload; no code changes required.

Each PNG in this folder has a sibling `.md` describing what panel it is
visually responsible for, with notes on size, where it appears, and any
gameplay context that should inform the texture's tone.

When adding a new panel:
1. Drop a 48x48 PNG with 16px corners here.
2. Add a `.md` next to it describing the role.
3. Register it from `scripts/ui/ColonyHud._panel_textured_style(name, ...)`
   (or wherever the new panel is constructed).
