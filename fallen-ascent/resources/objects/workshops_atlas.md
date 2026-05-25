# Workshops Atlas

`workshops_atlas.png` uses 64 px cells. Workshop sprites are drawn once from
their anchor cell and cover a 2x2 tile visual footprint. Doors, walls, lights,
and crafted placeable objects do not live in this atlas.

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
