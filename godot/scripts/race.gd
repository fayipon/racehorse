extends Node3D

# React owns the clock and betting ledger. Godot renders the same distances,
# interpolating the bridge's snapshots for smooth, deterministic racing.
# Races are judged at the nose: a horse's progress places its muzzle, which
# gallops about 2.4 m ahead of its origin, rather than the middle of its body.
const NOSE := 2.4
const IDLE_CLIPS = ["Idle","Idle_2","Idle_Headlow","Eating"]
# On an upright phone stage a shot spans this much more than its lens angle, and
# its subject sits this far above the picture's centre (in picture heights).
const UPRIGHT_WIDTH := 1.15
const UPRIGHT_BETTING_SHIFT := .25
const UPRIGHT_RACE_SHIFT := .08
const UPRIGHT_PODIUM_SHIFT := .135
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
var landscape_node: Node3D
var infield_node: Node3D
var track_node: Node3D
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
# How each horse runs this round; React sends it, native previews use a fixture.
var race_plan: Dictionary = MOTION.preview_plan()
var preview_paused := false
const PARADE = preload("res://scripts/parade_motion.gd")
var parade_plan: Array = []
var betting_clock := 0.0
var last_betting_snapshot := -1.0
var finished := false
var dust: Array[MeshInstance3D] = []
var animation_clock := 0.0
var reduced_motion := false
var low_power := false
# React reports whether the stage is on screen; off screen the engine idles.
var stage_visible := true
var camera_focus := Vector3.ZERO
var camera_offset := Vector3.ZERO
var focus_offset := Vector3.ZERO
var camera_roll := 0.0
# Special-move effects: anime focus lines, a two-tone impact frame and a
# short shake, each triggered by the sprint cuts.
var lines_material: ShaderMaterial
var lines_rect: ColorRect
var lines_strength := 0.0
var lines_target := 0.0
var impact_material: ShaderMaterial
var impact_rect: ColorRect
var impact_clock := 10.0
var impact_scale := 0.0
var impact_shake := false
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
var winner_nose := NOSE
var paddock_shift := PackedFloat32Array([0,0,0,0,0,0,0,0])
var paddock_clock := 0.0
var paddock_settled := false
# Scene parts shown one per frame while the web build warms up its shaders.
var warmup: Array = []
var warmup_step := 0
# The shot's lens angle before any adjustment for an upright phone stage.
var lens_fov := 52.0
# Current upright lens shift, and the phase it was framed for.
var frame_shift := 0.0
var frame_phase := ""

