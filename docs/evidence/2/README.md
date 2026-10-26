# Evidence — Issue #2: Terrain heightmap + D8 water flow

All artifacts here are generated, not mocked.

- `terrain_topdown.png` — actual Godot 4.7.2 viewport capture of the seeded
  Sonoran heightmap mesh (fixed seed 1337, 20x20 cells), terrain palette.
- `moisture_overlay.png` — actual viewport capture of the same mesh in
  moisture-overlay render mode (tan = dry, blue = wet, D8 accumulation).
- `headless_test.log` — full output of the headless logic test
  (`godot --headless --path . --script res://tests/test_terrain.gd`,
  exit code 0, 20/20 checks pass).

## Reproduce

```sh
# Headless logic test (no GPU needed)
godot --headless --path . --script res://tests/test_terrain.gd

# Viewport captures (requires a display; uses an offscreen SubViewport
# so the main window never needs to be visible)
godot --path . --quit-after 120 -- --capture-mode=terrain --capture-path=/tmp/terrain_topdown.png
godot --path . --quit-after 120 -- --capture-mode=moisture --capture-path=/tmp/moisture_overlay.png
```

Capture machine: Apple M1 Pro, Metal 4.0, Forward+, 1280x720.
