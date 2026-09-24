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
var track_positions: Array = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
var elapsed := 0.0
var bridge_timer := 0.0
var venue: Node3D
var standings: Array = [0,1,2,3,4,5,6,7]
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
var finished := false
var dust: Array[MeshInstance3D] = []
var animation_clock := 0.0
var reduced_motion := false
var camera_focus := Vector3.ZERO
var camera_initialized := false
var sprint_grade: ColorRect
var sprint_material: ShaderMaterial
var dust_materials: Array[StandardMaterial3D] = []
var dust_cycles: PackedInt32Array = []
var dust_origins: Array[Vector3] = []
var dust_forwards: Array[Vector3] = []
var dust_outwards: Array[Vector3] = []
var podium = preload("res://scripts/podium.gd").new()
var featured_runner := 0

func course_point(progress: float, lane: int) -> Vector3:
	return course.sample(progress,course.lane_radius(lane)).position

func _ready() -> void:
	rng.seed = 61293
	if OS.has_feature("web"):
		reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
	if not OS.has_feature("web"): parade_plan=PARADE.preview_plan(61293)
	build_environment()
	for i in range(8): build_horse(i)
	add_child(podium)
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
	var lens_layer := CanvasLayer.new()
	lens_layer.layer=1
	add_child(lens_layer)
	sprint_grade=ColorRect.new()
	sprint_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sprint_grade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sprint_material=ShaderMaterial.new()
	sprint_material.shader=preload("res://shaders/sprint_lens.gdshader")
	sprint_grade.material=sprint_material
	lens_layer.add_child(sprint_grade)
	if OS.has_feature("web"):
		reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
		JavaScriptBridge.eval("window.parent.postMessage({type:'godot-ready'},window.location.origin)")

func build_environment() -> void:
	var env := Environment.new()
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = preload("res://assets/sky/kloppenheim_05_puresky.jpg")
	sky_material.energy_multiplier = 1.45
	var sky := Sky.new()
	sky.sky_material=sky_material
	env.background_mode = Environment.BG_SKY
	env.sky=sky
	env.fog_enabled=true
	env.fog_light_color=Color("dbe6ec")
	env.fog_density=.0011
	env.fog_sky_affect=0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6d2dc")
	env.ambient_light_energy = 0.4
	env.tonemap_exposure = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = .3
	env.glow_bloom = .02
	env.glow_hdr_threshold = .95
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	# Late-afternoon sun from the left of the home-straight cameras models the
	# runners from the side instead of flattening them from behind the lens.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38,-80,0)
	sun.light_color = Color("ffe6c2")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = .82
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	var landscape=preload("res://scripts/landscape.gd").new()
	add_child(landscape)
	landscape.build(course,reduced_motion)
	var infield=preload("res://scripts/infield.gd").new()
	add_child(infield)
	infield.build(course,reduced_motion)
	var racing_track=preload("res://scripts/race_track.gd").new()
	add_child(racing_track)
	# The physical finish and minimap both lie at x=0 on the near straight.
	racing_track.build(course)
	venue = preload("res://scripts/venue.gd").new()
	add_child(venue)
	venue.build(reduced_motion,COLORS)

func build_horse(index: int) -> void:
	var pony = PONY.new()
	add_child(pony)
	pony.build(index,COLORS[index].darkened(.08))
	horses.append(pony)

func build_finish_effects() -> void:
	var gradient := Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,.35,1.0])
	gradient.colors=PackedColorArray([Color(1,1,1,.65),Color(1,1,1,.25),Color(1,1,1,0)])
	var soft_disc := GradientTexture2D.new()
	soft_disc.gradient=gradient
	soft_disc.width=64
	soft_disc.height=64
	soft_disc.fill=GradientTexture2D.FILL_RADIAL
	soft_disc.fill_from=Vector2(.5,.5)
	soft_disc.fill_to=Vector2(.5,1.0)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color=Color("8a9862")
	dust_mat.albedo_texture=soft_disc
	dust_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var dust_mesh := QuadMesh.new()
	dust_mesh.size=Vector2(.8,.65)
	for i in range(96):
		var puff := MeshInstance3D.new()
		puff.mesh=dust_mesh
		var particle_mat := dust_mat.duplicate() as StandardMaterial3D
		puff.material_override=particle_mat
		add_child(puff)
		puff.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visible=false
		dust.append(puff)
		dust_materials.append(particle_mat)
		dust_cycles.append(-1)
		dust_origins.append(Vector3.ZERO)
		dust_forwards.append(Vector3.RIGHT)
		dust_outwards.append(Vector3.BACK)

