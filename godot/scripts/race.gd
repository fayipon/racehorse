extends Node3D

# React owns the clock and betting ledger. Godot renders the same distances,
# interpolating the bridge's snapshots for smooth, deterministic racing.
const COLORS = [Color("e75d56"), Color("91ac6b"), Color("efc54f"), Color("b394d0"), Color("eca05b"), Color("e787b4"), Color("79c9d8"), Color("7299df")]
var horses: Array[Node3D] = []
var camera: Camera3D
var phase := "betting"
var seconds := 0.0
var race_round := 1
var winner := 1
var shot := 0
var positions: Array = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
var visual_positions: Array = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
var elapsed := 0.0
var bridge_timer := 0.0
var mats: Dictionary = {}
var confetti_rain = preload("res://scripts/confetti_rain.gd").new()
var previous_shot := -1
var rng := RandomNumberGenerator.new()
var course = preload("res://scripts/course.gd").new()
const PONY = preload("res://scripts/asset_horse.gd")
var race_clock := 0.0
const MOTION = preload("res://scripts/race_motion.gd")
var motion_clock = MOTION.new()
var parade_clock = MOTION.new()
var finish_times: Array = [44.5,45.15,45.8,46.45,47.1,47.75,48.4,49.05]
var preview_paused := false
const PARADE = preload("res://scripts/parade_motion.gd")
var parade_plan: Array = []
var betting_clock := 0.0
var last_betting_snapshot := -1.0
var finish_age := -1.0
var finished := false
var dust: Array[MeshInstance3D] = []
var animation_clock := 0.0
var reduced_motion := false
var crossed_at: Array = [-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0]
var camera_focus := Vector3.ZERO
var camera_initialized := false

func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if mats.has(key): return mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.06)
	mat.roughness = 0.95
	mat.metallic_specular = 0.15
	mats[key] = mat
	return mat

