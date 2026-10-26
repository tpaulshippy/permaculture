extends Node3D
## Terrain + hex overlay scene driver (issues #2, #3).
##
## Builds the deterministic Sonoran heightmap mesh (fixed seed) in TERRAIN,
## MOISTURE, or HEX render mode, with a ~20x20 hex gameplay overlay on top
## (scripts/hex_grid.gd). Supports viewport captures for evidence via an
## offscreen SubViewport (robust when the main window is not drawable):
##   godot --path . -- --capture-mode=terrain --capture-path=/tmp/terrain_topdown.png
##   godot --path . -- --capture-mode=hex --capture-path=/tmp/hex_overlay.png
##
## Interactive play: drag to orbit, wheel to zoom, click terrain to place the
## selected item (keys 1-4 or HUD buttons), N or the HUD button for Next
## (Q13 gating: house + well L1 + mesquite required before Next unlocks).
## Scripted demo for screen recordings:
##   godot --path . --resolution 1280x720 -- --demo

const WaterScript := preload("res://scripts/terrain_water.gd")
const MeshScript := preload("res://scripts/terrain_mesh.gd")
const HexScript := preload("res://scripts/hex_grid.gd")
const Cfg := preload("res://scripts/terrain_config.gd")

const CAPTURE_AFTER_FRAMES := 30
const CAPTURE_SIZE := Vector2i(1280, 720)

const SELECT_KEYS := {
	KEY_1: "house",
	KEY_2: "well_l1",
	KEY_3: "ditch_berm",
	KEY_4: "mesquite",
}

# Scripted demo timeline (seconds): orbit + place house/well/ditch/plant.
const DEMO_EVENTS := [
	{"t": 2.0, "item": "house"},
	{"t": 5.0, "item": "well_l1"},
	{"t": 8.0, "item": "ditch_berm"},
	{"t": 11.0, "item": "mesquite"},
]
const DEMO_QUIT_AFTER := 26.0
const DEMO_ORBIT_SPEED := deg_to_rad(14.0)
# In-engine frame recording (evidence video when no display capturer is
# available to this session): --demo-record=<dir> dumps viewport frames,
# assembled afterwards with ffmpeg. Fixed demo-time spacing keeps the video
# time-accurate even if render FPS varies.
const DEMO_RECORD_FPS := 24.0
const DEMO_RECORD_MAX_FRAMES := 700

var _capture_mode := ""
var _capture_path := ""
var _demo := false
var _record_dir := ""
var _record_index := 0
var _record_accum := 0.0
var _frames := 0
var _capture_failed := false
var _offscreen: SubViewport

var _water = null
var _hex = null
var _cam: Camera3D
var _overlay: Node3D
var _selected := "house"
var _status_label: Label
var _gate_label: Label
var _next_button: Button
var _item_buttons := {}

# Orbit state.
var _yaw := 0.0
var _pitch := 0.62
var _dist := 0.0
var _dragging := false
var _press_pos := Vector2.ZERO
var _moved := false

# Demo state.
var _demo_time := 0.0
var _demo_step := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-mode="):
			_capture_mode = arg.trim_prefix("--capture-mode=")
		elif arg.begins_with("--capture-path="):
			_capture_path = arg.trim_prefix("--capture-path=")
		elif arg == "--demo":
			_demo = true
		elif arg.begins_with("--demo-record="):
			_demo = true
			_record_dir = arg.trim_prefix("--demo-record=")
	var mode: int = MeshScript.RenderMode.TERRAIN
	if _capture_mode == "" or _capture_mode == "terrain":
		mode = MeshScript.RenderMode.TERRAIN
	elif _capture_mode == "moisture":
		mode = MeshScript.RenderMode.MOISTURE
	elif _capture_mode == "hex":
		mode = MeshScript.RenderMode.TERRAIN
	else:
		push_warning("Unknown capture mode '%s', using terrain." % _capture_mode)
	_build(mode)


func _framing() -> Dictionary:
	var span := float(maxi(Cfg.GRID_W, Cfg.GRID_H)) * Cfg.CELL_SIZE
	return {
		"cam_pos": Vector3(0.0, span * 1.08, span * 0.35),
		"cam_fov": 50.0,
		"sun_rot": Vector3(-48.0, -32.0, 0.0),
	}


func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	return mat


