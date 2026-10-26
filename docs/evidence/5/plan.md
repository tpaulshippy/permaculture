# Issue #5 — HUD (tight scope)

Goal: HUD-only on top of existing main.gd + hex_grid.gd (no rewrites).

## What ships
- `scripts/turn_sim.gd` (new, pure logic): resources sim reading `data/tuning.json`
  costs/upkeep read-only + `data/sonoran_rainfall.json` monthly mm. Tracks
  money / manhours bank / water reserve, month_index, per-plant age. Deterministic.
- `main.gd` minimal hooks: build bars + rainfall/wind/month labels + red warning
  banner; placement deducts build costs; Next advances month + updates bars.
  Q13 gate (`hex.can_advance()`) still owns Next enable; Q14 warning never blocks.
- Wind display-only (deterministic from month_index, no sim effect) per Q12.
- `tests/test_hud.gd` headless checks.
- Evidence: `docs/evidence/5/demo.mp4` (in-engine frame dump + ffmpeg, per
  `docs/evidence/3/README.md` recipe) + PNGs, attached to PR.

## Constraints respected
- No tuning.json number changes, no D8/hex-validation/save-schema/export changes.
