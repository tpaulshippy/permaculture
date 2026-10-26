class_name TerrainWater
extends RefCounted
## Seeded Sonoran heightmap + D8 downhill accumulation (issue #2).
##
## Pure logic, no UI dependency: safe to drive from the 3D scene
## (scripts/main.gd) and from the headless test (tests/test_terrain.gd).
##
## Pipeline: generate() builds the deterministic heightfield, then
## apply_rain() runs D8 flow -> accumulation -> per-cell moisture plus a
## global water table delta. No erosion/deposition (deferred).

const Cfg := preload("res://scripts/terrain_config.gd")

# Fixed D8 neighbor order (row-major). Doubles as the tie-break order so
# equal-height descents resolve deterministically.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

const OOB_FLOW := Vector2i(-1, -1)

var grid_w: int = Cfg.GRID_W
var grid_h: int = Cfg.GRID_H
var seed_used: int = Cfg.FIXED_SEED
var rain_amount: float = Cfg.DEFAULT_RAIN
var heights := PackedFloat32Array()
var flow_to := PackedInt32Array()
var accumulation := PackedFloat32Array()
var moisture := PackedFloat32Array()
var water_table_delta := 0.0
var max_accumulation := 1.0
var sink_count := 0
var min_height := 0.0
var max_height := 1.0


func _init(p_w: int = Cfg.GRID_W, p_h: int = Cfg.GRID_H) -> void:
	grid_w = p_w
	grid_h = p_h


func cell_count() -> int:
	return grid_w * grid_h


func idx(x: int, y: int) -> int:
	return y * grid_w + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < grid_w and y < grid_h


## Build the deterministic Sonoran heightfield, then run the water model.
func generate(p_seed: int = Cfg.FIXED_SEED, p_rain: float = Cfg.DEFAULT_RAIN) -> void:
	if grid_w < 2 or grid_h < 2:
		push_error("TerrainWater.generate: grid %dx%d is degenerate, need at least 2x2." % [grid_w, grid_h])
		return
	seed_used = p_seed
	rain_amount = p_rain
	var noise := FastNoiseLite.new()
	noise.seed = p_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = Cfg.NOISE_FREQUENCY
	noise.fractal_octaves = Cfg.NOISE_OCTAVES
	noise.fractal_gain = Cfg.NOISE_FRACTAL_GAIN
	heights.resize(cell_count())
	for y in range(grid_h):
		for x in range(grid_w):
			var fx := float(x) / float(grid_w - 1)
			var fy := float(y) / float(grid_h - 1)
			# Bajada slope: high in the NW, low in the SE.
			var t := Cfg.SLOPE_X_WEIGHT * fx + Cfg.SLOPE_Y_WEIGHT * fy
			var h := lerpf(Cfg.SLOPE_HIGH, Cfg.SLOPE_LOW, t)
			h += noise.get_noise_2d(float(x), float(y)) * Cfg.NOISE_AMPLITUDE
			# Rocky highland bump in the NW (deterministic).
			var dx := float(x) - Cfg.HIGHLAND_BUMP_X
			var dy := float(y) - Cfg.HIGHLAND_BUMP_Y
			var bs := Cfg.HIGHLAND_BUMP_SIGMA
			h += Cfg.HIGHLAND_BUMP_HEIGHT * exp(-(dx * dx + dy * dy) / (2.0 * bs * bs))
			# Carved wash running N -> SE (deterministic diagonal channel).
			var center_x := float(grid_w) * (Cfg.WASH_START_FRACTION + fy * Cfg.WASH_DRIFT_FRACTION)
			var d := float(x) - center_x
			var ws := Cfg.WASH_SIGMA
			h -= Cfg.WASH_DEPTH * exp(-(d * d) / (2.0 * ws * ws))
			heights[idx(x, y)] = h
	min_height = heights[0]
	max_height = heights[0]
	for v in heights:
		min_height = minf(min_height, v)
		max_height = maxf(max_height, v)
	apply_rain(p_rain)


## Rain input -> D8 flow -> accumulation -> moisture + water table delta.
func apply_rain(p_rain: float) -> void:
	if p_rain < 0.0:
		push_warning("TerrainWater.apply_rain: negative rain %.3f clamped to 0." % p_rain)
		p_rain = 0.0
	rain_amount = p_rain
	compute_d8()
	compute_accumulation()
	compute_moisture()


