extends SceneTree
## One-shot: rasterize res://icon.svg to a crisp 1024px PNG for iOS export.
## Run: godot --headless --path . --script res://tools/gen_ios_icon.gd
## The iOS exporter derives all icon sizes from icons/icon_1024x1024.

const SVG_SIZE := 128.0
const OUT_PATH := "res://icons/icon_1024.png"
const OUT_SIZE := 1024


func _init() -> void:
	var svg_text := FileAccess.get_file_as_string("res://icon.svg")
	if svg_text.is_empty():
		push_error("gen_ios_icon: res://icon.svg missing or empty")
		quit(1)
		return
	var img := Image.new()
	var err := img.load_svg_from_string(svg_text, float(OUT_SIZE) / SVG_SIZE)
	if err != OK:
		push_error("gen_ios_icon: load_svg_from_string failed (err %d)" % err)
		quit(1)
		return
	if img.get_width() != OUT_SIZE or img.get_height() != OUT_SIZE:
		push_error("gen_ios_icon: unexpected raster size %s" % str(img.get_size()))
		quit(1)
		return
	# App Store 1024px icon must be opaque (exporter enforces this). The
	# source SVG has rounded corners, so composite onto its own base fill
	# (#C9A86A) to keep corners seamless under the iOS icon mask.
	var bg := Image.create_empty(OUT_SIZE, OUT_SIZE, false, Image.FORMAT_RGBA8)
	bg.fill(Color("c9a86a"))
	bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	img = bg
	err = img.save_png(OUT_PATH)
	if err != OK:
		push_error("gen_ios_icon: save_png failed (err %d)" % err)
		quit(1)
		return
	print("gen_ios_icon: wrote %s (%dx%d)" % [OUT_PATH, img.get_width(), img.get_height()])
	quit(0)