func ball(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 12
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.scale = size * 2.0
	parent.add_child(node)
	return node

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func beam(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var node := box(self, (a+b)*0.5, Vector3(radius, radius, a.distance_to(b)), color)
	node.look_at(b, Vector3.UP)

func ring(radius: float, width: float, color: Color, y: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(192):
		var a := i/192.0
		var b := (i+1)/192.0
		var pts: Array[Vector3] = [course.sample(a,radius).position,course.sample(a,radius+width).position,course.sample(b,radius).position,course.sample(b,radius+width).position]
		for idx in [0,2,1,1,2,3]:
			var pos := pts[idx]
			pos.y = y
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(pos.x,pos.z)*0.25)
			st.add_vertex(pos)
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	var mat := material(color).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	add_child(instance)

func course_point(progress: float, lane: int) -> Vector3:
	return course.sample(progress,course.lane_radius(lane)).position

func _ready() -> void:
	rng.seed = 61293
	if OS.has_feature("web"):
		reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
	if not OS.has_feature("web"): parade_plan=PARADE.preview_plan(61293)
	build_environment()
	for i in range(8): build_horse(i)
	camera = Camera3D.new()
	camera.fov = 52
	camera.far = 480
	add_child(camera)
	camera.current = true
	var fill := DirectionalLight3D.new()
	fill.light_energy = .42
	fill.light_color = Color("f0e5d7")
	fill.light_cull_mask = 2
	fill.shadow_enabled = false
	camera.add_child(fill)
	var celebration_layer := CanvasLayer.new()
	celebration_layer.layer = 5
	add_child(celebration_layer)
	celebration_layer.add_child(confetti_rain)
	confetti_rain.configure(COLORS)
	build_finish_effects()
	if OS.has_feature("web"):
		reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
		JavaScriptBridge.eval("window.parent.postMessage({type:'godot-ready'},window.location.origin)")

func build_environment() -> void:
	var env := Environment.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sunny_sky.gdshader")
	sky_material.set_shader_parameter("drift_speed",0.0 if reduced_motion else 0.001)
	var sky := Sky.new()
	sky.sky_material=sky_material
	env.background_mode = Environment.BG_SKY
	env.sky=sky
	env.fog_enabled=true
	env.fog_light_color=Color("c5ddeb")
	env.fog_density=.0014
	env.fog_sky_affect=0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aebac6")
	env.ambient_light_energy = 0.25
	env.tonemap_exposure = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42,-28,0)
	sun.light_color = Color("f1e4cf")
	sun.light_energy = 0.64
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	add_child(sun)
	var landscape=preload("res://scripts/landscape.gd").new()
	add_child(landscape)
	landscape.build(course,reduced_motion)
	ring(float(course.config.innerRadius),float(course.config.trackWidth),Color("a77c54"),0.01)
	# Sand grooves and lane markings form a single continuous course.
	for i in range(18): ring(float(course.config.innerRadius)+.3+i*.72,.035,Color("956d48"),.026)
	for r in [float(course.config.innerRadius)-.4,float(course.config.innerRadius)+float(course.config.trackWidth)+.4]:
		for i in range(128):
			var p: Vector3 = course.sample(i/128.0,r).position
			var q: Vector3 = course.sample((i+1)/128.0,r).position
			box(self,p+Vector3(0,.65,0),Vector3(.14,1.3,.14),Color("c5c0ac"))
			beam(p+Vector3(0,1.15,0),q+Vector3(0,1.15,0),.17,Color("d0c9b5"))
			beam(p+Vector3(0,.60,0),q+Vector3(0,.60,0),.1,Color("b6b09e"))
	# The physical finish and minimap both lie at x=0 on the near straight.
	for lane in range(27):
		for column in range(4):
			box(self,Vector3((column-1.5)*.42,.043,float(course.config.innerRadius)+.25+lane*.5),Vector3(.42,.02,.5),Color("cfc7af") if (lane+column)%2==0 else Color("303b36"))
	var venue = preload("res://scripts/venue.gd").new()
	add_child(venue)
	venue.build(reduced_motion)
	var sign := Label3D.new()
	sign.text = "SUNNY CUP"
	sign.font_size = 140
	sign.pixel_size = 0.014
	sign.position = Vector3(0,2.7,-38.7)
	sign.modulate = Color("fff4d9")
	add_child(sign)
	box(self,Vector3(0,2.6,-39),Vector3(25,4.8,0.4),Color("40664e"))

func build_horse(index: int) -> void:
	var pony = PONY.new()
	add_child(pony)
	pony.build(index,COLORS[index].darkened(.08))
	horses.append(pony)

func build_finish_effects() -> void:
	var gradient := Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,.35,1.0])
	gradient.colors=PackedColorArray([Color(1,1,1,.23),Color(1,1,1,.13),Color(1,1,1,0)])
	var soft_disc := GradientTexture2D.new()
	soft_disc.gradient=gradient
	soft_disc.width=64
	soft_disc.height=64
	soft_disc.fill=GradientTexture2D.FILL_RADIAL
	soft_disc.fill_from=Vector2(.5,.5)
	soft_disc.fill_to=Vector2(.5,1.0)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color=Color("b19776")
	dust_mat.albedo_texture=soft_disc
	dust_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var dust_mesh := QuadMesh.new()
	dust_mesh.size=Vector2(.8,.65)
	for i in range(64):
		var puff := MeshInstance3D.new()
		puff.mesh=dust_mesh
		puff.material_override=dust_mat
		add_child(puff)
		puff.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visible=false
		dust.append(puff)

func trigger_finish() -> void:
	finished=true
	finish_age=0.0
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.parent.postMessage({type:'race-finish',round:%d,winner:%d},window.location.origin)" % [race_round,winner])

