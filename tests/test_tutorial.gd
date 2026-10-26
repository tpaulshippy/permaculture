extends SceneTree
## Headless test for the in-app tutorial (pure logic, no UI).
## Run: godot --headless --path . --script res://tests/test_tutorial.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

const TutScript := preload("res://scripts/tutorial.gd")

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		_failures += 1
		printerr("FAIL: ", label)


func _simple_enough(text: String) -> bool:
	if text.length() > 200:
		return false
	var lower := text.to_lower()
	for word in TutScript.JARGON:
		if lower.contains(word):
			return false
	return true


func _init() -> void:
	print("=== Tutorial headless test (in-app walkthrough) ===")
	_check(TutScript.step_count() == 7, "7 steps")
	var reqs := []
	for i in range(TutScript.step_count()):
		var step: Dictionary = TutScript.step_at(i)
		_check(String(step.get("title", "")) != "", "step %d has a title" % i)
		_check(String(step.get("body", "")) != "", "step %d has a body" % i)
		_check(_simple_enough(String(step.get("body", ""))),
			"step %d plain words (short, no jargon)" % i)
		reqs.append(String(step.get("require", "")))
	_check(reqs == ["continue", "house", "well_l1", "ditch_berm", "mesquite", "month", "finish"],
		"steps run land, house, well, ditch, tree, month, tips")
	# Fresh garden: only the tap-to-continue step is satisfied.
	var empty := {"house": 0, "well_l1": 0, "ditch_berm": 0, "mesquite": 0, "months": 0}
	_check(TutScript.is_satisfied("continue", empty), "continue always satisfied")
	_check(TutScript.is_satisfied("finish", empty), "finish always satisfied")
	for r in ["house", "well_l1", "ditch_berm", "mesquite", "month"]:
		_check(not TutScript.is_satisfied(r, empty), "empty garden blocks '%s'" % r)
	# Each gameplay step unlocks on its own action only.
	var kinds := ["house", "well_l1", "ditch_berm", "mesquite"]
	for k in kinds:
		var s := {"house": 0, "well_l1": 0, "ditch_berm": 0, "mesquite": 0, "months": 0}
		s[k] = 1
		_check(TutScript.is_satisfied(k, s), "'%s' satisfied by its own action" % k)
		for other in kinds:
			if other != k:
				_check(not TutScript.is_satisfied(other, s),
					"'%s' does not unlock '%s'" % [k, other])
		_check(not TutScript.is_satisfied("month", s), "placements do not unlock month")
	var m := {"house": 1, "well_l1": 1, "ditch_berm": 1, "mesquite": 1, "months": 0}
	_check(not TutScript.is_satisfied("month", m), "month needs a Next press")
	m["months"] = 1
	for r in ["house", "well_l1", "ditch_berm", "mesquite", "month"]:
		_check(TutScript.is_satisfied(r, m), "full garden satisfies '%s'" % r)
	_check(not TutScript.is_satisfied("nope", m), "unknown requirement fails closed")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	quit(1 if _failures > 0 else 0)
