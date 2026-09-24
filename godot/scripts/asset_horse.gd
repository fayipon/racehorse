extends Node3D

# Quaternius / CC0. The imported rig supplies all poses and skin deformation.
# Keep the same adapter used by race.gd, so timing and results stay independent.
const HORSE = preload("res://assets/quaternius/horse.glb")
var styles: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/horse_styles.json"))
var player: AnimationPlayer
var model: Node3D
var motion_blend := 0.0
var current_clip := "Idle"
var gait_phase := 0.0
var cadence := 1.0

func build(index: int, _color: Color) -> void:
	var style: Dictionary=styles[index]
	var coat:=Color(style.coat)
	gait_phase=fposmod(index*.381966,1.0)
	cadence=[.96,1.02,1.05,.98,1.01,.94,1.04,.99][index]
	model = HORSE.instantiate()
	model.scale = Vector3.ONE*.62
	model.rotation.y = PI # Source faces +Z; the course uses -Z as forward.
	model.position.y = .018
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		mesh.layers = 3
		for surface in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.mesh.surface_get_material(surface)
			var mat := StandardMaterial3D.new()
			mat.roughness = .9
			mat.metallic_specular = .16
			match original.resource_name:
				"Main": mat.albedo_color=coat
				"Main_Dark": mat.albedo_color=coat.darkened(.08)
				"Main_Light": mat.albedo_color=coat.lightened(.05)
				"Hair": mat.albedo_color=Color(style.mane)
				"Muzzle": mat.albedo_color=Color(style.muzzle)
				"Hooves": mat.albedo_color=Color("554638")
				"Eye_Black": mat.albedo_color=Color("171a1b")
				"Eye_White": mat.albedo_color=Color("ddd7c5")
				_: mat.albedo_color=coat
			mesh.set_surface_override_material(surface,mat)
	player = model.find_children("*","AnimationPlayer",true,false)[0]
	# Advance manually with the race's visual clock, including the finish slowdown.
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time=.32
	for clip in ["Idle","Walk","Gallop"]:
		var animation := player.get_animation(clip)
		animation.loop_mode=Animation.LOOP_LINEAR
	player.play("Idle")
	player.advance(0)
	player.seek(index*.19,true)
	var skeleton: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
	add_race_cloth(skeleton,index,Color(style.number))

func add_race_cloth(skeleton: Skeleton3D, index: int, color: Color) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name="Back"
	skeleton.add_child(attachment)
	# Convert the authored metre-space cloth into the back bone's rest frame.
	# Following the spine also follows its tilt, rather than hovering over it.
	var cloth := Node3D.new()
	var source_from_meters:=Transform3D(Basis(Vector3.RIGHT,PI/2)*.01,Vector3.ZERO)
	cloth.transform=skeleton.get_bone_global_rest(skeleton.find_bone("Back")).affine_inverse()*source_from_meters
	attachment.add_child(cloth)
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=.96
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var trim := StandardMaterial3D.new()
	trim.albedo_color=Color("ddd0ac")
	trim.roughness=.95
	trim.cull_mode=BaseMaterial3D.CULL_DISABLED
	# One connected sheet goes from the left hem, over the spine, to the
	# right hem. The lower sides hang vertically, like a racing saddlecloth.
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edging:=SurfaceTool.new()
	edging.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(40):
		for column in range(12):
			var edge:=row==0 or row==39 or column==0 or column==11
			for corner: Vector2i in [Vector2i(row,column),Vector2i(row+1,column),Vector2i(row,column+1),Vector2i(row,column+1),Vector2i(row+1,column),Vector2i(row+1,column+1)]:
				var u:=corner.x/40.0*2.0-1.0
				var v:=corner.y/12.0
				var shoulder:=minf(absf(u)/.57,1.0)*PI*.5
				var x:=signf(u)*sin(shoulder)*.71
				var y:=2.90+cos(shoulder)*.69-maxf(0.0,absf(u)-.57)/.43*.60
				var z:=-.97+v*1.24
				var point:=Vector3(x,y+.025*cos((v-.5)*PI),z)
				var target: SurfaceTool=edging if edge else surface
				target.add_vertex(point)
	for pair in [[surface,mat],[edging,trim]]:
		pair[0].generate_normals()
		var sheet:=MeshInstance3D.new()
		sheet.mesh=pair[0].commit()
		sheet.material_override=pair[1]
		sheet.layers=3
		cloth.add_child(sheet)
	for side in [-1,1]:
		var number := Label3D.new()
		number.text=str(index+1)
		number.font_size=96
		number.pixel_size=.009
		number.outline_size=0
		number.shaded=true
		number.layers=3
		number.modulate=Color("fff7e7") if index in [0,3,7] else Color("202822")
		number.position=Vector3(side*.722,2.73,-.35)
		number.rotation.y=side*PI/2
		cloth.add_child(number)

func animate(time: float, motion: float, running: bool, _celebration: bool, delta := .016, sprint_effort := 0.0) -> void:
	motion_blend=lerpf(motion_blend,clampf(motion,0,1),1.0-exp(-delta*8))
	# Hysteresis keeps tiny changes near standstill from repeatedly restarting clips.
	var clip := current_clip
	if motion_blend<.08:
		clip="Idle"
	elif motion_blend>.16:
		clip="Gallop" if running else "Walk"
	if clip!=current_clip:
		current_clip=clip
		player.play(clip,.32)
		# Offset once on clip entry; never restart a stride for a new snapshot.
		player.seek(gait_phase*player.get_animation(clip).length,false)
	var speed := 1.0
	if current_clip=="Walk": speed=lerpf(.55,1.15,motion_blend)
	if current_clip=="Gallop": speed=lerpf(.75,1.20,motion_blend)
	if current_clip=="Gallop": speed*=1.0+clampf(sprint_effort,0.0,1.0)*.1
	speed*=cadence*(1.0+sin(time*.83+gait_phase*TAU)*.025)
	player.advance(delta*speed)
