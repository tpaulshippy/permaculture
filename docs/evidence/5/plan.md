# Issue #5 — HUD (tight scope)

Goal: HUD + resource sim wired into placement and Next, on top of existing
main.gd + hex_grid.gd (no rewrites of terrain/hex logic).

## What ships
- `scripts/turn_sim.gd` (new, pure logic): monthly resource sim reading
  `data/tuning.json` costs/upkeep read-only + `data/sonoran_rainfall.json`
  monthly mm. Tracks money / manhours bank / water-table stock, month_index,
  per-plant age. Deterministic. Wells draw from the table (never raise it);
  ditch capture recharges it; unmet irrigation is a shortfall warning.
- `main.gd` hooks (~150 lines): placement deducts build costs through the
  sim; Next advances the month and refreshes bars/labels/banner.
  Q13 gate (`hex.can_advance()`) still owns Next enable; Q14 warning never blocks.
- Wind display-only (deterministic from month_index, no sim effect) per Q12.
- `tests/test_hud.gd` headless checks.
- Evidence: `docs/evidence/5/demo.mp4` (in-engine frame dump + ffmpeg, per
  `docs/evidence/3/README.md` recipe) + PNGs, attached to PR.

## Constraints respected
- No tuning.json number changes, no D8/hex-validation/save-schema/export changes.