func _build(mode: int) -> void:
	_water = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	_water.generate(Cfg.FIXED_SEED, Cfg.DEFAULT_RAIN)
	_hex = HexScript.new()
	if not _hex.setup(_water):
		push_error("Hex overlay setup failed.")
	var mesh: ArrayMesh = MeshScript.build_array_mesh(_water, mode)
	var framing := _framing()
	# On-screen scene (interactive viewing).
	var mi := $MeshInstance3D as MeshInstance3D
	mi.mesh = mesh
	mi.set_surface_override_material(0, _make_material())
	_cam = $Camera3D as Camera3D
	_cam.position = framing["cam_pos"]
	_cam.fov = framing["cam_fov"]
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.current = true
	_yaw = atan2(_cam.position.x, _cam.position.z)
	var flat := Vector2(_cam.position.x, _cam.position.z).length()
	_pitch = atan2(_cam.position.y, flat)
	_dist = _cam.position.length()
	var sun := $Sun as DirectionalLight3D
	sun.rotation_degrees = framing["sun_rot"]
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	# Offscreen capture viewport (evidence screenshots). It shares the main
	# world and only adds its own camera, so exactly the on-screen scene is
	# rendered into an always-valid render target.
	if _capture_path != "":
		_make_offscreen()
	# Static body so mouse clicks raycast onto the heightfield.
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	col.shape = shape
	body.add_child(col)
	add_child(body)
	# Hex overlay visuals: grid lines, hint ghosts, placed-item markers.
	_overlay = Node3D.new()
	_overlay.name = "HexOverlay"
	add_child(_overlay)
	_build_grid_lines()
	_build_hints()
	if _capture_mode == "hex":
		_place_capture_set()
	_build_hud()
	_refresh_hud("Select an item (1-4) and click the terrain.")
	if _demo:
		_selected = "house"
		_dist *= 0.8
		_apply_orbit()
		if _record_dir != "":
			DirAccess.make_dir_recursive_absolute(_record_dir)
		_refresh_hud("Demo running: scripted placements + orbit.")