func fullscreen_rect(mat: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect.material=mat
	rect.visible=false
	return rect

func course_point(progress: float, lane: int) -> Vector3:
	return course.sample(progress,course.lane_radius(lane)).position

func _ready() -> void:
	rng.seed = 61293
	if OS.has_feature("web"):
		reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
		# Phones and tablets get the power-saving tier: 30 fps, a lighter crowd and
		# planting, no MSAA or glow, and a smaller shadow map.
		low_power = bool(JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches"))
	Engine.max_fps = 30 if low_power else 60
	if low_power:
		get_viewport().msaa_3d=Viewport.MSAA_DISABLED
		RenderingServer.directional_shadow_atlas_set_size(2048,true)
	if not OS.has_feature("web"):
		parade_plan=PARADE.preview_plan(61293)
		winner=int(race_plan.winner)+1
		finish_times=race_plan.finishTimes
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
	var fx_layer := CanvasLayer.new()
	fx_layer.layer=2
	add_child(fx_layer)
	lines_material=ShaderMaterial.new()
	lines_material.shader=preload("res://shaders/focus_lines.gdshader")
	lines_rect=fullscreen_rect(lines_material)
	fx_layer.add_child(lines_rect)
	impact_material=ShaderMaterial.new()
	impact_material.shader=preload("res://shaders/impact_frame.gdshader")
	impact_rect=fullscreen_rect(impact_material)
	fx_layer.add_child(impact_rect)
	if OS.has_feature("web"):
		reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
		JavaScriptBridge.eval("window.parent.postMessage({type:'godot-ready'},window.location.origin)")
		# WebGL compiles each material's shaders the first time it draws, all on the
		# page's main thread. Revealing the scene a part per frame spreads that work,
		# so the page keeps painting and the loading bar keeps moving.
		# The first frame only reports that the build is done; each later part
		# brings a few new shaders.
		warmup=[[],[landscape_node],[infield_node,track_node],[venue],horses.duplicate()]
		for group: Array in warmup:
			for node: Node3D in group: node.visible=false

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
	env.glow_enabled = not low_power
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
	sun.directional_shadow_max_distance = 70.0 if low_power else 110.0
	add_child(sun)
	landscape_node=preload("res://scripts/landscape.gd").new()
	add_child(landscape_node)
	landscape_node.build(course,reduced_motion,low_power)
	infield_node=preload("res://scripts/infield.gd").new()
	add_child(infield_node)
	infield_node.build(course,reduced_motion or low_power)
	track_node=preload("res://scripts/race_track.gd").new()
	add_child(track_node)
	# The physical finish and minimap both lie at x=0 on the near straight.
	track_node.build(course)
	venue = preload("res://scripts/venue.gd").new()
	add_child(venue)
	venue.build(reduced_motion,COLORS,low_power)

# Shots are framed as a vertical angle on a wide stage. An upright phone stage
# turns a race or paddock shot into a horizontal angle a little wider than the
# shot, so the runners fill the width and the extra height adds turf and sky
# instead of cropping them; the podium shot already backs off to fit the three
# horses across. The picture fills the whole stage there with the controls laid
# over its lower part, so the lens also shifts the subject up into the open
# picture: well up while the betting panel is open, a little during the race
# and above the podium's standings.
func frame_upright(delta: float) -> void:
	var view:=get_viewport().get_visible_rect().size
	if view.x>=view.y:
		camera.projection=Camera3D.PROJECTION_PERSPECTIVE
		camera.keep_aspect=Camera3D.KEEP_HEIGHT
		camera.fov=lens_fov
		frame_phase=""
		return
	var target:=UPRIGHT_PODIUM_SHIFT if phase=="result" else UPRIGHT_BETTING_SHIFT if phase=="betting" and betting_clock<48.0 else UPRIGHT_RACE_SHIFT
	# Phase changes cut the camera, so the framing cuts with it.
	frame_shift=target if frame_phase!=phase else lerpf(frame_shift,target,1.0-exp(-delta*2.5))
	frame_phase=phase
	var lens:=2.0*camera.near*tan(deg_to_rad(lens_fov)*.5)
	if phase=="result":
		camera.keep_aspect=Camera3D.KEEP_HEIGHT
		camera.set_frustum(lens,Vector2(0,-frame_shift*lens),camera.near,camera.far)
	else:
		camera.keep_aspect=Camera3D.KEEP_WIDTH
		camera.set_frustum(lens*UPRIGHT_WIDTH,Vector2(0,-frame_shift*lens*UPRIGHT_WIDTH*view.y/view.x),camera.near,camera.far)

func warm_up() -> void:
	if warmup_step<warmup.size():
		for node: Node3D in warmup[warmup_step]: node.visible=true
		JavaScriptBridge.eval("window.parent.postMessage({type:'godot-warmup',step:%d,total:%d},window.location.origin)" % [warmup_step+1,warmup.size()])
	else:
		# The last part has drawn once; the stage can now fade in hitch-free.
		JavaScriptBridge.eval("window.parent.postMessage({type:'game-visible'},window.location.origin)")
	warmup_step+=1

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
	# Same flags as the fountain spray, so both share one shader.
	dust_mat.vertex_color_use_as_albedo=true
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
	var incoming_plan = data.get("racePlan",null)
	if incoming_plan is Dictionary and incoming_plan.get("knots",[]).size()==8: race_plan=incoming_plan
	preview_paused=bool(data.get("paused",false))
	stage_visible=bool(data.get("visible",true))
	# Off screen the race keeps its clock but draws only a few frames a second.
	var fps:=(30 if low_power else 60) if stage_visible else 4
	if Engine.max_fps!=fps: Engine.max_fps=fps
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
	if warmup_step<=warmup.size() and not warmup.is_empty(): warm_up()
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
	var strolls: Array=paddock_poses(delta) if phase=="betting" else []
	for i in range(8):
		track_positions[i]=MOTION.plan_progress(race_plan,i,presentation_clock) if phase!="betting" else 0.0
		visual_positions[i]=minf(float(track_positions[i]),1.0)
		var p := float(track_positions[i])
		var sample: Dictionary
		var moving := 1.0 if phase=="racing" else 0.0
		var running := phase=="racing"
		if phase=="betting":
			visual_positions[i]=0.0
			var stroll: Dictionary=strolls[i]
			var velocity: Vector2=stroll.velocity
			var target_yaw:=horses[i].rotation.y
			var stepping:=0.0
			if velocity.length()>.05:
				target_yaw=atan2(-velocity.x,-velocity.y)
			elif float(stroll.until_move)<1.4:
				# Step round toward the next walk before setting off, rather than
				# pivoting while already walking backwards.
				var next: Vector2=stroll.next_heading
				target_yaw=atan2(-next.x,-next.y)
				stepping=.3 if absf(angle_difference(horses[i].rotation.y,target_yaw))>.3 or float(stroll.until_move)<.5 else 0.0
			if betting_clock>=47.0 and (betting_clock<48.0 or betting_clock>=53.0 or velocity.length()<=.05):
				target_yaw=-PI/2
				if absf(angle_difference(horses[i].rotation.y,target_yaw))>.3: stepping=.3
			horses[i].rotation.y=lerp_angle(horses[i].rotation.y,target_yaw,minf(delta*2.4,1.0))
			# Any real translation keeps the walk cycle on, so hooves never slide.
			moving=clampf(maxf(velocity.length()/1.65,.25 if velocity.length()>.02 else 0.0)+stepping,0,1)
			horses[i].idle_clip=IDLE_CLIPS[int(stroll.mood)] if betting_clock<46.0 else "Idle"
			horses[i].position=Vector3(float(stroll.x)-NOSE,0,course.lane_radius(i)+float(stroll.lat))
		else:
			horses[i].idle_clip="Idle"
			sample=course.sample(p,course.lane_radius(i))
			var tangent: Vector3=sample.tangent
			horses[i].position=sample.position-tangent*(winner_nose if i==winner-1 else NOSE)
			horses[i].rotation.y=atan2(-tangent.x,-tangent.z)
		var celebration := phase=="result" and i==winner-1
		horses[i].visible=phase!="result"
		horses[i].call("animate",animation_clock,moving,running,celebration,delta*slow_motion,sprint_effort)
	# As the winner slows into the crossing hold, its measured muzzle rather than
	# the stride average is brought exactly onto the line.
	var exact:=smoothstep(44.45,44.6,race_clock)*(1.0-smoothstep(45.8,46.3,race_clock)) if phase=="racing" else 0.0
	winner_nose=lerpf(NOSE,horses[winner-1].muzzle_reach(),exact)
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
	# From the far turn, ease toward the front group without cutting to the
	# preselected winner or jumping whenever the live leader changes.
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
	var active_shot := shot
	if phase=="racing":
		if finished and race_clock<45.8: active_shot=10
		elif finished or race_clock>=42.3: active_shot=6
		elif race_clock>=39.5: active_shot=8
		elif race_clock>=37.0: active_shot=5
	if active_shot==8 and previous_shot!=8:
		featured_runner=visual_positions.find(visual_positions.max())
	# Follow shots ride along with an anchor, so fast runners never drift out of
	# frame; only the framing offsets ease. Fixed shots hold a world position
	# and pan like a lens on a tripod.
	var anchor := target
	var fixed := false
	var crisp := false
	var roll := 0.0
	var cam_pos: Vector3
	var focus := target
	var fov := 49.0
	lines_target=0.0
	var aspect:=get_viewport().get_visible_rect().size.aspect()
	var middle_lane:=float(course.config.laneStart)+3.5*float(course.config.laneSpacing)
	match active_shot:
		0:
			fixed=true
			focus=Vector3(-4,1.3,23.5)
			cam_pos=Vector3(8.5,6.0,42)
		1:
			focus=target+outward*1.3
			cam_pos=focus+forward*12+outward*7+Vector3(0,3.4,0)
		2:
			focus=target+forward*.8
			cam_pos=target+outward*9+forward*5+Vector3(0,2.3,0)
		3:
			# Chase the front runners through the far turn from behind and above.
			focus=target+forward*3.2
			cam_pos=target-forward*9.5+outward*5.2+Vector3(0,4.2,0)
			fov=46.0
		4:
			fixed=true
			var reveal:=0.5 if reduced_motion else smoothstep(50.0,60.0,race_clock)
			fov=34.0
			var distance:=maxf(19.0,15.5/(2.0*tan(deg_to_rad(fov*.5))*aspect))
			focus=podium.position+Vector3(0,2.6,0)
			cam_pos=podium.position+Vector3(lerpf(.8,-.5,reveal),4.8,distance+lerpf(1.2,0.0,reveal))
		5:
			# Turning for home: a long lens beside the winning post watches the
			# field charge out of the final bend, compressed and head-on.
			fixed=true
			cam_pos=Vector3(7.0,1.5,float(course.config.innerRadius)+float(course.config.trackWidth)+2.2)
			focus=target+forward*2.0+Vector3(0,.1,0)
			var half_width:=atan(5.2/cam_pos.distance_to(focus))
			fov=clampf(rad_to_deg(2.0*atan(tan(half_width)/aspect)),9.0,38.0)
			lines_target=.3*smoothstep(37.0,39.3,race_clock)
		6:
			fixed=true
			if finished:
				# After the crossing orbit, a still view from inside the main stand,
				# under its roof, keeps the line and the field in frame as they gallop on.
				cam_pos=Vector3(-4.0,11.0,47.5)
				focus=Vector3(10.0,.5,24.0)
				fov=50.0
			else:
				# Release after the cut-in: a low wide lens races beside the front
				# runners at hoof height, horizon tilted, toward the post.
				fixed=false
				focus=target+forward*2.6+Vector3(0,.1,0)
				cam_pos=target+outward*6.2+forward*1.0+Vector3(0,-.5,0)
				fov=lerpf(58.0,52.0,smoothstep(42.3,44.6,race_clock))
				roll=-5.0
				lines_target=.45
		7:
			fixed=true
			cam_pos=Vector3(0,100,5)
			focus=Vector3.ZERO
			fov=70.0
		8:
			# Special-move cut-in on the live leader: slow motion, a snap zoom onto
			# its face from a low heroic angle, then a sweep round to the side.
			var close_path: Dictionary=course.sample(float(visual_positions[featured_runner]),course.lane_radius(featured_runner))
			var close_forward: Vector3=close_path.tangent
			var close_out: Vector3=close_path.outward
			var sweep:=lerpf(.8,.32,smoothstep(39.5,42.3,race_clock))
			var punch:=1.0 if reduced_motion else 1.0-pow(1.0-clampf((race_clock-39.5)/.32,0.0,1.0),3.0)
			anchor=horses[featured_runner].position
			focus=anchor+close_forward*1.75+Vector3(0,2.05,0)
			cam_pos=focus+(close_out*cos(sweep)+close_forward*sin(sweep))*4.0+Vector3(0,-.35,0)
			fov=lerpf(60.0,31.0,punch)-4.0*smoothstep(39.9,42.3,race_clock)
			roll=lerpf(13.0,6.0,smoothstep(39.5,42.3,race_clock))
			crisp=true
			lines_target=1.0-.35*smoothstep(40.6,42.3,race_clock)
		10:
			# Photo finish: the impact lands with the lens in the plane of the line,
			# so the line, the winning post and the winner's nose stand in one
			# vertical at the centre. After that beat the camera swings low round
			# to the front while the race clock holds the crossing pose.
			var sweep:=0.5 if reduced_motion else smoothstep(45.1,45.8,race_clock)
			var punch:=1.0 if reduced_motion else 1.0-pow(1.0-clampf((race_clock-44.6)/.25,0.0,1.0),3.0)
			var tip: Vector3=horses[winner-1].transform*horses[winner-1].muzzle_position()
			var hero:=horses[winner-1].position+forward*1.2+Vector3(0,1.75,0)
			var pivot:=tip.lerp(hero,sweep)
			var angle:=lerpf(0.0,.75,sweep)
			cam_pos=pivot+(outward*cos(angle)+forward*sin(angle))*6.0+Vector3(0,lerpf(-.35,.35,sweep),0)
			focus=pivot
			fov=lerpf(58.0,36.0,punch)
			crisp=true
			lines_target=.95
		_:
			cam_pos=target+outward*9+forward*7+Vector3(0,2.1,0)
	var mount:=Vector3.ZERO if fixed else anchor
	var cut:=active_shot!=previous_shot
	# The cut-in and the crossing land with an impact frame; the crossing shakes.
	if cut and camera_initialized and phase=="racing" and active_shot in [8,10]:
		impact_clock=0.0
		impact_scale=.7 if active_shot==8 else 1.0
		impact_shake=active_shot==10
	# Every change of shot is a straight cut, as in a race broadcast. Crisp
	# shots are choreographed curves already and are never eased.
	# Focus lines belong to their shot; a cut to a calm view drops them at once.
	if cut: lines_strength=minf(lines_strength,lines_target)
	if not camera_initialized or cut or crisp:
		camera_offset=cam_pos-mount
		focus_offset=focus-mount
		lens_fov=fov
		camera_roll=roll
		camera_initialized=true
	else:
		var framing:=1.0-exp(-delta*3.0)
		camera_offset=camera_offset.lerp(cam_pos-mount,framing)
		# A fixed lens pans onto its subject directly; easing it would lag behind.
		focus_offset=focus_offset.lerp(focus-mount,1.0 if fixed else framing)
		lens_fov=lerpf(lens_fov,fov,1.0-exp(-delta*4.0))
		camera_roll=lerpf(camera_roll,roll,framing)
	frame_upright(delta)
	camera.position=mount+camera_offset
	camera_focus=mount+focus_offset
	if impact_shake and not reduced_motion and impact_clock<.28:
		var decay:=1.0-smoothstep(0.0,.28,impact_clock)
		camera.position+=Vector3(sin(impact_clock*71.0),sin(impact_clock*53.0+1.3),sin(impact_clock*61.0+2.1))*.07*decay
	previous_shot=active_shot
	camera.look_at(camera_focus,Vector3.UP)
	if absf(camera_roll)>.001: camera.rotate_object_local(Vector3.BACK,deg_to_rad(camera_roll))
	update_effects(delta)
	update_board(delta)

# Pre-race stroll for all eight horses. Neighbours walking alongside ease apart
# sideways instead of passing through each other; x stays on the shared plan.
# Only a horse on the move steps aside: a standing horse's offset is frozen,
# so it never slides.
func paddock_poses(delta: float) -> Array:
	if betting_clock<paddock_clock-1.0: paddock_settled=false
	paddock_clock=betting_clock
	var poses: Array=[]
	var walking: Array[bool]=[]
	for i in range(8):
		var pose: Dictionary=PARADE.pose(betting_clock,parade_plan[i] if parade_plan.size()==8 else [])
		poses.append(pose)
		walking.append((pose.velocity as Vector2).length()>.02 or not paddock_settled)
	var desired:=PackedFloat32Array([0,0,0,0,0,0,0,0])
	for i in range(8):
		if not walking[i]: desired[i]=paddock_shift[i]
	for sweep in range(3):
		for i in range(7):
			var inner: Dictionary=poses[i]
			var outer: Dictionary=poses[i+1]
			var alongside:=1.0-smoothstep(2.2,3.0,absf(float(inner.x)-float(outer.x)))
			var gap:=float(course.config.laneSpacing)+float(outer.lat)+desired[i+1]-float(inner.lat)-desired[i]
			var need:=maxf(0.0,1.05-gap)*alongside
			if need<=0.0: continue
			if walking[i] and walking[i+1]:
				desired[i]-=need*.5
				desired[i+1]+=need*.5
			elif walking[i]: desired[i]-=need
			elif walking[i+1]: desired[i+1]+=need
	for i in range(8):
		var before:=paddock_shift[i]
		var pace:=(poses[i].velocity as Vector2).length()
		# Side-steps stay slower than the walk itself, and turn the head with them.
		if walking[i]: paddock_shift[i]=move_toward(before,desired[i],maxf(.12,pace*.5)*delta) if paddock_settled else desired[i]
		poses[i].lat=float(poses[i].lat)+paddock_shift[i]
		if paddock_settled and delta>0.0: poses[i].velocity=(poses[i].velocity as Vector2)+Vector2(0,(paddock_shift[i]-before)/delta)
	paddock_settled=true
	return poses

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
	var sprint:=smoothstep(34.0,40.0,race_clock) if phase=="racing" else 0.0
	# Edge speed blur belongs to moving cameras. The tripod lenses, the slow
	# motion cut-in, the frozen crossing and the still finish view stay sharp.
	var rushing:=phase=="racing" and previous_shot==6 and not finished
	var lens_strength: float=sprint*float({3:.8,5:.2,8:.25}.get(previous_shot,0.0))
	if rushing: lens_strength=1.0
	sprint_grade.visible=not reduced_motion and lens_strength>.001
	sprint_material.set_shader_parameter("strength",lens_strength)
	sprint_material.set_shader_parameter("rush",1.0 if rushing else 0.0)
	impact_clock+=delta
	var lines_goal:=0.0 if reduced_motion or phase!="racing" else lines_target
	lines_strength=lines_goal if lines_goal>lines_strength else lerpf(lines_strength,lines_goal,1.0-exp(-delta*6.0))
	lines_rect.visible=lines_strength>.01
	if lines_rect.visible:
		lines_material.set_shader_parameter("strength",lines_strength)
		lines_material.set_shader_parameter("seed",floorf(elapsed*12.0))
	var impact:=0.0 if reduced_motion else impact_scale*(1.0-smoothstep(.06,.2,impact_clock))
	impact_rect.visible=impact>.01
	impact_material.set_shader_parameter("strength",impact)
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
