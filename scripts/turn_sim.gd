class_name TurnSim
extends RefCounted
## Turn/wizard economy for the HUD (issue #5). Pure logic, no UI dependency.
##
## Reads costs/upkeep from data/tuning.json (read-only, numbers never changed
## here) and monthly rainfall from data/sonoran_rainfall.json. Tracks
## money_usd / manhour bank / water reserve across Next presses.
##
## Monthly math (documented, deterministic, Q11 no-RNG):
## - upkeep_usd = per-item upkeep_usd_per_mo summed over placements
##   (80/house, 15/well_L1, 0 elsewhere per current tuning)
## - upkeep_mh  = 8/house + 4/well + 2/ditch + 1/mesquite
## - provided_mh = 160/house; mh_bank += provided - upkeep
## - mature mesquite (age in months >= yield_start_month 12, counting the
##   planting month) pays yield_usd_per_mo 12
## - rain_gal_ref = month_mm * (1000 / avg_monthly_mm): scales the tuning
##   1000 gal/mo reference plot-rainfall by actual biome rainfall
## - capture recharges the table: min(base 5% + 12 %/ditch, 60 %) * rain_gal
## - pump capacity = 2500/well (tuning pump_gal_per_mo). The well draws from
##   the table, so it can only deliver what the table holds and never raises
##   it: delivered = min(capacity, demand, table + capture). Unmet demand is
##   an irrigation shortfall (advisory warning, Q14).
##
## Warnings (Q14): money < 0, mh_bank < 0, irrigation shortfall > 0, or water
## table at 0. Advisory only: they NEVER block, no game over, Next works.
## Wind is display-only (Q12): deterministic from month_index, zero effect.

const TUNING_PATH := "res://data/tuning.json"
const RAIN_PATH := "res://data/sonoran_rainfall.json"

const WATER_CAP_GAL := 10000.0
const START_WATER_GAL := 6000.0
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const WIND_DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var _ready := false
var _items := {}
var _rain_mm: Array[float] = []
var _avg_mm := 0.0
var _annual_mm := 0.0
var _start_money := 10000.0
var _start_mh := 40.0
var _base_capture := 0.05
var _ref_rain := 1000.0

var month_index := 0
var money := 0.0
var mh_bank := 0.0
## Usable groundwater stock. Wells draw from it (never add to it); ditch
## capture recharges it. Displayed as the water-table bar.
var water_gal := START_WATER_GAL
var houses := 0
var wells := 0
var ditches := 0
var mesquite := 0
var _planted_at: Array[int] = []
var _last_unmet := 0.0


func is_ready() -> bool:
	return _ready


static func _num(d: Dictionary, key: String) -> float:
	return float(d.get(key, 0.0))


## Load tuning + rainfall packs. Returns false (stays not-ready) on any
## missing file / parse error so callers fail safe.
func setup() -> bool:
	_ready = false
	var tuning := _load_json(TUNING_PATH)
	var rain := _load_json(RAIN_PATH)
	if tuning.is_empty() or rain.is_empty():
		push_error("TurnSim.setup: missing tuning or rainfall pack.")
		return false
	if not tuning.has("items") or not rain.has("rainfall_mm"):
		push_error("TurnSim.setup: pack shape unexpected.")
		return false
	_items.clear()
	for entry in tuning["items"]:
		_items[String(entry["id"])] = entry
	_rain_mm.clear()
	for v in rain["rainfall_mm"]:
		_rain_mm.append(float(v))
	if _rain_mm.size() != 12:
		push_error("TurnSim.setup: need 12 monthly rainfall values.")
		return false
	_annual_mm = 0.0
	for v in _rain_mm:
		_annual_mm += v
	_avg_mm = _annual_mm / 12.0
	var base: Dictionary = tuning.get("meta", {}).get("sim_baseline", {})
	_start_money = float(base.get("starting_money_usd", 10000.0))
	_start_mh = float(base.get("starting_manhours_mh", 40.0))
	_base_capture = float(base.get("base_rain_capture_percent", 5.0)) / 100.0
	_ref_rain = float(base.get("rainfall_reference_gal_per_mo", 1000.0))
	reset()
	_ready = true
	return true


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func reset() -> void:
	month_index = 0
	money = _start_money
	mh_bank = _start_mh
	water_gal = START_WATER_GAL
	houses = 0
	wells = 0
	ditches = 0
	mesquite = 0
	_planted_at.clear()
	_last_unmet = 0.0


func start_money() -> float:
	return _start_money


func rain_mm(month: int = -1) -> float:
	if _rain_mm.is_empty():
		return 0.0
	var m := month if month >= 0 else month_index % 12
	return _rain_mm[posmod(m, 12)]


func month_name(month: int = -1) -> String:
	var m := month if month >= 0 else month_index % 12
	return MONTHS[posmod(m, 12)]


## Display-only wind (Q12): deterministic breeze from the month counter.
## Pure function of month_index; never touches money/water/manhours.
func wind_label(month: int = -1) -> String:
	var m := month if month >= 0 else month_index
	var dir: String = WIND_DIRS[posmod(m, WIND_DIRS.size())]
	var speed := 6 + posmod(m * 5 + 3, 14)
	return "Wind %s %d km/h (display only)" % [dir, speed]


