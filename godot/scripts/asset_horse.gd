extends Node3D

# Quaternius / CC0. The imported rig supplies all poses and skin deformation.
# Keep the same adapter used by race.gd, so timing and results stay independent.
const HORSE = preload("res://assets/quaternius/horse.glb")
const KIT = preload("res://scripts/mesh_kit.gd")
var styles: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/horse_styles.json"))
var player: AnimationPlayer
var model: Node3D
var motion_blend := 0.0
var current_clip := "Idle"
var gait_phase := 0.0
var cadence := 1.0
# What a standing horse does: Idle, Idle_2 (looks around), Idle_Headlow or Eating.
var idle_clip := "Idle"
# Races are judged at the nose: the muzzle tip is tracked on the head bone.
var skeleton: Skeleton3D
var head_bone := -1
var muzzle_local := Vector3.ZERO
var horse_from_skeleton := Transform3D.IDENTITY

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
	for clip in ["Idle","Idle_2","Idle_Headlow","Eating","Walk","Gallop"]:
		var animation := player.get_animation(clip)
		animation.loop_mode=Animation.LOOP_LINEAR
	player.play("Idle")
	player.advance(0)
	player.seek(index*.19,true)
	skeleton = model.find_children("*","Skeleton3D",true,false)[0]
	add_race_cloth(skeleton,index,Color(style.number))
	find_muzzle()

# The muzzle tip is the forward-most vertex of the rest pose, stored in the
# head bone's space so it follows the head through every gait.
func find_muzzle() -> void:
	var node: Node = skeleton
	while node!=self:
		horse_from_skeleton=(node as Node3D).transform*horse_from_skeleton
		node=node.get_parent()
	head_bone=skeleton.find_bone("Head")
	var best := -INF
	for mesh_instance: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh_instance.skin==null: continue
		var skin: Skin=mesh_instance.skin
		for bind in range(skin.get_bind_count()):
			# Imported skins bind by bone name, so the bone index can be -1.
			var bone:=skin.get_bind_bone(bind)
			if bone<0: bone=skeleton.find_bone(skin.get_bind_name(bind))
			if bone!=head_bone: continue
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var arrays := mesh_instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
				var per:=bones.size()/vertices.size()
				for v in range(vertices.size()):
					var weight:=0.0
					for k in range(per):
						if bones[v*per+k]==bind: weight+=weights[v*per+k]
					if weight<.5: continue
					var local: Vector3=skin.get_bind_pose(bind)*vertices[v]
					var ahead:=-(horse_from_skeleton*(skeleton.get_bone_global_rest(head_bone)*local)).z
					if ahead<=best: continue
					best=ahead
					muzzle_local=local

# The muzzle tip in the horse's own space for the current pose.
func muzzle_position() -> Vector3:
	return horse_from_skeleton*(skeleton.get_bone_global_pose(head_bone)*muzzle_local)

# How far the muzzle currently reaches ahead of the horse's origin, in metres.
func muzzle_reach() -> float:
	return -muzzle_position().z

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

# The champion's garland: a ring of blooms resting on the base of the neck.
func add_garland() -> void:
	var skeleton: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
	var attachment := BoneAttachment3D.new()
	attachment.bone_name="Neck1"
	skeleton.add_child(attachment)
	var holder := Node3D.new()
	var source_from_meters:=Transform3D(Basis(Vector3.RIGHT,PI/2)*.01,Vector3.ZERO)
	holder.transform=skeleton.get_bone_global_rest(skeleton.find_bone("Neck1")).affine_inverse()*source_from_meters
	attachment.add_child(holder)
	var ring := MeshInstance3D.new()
	ring.mesh=garland_mesh()
	ring.layers=3
	holder.add_child(ring)

# Authored like the saddlecloth: +Y is up and +Z points toward the head. The
# loop rests on the withers and its front drapes down over the chest.
func garland_point(a: float) -> Vector3:
	var front:=maxf(0.0,sin(a))
	return Vector3(cos(a)*.56,2.98-front*front*.62,1.32+sin(a)*.6)

func garland_mesh() -> ArrayMesh:
	var st := KIT.begin()
	var blooms: Array[Color]=[Color("f7c948"),Color("f29a3d"),Color("fbf0d4"),Color("f5b53d"),Color("e8663a")]
	var random := RandomNumberGenerator.new()
	random.seed=5150
	var major := 72
	var minor := 8
	var colors: Array[Color]=[]
	for cell in range(major*minor/4):
		colors.append(Color("3f7a35") if random.randf()<.12 else blooms[random.randi_range(0,blooms.size()-1)])
	for i in range(major):
		for j in range(minor):
			var points: Array[Vector3]=[]
			var normals: Array[Vector3]=[]
			for corner: Vector2i in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,j+1),Vector2i(i,j+1)]:
				var a:=TAU*corner.x/major
				var b:=TAU*corner.y/minor
				var center:=garland_point(a)
				var tangent:=(garland_point(a+.01)-garland_point(a-.01)).normalized()
				var side:=tangent.cross(Vector3.UP).normalized()
				var up:=side.cross(tangent)
				var normal:=side*cos(b)+up*sin(b)
				# Each pair of segments swells into one round bloom.
				var bloom:=absf(sin(a*major*.5))
				normals.append(normal)
				points.append(center+normal*.15*(.72+.5*bloom))
			var color: Color=colors[(i/2)*(minor/2)+j/2]
			for index: int in [0,2,1,0,3,2]: KIT.vertex(st,points[index],normals[index],color)
	var mat := KIT.painted(.85,.2)
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st.commit()

func animate(time: float, motion: float, running: bool, _celebration: bool, delta := .016, sprint_effort := 0.0) -> void:
	motion_blend=lerpf(motion_blend,clampf(motion,0,1),1.0-exp(-delta*8))
	# Hysteresis keeps tiny changes near standstill from repeatedly restarting clips.
	var clip := current_clip
	if motion_blend<.08:
		clip=idle_clip
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