func read_bridge() -> void:
	if not OS.has_feature("web"): return
	var raw = JavaScriptBridge.eval("JSON.stringify(window.raceState || null)")
	if raw == null: return
	var data = JSON.parse_string(str(raw))
	if not data is Dictionary: return
	var next_round := int(data.get("round",1))
	var reset_clock := next_round!=race_round or phase!=str(data.get("phase","betting"))
	if next_round != race_round:
		visual_positions = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
		race_round = next_round
		finish_age=-1.0
		finished=false
		previous_shot=-1
		camera_initialized=false
		crossed_at=[-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0]
	phase = str(data.get("phase","betting"))
	var snapshot := float(data.get("seconds",0.0))
	if snapshot != seconds or reset_clock or not motion_clock.initialized:
		seconds=snapshot
		motion_clock.sync(seconds,reset_clock)
		race_clock=motion_clock.seconds
	var incoming_times = data.get("finishTimes",[])
	if incoming_times is Array and incoming_times.size()==8: finish_times=incoming_times
	preview_paused=bool(data.get("paused",false))
	parade_plan=data.get("paradePlan",parade_plan)
	var betting_snapshot := float(data.get("bettingElapsed",0.0))
	if betting_snapshot != last_betting_snapshot:
		parade_clock.sync(betting_snapshot,reset_clock)
		betting_clock=parade_clock.seconds
		last_betting_snapshot=betting_snapshot
	winner = int(data.get("winner",1))
	shot = int(data.get("camera",0))
	positions = data.get("positions",positions)

