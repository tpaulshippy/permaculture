extends SceneTree
## Headless test for the issue #5 turn sim (pure logic, no UI).
## Run: godot --headless --path . --script res://tests/test_hud.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

const SimScript := preload("res://scripts/turn_sim.gd")

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		_failures += 1
		printerr("FAIL: ", label)


func _init() -> void:
	print("=== HUD turn-sim headless test (issue #5) ===")
	var sim = SimScript.new()
	_check(sim.setup(), "setup loads tuning + rainfall packs")
	_check(sim.is_ready(), "sim reports ready after setup")

	# Starting resources come from tuning sim_baseline (read, not changed).
	_check(is_equal_approx(sim.money, 10000.0), "money starts at tuning $10000")
	_check(is_equal_approx(sim.mh_bank, 40.0), "manhours start at tuning 40 mh grant")
	_check(is_equal_approx(sim.water_gal, 6000.0), "water reserve starts 6000 gal")
	_check(sim.month_index == 0, "month_index starts at 0")
	_check(sim.warning_text() == "", "no warning at start")

	# Rainfall text matches the Sonoran pack: Jan 21.3 mm.
	_check(sim.month_name() == "Jan", "month 0 is Jan")
	_check(is_equal_approx(sim.rain_mm(), 21.3), "Jan rainfall 21.3 mm")
	_check(sim.rain_label() == "Jan rainfall 21.3 mm", "rain label text")

	# Wind is display-only: same output, zero state change.
	var w0: String = sim.wind_label()
	var m0: float = sim.money
	var g0: float = sim.water_gal
	var h0: float = sim.mh_bank
	_check(w0.length() > 0 and w0.contains("display only"), "wind label marked display-only")
	_check(sim.money == m0 and sim.water_gal == g0 and sim.mh_bank == h0,
		"reading wind changes no resources")

	# Placement charges one-time costs (house $4000 + 40 mh).
	var res: Dictionary = sim.charge_place("house")
	_check(bool(res.get("ok")), "house charge ok")
	_check(is_equal_approx(sim.money, 6000.0), "house deducts $4000")
	_check(is_equal_approx(sim.mh_bank, 0.0), "house deducts 40 mh grant")
	_check(sim.warning_text() == "", "still no warning after affordable house")

	# Unknown items fail safe.
	var bad: Dictionary = sim.charge_place("nope")
	_check(not bool(bad.get("ok")), "unknown item rejected")

	# Next advances the month and applies house labor (+160 - 8 upkeep).
	sim.charge_place("well_l1")
	sim.charge_place("mesquite")
	var before_mh: float = sim.mh_bank
	var report: Dictionary = sim.advance_month()
	_check(bool(report.get("ok")), "advance_month ok")
	_check(sim.month_index == 1, "month_index increments")
	_check(sim.month_name() == "Feb", "month 1 is Feb")
	_check(is_equal_approx(sim.rain_mm(), 21.3), "Feb rainfall 21.3 mm")
	_check(is_equal_approx(sim.mh_bank, before_mh + 160.0 - 8.0 - 4.0 - 1.0),
		"monthly labor = +160 house - upkeep")
	_check(float(report.get("pump_gal", 0.0)) > 0.0, "well pumps water on Next")

	# Warning path (Q14): over-plant so demand outruns supply, advance
	# until the table hits 0. Banner appears, sim keeps running (no game over).
	for i in range(30):
		sim.charge_place("mesquite")
	var warned := false
	for i in range(6):
		var r: Dictionary = sim.advance_month()
		if String(r.get("warning", "")) != "":
			warned = true
			break
	_check(warned, "over-demand depletes table -> warning text")
	_check(String(sim.warning_text()).begins_with("WARNING:"),
		"warning banner text set")
	_check(String(sim.warning_text()).contains("no game over"),
		"warning cites no-game-over rule")
	var still_ok: Dictionary = sim.advance_month()
	_check(bool(still_ok.get("ok")), "Next still works while warned (no game over)")

	# Every warning branch is covered, not just water: negative money and
	# negative manhours each raise the banner on their own.
	var s_money = SimScript.new()
	_check(s_money.setup(), "second sim sets up")
	s_money.money = -5.0
	_check(String(s_money.warning_text()).contains("Money negative"),
		"negative money raises banner")
	var s_mh = SimScript.new()
	_check(s_mh.setup(), "third sim sets up")
	s_mh.mh_bank = -1.0
	_check(String(s_mh.warning_text()).contains("Manhours negative"),
		"negative manhours raise banner")

	# Yield starts with month 12 (tuning yield_start_month), counting the
	# planting month: 11 advances pay nothing, the 12th pays $12/tree.
	var s_yield = SimScript.new()
	_check(s_yield.setup(), "yield sim sets up")
	s_yield.charge_place("mesquite")
	for i in range(11):
		s_yield.advance_month()
	_check(is_equal_approx(s_yield.money, 9960.0),
		"no yield before month 12")
	s_yield.advance_month()
	_check(is_equal_approx(s_yield.money, 9972.0),
		"mesquite yields $12 from month 12")

	if _failures == 0:
		print("HUD sim test: all checks passed.")
	else:
		printerr("HUD sim test: %d FAILURES." % _failures)
	quit(1 if _failures > 0 else 0)
