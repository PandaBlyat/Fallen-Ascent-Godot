# Basic Wall Atlas

`wall_basic_atlas.png` uses 32 px cells. Columns are 4-bit cardinal connection masks:

- `N = 1`
- `E = 2`
- `S = 4`
- `W = 8`

Column `0` is isolated wall, column `15` connects on all four sides.

Rows:

- `y=0`: basic wall, used by `TILE_WALL`

Basic walls connect only to other basic walls.
