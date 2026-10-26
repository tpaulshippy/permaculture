# Evidence — Issue #5: HUD + turn wizard

All artifacts are from actual Godot 4.7.2 runs, not mockups.

- `demo.mp4` — real in-engine video (1280x720, 24 fps, ~26 s): orbit while
  house / well L1 / ditch-berm / mesquite are placed via the click raycast
  (Q13 gate goes LOCKED -> UNLOCKED), Next advances Month 1 -> 2 (bars
  update: money $2965, water table 59 % (5911 gal), 107 mh), 24 extra mesquite are
  planted, then 3x Next outruns the well and trips the red irrigation/water
  warnings (Q14: banner shows, Next stays enabled, no game over). Assembled
  with ffmpeg from 626 viewport frames dumped by the running game (see Reproduce).
- `demo_console.log` — stdout of that demo run (placements + Next summaries).
- `demo_frame_locked.png` — Month 1: house placed, Next LOCKED + disabled,
  bars live, Jan rainfall 21.3 mm, wind display-only, no warning.
- `demo_frame_unlocked.png` — Month 2 after first Next: gate UNLOCKED,
  updated bars, monthly summary line.
- `demo_frame_warned.png` — Month 5: water table 0 %, red Q14 banner,
  Next still enabled (game continues).
- `headless_test_hud.log` — turn-sim logic test, exit code 0.

Short honest beat in the footage: placing the well before the first Next
drives manhours briefly negative (40 mh grant covers exactly the house, per
tuning sim_baseline), so the red banner flashes once mid-demo until the
first Next adds the house's 160 mh/mo output minus upkeep, taking mh from
about -38 to 107. Banner-then-clear plus the final water warnings both
demonstrate the Q14 advisory path.

## Reproduce

```sh
godot --headless --path . --script res://tests/test_hud.gd   # sim logic, exit 0
godot --headless --path . --script res://tests/test_hex.gd    # unchanged, still green
godot --headless --path . --script res://tests/test_terrain.gd  # unchanged, still green

# Demo video: game dumps one viewport PNG per 1/24 s of demo time, then
# ffmpeg assembles them (same recipe as docs/evidence/3/README.md).
rm -rf /tmp/frames5
godot --path . --resolution 1280x720 -- --demo-record=/tmp/frames5
ffmpeg -y -framerate 24 -i /tmp/frames5/frame_%04d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 26 docs/evidence/5/demo.mp4
```

Interactive play: `godot --path .` — keys 1-4 select, click places, N = Next.
Scripted demo without recording: `godot --path . -- --demo`.

Capture machine: Apple M1 Pro, Metal 4.0, Forward+, 1280x720.

## Sim notes (see scripts/turn_sim.gd header)

Costs/upkeep read from `data/tuning.json` at runtime (numbers untouched);
rainfall from `data/sonoran_rainfall.json`; wind is a deterministic function
of `month_index` with zero sim effect (Q12). The water-table bar is the
groundwater stock: ditch capture recharges it, wells draw from it (delivery
is capped by demand and by what the table holds, so wells never raise it).
The banner's shortfall line is the live demand-above-capacity gap, so a new
well clears it immediately; the monthly report carries the realized
last-month shortfall. Warnings (negative money/mh, shortfall, depleted
table) never block (Q14).
