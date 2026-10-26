class_name TerrainConfig
extends RefCounted
## Tuning constants for the terrain MVP (issue #2).
##
## Single source of truth for grid size, deterministic seed, Sonoran landform
## shaping, and water model coefficients. Change values here to retune; the
## headless test (tests/test_terrain.gd) pins determinism for FIXED_SEED.

# Grid: ~20x20 hex equivalent. Each cell is one moisture sample for the
# future hex overlay (hex gameplay itself is out of scope for this issue).
const GRID_W := 20
const GRID_H := 20
# World-space size of one cell in meters.
const CELL_SIZE := 2.0

# Fixed seed: deterministic MVP. Same seed -> same terrain, every run.
const FIXED_SEED := 1337

# Sonoran landform shaping.
const NOISE_FREQUENCY := 0.09
const NOISE_AMPLITUDE := 2.2
const NOISE_OCTAVES := 4
const NOISE_FRACTAL_GAIN := 0.5
const SLOPE_HIGH := 6.0
const SLOPE_LOW := 0.0
# Bajada slope blend: high in the NW, low in the SE (t = X_W * fx + Y_W * fy).
const SLOPE_X_WEIGHT := 0.6
const SLOPE_Y_WEIGHT := 0.4
const HIGHLAND_BUMP_HEIGHT := 3.0
const HIGHLAND_BUMP_X := 3.0
const HIGHLAND_BUMP_Y := 3.0
const HIGHLAND_BUMP_SIGMA := 3.0
const WASH_DEPTH := 2.0
const WASH_SIGMA := 1.6
# Wash centerline: starts at 35% width at the north edge, drifts +30% width
# toward the south edge (diagonal N -> SE channel).
const WASH_START_FRACTION := 0.35
const WASH_DRIFT_FRACTION := 0.3

# Water model input: uniform rain units per cell per turnover.
const DEFAULT_RAIN := 1.0
# Global water table responds to mean moisture by this coefficient.
const WATER_TABLE_COEFF := 0.5
