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
- `y=3`: deep acid, used by `TILE_ACID` (impassable).
- `y=4`: shallow acid, used by `TILE_ACID_SHALLOW` (walkable, slow + damage).
- `y=5`: acid puddle, used by `TILE_ACID_PUDDLE` (walkable, light damage).

Each row is one body-of-water family — cells only connect to cells of the
same depth. The water shader at `resources/shaders/water_tile.gdshader`
reads the sample UV row to pick a per-depth palette and ripple intensity,
so this atlas mostly drives connection geometry; you can repaint each row
with detailed art and the shader will still tint it convincingly.

`resources/shaders/water_tile.gdshader` receives fluid band from code
(`TileVisuals.water_band`) instead of deriving it from UV rows. Keep row
layout above intact when authoring real art, or update both files together.
