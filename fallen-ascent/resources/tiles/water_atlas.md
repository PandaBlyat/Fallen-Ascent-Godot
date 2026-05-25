# Water Atlas

`water_atlas.png` uses 32 px cells. Columns are 4-bit cardinal connection masks:

- `N = 1`
- `E = 2`
- `S = 4`
- `W = 8`

Column `0` is no water neighbors, column `15` is connected on all four sides.

Rows:

- `y=0`: deep water, used by `TILE_WATER` (impassable).
- `y=1`: shallow water, used by `TILE_WATER_SHALLOW` (walkable, slower).
- `y=2`: puddle, used by `TILE_WATER_PUDDLE` (walkable, slightly slower).

Each row is one body-of-water family — cells only connect to cells of the
same depth. The water shader at `resources/shaders/water_tile.gdshader`
reads the sample UV row to pick a per-depth palette and ripple intensity,
so this atlas mostly drives connection geometry; you can repaint each row
with detailed art and the shader will still tint it convincingly.

The fragment shader treats UV.y < 1/3 as deep, 1/3..2/3 as shallow,
> 2/3 as puddle. Keep the row layout above intact when authoring real
art, or update `resources/shaders/water_tile.gdshader` to match.
