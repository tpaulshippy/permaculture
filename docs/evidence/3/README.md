# Evidence — Issue #3: Hex overlay + placement rules

All artifacts here are generated from actual Godot 4.7.2 runs, not mockups.

- `demo.mp4` — real in-engine video (1280x720, 24 fps, ~26 s) of the demo
  run: camera orbits the seeded Sonoran terrain while house, well L1,
  ditch-berm, and mesquite are placed one by one; the HUD gate readout goes
  from `Next LOCKED` to `Next UNLOCKED` (Q13). Assembled with ffmpeg from
  626 viewport frames dumped by the running game (see Reproduce).
- `demo_console.log` — stdout of that demo run (placements + gate transitions).
- `hex_overlay.png` — offscreen-viewport still: terrain palette + hex grid
  lines, native hint ghosts (pale green discs), and pre-placed
  house / well / ditch / mesquite markers near the center.
- `demo_frame_house.png`, `demo_frame_unlocked.png` — two frames pulled from
  `demo.mp4` (house placed with Next locked; all three required items placed
  with Next unlocked).
- `headless_test_hex.log` — full output of the hex logic test (exit code 0).

## Reproduce

```sh
# Headless logic tests (no GPU needed)
godot --headless --path . --script res://tests/test_terrain.gd  # issue #2, unchanged
godot --headless --path . --script res://tests/test_hex.gd      # issue #3, 55 checks

# Still captures (offscreen SubViewport; main window never needs to be visible)
godot --path . --quit-after 120 -- --capture-mode=hex --capture-path=docs/evidence/3/hex_overlay.png

# Demo video: the game dumps one viewport PNG per 1/24 s of demo time, then
# ffmpeg assembles them. `screencapture -v` was not usable from the build
# shell in this session ("could not create image from display": no window-
# server access), so the frames come straight from the running game instead —
# lossless captures of the actual rendered window, HUD included.
rm -rf /tmp/frames3
godot --path . --resolution 1280x720 -- --demo-record=/tmp/frames3
ffmpeg -y -framerate 24 -i /tmp/frames3/frame_%04d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 26 docs/evidence/3/demo.mp4
```

Interactive play: `godot --path .` — drag to orbit, wheel to zoom, click
terrain to place the selected item (keys 1-4 or HUD buttons, N for Next).
Scripted demo without recording: `godot --path . -- --demo`.

Capture machine: Apple M1 Pro, Metal 4.0, Forward+, 1280x720.
