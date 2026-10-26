class_name HexGrid
extends RefCounted
## Hex overlay + placement rules for the permaculture MVP (issue #3).
##
## Pure logic, no UI dependency: safe to drive from the 3D scene
## (scripts/main.gd) and from the headless test (tests/test_hex.gd).
##
## Layout: HEX_W x HEX_H overlay in offset (col, row) coords, 1:1 with the
## TerrainWater cells (~20x20 per Q9). The mesh owns height; each hex owns
## gameplay state. Per-hex average height is sampled from the mesh by
## averaging the underlying heightfield over the hex footprint (the cell
## plus its valid 8-neighbors), and moisture is read from the D8 model via
## TerrainWater.get_moisture_at(). Tuning numbers in data/tuning.json are
## costs/upkeep only and are untouched here; placement thresholds below are
## gameplay rules justified per-item (see can_place()).
##
## Slots mirror data/save_schema.json hex entries: structures (house,
## well_l1, ditch_berm) occupy `structure_id`, plants (mesquite) occupy
## `plant_id` with `growth_stage` / `condition` defaults. One structure and
## one plant may share a hex.

const Cfg := preload("res://scripts/terrain_config.gd")

# Overlay size tracks the terrain grid (Q9 ~20x20).
const HEX_W := 20
const HEX_H := 20

# Placeable item ids match data/tuning.json exactly.
const ITEM_HOUSE := "house"
const ITEM_WELL := "well_l1"
const ITEM_DITCH := "ditch_berm"
const ITEM_MESQUITE := "mesquite"

# Slot assignment per item.
const STRUCTURE_ITEMS: Array[String] = [ITEM_HOUSE, ITEM_WELL, ITEM_DITCH]
const PLANT_ITEMS: Array[String] = [ITEM_MESQUITE]

# Q13 gating: Next unlocks once the grid holds at least one of each.
const GATE_NEED := [ITEM_HOUSE, ITEM_WELL, ITEM_MESQUITE]

# Placement rules (gameplay, not economy tuning):
# - house: needs buildable ground (gentle slope) and must stay out of the
#   wash core (flood risk). Flat, dry-ish ground.
const HOUSE_MAX_SLOPE := 0.9
const HOUSE_MAX_MOISTURE := 0.75
# - well L1: must be on moist ground. D8 moisture is the groundwater/wash
#   proxy (the carved wash band tests wetter than average), so moist cells
#   are where a well can reach water.
const WELL_MIN_MOISTURE := 0.45
# - ditch/berm: contour earthwork needs some slope to catch runoff but must
#   not sit in the channel itself (washout risk).
const DITCH_MIN_SLOPE := 0.15
const DITCH_MAX_SLOPE := 1.2
const DITCH_MAX_MOISTURE := 0.6
# - mesquite: hardy native, plantable anywhere with a free plant slot.

# Native hint markers pre-placed on moist, spread-out cells (suggested
# mesquite spots). Hints are ghosts: they never count toward Q13 gating.
const HINT_COUNT := 4
const HINT_MIN_SEPARATION := 3

const OOB_HEX := Vector2i(-1, -1)

var _water = null
var _avg_height := PackedFloat32Array()
var _moisture := PackedFloat32Array()
var _slope := PackedFloat32Array()
var _structure := PackedStringArray()
var _plant := PackedStringArray()
var _growth := PackedInt32Array()
var _condition := PackedStringArray()
var _hint := PackedByteArray()
var _ready := false


func hex_count() -> int:
	return HEX_W * HEX_H


func is_ready() -> bool:
	return _ready


func _hidx(c: int, r: int) -> int:
	return r * HEX_W + c


