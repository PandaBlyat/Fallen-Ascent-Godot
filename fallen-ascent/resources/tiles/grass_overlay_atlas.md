# Grass Overlay Atlas

`grass_overlay_atlas.png` uses 32 px cells with transparent background.

- `x=0..15`: 4-bit floor-neighbor mask, `N/E/S/W = 1/2/4/8`.
- `y=0..5`: normal grass variations, weighted from sparse/short to rare tall.
- `y=6..9`: red / acid-stressed variations used near acid pools.

Grass is overlay art, not base terrain. It draws over floor-family terrain from
`Chunk._grass_layer`. Blades are scattered inside the whole tile, not only
along edges. Variant choice is deterministic from grid coordinate; acid-near
cells set an encoded mask flag so `TileVisuals.grass_atlas_coords` selects
red-stressed rows.
