# permaculture

## Terrain MVP (issue #2)

Base Godot 4.x project: seeded Sonoran heightmap mesh (fixed seed 1337,
20x20 cells ≈ hex equivalent) + D8 downhill accumulation exposing a
per-hex moisture API (`TerrainWater.get_moisture_at()`).

- `project.godot`, `scenes/terrain.tscn`, `scripts/main.gd` — scene + driver
- `scripts/terrain_config.gd` — tuning constants (grid, seed, landform, water)
- `scripts/terrain_water.gd` — deterministic heightfield + D8 + moisture (no UI dependency)
- `scripts/terrain_mesh.gd` — ArrayMesh builder, TERRAIN / MOISTURE render modes
- `scripts/future_stubs.gd` — stubs for hex overlay gameplay, store, HUD, save, export presets (owned by other issues)
- `tests/test_terrain.gd` — headless test, 20 checks, exit code 0 on pass

```sh
godot --headless --path . --script res://tests/test_terrain.gd
```

Evidence: `docs/evidence/2/` (viewport renders + test log).
