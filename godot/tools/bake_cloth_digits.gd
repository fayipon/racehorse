extends SceneTree

# Bakes the saddlecloth numerals: ten white digits side by side, one per 128 x 160
# cell, which the cloth shader prints onto each horse's cloth. Rendering needs a
# window, so run it without --headless:
#   godot --path godot --resolution 320x180 -s res://tools/bake_cloth_digits.gd
const OUT := "res://assets/cloth_digits.png"
const CELL := Vector2i(128,160)

func _initialize() -> void:
	call_deferred("bake")

func bake() -> void:
	var view := SubViewport.new()
	# Drawn roomy, then each numeral is centred in its cell on a shared baseline.
	view.size = Vector2i(CELL.x*10,CELL.y*2)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for digit in range(10):
		var label := Label.new()
		label.text = str(digit)
		label.position = Vector2(CELL.x*digit,0)
		label.size = Vector2(CELL.x,CELL.y*2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",150)
		label.add_theme_color_override("font_color",Color.WHITE)
		# A same-colour outline sets the numerals in a racing weight.
		label.add_theme_constant_override("outline_size",14)
		label.add_theme_color_override("font_outline_color",Color.WHITE)
		view.add_child(label)
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var drawn := view.get_texture().get_image()
	var rows := Rect2i()
	for digit in range(10):
		var used := drawn.get_region(Rect2i(CELL.x*digit,0,CELL.x,CELL.y*2)).get_used_rect()
		rows = used if digit==0 else rows.merge(used)
	var image := Image.create(CELL.x*10,CELL.y,false,Image.FORMAT_RGBA8)
	for digit in range(10):
		var glyph := drawn.get_region(Rect2i(CELL.x*digit,rows.position.y,CELL.x,rows.size.y))
		var used := glyph.get_used_rect()
		var at := Vector2i(CELL.x*digit+(CELL.x-used.size.x)/2,(CELL.y-rows.size.y)/2)
		image.blit_rect(glyph,Rect2i(used.position.x,0,used.size.x,rows.size.y),at)
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("Baked ",OUT)
	quit()
