# Selection Details Panel (`selection_panel.png`)

Left-side panel that appears when worker(s) / structures / stockpiles
are selected. Built in `scripts/ui/ColonyHud.gd` (`SelectionPanel`,
around line 323). Hosts the worker roster grid (`roster_panel.png`)
and worker cards (`worker_card.png`).

- Anchored: top-left.
- Width ~`SELECTION_PANEL_WIDTH` (760), height ~`SELECTION_PANEL_HEIGHT` (430).
- Tone: dark "console window" feel; long-lived panel that the player
  reads from for tens of seconds at a time.
