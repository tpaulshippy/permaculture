# permaculture

## Terrain MVP (issue #2)

Base Godot 4.x project: seeded Sonoran heightmap mesh (fixed seed 1337,
20x20 cells ≈ hex equivalent) + D8 downhill accumulation exposing a
per-hex moisture API (`TerrainWater.get_moisture_at()`).

- `project.godot`, `scenes/terrain.tscn`, `scripts/main.gd` — scene + driver
- `scripts/terrain_config.gd` — tuning constants (grid, seed, landform, water)
- `scripts/terrain_water.gd` — deterministic heightfield + D8 + moisture (no UI dependency)
- `scripts/terrain_mesh.gd` — ArrayMesh builder, TERRAIN / MOISTURE render modes
- `scripts/future_stubs.gd` — stubs for store, save, export presets (owned by other issues)
- `tests/test_terrain.gd` — headless test, 34 checks, exit code 0 on pass (1 on failure)

```sh
godot --headless --path . --script res://tests/test_terrain.gd
```

Evidence: `docs/evidence/2/` (viewport renders + test log).

## Hex overlay + placement rules (issue #3)

20x20 hex gameplay overlay on top of the issue #2 terrain. Mesh owns height;
each hex owns gameplay state. Avg-height sampled from the heightfield (3x3
cell mean), moisture from the D8 model. Place house / well L1 / ditch-berm /
mesquite with raycast validation; Q13 gating (house + well + plant required)
locks Next until satisfied. 4 native mesquite hint ghosts pre-placed.

- `scripts/hex_grid.gd` — pure-logic overlay: sampling, placement rules,
  Q13 gating, save-shaped snapshot (no UI dependency)
- `scripts/main.gd` — orbit camera, click-to-place raycast, HUD + Next
  button, scripted `--demo` / `--demo-record` for evidence video
- `tests/test_hex.gd` — headless test, 55 checks, exit code 0 on pass (1 on failure)

```sh
godot --headless --path . --script res://tests/test_hex.gd
godot --path . -- --capture-mode=hex --capture-path=/tmp/hex_overlay.png
godot --path . -- --demo
```

Evidence: `docs/evidence/3/` (demo video, stills, test log).