func _build_grid_lines() -> void:
	var verts := PackedVector3Array()
	var w: int = Cfg.GRID_W
	var h: int = Cfg.GRID_H
	var cell: float = Cfg.CELL_SIZE
	# Corner heights: mean of adjacent cell heights.
	var corner := PackedFloat32Array()
	corner.resize((w + 1) * (h + 1))
	for j in range(h + 1):
		for i in range(w + 1):
			var total := 0.0
			var n := 0
			for dj in [-1, 0]:
				for di in [-1, 0]:
					var cx: int = i + di
					var cy: int = j + dj
					if cx >= 0 and cy >= 0 and cx < w and cy < h:
						total += _water.heights[cy * w + cx]
						n += 1
			corner[j * (w + 1) + i] = total / float(maxi(n, 1)) + 0.12
	for j in range(h + 1):
		for i in range(w):
			var a := j * (w + 1) + i
			var b := a + 1
			verts.append(_corner_pos(i, j, w, h, cell, corner[a]))
			verts.append(_corner_pos(i + 1, j, w, h, cell, corner[b]))
	for j in range(h):
		for i in range(w + 1):
			var a := j * (w + 1) + i
			var b := a + (w + 1)
			verts.append(_corner_pos(i, j, w, h, cell, corner[a]))
			verts.append(_corner_pos(i, j + 1, w, h, cell, corner[b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var lines := ArrayMesh.new()
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.10, 0.06, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.set_surface_override_material(0, mat)
	_overlay.add_child(mi)


func _corner_pos(i: int, j: int, w: int, h: int, cell: float, y: float) -> Vector3:
	return Vector3((float(i) - float(w) * 0.5) * cell, y, (float(j) - float(h) * 0.5) * cell)


func _marker_mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.roughness = 0.8
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _build_hints() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.08
	var mat := _marker_mat(Color(0.25, 0.85, 0.35), 0.55)
	for hex in _hex.hint_hexes():
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.set_surface_override_material(0, mat)
		var p: Vector3 = _hex.hex_to_world(hex)
		p.y = _water.get_height_at(hex) + 0.25
		mi.position = p
		mi.name = "Hint_%d_%d" % [hex.x, hex.y]
		_overlay.add_child(mi)


func _spawn_marker(hex: Vector2i, item_id: String) -> void:
	var root := Node3D.new()
	root.name = "Marker_%s_%d_%d" % [item_id, hex.x, hex.y]
	var base_y: float = _water.get_height_at(hex)
	match item_id:
		"house":
			var walls := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.3, 0.9, 1.1)
			walls.mesh = box
			walls.set_surface_override_material(0, _marker_mat(Color(0.55, 0.32, 0.16)))
			walls.position.y = 0.45
			root.add_child(walls)
			var roof := MeshInstance3D.new()
			var prism := BoxMesh.new()
			prism.size = Vector3(1.5, 0.18, 1.3)
			roof.mesh = prism
			roof.set_surface_override_material(0, _marker_mat(Color(0.35, 0.18, 0.10)))
			roof.position.y = 1.0
			root.add_child(roof)
		"well_l1":
			var shaft := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.45
			cyl.bottom_radius = 0.5
			cyl.height = 0.9
			shaft.mesh = cyl
			shaft.set_surface_override_material(0, _marker_mat(Color(0.45, 0.47, 0.50)))
			shaft.position.y = 0.45
			root.add_child(shaft)
			var water_top := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.36
			disc.bottom_radius = 0.36
			disc.height = 0.06
			water_top.mesh = disc
			water_top.set_surface_override_material(0, _marker_mat(Color(0.10, 0.35, 0.85)))
			water_top.position.y = 0.93
			root.add_child(water_top)
		"ditch_berm":
			var berm := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.9, 0.28, 0.7)
			berm.mesh = box
			berm.set_surface_override_material(0, _marker_mat(Color(0.72, 0.58, 0.36)))
			berm.position.y = 0.14
			berm.rotation.y = PI / 4.0
			root.add_child(berm)
		"mesquite":
			var trunk := MeshInstance3D.new()
			var tc := CylinderMesh.new()
			tc.top_radius = 0.10
			tc.bottom_radius = 0.14
			tc.height = 0.9
			trunk.mesh = tc
			trunk.set_surface_override_material(0, _marker_mat(Color(0.30, 0.20, 0.12)))
			trunk.position.y = 0.45
			root.add_child(trunk)
			var canopy := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.75
			ball.height = 1.1
			canopy.mesh = ball
			canopy.set_surface_override_material(0, _marker_mat(Color(0.22, 0.48, 0.20)))
			canopy.position.y = 1.35
			root.add_child(canopy)
	var p: Vector3 = _hex.hex_to_world(hex)
	p.y = base_y
	root.position = p
	_overlay.add_child(root)
	# A real planting clears its hint ghost if present.
	var ghost := _overlay.get_node_or_null("Hint_%d_%d" % [hex.x, hex.y])
	if ghost != null and item_id == "mesquite":
		ghost.queue_free()


func _nearest_placeable(item_id: String, used: Dictionary) -> Vector2i:
	# Nearest-to-center valid cell: keeps evidence stills and the demo
	# readable instead of stacking markers in a terrain corner.
	var best := Vector2i(-1, -1)
	var best_d := 1e30
	var center := Vector2(9.5, 9.5)
	for r in range(HexScript.HEX_H):
		for c in range(HexScript.HEX_W):
			var hex := Vector2i(c, r)
			if hex in used:
				continue
			if item_id == "mesquite" and _hex.is_hint(hex):
				continue
			if not bool(_hex.can_place(hex, item_id).get("ok")):
				continue
			var d := center.distance_to(Vector2(c, r))
			if d < best_d:
				best_d = d
				best = hex
	return best


func _place_capture_set() -> void:
	# Deterministic pre-placements for still evidence: house, well, ditch on
	# distinct hexes plus one mesquite off the hint cells (ghosts stay visible).
	var used := {}
	for item in ["house", "well_l1", "ditch_berm", "mesquite"]:
		var hex := _nearest_placeable(item, used)
		if hex != Vector2i(-1, -1) and bool(_hex.place(hex, item).get("ok")):
			used[hex] = true
			_spawn_marker(hex, item)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Hex overlay (issue #3) — click terrain to place"
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	for item in ["house", "well_l1", "ditch_berm", "mesquite"]:
		var b := Button.new()
		b.text = "[%d] %s" % [["house", "well_l1", "ditch_berm", "mesquite"].find(item) + 1, item]
		b.toggle_mode = true
		b.pressed.connect(_on_item_button.bind(item))
		row.add_child(b)
		_item_buttons[item] = b
	_item_buttons[_selected].button_pressed = true
	_gate_label = Label.new()
	box.add_child(_gate_label)
	_status_label = Label.new()
	box.add_child(_status_label)
	_next_button = Button.new()
	_next_button.text = "Next turn (N)"
	_next_button.pressed.connect(_on_next)
	box.add_child(_next_button)


func _on_item_button(item_id: String) -> void:
	_selected = item_id
	for key in _item_buttons:
		_item_buttons[key].set_pressed_no_signal(key == item_id)
	_refresh_hud("Selected '%s' — click terrain to place." % item_id)


func _on_next() -> void:
	if _hex.can_advance():
		_refresh_hud("Advancing a month (month sim owned by other issues).")
	else:
		_refresh_hud("Next is locked: " + _hex.gate_label())


func _refresh_hud(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
	if _gate_label != null:
		_gate_label.text = _hex.gate_label()
	if _next_button != null:
		_next_button.disabled = not _hex.can_advance()


func _try_place_at(screen_pos: Vector2) -> void:
	var origin := _cam.project_ray_origin(screen_pos)
	var normal := _cam.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, origin + normal * 500.0)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		_refresh_hud("Clicked outside the terrain.")
		return
	var hex: Vector2i = _hex.world_to_hex(hit["position"])
	if hex == Vector2i(-1, -1):
		_refresh_hud("Clicked outside the hex overlay.")
		return
	var res: Dictionary = _hex.place(hex, _selected)
	if bool(res.get("ok")):
		_spawn_marker(hex, _selected)
		_refresh_hud("Placed '%s' at %s." % [_selected, hex])
	else:
		_refresh_hud("Cannot place '%s' at %s: %s" % [_selected, hex, res.get("reason")])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		for key in SELECT_KEYS:
			if event.keycode == key:
				_on_item_button(SELECT_KEYS[key])
				get_viewport().set_input_as_handled()
				return
		if event.keycode == KEY_N:
			_on_next()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_dist = clampf(_dist - 3.0, 12.0, 120.0)
			_apply_orbit()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_dist = clampf(_dist + 3.0, 12.0, 120.0)
			_apply_orbit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_press_pos = event.position
				_moved = false
			else:
				if _dragging and not _moved:
					_try_place_at(event.position)
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		if (event.position - _press_pos).length() > 6.0:
			_moved = true
		if _moved:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch + event.relative.y * 0.006, 0.15, 1.35)
			_apply_orbit()


func _apply_orbit() -> void:
	var p := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.position = p
	_cam.look_at(Vector3.ZERO, Vector3.UP)


func _process(delta: float) -> void:
	if _demo:
		_demo_time += delta
		_yaw += DEMO_ORBIT_SPEED * delta
		_apply_orbit()
		while _demo_step < DEMO_EVENTS.size() and _demo_time >= DEMO_EVENTS[_demo_step]["t"]:
			_demo_place(DEMO_EVENTS[_demo_step]["item"])
			_demo_step += 1
		if _record_dir != "":
			_record_accum += delta
			while _record_accum >= 1.0 / DEMO_RECORD_FPS and _record_index < DEMO_RECORD_MAX_FRAMES:
				_record_accum -= 1.0 / DEMO_RECORD_FPS
				_record_index += 1
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s/frame_%04d.png" % [_record_dir, _record_index])
		if _demo_time >= DEMO_QUIT_AFTER or _record_index >= DEMO_RECORD_MAX_FRAMES:
			print("Demo finished: ", _hex.gate_label(), " frames=", _record_index)
			get_tree().quit(0)
			return
	if _capture_path == "" or _offscreen == null:
		return
	_frames += 1
	if _frames >= CAPTURE_AFTER_FRAMES:
		var img := _offscreen.get_texture().get_image()
		var err := img.save_png(_capture_path)
		if err != OK:
			_capture_failed = true
			push_error("Capture failed: %s (err %d)" % [_capture_path, err])
		else:
			print("Captured (%dx%d): %s" % [img.get_width(), img.get_height(), _capture_path])
		get_tree().quit(1 if _capture_failed else 0)


func _demo_place(item_id: String) -> void:
	_selected = item_id
	for key in _item_buttons:
		_item_buttons[key].set_pressed_no_signal(key == item_id)
	var used := {}
	for other in _overlay.get_children():
		if other.name.begins_with("Marker_"):
			var parts := other.name.split("_")
			used[Vector2i(int(parts[2]), int(parts[3]))] = true
	var hex := _nearest_placeable(item_id, used)
	if hex == Vector2i(-1, -1):
		_refresh_hud("Demo: no valid cell for '%s'." % item_id)
		return
	_hex.place(hex, item_id)
	_spawn_marker(hex, item_id)
	print("Demo: placed '%s' at %s | %s" % [item_id, hex, _hex.gate_label()])
	_refresh_hud("Demo placed '%s' at %s." % [item_id, hex])


func _make_offscreen() -> void:
	var framing := _framing()
	_offscreen = SubViewport.new()
	_offscreen.name = "OffscreenViewport"
	_offscreen.size = CAPTURE_SIZE
	_offscreen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_offscreen)
	var off_cam := Camera3D.new()
	_offscreen.add_child(off_cam)
	off_cam.position = framing["cam_pos"]
	off_cam.fov = framing["cam_fov"]
	off_cam.look_at(Vector3.ZERO, Vector3.UP)
	off_cam.current = true
