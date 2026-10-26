class_name FutureStubs
extends RefCounted
## Stub APIs for systems owned by OTHER issues (issue #2 constraint).
##
## Hex overlay gameplay, store, HUD, save, and export presets are explicitly
## out of scope here. These stubs exist so callers have a stable interface
## to program against; every method warns and returns a safe default.

const Water := preload("res://scripts/terrain_water.gd")


static func hex_overlay_data(_water: Water) -> Dictionary:
	push_warning("FutureStubs.hex_overlay_data: hex overlay gameplay is not implemented (deferred).")
	return {}


static func store_catalog() -> Dictionary:
	push_warning("FutureStubs.store_catalog: store is not implemented (deferred).")
	return {}


static func hud_state(_water: Water) -> Dictionary:
	push_warning("FutureStubs.hud_state: HUD is not implemented (deferred).")
	return {}


static func save_game(_slot: String, _water: Water) -> Error:
	push_warning("FutureStubs.save_game: save is not implemented (deferred).")
	return ERR_UNAVAILABLE


## Stub result shape: {"ok": bool, "error": Error, "data": Dictionary}.
## "ok" is always false until save is implemented, so callers can tell
## "not implemented / load failed" apart from a valid (possibly empty) save.
static func load_game(_slot: String) -> Dictionary:
	push_warning("FutureStubs.load_game: save is not implemented (deferred).")
	return {"ok": false, "error": ERR_UNAVAILABLE, "data": {}}


static func export_preset(_water: Water) -> Dictionary:
	push_warning("FutureStubs.export_preset: export presets are not implemented (deferred).")
	return {}