## D8: each cell drains to its steepest-descent lower neighbor (drop over
## distance, 1.0 orthogonal / sqrt(2) diagonal), else it is a sink. Fixed
## neighbor order doubles as the tie-break order for equal slopes.
func compute_d8() -> void:
	flow_to.resize(cell_count())
	flow_to.fill(-1)
	sink_count = 0
	if heights.size() != cell_count():
		push_error("TerrainWater.compute_d8: heightfield not generated.")
		return
	for y in range(grid_h):
		for x in range(grid_w):
			var i := idx(x, y)
			var best := -1
			var best_slope := 0.0
			for off in NEIGHBOR_OFFSETS:
				var nx := x + off.x
				var ny := y + off.y
				if not in_bounds(nx, ny):
					continue
				var j := idx(nx, ny)
				var drop := heights[i] - heights[j]
				if drop <= 0.0:
					continue
				var dist := 1.0
				if off.x != 0 and off.y != 0:
					dist = sqrt(2.0)
				var slope := drop / dist
				if slope > best_slope:
					best_slope = slope
					best = j
			flow_to[i] = best
			if best == -1:
				sink_count += 1


## Accumulation: every cell starts with `rain_amount` and passes it
## downstream, processed tallest-first so upstream adds land before the
## downstream cell itself drains.
func compute_accumulation() -> void:
	accumulation.resize(cell_count())
	accumulation.fill(rain_amount)
	var h := heights
	var order: Array[int] = []
	order.resize(cell_count())
	for i in range(cell_count()):
		order[i] = i
	order.sort_custom(func(a: int, b: int) -> bool: return h[a] > h[b])
	for i in order:
		var downstream := flow_to[i]
		if downstream >= 0:
			accumulation[downstream] += accumulation[i]
	max_accumulation = rain_amount
	for v in accumulation:
		max_accumulation = maxf(max_accumulation, v)


## Moisture: log-normalized accumulation in [0, 1]; the global water table
## delta tracks mean moisture via TerrainConfig.WATER_TABLE_COEFF.
func compute_moisture() -> void:
	moisture.resize(cell_count())
	var denom := log(1.0 + max_accumulation)
	var total := 0.0
	for i in range(cell_count()):
		var m := 0.0
		if denom > 0.0:
			m = clampf(log(1.0 + accumulation[i]) / denom, 0.0, 1.0)
		moisture[i] = m
		total += m
	var mean := total / float(maxi(cell_count(), 1))
	water_table_delta = mean * Cfg.WATER_TABLE_COEFF


# --- Per-hex moisture API (consumed by the future hex overlay) ---

func get_grid_size() -> Vector2i:
	return Vector2i(grid_w, grid_h)


func get_moisture_at(cell: Vector2i) -> float:
	if not in_bounds(cell.x, cell.y):
		return 0.0
	var i := idx(cell.x, cell.y)
	if i < 0 or i >= moisture.size():
		return 0.0
	return moisture[i]


func get_all_moisture() -> Dictionary:
	var out := {}
	for y in range(grid_h):
		for x in range(grid_w):
			out[Vector2i(x, y)] = moisture[idx(x, y)]
	return out


func get_height_at(cell: Vector2i) -> float:
	if not in_bounds(cell.x, cell.y):
		return 0.0
	var i := idx(cell.x, cell.y)
	if i < 0 or i >= heights.size():
		return 0.0
	return heights[i]


func get_accumulation_at(cell: Vector2i) -> float:
	if not in_bounds(cell.x, cell.y):
		return 0.0
	var i := idx(cell.x, cell.y)
	if i < 0 or i >= accumulation.size():
		return 0.0
	return accumulation[i]


## Downstream cell, or Vector2i(-1, -1) for sinks / out-of-bounds.
func get_flow_to(cell: Vector2i) -> Vector2i:
	if not in_bounds(cell.x, cell.y):
		return OOB_FLOW
	var i := idx(cell.x, cell.y)
	if i < 0 or i >= flow_to.size():
		return OOB_FLOW
	var d := flow_to[i]
	if d < 0:
		return OOB_FLOW
	return Vector2i(d % grid_w, d / grid_w)


func get_water_table_delta() -> float:
	return water_table_delta


func mean_moisture() -> float:
	if moisture.is_empty():
		return 0.0
	var total := 0.0
	for v in moisture:
		total += v
	return total / float(moisture.size())