func water_pct() -> float:
	return clampf(water_gal / WATER_CAP_GAL * 100.0, 0.0, 100.0)


## Charge one-time build costs for a validated placement. Always applied
## (balances may go negative -> warning path, never a block, Q14).
func charge_place(item_id: String) -> Dictionary:
	if not _ready:
		return {"ok": false, "reason": "sim not ready"}
	if not _items.has(item_id):
		return {"ok": false, "reason": "unknown item '%s'" % item_id}
	var spec: Dictionary = _items[item_id]
	money -= _num(spec, "cost_usd")
	mh_bank -= _num(spec, "build_manhours")
	match item_id:
		"house":
			houses += 1
		"well_l1":
			wells += 1
		"ditch_berm":
			ditches += 1
		"mesquite":
			mesquite += 1
			_planted_at.append(month_index)
	return {"ok": true, "reason": ""}


## Advance one month. Applies upkeep, labor, yield, and the water-table
## balance for the CURRENT month, then month_index += 1. The returned
## "month"/"rain_mm" describe the month just processed (not the new one).
func advance_month() -> Dictionary:
	if not _ready:
		return {"ok": false, "reason": "sim not ready"}
	var done_name := month_name()
	var mm := rain_mm(month_index % 12)
	var counts := {"house": houses, "well_l1": wells,
		"ditch_berm": ditches, "mesquite": mesquite}
	var upkeep_usd := 0.0
	for id in counts.keys():
		if _items.has(id):
			upkeep_usd += _num(_items[id], "upkeep_usd_per_mo") * counts[id]
	var upkeep_mh := 0.0
	var provided_mh := 0.0
	if _items.has("house"):
		var h: Dictionary = _items["house"]
		upkeep_mh += _num(h, "upkeep_manhours_per_mo") * houses
		provided_mh += _num(h, "provides_manhours_per_mo") * houses
	if _items.has("well_l1"):
		upkeep_mh += _num(_items["well_l1"], "upkeep_manhours_per_mo") * wells
	if _items.has("ditch_berm"):
		upkeep_mh += _num(_items["ditch_berm"], "upkeep_manhours_per_mo") * ditches
	var yield_usd := 0.0
	if _items.has("mesquite"):
		var p: Dictionary = _items["mesquite"]
		upkeep_mh += _num(p, "upkeep_manhours_per_mo") * mesquite
		var ystart := int(_num(p, "yield_start_month") if p.has("yield_start_month") else 12.0)
		var mature := 0
		for planted in _planted_at:
			if month_index - planted + 1 >= ystart:
				mature += 1
		yield_usd = _num(p, "yield_usd_per_mo") * mature
	var rain_gal := mm * (_ref_rain / _avg_mm) if _avg_mm > 0.0 else 0.0
	var ditch_pct := 0.0
	if _items.has("ditch_berm"):
		ditch_pct = _num(_items["ditch_berm"], "retention_percent") / 100.0
	var capture := minf(_base_capture + ditch_pct * ditches, 0.60) * rain_gal
	var pump_cap := 0.0
	var demand := 0.0
	if _items.has("well_l1"):
		pump_cap = _num(_items["well_l1"], "pump_gal_per_mo") * wells
	if _items.has("mesquite"):
		demand = _num(_items["mesquite"], "water_need_gal_per_mo") * mesquite
	# Wells draw from the table: delivery is capped by demand and by what
	# the table holds (plus this month's recharge), so wells never raise it.
	var delivered := minf(pump_cap, minf(demand, water_gal + capture))
	money += yield_usd - upkeep_usd
	mh_bank += provided_mh - upkeep_mh
	water_gal = clampf(water_gal + capture - delivered, 0.0, WATER_CAP_GAL)
	_last_unmet = maxf(demand - delivered, 0.0)
	month_index += 1
	return {
		"ok": true,
		"month": done_name,
		"rain_mm": mm,
		"upkeep_usd": upkeep_usd,
		"yield_usd": yield_usd,
		"pump_gal": delivered,
		"capture_gal": capture,
		"demand_gal": demand,
		"unmet_gal": _last_unmet,
		"warning": warning_text(),
	}


## Red-banner text, or "" when all clear. Advisory only (Q14: no game over).
func warning_text() -> String:
	if not _ready:
		return ""
	var parts: Array[String] = []
	if money < 0.0:
		parts.append("Money negative ($%.0f)" % money)
	if mh_bank < 0.0:
		parts.append("Manhours negative (%.0f mh)" % mh_bank)
	if _last_unmet > 0.0:
		parts.append("Irrigation shortfall %.0f gal" % _last_unmet)
	if water_gal <= 0.0:
		parts.append("Water table depleted")
	if parts.is_empty():
		return ""
	return "WARNING: %s — no game over (Q14)" % "; ".join(parts)


func rain_label() -> String:
	return "%s rainfall %.1f mm" % [month_name(), rain_mm()]


func month_label() -> String:
	return "Month %d (%s)" % [month_index + 1, month_name()]
