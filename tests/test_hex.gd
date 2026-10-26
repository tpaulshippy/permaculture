extends SceneTree
## Headless test for the hex overlay + placement rules (issue #3).
## No UI dependency.
## Run: godot --headless --path . --script res://tests/test_hex.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

const WaterScript := preload("res://scripts/terrain_water.gd")
const HexScript := preload("res://scripts/hex_grid.gd")
const Cfg := preload("res://scripts/terrain_config.gd")

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		_failures += 1
		printerr("FAIL: ", label)


func _first_placeable(grid, item_id: String) -> Vector2i:
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var hex := Vector2i(c, r)
			if bool(grid.can_place(hex, item_id).get("ok")):
				return hex
	return Vector2i(-1, -1)


func _init() -> void:
	print("=== Hex overlay headless test (issue #3) ===")
	var water = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	water.generate(Cfg.FIXED_SEED, Cfg.DEFAULT_RAIN)
	var grid = HexScript.new()

	# Setup binds the overlay to the merged terrain_water.gd API.
	_check(grid.setup(water), "setup binds to 20x20 terrain water model")
	_check(grid.is_ready(), "grid reports ready after setup")
	_check(grid.hex_count() == 400, "overlay is 20x20 (400 hexes)")

	# Rejected setups fail safe.
	var bad_grid = HexScript.new()
	var raw = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	_check(not bad_grid.setup(raw), "setup rejects ungenerated water model")
	_check(not bad_grid.is_ready(), "rejected setup stays not-ready")
	_check(not bad_grid.can_place(Vector2i(0, 0), "house").get("ok"),
		"not-ready grid rejects placements")
	var odd_water = WaterScript.new(8, 8)
	odd_water.generate(Cfg.FIXED_SEED, Cfg.DEFAULT_RAIN)
	var odd_grid = HexScript.new()
	_check(not odd_grid.setup(odd_water), "setup rejects mismatched grid size")

	# Avg-height sampling: hex value equals the independent 3x3 mean.
	var sampling_ok := true
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var total := 0.0
			var n := 0
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					var nc := c + dc
					var nr := r + dr
					if nc < 0 or nr < 0 or nc >= Cfg.GRID_W or nr >= Cfg.GRID_H:
						continue
					total += water.get_height_at(Vector2i(nc, nr))
					n += 1
			if absf(grid.get_avg_height(Vector2i(c, r)) - total / float(n)) > 1e-5:
				sampling_ok = false
				break
	_check(sampling_ok, "avg-height sampling matches independent 3x3 mean on all 400 hexes")

	# Moisture comes straight from the D8 model.
	var moist_ok := true
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			if grid.get_moisture(Vector2i(c, r)) != water.get_moisture_at(Vector2i(c, r)):
				moist_ok = false
				break
	_check(moist_ok, "hex moisture matches TerrainWater on all 400 hexes")
	_check(grid.get_moisture(Vector2i(-1, 0)) == 0.0, "out-of-bounds moisture is 0.0")
	_check(grid.get_avg_height(Vector2i(99, 99)) == 0.0, "out-of-bounds height is 0.0")

	# Determinism: same seed -> identical overlay.
	var twin_water = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	twin_water.generate(Cfg.FIXED_SEED, Cfg.DEFAULT_RAIN)
	var twin = HexScript.new()
	twin.setup(twin_water)
	var identical := true
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var hex := Vector2i(c, r)
			if grid.get_avg_height(hex) != twin.get_avg_height(hex):
				identical = false
				break
	_check(identical, "fixed seed gives deterministic hex sampling")
	_check(twin.hint_hexes() == grid.hint_hexes(), "native hints are deterministic")

	# Native hints: 3-5 mesquite ghosts, spread out, on moist ground.
	var hints: Array = grid.hint_hexes()
	_check(hints.size() >= 3 and hints.size() <= 5, "3-5 native hints pre-placed")
	var spread_ok := true
	for a in range(hints.size()):
		for b in range(a + 1, hints.size()):
			var d: int = maxi(absi(hints[a].x - hints[b].x), absi(hints[a].y - hints[b].y))
			if d < HexScript.HINT_MIN_SEPARATION:
				spread_ok = false
	_check(spread_ok, "hints are spaced apart")
	var hint_moist_ok := true
	for h in hints:
		if grid.get_moisture(h) <= water.mean_moisture():
			hint_moist_ok = false
	_check(hint_moist_ok, "hints sit on above-average moisture (wash-side natives)")
	_check(not grid.has_plant(), "hints are ghosts: they do not count as plants")
	_check(not grid.can_advance(), "hints alone do not unlock Next")

	# World mapping round-trips through the overlay.
	var map_ok := true
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var hex := Vector2i(c, r)
			if grid.world_to_hex(grid.hex_to_world(hex)) != hex:
				map_ok = false
				break
	_check(map_ok, "hex_to_world / world_to_hex round-trips on all 400 hexes")
	_check(grid.world_to_hex(Vector3(9999, 0, 9999)) == Vector2i(-1, -1),
		"far-away world position maps out of bounds")

	# Placement rules discriminate: every item is placeable somewhere, and
	# every restricted item is rejected somewhere.
	for item in ["house", "well_l1", "ditch_berm", "mesquite"]:
		var cell := _first_placeable(grid, item)
		_check(cell != Vector2i(-1, -1), "item '%s' is placeable somewhere" % item)
	var dry_hex := Vector2i(-1, -1)
	var wash_hex := Vector2i(-1, -1)
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var hex := Vector2i(c, r)
			if grid.get_moisture(hex) < HexScript.WELL_MIN_MOISTURE and dry_hex == Vector2i(-1, -1):
				dry_hex = hex
			if grid.get_moisture(hex) > HexScript.HOUSE_MAX_MOISTURE and wash_hex == Vector2i(-1, -1):
				wash_hex = hex
	_check(dry_hex != Vector2i(-1, -1) and wash_hex != Vector2i(-1, -1),
		"terrain has both dry and wash-core cells")
	_check(not bool(grid.can_place(dry_hex, "well_l1").get("ok")),
		"well rejected on dry ground")
	_check(not bool(grid.can_place(wash_hex, "house").get("ok")),
		"house rejected in the wash core")
	var steep_hex := Vector2i(-1, -1)
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var hex := Vector2i(c, r)
			if grid.get_slope(hex) > HexScript.HOUSE_MAX_SLOPE:
				steep_hex = hex
				break
	_check(steep_hex == Vector2i(-1, -1) or not bool(grid.can_place(steep_hex, "house").get("ok")),
		"house rejected on steep ground (or terrain has no steep cells)")
	_check(not bool(grid.can_place(Vector2i(0, 0), "greenhouse").get("ok")),
		"unknown item rejected")
	_check(not bool(grid.can_place(Vector2i(-1, 0), "house").get("ok")),
		"out-of-bounds placement rejected")

	# Occupancy: structure and plant slots are independent but exclusive.
	var house_cell := _first_placeable(grid, "house")
	_check(bool(grid.place(house_cell, "house").get("ok")), "house places on valid cell")
	_check(grid.structure_at(house_cell) == "house", "structure slot reads back")
	_check(not bool(grid.can_place(house_cell, "well_l1").get("ok")),
		"second structure rejected on occupied slot")
	_check(not bool(grid.place(house_cell, "house").get("ok")),
		"double-place rejected")
	# A plant may share a hex with a structure.
	_check(bool(grid.place(house_cell, "mesquite").get("ok")),
		"mesquite shares a hex with a structure (independent slots)")
	_check(not bool(grid.place(house_cell, "mesquite").get("ok")),
		"second plant rejected on occupied plant slot")
	grid.clear_hex(house_cell)
	_check(grid.structure_at(house_cell) == "" and grid.plant_at(house_cell) == "",
		"clear_hex empties both slots")

	# Planting on a hint clears the ghost.
	var hint_cell: Vector2i = hints[0]
	_check(bool(grid.place(hint_cell, "mesquite").get("ok")), "mesquite plants on a hint hex")
	_check(not grid.is_hint(hint_cell), "planting clears the hint ghost")
	grid.clear_hex(hint_cell)

	# Q13 gating: house + well + plant required before Next unlocks.
	var gate = HexScript.new()
	gate.setup(water)
	_check(not gate.can_advance(), "fresh grid: Next locked")
	_check(gate.gate_status() == {"house": false, "well": false, "plant": false, "can_advance": false},
		"fresh gate status is all-false")
	var g_house := _first_placeable(gate, "house")
	gate.place(g_house, "house")
	_check(not gate.can_advance(), "house alone: Next still locked")
	_check("LOCKED" in gate.gate_label(), "gate label reports LOCKED")
	var g_well := _first_placeable(gate, "well_l1")
	gate.place(g_well, "well_l1")
	_check(not gate.can_advance(), "house + well: Next still locked (plant missing)")
	_check(not gate.has_plant(), "no plant yet")
	var g_ditch := _first_placeable(gate, "ditch_berm")
	gate.place(g_ditch, "ditch_berm")
	_check(not gate.can_advance(), "ditch does not substitute for the required plant")
	var g_tree := Vector2i(-1, -1)
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var hex := Vector2i(c, r)
			if hex == g_house or hex == g_well or hex == g_ditch:
				continue
			if bool(gate.can_place(hex, "mesquite").get("ok")):
				g_tree = hex
				break
		if g_tree != Vector2i(-1, -1):
			break
	_check(g_tree != Vector2i(-1, -1), "found a distinct mesquite cell")
	gate.place(g_tree, "mesquite")
	_check(gate.can_advance(), "house + well + plant: Next UNLOCKED")
	_check("UNLOCKED" in gate.gate_label(), "gate label reports UNLOCKED")
	print("gate: ", gate.gate_label())

	# Snapshot shape matches data/save_schema.json hex entries.
	var snap: Array = gate.snapshot()
	_check(snap.size() == 4, "snapshot holds exactly the 4 placed hexes")
	var snap_ok := true
	for e in snap:
		if not ("q" in e and "r" in e and "structure_id" in e and "plant_id" in e
				and "growth_stage" in e and "condition" in e):
			snap_ok = false
	_check(snap_ok, "snapshot entries carry save-schema fields")

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("TESTS FAILED: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)
