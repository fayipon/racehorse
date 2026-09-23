extends Node2D

# Screen-space ribbons stay spread across the view when the camera changes shots.
# Every ribbon enters from above; there is no emitter at the winning horse.
var pieces: Array[Dictionary] = []
var age := 0.0
var active := false
var last_round := -1
var reduced := false
var palette: Array = []

func configure(colors: Array) -> void:
	palette = colors.duplicate()
	palette.append(Color("e8c679"))
	palette.append(Color("f1dfb7"))
	visible = false

func seed_rain(round_number: int) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = round_number * 7919 + 1627
	pieces.clear()
	var count := 42 if reduced else 168
	for i in range(count):
		var depth := random.randf_range(.55,1.0)
		pieces.append({
			"x": (i + random.randf()) / count * 1.14 - .07,
			"delay": random.randf_range(0.0,2.8),
			"duration": random.randf_range(5.2,8.4) / depth * (1.3 if reduced else 1.0),
			"phase": random.randf_range(0.0,TAU),
			"sway": random.randf_range(.009,.035),
			"flutter": random.randf_range(1.4,3.2),
			"spin": random.randf_range(-.7,.7),
			"width": random.randf_range(3.5,6.5) * depth,
			"length": random.randf_range(22.0,42.0) * depth if i % 3 == 0 else random.randf_range(9.0,20.0) * depth,
			"curl": random.randf_range(1.2,4.0) * depth,
			"color": palette[random.randi_range(0,palette.size()-1)],
			"opacity": random.randf_range(.65,.92)
		})

func advance(delta: float, celebrate: bool, round_number: int, reduce_motion: bool) -> void:
	if round_number != last_round or reduce_motion != reduced:
		last_round = round_number
		reduced = reduce_motion
		active = false
		seed_rain(round_number)
	if celebrate and not active:
		age = 0.0
	active = celebrate
	visible = active
	if not active: return
	age += delta
	queue_redraw()

func _draw() -> void:
	if not active: return
	var viewport_size := get_viewport_rect().size
	var scale_factor := clampf(viewport_size.y / 720.0,.7,1.5)
	for piece in pieces:
		var elapsed := age - float(piece.delay)
		if elapsed < 0.0: continue
		var life := fmod(elapsed,float(piece.duration)) / float(piece.duration)
		var phase_offset := float(piece.phase)
		var flutter := elapsed * float(piece.flutter) + phase_offset
		var sway := sin(elapsed * .85 + phase_offset) * float(piece.sway)
		var x := (float(piece.x) + sway + (life-.5)*.035) * viewport_size.x
		var y := lerpf(-60.0,viewport_size.y+60.0,life)
		var rotation_angle := sin(flutter*.43)*.65 + elapsed*float(piece.spin)
		var flip := cos(flutter)
		draw_set_transform(Vector2(x,y),rotation_angle,Vector2(maxf(.12,absf(flip)),1)*scale_factor)
		var vertices := PackedVector2Array()
		var length := float(piece.length)
		var half_width := float(piece.width) * .5
		# A small travelling bend gives long strips a soft paper-ribbon silhouette.
		for edge in [-1,1]:
			for step in range(7):
				var u := (step if edge == -1 else 6-step) / 6.0
				var bend := sin(u*TAU+flutter) * float(piece.curl)
				vertices.append(Vector2(bend+half_width*edge,(u-.5)*length))
		var color: Color = piece.color
		color = color.darkened((1.0-absf(flip))*.18)
		color.a = float(piece.opacity) * smoothstep(0.0,.045,life) * (1.0-smoothstep(.93,1.0,life))
		draw_colored_polygon(vertices,color)
	draw_set_transform(Vector2.ZERO)
