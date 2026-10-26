extends SceneTree
## Headless test for the terrain MVP (issue #2). No UI dependency.
## Run: godot --headless --path . --script res://tests/test_terrain.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

const WaterScript := preload("res://scripts/terrain_water.gd")
const MeshScript := preload("res://scripts/terrain_mesh.gd")
const Stubs := preload("res://scripts/future_stubs.gd")
const Cfg := preload("res://scripts/terrain_config.gd")

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		_failures += 1
		printerr("FAIL: ", label)


func _init() -> void:
	print("=== Terrain MVP headless test (issue #2) ===")
	var water = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	water.generate(Cfg.FIXED_SEED, Cfg.DEFAULT_RAIN)

	print("seed=", water.seed_used,
		" grid=", water.get_grid_size(),
		" rain=", water.rain_amount)
	print("height_min=%.4f height_max=%.4f" % [water.min_height, water.max_height])
	print("sinks=", water.sink_count,
		" max_accum=%.4f" % water.max_accumulation,
		" mean_moisture=%.4f" % water.mean_moisture(),
		" water_table_delta=%.4f" % water.get_water_table_delta())

	# Grid contract.
	_check(water.get_grid_size() == Vector2i(20, 20), "grid is 20x20 hex equivalent")
	_check(water.cell_count() == 400, "cell count is 400")
	_check(water.heights.size() == 400, "heightfield has one sample per cell")

	# Determinism: same fixed seed -> identical terrain and water.
	var twin = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	twin.generate(Cfg.FIXED_SEED, Cfg.DEFAULT_RAIN)
	var identical := true
	for i in range(water.cell_count()):
		if water.heights[i] != twin.heights[i] or water.moisture[i] != twin.moisture[i]:
			identical = false
			break
	_check(identical, "fixed seed is deterministic (heights + moisture identical)")

	# Different seed -> different terrain (sanity that seed matters).
	var other = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	other.generate(Cfg.FIXED_SEED + 1, Cfg.DEFAULT_RAIN)
	var differs := false
	for i in range(water.cell_count()):
		if water.heights[i] != other.heights[i]:
			differs = true
			break
	_check(differs, "different seed produces different terrain")

	# D8 validity: every non-sink cell drains to a strictly lower neighbor.
	var d8_valid := true
	for y in range(Cfg.GRID_H):
		for x in range(Cfg.GRID_W):
			var cell := Vector2i(x, y)
			var down := water.get_flow_to(cell)
			if down == Vector2i(-1, -1):
				continue
			if not water.in_bounds(down.x, down.y):
				d8_valid = false
				break
			var dx := absi(down.x - x)
			var dy := absi(down.y - y)
			if dx > 1 or dy > 1 or (dx == 0 and dy == 0):
				d8_valid = false
				break
			if not water.get_height_at(down) < water.get_height_at(cell):
				d8_valid = false
				break
	_check(d8_valid, "D8 flow targets are strictly lower neighbors")
	_check(water.sink_count > 0, "terrain has at least one sink")
	_check(water.sink_count < water.cell_count(), "terrain is not all sinks")

	# Accumulation: sources keep exactly `rain`, convergence exceeds it.
	var acc_min := 1e30
	for v in water.accumulation:
		acc_min = minf(acc_min, v)
	_check(absf(acc_min - Cfg.DEFAULT_RAIN) < 1e-6, "source cells accumulate exactly rain input")
	_check(water.max_accumulation > Cfg.DEFAULT_RAIN, "flow converges (max accumulation exceeds rain)")

	# Moisture: bounded, max-normalized, API consistent.
	var m_min := 1e30
	var m_max := -1e30
	for v in water.moisture:
		m_min = minf(m_min, v)
		m_max = maxf(m_max, v)
	_check(m_min >= 0.0 and m_max <= 1.0, "moisture in [0, 1]")
	_check(absf(m_max - 1.0) < 1e-6, "wettest cell normalizes to moisture 1.0")
	_check(absf(water.get_moisture_at(Vector2i(0, 0)) - water.moisture[0]) < 1e-9,
		"get_moisture_at matches internal array")
	_check(water.get_moisture_at(Vector2i(-1, 0)) == 0.0, "out-of-bounds moisture is 0.0")
	_check(water.get_flow_to(Vector2i(-5, 99)) == Vector2i(-1, -1),
		"out-of-bounds flow is (-1, -1)")
	_check(water.get_all_moisture().size() == water.cell_count(),
		"get_all_moisture exposes every cell")

	# Water table delta tracks mean moisture.
	var expected_wtd := water.mean_moisture() * Cfg.WATER_TABLE_COEFF
	_check(absf(water.get_water_table_delta() - expected_wtd) < 1e-6,
		"water table delta = mean moisture * coeff")
	_check(water.get_water_table_delta() > 0.0
		and water.get_water_table_delta() <= Cfg.WATER_TABLE_COEFF,
		"water table delta in (0, coeff]")

	# Sonoran structure: the carved wash band collects more water than average.
	var band_total := 0.0
	var band_n := 0
	for y in range(Cfg.GRID_H):
		var fy := float(y) / float(Cfg.GRID_H - 1)
		var center_x := float(Cfg.GRID_W) * (Cfg.WASH_START_FRACTION + fy * Cfg.WASH_DRIFT_FRACTION)
		for x in range(Cfg.GRID_W):
			if absf(float(x) - center_x) <= Cfg.WASH_SIGMA:
				band_total += water.get_moisture_at(Vector2i(x, y))
				band_n += 1
	var band_mean := band_total / float(maxi(band_n, 1))
	print("wash_band_cells=", band_n,
		" wash_band_mean_moisture=%.4f" % band_mean)
	_check(band_mean > water.mean_moisture(), "wash band is wetter than terrain average")

	# Config is the single tuning source: defaults track TerrainConfig.
	var defaults = WaterScript.new()
	_check(defaults.grid_w == Cfg.GRID_W and defaults.grid_h == Cfg.GRID_H,
		"TerrainWater defaults track TerrainConfig grid size")
	_check(defaults.seed_used == Cfg.FIXED_SEED and defaults.rain_amount == Cfg.DEFAULT_RAIN,
		"TerrainWater defaults track TerrainConfig seed and rain")

	# Degenerate grids are rejected without crashing.
	var tiny = WaterScript.new(1, 5)
	tiny.generate()
	_check(tiny.heights.is_empty(), "1-wide grid is rejected (no heightfield)")
	_check(tiny.get_height_at(Vector2i(0, 0)) == 0.0,
		"rejected grid height reads as 0.0")
	var empty = WaterScript.new(0, 0)
	empty.generate()
	_check(empty.heights.is_empty() and empty.mean_moisture() == 0.0,
		"0x0 grid is rejected (no heightfield, zero moisture)")

	# Negative rain clamps to zero instead of producing nonsense.
	var dry = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	dry.generate(Cfg.FIXED_SEED, -2.0)
	_check(dry.rain_amount == 0.0, "negative rain clamps to 0")
	var dry_max := 0.0
	for v in dry.moisture:
		dry_max = maxf(dry_max, v)
	_check(dry_max == 0.0, "clamped rain yields zero moisture everywhere")

	# D8 follows steepest descent, not merely the lowest neighbor: an
	# orthogonal drop of 0.2 (slope 0.2) must beat a diagonal drop of 0.25
	# (slope 0.25 / sqrt(2) ~= 0.177).
	var slope_test = WaterScript.new(3, 3)
	slope_test.heights.resize(9)
	slope_test.heights.fill(5.0)
	slope_test.heights[slope_test.idx(1, 1)] = 2.0
	slope_test.heights[slope_test.idx(2, 1)] = 1.8
	slope_test.heights[slope_test.idx(2, 2)] = 1.75
	slope_test.compute_d8()
	_check(slope_test.get_flow_to(Vector2i(1, 1)) == Vector2i(2, 1),
		"D8 follows steepest descent (orthogonal beats deeper diagonal)")

	# Mesh builder smoke test in both render modes.
	var mesh_terrain: ArrayMesh = MeshScript.build_array_mesh(water, MeshScript.RenderMode.TERRAIN)
	var mesh_moisture: ArrayMesh = MeshScript.build_array_mesh(water, MeshScript.RenderMode.MOISTURE)
	_check(mesh_terrain.get_surface_count() == 1 and mesh_moisture.get_surface_count() == 1,
		"mesh builder emits one surface per render mode")
	_check(mesh_terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == water.cell_count(),
		"mesh has one vertex per cell")

	# Perimeter normals use a one-sided difference: on an x-ramp the corner
	# normal must be (-0.5, 1, 0) normalized, not the halved central value.
	var ramp = WaterScript.new(3, 3)
	ramp.heights.resize(9)
	for yy in range(3):
		for xx in range(3):
			ramp.heights[yy * 3 + xx] = float(xx)
	var corner_n: Vector3 = MeshScript.grid_normal(ramp, 0, 0)
	_check(absf(corner_n.x - (-0.5 / sqrt(1.25))) < 1e-5 and absf(corner_n.z) < 1e-6,
		"corner normal uses one-sided derivative")

	# Deferred-system stubs keep their safe-default contract with an explicit
	# error channel on load.
	_check(Stubs.save_game("slot1", water) == ERR_UNAVAILABLE,
		"save_game stub returns ERR_UNAVAILABLE")
	var load_res: Dictionary = Stubs.load_game("slot1")
	_check(load_res.get("ok") == false and load_res.get("error") == ERR_UNAVAILABLE,
		"load_game stub reports explicit error channel")

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("TESTS FAILED: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)
