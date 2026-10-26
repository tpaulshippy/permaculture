class_name TerrainMesh
extends Node3D
## Heightfield mesh builder for the terrain MVP (issue #2).
##
## Builds an ArrayMesh from a TerrainWater heightfield with per-vertex
## colors. Two render modes: TERRAIN (Sonoran palette with riparian tint)
## and MOISTURE (dry->wet overlay for evidence + future hex overlay work).

enum RenderMode { TERRAIN, MOISTURE }

const Cfg := preload("res://scripts/terrain_config.gd")
const Water := preload("res://scripts/terrain_water.gd")


static func build_array_mesh(water: Water, mode: int) -> ArrayMesh:
	var w: int = water.grid_w
	var h: int = water.grid_h
	var cell: float = Cfg.CELL_SIZE
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(w * h)
	normals.resize(w * h)
	colors.resize(w * h)
	var hmin: float = water.min_height
	var hmax: float = water.max_height
	var span := maxf(hmax - hmin, 0.001)
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			var px := (float(x) - float(w - 1) * 0.5) * cell
			var pz := (float(y) - float(h - 1) * 0.5) * cell
			verts[i] = Vector3(px, water.heights[i], pz)
			normals[i] = grid_normal(water, x, y)
			var hn: float = (water.heights[i] - hmin) / span
			if mode == RenderMode.MOISTURE:
				colors[i] = moisture_color(water.moisture[i])
			else:
				colors[i] = terrain_color(hn, water.moisture[i])
	for y in range(h - 1):
		for x in range(w - 1):
			var a := y * w + x
			var b := a + 1
			var c := a + w
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func grid_normal(water: Water, x: int, y: int) -> Vector3:
	var w: int = water.grid_w
	var grid_h: int = water.grid_h
	var heights: PackedFloat32Array = water.heights
	var cell: float = Cfg.CELL_SIZE
	var hl: float = heights[y * w + maxi(x - 1, 0)]
	var hr: float = heights[y * w + mini(x + 1, w - 1)]
	var hd: float = heights[maxi(y - 1, 0) * w + x]
	var hu: float = heights[mini(y + 1, grid_h - 1) * w + x]
	# Central difference in the interior, one-sided difference at the
	# perimeter where the missing neighbor is clamped to the edge sample.
	var dhdx := (hr - hl) / (2.0 * cell)
	if x <= 0 or x >= w - 1:
		dhdx = (hr - hl) / cell
	var dhdz := (hu - hd) / (2.0 * cell)
	if y <= 0 or y >= grid_h - 1:
		dhdz = (hu - hd) / cell
	return Vector3(-dhdx, 1.0, -dhdz).normalized()


static func terrain_color(h_norm: float, moist: float) -> Color:
	var sand := Color(0.76, 0.63, 0.44).srgb_to_linear()
	var scrub := Color(0.50, 0.44, 0.27).srgb_to_linear()
	var rock := Color(0.38, 0.29, 0.24).srgb_to_linear()
	var c: Color
	if h_norm < 0.5:
		c = sand.lerp(scrub, h_norm * 2.0)
	else:
		c = scrub.lerp(rock, (h_norm - 0.5) * 2.0)
	var riparian := Color(0.27, 0.47, 0.23).srgb_to_linear()
	return c.lerp(riparian, clampf(moist, 0.0, 1.0) * 0.65)


static func moisture_color(moist: float) -> Color:
	var dry := Color(0.79, 0.71, 0.54).srgb_to_linear()
	var wet := Color(0.08, 0.26, 0.72).srgb_to_linear()
	return dry.lerp(wet, clampf(moist, 0.0, 1.0))
