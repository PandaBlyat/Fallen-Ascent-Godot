# Water Atlas

`water_atlas.png` uses 32 px cells. Columns are 4-bit cardinal connection masks:

- `N = 1`
- `E = 2`
- `S = 4`
- `W = 8`

Column `0` is no water neighbors, column `15` is connected on all four sides.

Rows:

- `y=0`: water, used by `TILE_WATER`

Water connects only to other water tiles. It is non-walkable by default.