func _process(delta: float) -> void:
	elapsed+=delta
	bridge_timer+=delta
	if phase!="betting" and not preview_paused:
		motion_clock.advance(delta)
		race_clock=motion_clock.seconds
	if phase=="betting" and not preview_paused:
		parade_clock.advance(delta)
		betting_clock=parade_clock.seconds
	if finish_age>=0.0: finish_age+=delta
	if bridge_timer>.05:
		read_bridge()
		bridge_timer=0.0
	if not OS.has_feature("web"):
		var preview_offset := 0.0
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--preview-at="): preview_offset=float(arg.trim_prefix("--preview-at="))
		var t := fmod(elapsed+preview_offset,120.0)
		phase="betting" if t<60 else "racing" if t<110 else "result"
		betting_clock=t
		seconds=maxf(0.0,t-60)
		race_clock=seconds
		shot=0 if t<60 else 1 if seconds<7 else 2 if seconds<24 else 3 if seconds<37 else 5 if t<110 else 4
		for i in range(8): positions[i]=clampf(seconds/(44.5+i*.65),0,1)
		if phase=="betting" and finished:
			finished=false
			finish_age=-1.0
	var playback: Vector2=motion_clock.presentation(race_clock)
	var presentation_clock:=playback.x
	var slow_motion:=playback.y if phase=="racing" else 1.0
	animation_clock+=delta*slow_motion
	for i in range(8):
		visual_positions[i]=MOTION.progress(presentation_clock,i+1,float(finish_times[i])) if phase!="betting" else 0.0
		var p := float(visual_positions[i])
		var sample: Dictionary
		var moving := 1.0
		var running := phase=="racing" and p<.9998
		if phase=="betting":
			visual_positions[i]=0.0
			crossed_at[i]=-1.0
			var itinerary: Array=parade_plan[i] if parade_plan.size()==8 else []
			var stroll: Vector2=PARADE.sample(betting_clock,itinerary)
			var x:=stroll.x
			var z:=course.lane_radius(i)
			var target_yaw:=horses[i].rotation.y
			if absf(stroll.y)>.04: target_yaw=-PI/2 if stroll.y>0 else PI/2
			if betting_clock>=47.0: target_yaw=-PI/2
			moving=clampf(absf(stroll.y)/1.65,0,1)
			horses[i].position=Vector3(x,0,z)
			horses[i].rotation.y=lerp_angle(horses[i].rotation.y,target_yaw,minf(delta*3,1.0))
		else:
			# Coast through the finish instead of freezing on top of the stripe.
			if p>=.9998:
				if float(crossed_at[i])<0.0: crossed_at[i]=float(finish_times[i])
				var since_finish := maxf(0.0,presentation_clock-float(crossed_at[i]))
				var coast := clampf(since_finish/4.0,0,1)
				var finish_rank := 0
				for finish_time in finish_times:
					if float(finish_time)<float(finish_times[i]): finish_rank+=1
				# Use world distances so outer lanes cannot stop ahead of a better rank.
				var winner_lap: float=4.0*float(course.config.halfStraight)+TAU*course.lane_radius(winner-1)
				var lane_lap: float=4.0*float(course.config.halfStraight)+TAU*course.lane_radius(i)
				var stop_distance: float=winner_lap*.034-mini(finish_rank,3)*1.6
				p=1.0+(1.0-pow(1.0-coast,3))*stop_distance/lane_lap
				running=since_finish<1.5
				moving=pow(1.0-coast,2)
			sample=course.sample(p,course.lane_radius(i))
			horses[i].position=sample.position
			var tangent: Vector3=sample.tangent
			horses[i].rotation.y=atan2(-tangent.x,-tangent.z)
		var celebration := phase=="result" and i==winner-1
		horses[i].call("animate",animation_clock,moving,running,celebration,delta*slow_motion)
	if phase=="racing" and not finished and float(visual_positions[winner-1])>=.9997:
		trigger_finish()
	var focus_index := winner-1
	var target := Vector3.ZERO
	var mean_progress := 0.0
	# Track the pack as a whole. Following a changing leader caused lateral
	# jumps; following the body's bounce caused unnecessary vertical motion.
	for i in range(8):
		target+=horses[i].position/8.0
		mean_progress+=float(visual_positions[i])/8.0
	target.y=1.45
	var path: Dictionary=course.sample(mean_progress,course.lane_radius(3)+.65)
	if finished or phase=="result":
		target=horses[focus_index].position
		target.y=1.45
		path=course.sample(float(visual_positions[focus_index]),course.lane_radius(focus_index))
	var outward: Vector3=path.outward
	var forward: Vector3=path.tangent
	var cam_pos: Vector3
	var focus := target
	var active_shot := 6 if race_clock>=42.8 and phase=="racing" else shot
	var fov := 49.0
	match active_shot:
		0:
			focus=Vector3(-4,1.3,25.0)
			cam_pos=Vector3(8.5,6.0,42)
			focus.z-=1.5
		1:
			focus=target+outward*1.3
			cam_pos=focus+forward*12+outward*7+Vector3(0,3.4,0)
		2:
			focus=target+forward*.8
			cam_pos=target+outward*9+forward*5+Vector3(0,2.3,0)
		3:
			focus=target+forward*2.0
			cam_pos=target-forward*10+outward*6+Vector3(0,5.0,0)
		4:
			cam_pos=target+outward*5.5+forward*6.0+Vector3(0,1.45,0)
			focus=target-outward*1.2
			fov=43.0
		6:
			# The line stays the focal point; horses cross through the composition.
			var push:=smoothstep(42.8,47.5,race_clock)
			focus=Vector3(0,1.25,float(course.config.laneStart)+3.5*float(course.config.laneSpacing))
			cam_pos=Vector3(8.5,3.8,42).lerp(Vector3(7.5,3.3,40.5),push)
			fov=lerpf(54.0,49.0,push)
		7:
			cam_pos=Vector3(0,100,5)
			focus=Vector3.ZERO
			fov=70.0
		_:
			cam_pos=target+outward*9+forward*7+Vector3(0,2.1,0)
	if not camera_initialized:
		camera.position=cam_pos
		camera_focus=focus
		camera_initialized=true
	else:
		var damping := 1.0-exp(-delta*2.8)
		camera.position=camera.position.lerp(cam_pos,damping)
		camera_focus=camera_focus.lerp(focus,damping)
	previous_shot=active_shot
	camera.fov=lerpf(camera.fov,fov,1.0-exp(-delta*2.0))
	camera.look_at(camera_focus,Vector3.UP)
	update_effects(delta)

func update_effects(delta: float) -> void:
	var celebrate := finished or phase=="result"
	confetti_rain.advance(delta,celebrate,race_round,reduced_motion)
	for i in range(dust.size()):
		var owner := i%8
		var p := float(visual_positions[owner])
		dust[i].visible=phase=="racing" and p>.002 and (p<.9998 or (finish_age>=0 and finish_age<1.7))
		if dust[i].visible:
			var t := fmod(animation_clock*1.6+i*.17,1.0)
			var path: Dictionary=course.sample(p,course.lane_radius(owner))
			var forward: Vector3=path.tangent
			var outward: Vector3=path.outward
			dust[i].position=horses[owner].position-forward*(.8+t*1.3)+outward*sin(i*7.3)*.25+Vector3(0,.12+t*.32,0)
			dust[i].scale=Vector3.ONE*(.3+sin(t*PI)*1.5)
