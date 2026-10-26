extends Node3D
## Terrain MVP scene driver (issue #2).
##
## Builds the deterministic Sonoran heightmap mesh (fixed seed) in TERRAIN
## or MOISTURE render mode. Supports viewport captures for evidence via an
## offscreen SubViewport (robust when the main window is not drawable):
##   godot --path . -- --capture-mode=terrain --capture-path=/tmp/terrain_topdown.png
##   godot --path . -- --capture-mode=moisture --capture-path=/tmp/moisture_overlay.png

const WaterScript := preload("res://scripts/terrain_water.gd")
const MeshScript := preload("res://scripts/terrain_mesh.gd")
const Cfg := preload("res://scripts/terrain_config.gd")

const CAPTURE_AFTER_FRAMES := 30
const CAPTURE_SIZE := Vector2i(1280, 720)

var _capture_mode := ""
var _capture_path := ""
var _frames := 0
var _offscreen: SubViewport


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-mode="):
			_capture_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--capture-path="):
			_capture_path = arg.get_slice("=", 1)
	var mode: int = MeshScript.RenderMode.TERRAIN
	if _capture_mode == "moisture":
		mode = MeshScript.RenderMode.MOISTURE
	elif _capture_mode == "" or _capture_mode == "terrain":
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
	var water: WaterScript = WaterScript.new(Cfg.GRID_W, Cfg.GRID_H)
	water.generate(Cfg.FIXED_SEED, Cfg.DEFAULT_RAIN)
	var mesh: ArrayMesh = MeshScript.build_array_mesh(water, mode)
	var framing := _framing()
	# On-screen scene (interactive viewing).
	var mi := $MeshInstance3D as MeshInstance3D
	mi.mesh = mesh
	mi.set_surface_override_material(0, _make_material())
	var cam := $Camera3D as Camera3D
	cam.position = framing["cam_pos"]
	cam.fov = framing["cam_fov"]
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	var sun := $Sun as DirectionalLight3D
	sun.rotation_degrees = framing["sun_rot"]
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	# Offscreen capture viewport (evidence screenshots). It shares the main
	# world and only adds its own camera, so exactly the on-screen scene is
	# rendered into an always-valid render target.
	if _capture_path != "":
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


func _process(_delta: float) -> void:
	if _capture_path == "" or _offscreen == null:
		return
	_frames += 1
	if _frames >= CAPTURE_AFTER_FRAMES:
		var img := _offscreen.get_texture().get_image()
		var err := img.save_png(_capture_path)
		if err != OK:
			push_error("Capture failed: %s (err %d)" % [_capture_path, err])
		else:
			print("Captured (%dx%d): %s" % [img.get_width(), img.get_height(), _capture_path])
		get_tree().quit()
