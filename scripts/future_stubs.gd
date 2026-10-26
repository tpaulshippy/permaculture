class_name FutureStubs
extends RefCounted
## Stub APIs for systems owned by OTHER issues (issue #2 constraint).
##
## Hex overlay gameplay, store, HUD, save, and export presets are explicitly
## out of scope here. These stubs exist so callers have a stable interface
## to program against; every method warns and returns a safe default.


static func hex_overlay_data(_water: RefCounted) -> Dictionary:
	push_warning("FutureStubs.hex_overlay_data: hex overlay gameplay is not implemented (deferred).")
	return {}


static func store_catalog() -> Dictionary:
	push_warning("FutureStubs.store_catalog: store is not implemented (deferred).")
	return {}


static func hud_state(_water: RefCounted) -> Dictionary:
	push_warning("FutureStubs.hud_state: HUD is not implemented (deferred).")
	return {}


static func save_game(_slot: String, _water: RefCounted) -> Error:
	push_warning("FutureStubs.save_game: save is not implemented (deferred).")
	return ERR_UNAVAILABLE


static func load_game(_slot: String) -> Dictionary:
	push_warning("FutureStubs.load_game: save is not implemented (deferred).")
	return {}


static func export_preset(_water: RefCounted) -> Dictionary:
	push_warning("FutureStubs.export_preset: export presets are not implemented (deferred).")
	return {}