func in_bounds_hex(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < HEX_W and r < HEX_H


## Bind to a generated TerrainWater and sample per-hex state from the mesh.
## Mismatched grid sizes are rejected (overlay stays not-ready).
func setup(water) -> bool:
	_ready = false
	_water = null
	_avg_height.resize(0)
	_moisture.resize(0)
	_slope.resize(0)
	_structure.resize(0)
	_plant.resize(0)
	_growth.resize(0)
	_condition.resize(0)
	_hint.resize(0)
	if water == null or water.heights.is_empty():
		push_error("HexGrid.setup: terrain water model is null or ungenerated.")
		return false
	if water.grid_w != HEX_W or water.grid_h != HEX_H:
		push_error("HexGrid.setup: water grid %dx%d does not match overlay %dx%d."
			% [water.grid_w, water.grid_h, HEX_W, HEX_H])
		return false
	_water = water
	var n := hex_count()
	_avg_height.resize(n)
	_moisture.resize(n)
	_slope.resize(n)
	_structure.resize(n)
	_plant.resize(n)
	_growth.resize(n)
	_condition.resize(n)
	_hint.resize(n)
	_structure.fill("")
	_plant.fill("")
	_growth.fill(0)
	_condition.fill("healthy")
	_hint.fill(0)
	for r in range(HEX_H):
		for c in range(HEX_W):
			var i := _hidx(c, r)
			_avg_height[i] = _sample_avg_height(c, r)
			_moisture[i] = water.get_moisture_at(Vector2i(c, r))
			_slope[i] = _sample_slope(c, r)
	_ready = true
	_place_hints()
	return true


## Average heightfield height over the hex footprint: the hex cell plus its
## valid 8-neighbors (3x3 window clamped at the edges).
func _sample_avg_height(c: int, r: int) -> float:
	var total := 0.0
	var n := 0
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nc := c + dc
			var nr := r + dr
			if nc < 0 or nr < 0 or nc >= HEX_W or nr >= HEX_H:
				continue
			total += _water.get_height_at(Vector2i(nc, nr))
			n += 1
	return total / float(maxi(n, 1))


## Steepest absolute height drop/rise to any of the 8 neighbors, as
## rise-over-run using the world-space cell size.
func _sample_slope(c: int, r: int) -> float:
	var h0: float = _water.get_height_at(Vector2i(c, r))
	var steep := 0.0
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dc == 0 and dr == 0:
				continue
			var nc := c + dc
			var nr := r + dr
			if nc < 0 or nr < 0 or nc >= HEX_W or nr >= HEX_H:
				continue
			var dist := Cfg.CELL_SIZE
			if dc != 0 and dr != 0:
				dist = Cfg.CELL_SIZE * sqrt(2.0)
			var s: float = absf(_water.get_height_at(Vector2i(nc, nr)) - h0) / dist
			steep = maxf(steep, s)
	return steep


## Pre-place HINT_COUNT native (mesquite) hint ghosts on the moistest
## cells, greedily spaced at least HINT_MIN_SEPARATION apart (Chebyshev).
## Deterministic: moisture-descending order, ties broken by hex index.
func _place_hints() -> void:
	var order: Array[int] = []
	order.resize(hex_count())
	for i in range(hex_count()):
		order[i] = i
	var m := _moisture
	order.sort_custom(func(a: int, b: int) -> bool:
		if m[a] != m[b]:
			return m[a] > m[b]
		return a < b)
	var picked: Array[int] = []
	for i in order:
		if picked.size() >= HINT_COUNT:
			break
		var c := i % HEX_W
		var r := i / HEX_W
		var clear := true
		for p in picked:
			var pc := p % HEX_W
			var pr := p / HEX_W
			if maxi(absi(pc - c), absi(pr - r)) < HINT_MIN_SEPARATION:
				clear = false
				break
		if clear:
			picked.append(i)
	for i in picked:
		_hint[i] = 1


func get_avg_height(hex: Vector2i) -> float:
	if not _ready or not in_bounds_hex(hex.x, hex.y):
		return 0.0
	return _avg_height[_hidx(hex.x, hex.y)]


func get_moisture(hex: Vector2i) -> float:
	if not _ready or not in_bounds_hex(hex.x, hex.y):
		return 0.0
	return _moisture[_hidx(hex.x, hex.y)]


func get_slope(hex: Vector2i) -> float:
	if not _ready or not in_bounds_hex(hex.x, hex.y):
		return 0.0
	return _slope[_hidx(hex.x, hex.y)]


func is_hint(hex: Vector2i) -> bool:
	if not _ready or not in_bounds_hex(hex.x, hex.y):
		return false
	return _hint[_hidx(hex.x, hex.y)] == 1


func hint_hexes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _ready:
		return out
	for r in range(HEX_H):
		for c in range(HEX_W):
			if _hint[_hidx(c, r)] == 1:
				out.append(Vector2i(c, r))
	return out


func structure_at(hex: Vector2i) -> String:
	if not _ready or not in_bounds_hex(hex.x, hex.y):
		return ""
	return _structure[_hidx(hex.x, hex.y)]


func plant_at(hex: Vector2i) -> String:
	if not _ready or not in_bounds_hex(hex.x, hex.y):
		return ""
	return _plant[_hidx(hex.x, hex.y)]


static func slot_for(item_id: String) -> String:
	if item_id in STRUCTURE_ITEMS:
		return "structure"
	if item_id in PLANT_ITEMS:
		return "plant"
	return ""


static func is_known_item(item_id: String) -> bool:
	return item_id in STRUCTURE_ITEMS or item_id in PLANT_ITEMS


## Placement validation by raycast callers and tests.
## Returns {"ok": bool, "reason": String} (reason is "" when ok).
func can_place(hex: Vector2i, item_id: String) -> Dictionary:
	if not _ready:
		return {"ok": false, "reason": "grid not ready"}
	if not in_bounds_hex(hex.x, hex.y):
		return {"ok": false, "reason": "out of bounds"}
	if not is_known_item(item_id):
		return {"ok": false, "reason": "unknown item '%s'" % item_id}
	var i := _hidx(hex.x, hex.y)
	var moist := _moisture[i]
	var slope := _slope[i]
	if item_id in STRUCTURE_ITEMS:
		if _structure[i] != "":
			return {"ok": false, "reason": "structure slot occupied by '%s'" % _structure[i]}
		match item_id:
			ITEM_HOUSE:
				if slope > HOUSE_MAX_SLOPE:
					return {"ok": false, "reason": "house needs gentle ground (slope %.2f > %.2f)" % [slope, HOUSE_MAX_SLOPE]}
				if moist > HOUSE_MAX_MOISTURE:
					return {"ok": false, "reason": "house cannot sit in the wash (moisture %.2f > %.2f)" % [moist, HOUSE_MAX_MOISTURE]}
			ITEM_WELL:
				if moist < WELL_MIN_MOISTURE:
					return {"ok": false, "reason": "well needs moist ground near water (%.2f < %.2f)" % [moist, WELL_MIN_MOISTURE]}
			ITEM_DITCH:
				if slope < DITCH_MIN_SLOPE or slope > DITCH_MAX_SLOPE:
					return {"ok": false, "reason": "ditch needs mid-slope ground (slope %.2f outside %.2f..%.2f)" % [slope, DITCH_MIN_SLOPE, DITCH_MAX_SLOPE]}
				if moist > DITCH_MAX_MOISTURE:
					return {"ok": false, "reason": "ditch cannot sit in the channel (moisture %.2f > %.2f)" % [moist, DITCH_MAX_MOISTURE]}
	else:
		if _plant[i] != "":
			return {"ok": false, "reason": "plant slot occupied by '%s'" % _plant[i]}
		# Mesquite is a hardy native: no terrain restriction.
	return {"ok": true, "reason": ""}


## Apply a validated placement. Returns the can_place() result; on success
## the hex state is updated and a planting on a hint clears the ghost.
func place(hex: Vector2i, item_id: String) -> Dictionary:
	var res := can_place(hex, item_id)
	if not bool(res.get("ok", false)):
		return res
	var i := _hidx(hex.x, hex.y)
	if item_id in STRUCTURE_ITEMS:
		_structure[i] = item_id
	else:
		_plant[i] = item_id
		_growth[i] = 0
		_condition[i] = "healthy"
		_hint[i] = 0
	return {"ok": true, "reason": ""}


## Clear one hex back to empty terrain (both slots, hint kept as-is).
func clear_hex(hex: Vector2i) -> bool:
	if not in_bounds_hex(hex.x, hex.y):
		return false
	var i := _hidx(hex.x, hex.y)
	_structure[i] = ""
	_plant[i] = ""
	_growth[i] = 0
	_condition[i] = "healthy"
	return true


func count_structures(item_id: String) -> int:
	var n := 0
	for s in _structure:
		if s == item_id:
			n += 1
	return n


## Real (non-hint) plantings only: hint ghosts never satisfy gating.
func count_plants(item_id: String) -> int:
	var n := 0
	for idx in range(hex_count()):
		if _plant[idx] == item_id and _hint[idx] == 0:
			n += 1
	return n


func has_house() -> bool:
	return count_structures(ITEM_HOUSE) > 0


func has_well() -> bool:
	return count_structures(ITEM_WELL) > 0


func has_plant() -> bool:
	return count_plants(ITEM_MESQUITE) > 0


## Q13 gating: house + well L1 + plant required before Next unlocks.
func can_advance() -> bool:
	return has_house() and has_well() and has_plant()


func gate_status() -> Dictionary:
	return {
		"house": has_house(),
		"well": has_well(),
		"plant": has_plant(),
		"can_advance": can_advance(),
	}


func gate_label() -> String:
	var parts: Array[String] = []
	parts.append("house %s" % ("OK" if has_house() else "missing"))
	parts.append("well %s" % ("OK" if has_well() else "missing"))
	parts.append("plant %s" % ("OK" if has_plant() else "missing"))
	var tail := "Next UNLOCKED" if can_advance() else "Next LOCKED"
	return "Q13 [%s] -> %s" % [", ".join(parts), tail]


## Hex world-space center (matches TerrainMesh vertex layout) at the hex's
## sampled average height.
func hex_to_world(hex: Vector2i) -> Vector3:
	var px := (float(hex.x) - float(HEX_W - 1) * 0.5) * Cfg.CELL_SIZE
	var pz := (float(hex.y) - float(HEX_H - 1) * 0.5) * Cfg.CELL_SIZE
	return Vector3(px, get_avg_height(hex), pz)


## World-space position -> nearest hex, or OOB_HEX when outside the overlay.
func world_to_hex(pos: Vector3) -> Vector2i:
	var c := int(round(pos.x / Cfg.CELL_SIZE + float(HEX_W - 1) * 0.5))
	var r := int(round(pos.z / Cfg.CELL_SIZE + float(HEX_H - 1) * 0.5))
	if not in_bounds_hex(c, r):
		return OOB_HEX
	return Vector2i(c, r)


## Sparse save-shaped snapshot: only occupied hexes, field names matching
## data/save_schema.json (structure_id / plant_id / growth_stage /
## condition). Hints are gameplay ghosts and are not persisted.
func snapshot() -> Array:
	var out := []
	if not _ready:
		return out
	for r in range(HEX_H):
		for c in range(HEX_W):
			var i := _hidx(c, r)
			if _structure[i] == "" and _plant[i] == "":
				continue
			var entry := {"q": c, "r": r}
			entry["structure_id"] = _structure[i] if _structure[i] != "" else null
			entry["plant_id"] = _plant[i] if _plant[i] != "" else null
			if _plant[i] != "":
				entry["growth_stage"] = _growth[i]
				entry["condition"] = _condition[i]
			else:
				entry["growth_stage"] = null
				entry["condition"] = null
			out.append(entry)
	return out
