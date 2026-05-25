# Service Core Wall Atlas

`wall_service_core_atlas.png` uses 32 px cells. Columns are 4-bit cardinal connection masks:

- `N = 1`
- `E = 2`
- `S = 4`
- `W = 8`

Column `0` is isolated service core wall, column `15` connects on all four sides.

Rows:

- `y=0`: derelict service core, used by `TILE_SERVICE_CORE`

Service cores connect only to other service cores.