func trigger_finish() -> void:
	finished=true
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
		finished=false
		previous_shot=-1
		camera_initialized=false
		dust_cycles.fill(-1)
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
	var playback: Vector2=motion_clock.presentation(race_clock)
	var presentation_clock:=playback.x
	var slow_motion:=playback.y if phase=="racing" else 1.0
	var sprint_effort:=smoothstep(34.0,41.5,race_clock) if phase=="racing" else 0.0
	animation_clock+=delta*slow_motion
	for i in range(8):
		track_positions[i]=MOTION.track_progress(presentation_clock,i+1,float(finish_times[i])) if phase!="betting" else 0.0
		visual_positions[i]=minf(float(track_positions[i]),1.0)
		var p := float(track_positions[i])
		var sample: Dictionary
		var moving := 1.0 if phase=="racing" else 0.0
		var running := phase=="racing"
		if phase=="betting":
			visual_positions[i]=0.0
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
			sample=course.sample(p,course.lane_radius(i))
			horses[i].position=sample.position
			var tangent: Vector3=sample.tangent
			horses[i].rotation.y=atan2(-tangent.x,-tangent.z)
		var celebration := phase=="result" and i==winner-1
		horses[i].visible=phase!="result"
		horses[i].call("animate",animation_clock,moving,running,celebration,delta*slow_motion,sprint_effort)
	podium.visible=phase=="result"
	if phase=="result":
		podium.present(finish_times,COLORS,race_round)
		podium.animate(animation_clock,delta)
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
	# Ease toward the front group without cutting to the preselected winner
	# or jumping whenever the live leader changes.
	if phase=="racing":
		var leading_progress:=float(visual_positions.max())
		var front_target:=Vector3.ZERO
		var front_progress:=0.0
		var total_weight:=0.0
		for i in range(8):
			var weight: float=pow(clampf(1.0-(leading_progress-float(visual_positions[i]))/.085,0.0,1.0),2)
			front_target+=horses[i].position*weight
			front_progress+=float(visual_positions[i])*weight
			total_weight+=weight
		var frame_front:=smoothstep(34.0,39.0,race_clock)
		target=target.lerp(front_target/total_weight,frame_front)
		mean_progress=lerpf(mean_progress,front_progress/total_weight,frame_front)
	target.y=1.45
	var path: Dictionary=course.sample(mean_progress,course.lane_radius(3)+.65)
	if finished or phase=="result":
		target=horses[focus_index].position
		target.y=1.45
		path=course.sample(float(track_positions[focus_index]),course.lane_radius(focus_index))
	var outward: Vector3=path.outward
	var forward: Vector3=path.tangent
	var cam_pos: Vector3
	var focus := target
	var active_shot := shot
	if phase=="racing":
		if finished and race_clock<45.8: active_shot=10
		elif race_clock>=42.8: active_shot=6
		elif race_clock>=39.5: active_shot=8
	if active_shot==8 and previous_shot!=8:
		featured_runner=visual_positions.find(visual_positions.max())
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
			var reveal:=0.5 if reduced_motion else smoothstep(50.0,60.0,race_clock)
			fov=34.0
			var aspect:=get_viewport().get_visible_rect().size.aspect()
			var distance:=maxf(19.0,15.5/(2.0*tan(deg_to_rad(fov*.5))*aspect))
			focus=podium.position+Vector3(0,2.6,0)
			cam_pos=podium.position+Vector3(lerpf(.8,-.5,reveal),4.8,distance+lerpf(1.2,0.0,reveal))
		5:
			# Low side dolly: the rail and hoof-level dust slide past the runners.
			var push:=smoothstep(37.0,42.8,race_clock)
			focus=target+forward*3.4
			focus.y=1.5
			cam_pos=focus+outward*lerpf(12.0,10.8,push)+forward*lerpf(3.0,1.5,push)+Vector3(0,1.0,0)
			fov=lerpf(54.0,49.0,push)
		6:
			var middle_lane:=float(course.config.laneStart)+3.5*float(course.config.laneSpacing)
			if finished:
				# After the crossing orbit, stay on the stripe as every runner
				# gallops through. This composition must not depend on a horse.
				focus=Vector3(0,1.3,middle_lane)
				cam_pos=focus+Vector3(4.5,4.2,17.0)
				fov=48.0
			else:
				var lock_to_line:=smoothstep(42.8,45.6,race_clock)
				var line_focus:=Vector3(0,1.3,lerpf(middle_lane,target.z,.75))
				focus=(target+forward*3.4).lerp(line_focus,lock_to_line)
				cam_pos=focus+Vector3(lerpf(1.5,3.0,lock_to_line),lerpf(.5,1.0,lock_to_line),lerpf(9.4,8.4,lock_to_line))
				fov=lerpf(46.0,42.0,smoothstep(43.0,47.5,race_clock))
		7:
			cam_pos=Vector3(0,100,5)
			focus=Vector3.ZERO
			fov=70.0
		8:
			# Editorial cut to the live leader's face and shoulder, then dolly alongside.
			var close_path: Dictionary=course.sample(float(visual_positions[featured_runner]),course.lane_radius(featured_runner))
			var close_forward: Vector3=close_path.tangent
			var push:=0.5 if reduced_motion else smoothstep(39.5,42.8,race_clock)
			focus=horses[featured_runner].position+close_forward*.75+Vector3(0,1.85,0)
			cam_pos=focus+close_path.outward*5.0+close_forward*lerpf(2.7,1.8,push)+Vector3(0,.15,0)
			fov=lerpf(42.0,37.0,push)
		10:
			# The race clock holds the crossing pose while the camera keeps moving.
			var orbit:=0.5 if reduced_motion else smoothstep(44.6,45.8,race_clock)
			var angle:=lerpf(-.20,.45,orbit)
			focus=horses[winner-1].position+forward*.5+Vector3(0,1.65,0)
			cam_pos=focus+outward*cos(angle)*6.5+forward*sin(angle)*6.5+Vector3(0,.6,0)
			fov=40.0
		_:
			cam_pos=target+outward*9+forward*7+Vector3(0,2.1,0)
	var edit_cut:=active_shot!=previous_shot and (active_shot in [4,6,8,10] or previous_shot==4)
	if not camera_initialized or edit_cut:
		camera.position=cam_pos
		camera_focus=focus
		camera.fov=fov
		camera_initialized=true
	else:
		var damping := 1.0-exp(-delta*(12.0 if active_shot==10 else 2.8))
		camera.position=camera.position.lerp(cam_pos,damping)
		camera_focus=camera_focus.lerp(focus,damping)
	previous_shot=active_shot
	camera.fov=lerpf(camera.fov,fov,1.0-exp(-delta*2.0))
	camera.look_at(camera_focus,Vector3.UP)
	update_effects(delta)
	update_board(delta)

