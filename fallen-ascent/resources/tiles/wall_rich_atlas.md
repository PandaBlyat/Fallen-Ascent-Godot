# Rich Wall Atlas

`wall_rich_atlas.png` uses 32 px cells. Columns are 4-bit cardinal connection masks:

- `N = 1`
- `E = 2`
- `S = 4`
- `W = 8`

Column `0` is isolated rich wall, column `15` connects on all four sides.

Rows:

- `y=0`: rich/plated wall, used by `TILE_RICH_WALL`

Rich walls connect only to other rich walls.
