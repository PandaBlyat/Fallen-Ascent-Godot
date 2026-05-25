# Floor Base Atlas

`floor_base_atlas.png` uses 32 px cells. Columns are 4-bit cardinal connection masks:

- `N = 1`
- `E = 2`
- `S = 4`
- `W = 8`

Column `0` is no connections, column `15` is connected on all four sides.

Rows:

- `y=0`: base floor, used by `TILE_FLOOR` and under `TILE_RUST`
- `y=1`: debris floor, used by `TILE_DEBRIS`
- `y=2`: conduit floor, used by `TILE_CONDUIT`
- `y=3`: outlet floor, used by `TILE_OUTLET`
- `y=4`: teleporter floor, used by `TILE_TELEPORTER`
- `y=5`: void, used by `TILE_VOID`

Floor-family masks connect `floor`, `debris`, `conduit`, `outlet`, `teleporter`, and `rust`.