# The infield screen shows live standings, then the official finishing order.
func update_board(delta: float) -> void:
	standings.assign([0,1,2,3,4,5,6,7])
	if phase=="racing":
		standings.sort_custom(func(a: int,b: int) -> bool:
			var pa:=float(track_positions[a])
			var pb:=float(track_positions[b])
			return pa>pb or (pa==pb and a<b))
	elif phase=="result":
		standings.sort_custom(func(a: int,b: int) -> bool: return float(finish_times[a])<float(finish_times[b]))
	venue.update_board(phase,race_round,standings,delta)

func update_effects(delta: float) -> void:
	var celebrate := finished or phase=="result"
	confetti_rain.advance(delta,celebrate,race_round,reduced_motion)
	var sprint:=smoothstep(34.0,42.0,race_clock) if phase=="racing" else 0.0
	var lens_strength:=sprint*(1.0-smoothstep(42.8,45.0,race_clock)*.8)*(1.0-smoothstep(47.0,50.0,race_clock))
	var rush:=smoothstep(45.8,46.05,race_clock)*lerpf(.65,1.0,smoothstep(46.05,50.0,race_clock)) if phase=="racing" else 0.0
	if race_clock>=44.6 and race_clock<45.8: lens_strength=0.0
	lens_strength=maxf(lens_strength,rush)
	# A stationary finish camera keeps the track sharp while the horses move.
	if phase=="racing" and finished and race_clock>=45.8: lens_strength=0.0
	sprint_grade.visible=not reduced_motion and lens_strength>.001
	sprint_material.set_shader_parameter("strength",lens_strength)
	sprint_material.set_shader_parameter("rush",rush)
	for i in range(dust.size()):
		var owner := i%8
		var p := float(track_positions[owner])
		dust[i].visible=phase=="racing" and p>.002 and (not reduced_motion or i<48)
		if dust[i].visible:
			var particle_clock:=animation_clock*(1.2+float(i%3)*.09)+i*.173
			var cycle:=int(floor(particle_clock))
			var t:=fposmod(particle_clock,1.0)
			var path: Dictionary=course.sample(p,course.lane_radius(owner))
			if cycle!=dust_cycles[i]:
				dust_cycles[i]=cycle
				dust_forwards[i]=path.tangent
				dust_outwards[i]=path.outward
				dust_origins[i]=horses[owner].position-path.tangent*.45+path.outward*sin(i*7.3)*.38
			# Leave dust behind in world space instead of attaching it to the horse.
			dust[i].position=dust_origins[i]-dust_forwards[i]*t*lerpf(.7,1.6,sprint)+dust_outwards[i]*sin(i*2.1)*t*.4+Vector3(0,.08+t*lerpf(.2,.4,sprint),0)
			var size: float=.12+sin(t*PI)*lerpf(.4,.75,sprint)
			dust[i].scale=Vector3(size*1.3,size,size)
			var tint:=Color("8a9862")
			tint.a=sin(t*PI)*lerpf(.10,.18,sprint)
			dust_materials[i].albedo_color=tint
