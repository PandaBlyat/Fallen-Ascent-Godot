# Rust Overlay Atlas

`rust_overlay_atlas.png` uses 32 px cells with transparent background.

Columns:

- `x=0..15`: rust visual variants

Rust is not base terrain art. `TILE_RUST` draws base floor from `floor_base_atlas.png`, then one rust overlay cell from this atlas. Variant choice is deterministic from grid coordinate.
