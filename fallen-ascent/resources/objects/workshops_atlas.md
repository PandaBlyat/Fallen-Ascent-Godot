# Workshops Atlas

`workshops_atlas.png` uses 64 px source slots. Workshop sprites are drawn once
from their anchor cell, but visual size can be 32x32, 64x32, or 64x64 via
`BuildBlueprint.visual_size_tiles`. Doors, walls, lights, and crafted
placeable objects do not live in this atlas.

Columns:

- `(0,0)`: dock bed
- `(64,0)`: repair bench
- `(128,0)`: research bench
- `(192,0)`: crafting spot
- `(256,0)`: sensor
- `(320,0)`: extractor
- `(384,0)`: charge
- `(448,0)`: crafting bench
- `(512,0)`: assembler press
- `(576,0)`: mechanic dock
- `(640,0)`: fabricator
- `(704,0)`: replication cradle

Column order matches `BuildBlueprint.workshop_atlas_index`.

Visual draw sizes:

- dock bed: 64x32
- research bench, crafting spot, extractor, sensor, charge: 32x32
- repair bench, crafting bench, assembler press, mechanic dock, fabricator,
  replication cradle: 64x64
