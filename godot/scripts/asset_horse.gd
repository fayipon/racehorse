extends Node3D

# The race horse. The imported rig supplies all poses and skin deformation; this
# adapter keeps race.gd independent of the model, so timing and results stay put.
# With the licensed Viverna stallion prepared locally (scripts/prepare_viverna_horse.py,
# never committed) the stable wears textured coats; a checkout without it runs
# the CC0 Quaternius horse instead, as does `-- --cc0-horse` on the command line.
const VIVERNA := "res://assets/viverna/stallion.glb"
const QUATERNIUS := "res://assets/quaternius/horse.glb"
const KIT = preload("res://scripts/mesh_kit.gd")
const STRIDE_FIT = preload("res://scripts/stride_fit.gd")
static var realistic := ResourceLoader.exists(VIVERNA) and not OS.get_cmdline_user_args().has("--cc0-horse")
static var source: PackedScene = load(VIVERNA if realistic else QUATERNIUS)
# Phones race the lighter level of detail.
static var low_power := false
# How far the body travels over one walk cycle while its planted hooves stand
# still, measured on each model. The walk advances by the ground a horse
# covers, so its hooves never skate round the paddock.
const WALK_STRIDE_VIVERNA := 1.39
const WALK_STRIDE_QUATERNIUS := 1.98
static var walk_stride: float = WALK_STRIDE_VIVERNA if realistic else WALK_STRIDE_QUATERNIUS
# The course is about a third of real size, so the field gallops at 6-7 m/s
# where racehorses run 17. Matched to that ground, the stallion's 6.4 m stride
# would come once a second and read as slow motion. The gallop keeps a
# racehorse's rhythm instead: GALLOP_TEMPO strides a second at the field's
# pace, quickening as a horse speeds up.
const GALLOP_TEMPO := 2.1
const GALLOP_PACE := 6.5
var styles: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/horse_styles.json"))
var player: AnimationPlayer
var model: Node3D
var motion_blend := 0.0
var current_clip := "Idle"
var gait_phase := 0.0
var cadence := 1.0
var last_position := Vector3.INF
# What a standing horse does: Idle, Idle_2 (looks around), Idle_Headlow or Eating.
var idle_clip := "Idle"
# Races are judged at the nose: the muzzle tip is tracked on the head bone.
var skeleton: Skeleton3D
var head_bone := -1
var muzzle_local := Vector3.ZERO
var horse_from_skeleton := Transform3D.IDENTITY
static var body_material: StandardMaterial3D
# The cloth's own material, told how hard the horse is moving so its skirt swings.
var cloth_material: ShaderMaterial
var cloth_stride := -1.0
# Narrows the gallop's stride to the ground covered (stride_fit.gd).
var stride_fit: SkeletonModifier3D
# A galloping horse banks into a bend; it leans by the turn it is making.
const LEAN_MOST := .2
# How far the neck turns into a bend, for each radian of lean.
const LOOK_INTO_TURN := .9
# Metres to the line while the winner is running in, set by race.gd; -1 otherwise.
# Over its last strides it quickens or eases its rhythm a little so it crosses
# at full stretch, not with its legs gathered under it.
var finish_in := -1.0
const FINISH_STEER := 1.6
const STEER_MOST := .3
var lean := 0.0
var last_heading := INF

func build(index: int, _color: Color) -> void:
	var style: Dictionary=styles[index]
	var coat:=Color(style.coat)
	gait_phase=fposmod(index*.381966,1.0)
	cadence=[.96,1.02,1.05,.98,1.01,.94,1.04,.99,1.03,.97,1.0,.95][index]
	model = source.instantiate()
	# Both sources face +Z; the course uses -Z as forward. Each is scaled to the
	# same horse: 2.2 m from origin to muzzle, about 2.95 m to the ears.
	model.rotation.y = PI
	if realistic:
		model.scale = Vector3.ONE*1.36
	else:
		model.scale = Vector3.ONE*.62
		model.position.y = .018
	add_child(model)
	skeleton = model.find_children("*","Skeleton3D",true,false)[0]
	var node: Node = skeleton
	while node!=self:
		horse_from_skeleton=(node as Node3D).transform*horse_from_skeleton
		node=node.get_parent()
	if realistic:
		dress(index,style)
	else:
		if body_material==null:
			# Vertex colour matches the course paint, so both share one shader.
			body_material=StandardMaterial3D.new()
			body_material.vertex_color_use_as_albedo=true
			body_material.roughness=.9
			body_material.metallic_specular=.16
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			mesh.layers = 3
			mesh.mesh=painted_body(mesh.mesh,style,coat)
			mesh.material_override=body_material
	player = model.find_children("*","AnimationPlayer",true,false)[0]
	# Advance manually with the race's visual clock, including the finish slowdown.
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time=.32
	for clip in ["Idle","Idle_2","Idle_Headlow","Eating","Walk","Gallop"]:
		var animation := player.get_animation(clip)
		animation.loop_mode=Animation.LOOP_LINEAR
		if not shared.has("trimmed:"+clip):
			trim_held_frame(animation)
			shared["trimmed:"+clip]=true
	if realistic:
		if not shared.has("stride"): shared.stride=STRIDE_FIT.study(skeleton,player,horse_from_skeleton)
		if not (shared.stride as Dictionary).is_empty():
			stride_fit=STRIDE_FIT.new()
			stride_fit.setup(shared.stride)
			skeleton.add_child(stride_fit)
	player.play("Idle",0.0)
	player.advance(0)
	player.seek(index*.19,true)
	add_race_cloth(index,Color(style.number))
	find_muzzle()

# The pack's clips begin on a held frame: their first two frames are the same
# pose, so every loop stalls for a frame (a hitch in each gallop stride). The
# first frame is cut and the clip starts on the second, which its last frame
# already matches. A clip without the held frame is left alone.
static func trim_held_frame(clip: Animation) -> void:
	var frame:=INF
	for t in range(clip.get_track_count()):
		for k in range(clip.track_get_key_count(t)):
			var time:=clip.track_get_key_time(t,k)
			if time>1e-4: frame=minf(frame,time)
	if not is_finite(frame) or frame>=clip.length*.5: return
	var held:=0.0
	var moving:=0.0
	for t in range(clip.get_track_count()):
		if clip.track_get_type(t)!=Animation.TYPE_ROTATION_3D: continue
		var a:=clip.rotation_track_interpolate(t,0.0)
		var b:=clip.rotation_track_interpolate(t,frame)
		var c:=clip.rotation_track_interpolate(t,frame*2.0)
		held+=a.angle_to(b)
		moving+=b.angle_to(c)
	if held>moving*.2: return
	for t in range(clip.get_track_count()):
		var type:=clip.track_get_type(t)
		if clip.track_get_key_count(t)<2: continue
		match type:
			Animation.TYPE_POSITION_3D: clip.position_track_insert_key(t,frame,clip.position_track_interpolate(t,frame))
			Animation.TYPE_ROTATION_3D: clip.rotation_track_insert_key(t,frame,clip.rotation_track_interpolate(t,frame))
			Animation.TYPE_SCALE_3D: clip.scale_track_insert_key(t,frame,clip.scale_track_interpolate(t,frame))
			Animation.TYPE_VALUE: clip.track_insert_key(t,frame,clip.value_track_interpolate(t,frame))
			_: continue
		while clip.track_get_key_count(t)>0 and clip.track_get_key_time(t,0)<frame-1e-4: clip.track_remove_key(t,0)
		for k in range(clip.track_get_key_count(t)): clip.track_set_key_time(t,k,clip.track_get_key_time(t,k)-frame)
	clip.length-=frame

# The textured stallion. The pack's coats are greys, whites, a black and a roan;
# bays, chestnuts and palominos are tinted from them, so the stable keeps the
# colours of horse_styles.json. The grey coat's black legs make a tinted bay;
# the cream coat tints to chestnut and palomino. The mane takes its style colour.
const TEXTURES := "res://assets/viverna/textures/"
const COATS := ["creame","gray","creame","black","creame","gray","white","gray","creame","grayrose","creame","creame"]
const TINTED := [true,true,true,false,true,false,false,true,true,false,true,true]
static var shared := {}
static func texture(name: String) -> Texture2D:
	if not shared.has(name): shared[name]=load(TEXTURES+name+".png")
	return shared[name]

# The average linear colour of a texture over a region given in UV, opaque texels only.
static func average(name: String, region: Rect2) -> Color:
	var key:="average:"+name
	if shared.has(key): return shared[key]
	var image:=texture(name).get_image()
	if image.is_compressed(): image.decompress()
	var sum:=Color(0,0,0,0)
	var count:=0
	for sy in range(24):
		for sx in range(24):
			var pixel:=image.get_pixelv(Vector2i((region.position+region.size*Vector2(sx/23.0,sy/23.0))*Vector2(image.get_size()-Vector2i.ONE)))
			if pixel.a<.5: continue
			sum+=pixel.srgb_to_linear()
			count+=1
	shared[key]=sum/maxi(count,1)
	return shared[key]

# The colour that turns a texture's own average into the wanted one, both linear.
static func tint(wanted: Color, base: Color) -> Color:
	var goal:=wanted.srgb_to_linear()
	return Color(minf(goal.r/maxf(base.r,.01),1.4),minf(goal.g/maxf(base.g,.01),1.4),minf(goal.b/maxf(base.b,.01),1.4)).linear_to_srgb()

func dress(index: int, style: Dictionary) -> void:
	var coat:=ORMMaterial3D.new()
	var name: String="coat_"+COATS[index]
	coat.albedo_texture=texture(name)
	# The body's big UV island, clear of the legs, head and mane.
	if TINTED[index]: coat.albedo_color=tint(Color(style.coat),average(name,Rect2(.1,.12,.55,.45)))
	coat.normal_enabled=true
	coat.normal_texture=texture("body_normal")
	coat.orm_texture=texture("body_orm")
	coat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var hair:=StandardMaterial3D.new()
	hair.albedo_texture=texture("hair_albedo")
	hair.albedo_color=tint(Color(style.mane),average("hair_albedo",Rect2(0,0,1,1)))
	hair.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	hair.alpha_scissor_threshold=.4
	hair.cull_mode=BaseMaterial3D.CULL_DISABLED
	hair.normal_enabled=true
	hair.normal_texture=texture("hair_normal")
	hair.roughness=.62
	var main:="BodyLow" if low_power else "Body"
	for mesh: MeshInstance3D in skeleton.find_children("*","MeshInstance3D",true,false):
		if mesh.name not in [main,"BodyShadow"]:
			mesh.queue_free()
			continue
		mesh.layers=3
		# A 780-triangle stand-in casts every shadow; the drawn body casts none.
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if mesh.name=="BodyShadow" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in range(mesh.mesh.get_surface_count()):
			mesh.set_surface_override_material(surface,hair if mesh.mesh.surface_get_material(surface).resource_name=="Hair" else coat)

# The drawn body mesh, for fitting the cloth and garland and finding the muzzle.
func body_mesh() -> MeshInstance3D:
	for mesh: MeshInstance3D in skeleton.find_children("*","MeshInstance3D",true,false):
		if mesh.is_queued_for_deletion() or mesh.name=="BodyShadow": continue
		if mesh.skin!=null: return mesh
	return null

# Rest-pose points of the body (manes and tails left out) in the horse's own
# space, with each vertex's bones and weights. The same for every horse of a
# model, so worked out once.
func body_points() -> Dictionary:
	if shared.has("body"): return shared.body
	var mesh:=body_mesh()
	var skin:=mesh.skin
	var bind_bone:=skin.get_bind_bone(0)
	if bind_bone<0: bind_bone=skeleton.find_bone(skin.get_bind_name(0))
	# In the rest pose every bind maps the mesh to the skeleton alike.
	var mesh_to_horse:=horse_from_skeleton*skeleton.get_bone_global_rest(bind_bone)*skin.get_bind_pose(0)
	var points:=PackedVector3Array()
	var triangles:=PackedInt32Array()
	var bones:=PackedInt32Array()
	var weights:=PackedFloat32Array()
	var per:=4
	for surface in range(mesh.mesh.get_surface_count()):
		var material:=mesh.mesh.surface_get_material(surface)
		if material!=null and material.resource_name=="Hair": continue
		var arrays:=mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		per=(arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size()/vertices.size()
		for i: int in arrays[Mesh.ARRAY_INDEX]: triangles.append(points.size()+i)
		for v in vertices: points.append(mesh_to_horse*v)
		bones.append_array(arrays[Mesh.ARRAY_BONES])
		weights.append_array(arrays[Mesh.ARRAY_WEIGHTS])
	shared.body={"points":points,"triangles":triangles,"bones":bones,"weights":weights,"per":per,"mesh_to_horse":mesh_to_horse}
	return shared.body

static func part_color(part: String, style: Dictionary, coat: Color) -> Color:
	match part:
		"Main_Dark": return coat.darkened(.08)
		"Main_Light": return coat.lightened(.05)
		"Hair": return Color(style.mane)
		"Muzzle": return Color(style.muzzle)
		"Hooves": return Color("554638")
		"Eye_Black": return Color("171a1b")
		"Eye_White": return Color("ddd7c5")
	return coat

# The model colours its parts with eight materials, and each was a draw call
# per horse and per shadow split. Baking each part's colour into its vertices
# draws the body in one call.
static func painted_body(source: Mesh, style: Dictionary, coat: Color) -> ArrayMesh:
	var surfaces: Array = []
	for surface in range(source.get_surface_count()): surfaces.append(source.surface_get_arrays(surface))
	var kinds: Array = []
	for kind in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS]:
		if surfaces.all(func(arrays: Array) -> bool: return arrays[kind]!=null): kinds.append(kind)
	var merged: Array = []
	merged.resize(Mesh.ARRAY_MAX)
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for surface in range(surfaces.size()):
		var arrays: Array = surfaces[surface]
		var base := colors.size()
		var tint := part_color(source.surface_get_material(surface).resource_name,style,coat)
		var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for i in range(count): colors.append(tint*(arrays[Mesh.ARRAY_COLOR][i] if arrays[Mesh.ARRAY_COLOR]!=null else Color.WHITE))
		for index: int in arrays[Mesh.ARRAY_INDEX]: indices.append(base+index)
		for kind: int in kinds:
			if merged[kind]==null: merged[kind]=arrays[kind].duplicate()
			else: merged[kind].append_array(arrays[kind])
	merged[Mesh.ARRAY_COLOR]=colors
	merged[Mesh.ARRAY_INDEX]=indices
	var flags := 0
	if merged[Mesh.ARRAY_BONES]!=null and merged[Mesh.ARRAY_BONES].size()==colors.size()*8: flags=Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var painted := ArrayMesh.new()
	painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,merged,[],{},flags)
	return painted

# The skeleton bone a skin bind drives. Imported skins bind by bone name, so
# the bone index can be -1.
func bind_bone(bind: int) -> int:
	var skin:=body_mesh().skin
	var bone:=skin.get_bind_bone(bind)
	return bone if bone>=0 else skeleton.find_bone(skin.get_bind_name(bind))

# The muzzle tip is the forward-most rest-pose vertex moved mostly by the head
# (the head bone or its jaw, lips and nose), stored in the head bone's space so
# it follows the head through every gait.
func find_muzzle() -> void:
	head_bone=skeleton.find_bone("Head")
	var head:={}
	for bind in range(body_mesh().skin.get_bind_count()):
		var bone:=bind_bone(bind)
		while bone>=0 and bone!=head_bone: bone=skeleton.get_bone_parent(bone)
		if bone==head_bone: head[bind]=true
	var body:=body_points()
	var points: PackedVector3Array=body.points
	var bones: PackedInt32Array=body.bones
	var weights: PackedFloat32Array=body.weights
	var per: int=body.per
	var best:=INF
	for v in range(points.size()):
		var weight:=0.0
		for k in range(per):
			if head.has(bones[v*per+k]): weight+=weights[v*per+k]
		if weight<.5 or points[v].z>=best: continue
		best=points[v].z
		muzzle_local=skeleton.get_bone_global_rest(head_bone).affine_inverse()*(horse_from_skeleton.affine_inverse()*points[v])

# The muzzle tip in the horse's own space for the current pose.
func muzzle_position() -> Vector3:
	return horse_from_skeleton*(skeleton.get_bone_global_pose(head_bone)*muzzle_local)

# How far the muzzle currently reaches ahead of the horse's origin, in metres.
func muzzle_reach() -> float:
	return -muzzle_position().z

# The saddlecloth is fitted to the body it lies on: over the back from behind
# the withers to the loin, following the coat a few centimetres off it, then
# hanging straight down each side below the barrel's widest point, like a
# racing saddlecloth. It takes the weights of the body under it, so it moves
# with every stride. The shape is worked out once per model; each horse only
# colours it. A light racing saddle sits on it and an elastic over-girth runs
# over the saddle and round the barrel, fitted and skinned the same way; the
# skirt below the barrel stands a little off the coat and swings with the gait.
const CLOTH_SPAN := Vector2(.46,.75) # of the body's length, from the muzzle back
const CLOTH_OFF := .035
const CLOTH_HANG := .24
const CLOTH_ROWS := 20
const CLOTH_ARC := 16 # steps over each side of the back, from the spine to the widest point
const CLOTH_DROP := 5
# How far the hem stands off the coat, and the cloth's thickness at its edges.
const CLOTH_FLARE := .035
const CLOTH_THICK := .012
# The number's centre: up from the hem, and along the flank from the front.
const CLOTH_NUMBER_UP := .25
const CLOTH_NUMBER_ALONG := .62
# Along the cloth from its front edge: the saddle seat's centre and the
# over-girth's centre line, in metres; the shader draws the saddle's outline.
const SADDLE_AT := .4
const GIRTH_AT := .36
const GIRTH_WIDTH := .065
const GIRTH_CLEAR := .012
const CLOTH = preload("res://shaders/saddle_cloth.gdshader")
const DIGITS = preload("res://assets/cloth_digits.png")

func cloth_shape() -> Dictionary:
	if shared.has("cloth"): return shared.cloth
	var body:=body_points()
	var points: PackedVector3Array=body.points
	var front:=INF
	var back:=-INF
	for p in points:
		front=minf(front,p.z)
		back=maxf(back,p.z)
	var z0:=lerpf(front,back,CLOTH_SPAN.x)
	var z1:=lerpf(front,back,CLOTH_SPAN.y)
	# Only the body under the cloth is searched for its nearest vertex.
	var under:=PackedInt32Array()
	for i in range(points.size()):
		if points[i].z>z0-.15 and points[i].z<z1+.15: under.append(i)
	# Each cross-section is a superellipse through the spine's height and the
	# barrel's widest point, swelled until no coat pokes through it.
	var rows: Array=[]
	for r in range(CLOTH_ROWS+1):
		var z:=lerpf(z0,z1,float(r)/CLOTH_ROWS)
		var slab:=section(z)
		var top:=-INF
		for p in slab:
			if absf(p.x)<.1: top=maxf(top,p.y)
		var widest:=0.0
		var widest_y:=top-.5
		for p in slab:
			if p.y<top-.1 and p.y>top-1.0 and absf(p.x)>widest:
				widest=absf(p.x)
				widest_y=p.y
		rows.append({"z":z,"top":top,"width":widest,"y":widest_y,"slab":slab})
	# Neighbouring rows are averaged so the cloth lies in one sweep.
	var shapes: Array=[]
	for r in range(rows.size()):
		var near: Array=rows.slice(maxi(r-2,0),mini(r+3,rows.size()))
		var shape:={"z":rows[r].z,"top":0.0,"width":0.0,"y":0.0}
		for row: Dictionary in near:
			for key in ["top","width","y"]: shape[key]+=float(row[key])/near.size()
		shapes.append(shape)
	for r in range(rows.size()):
		var shape: Dictionary=shapes[r]
		var swell:=1.0
		for p: Vector2 in rows[r].slab:
			if p.y<float(shape.y): continue
			var d:=Vector2(absf(p.x),p.y-float(shape.y))
			swell=maxf(swell,d.length()/superellipse(atan2(d.x,d.y),shape))
		shape.swell=swell
	for r in range(shapes.size()):
		var most:=1.0
		for near: Dictionary in shapes.slice(maxi(r-1,0),mini(r+2,shapes.size())): most=maxf(most,float(near.swell))
		shapes[r].fit=most
	# The sheet's grid in horse space: left hem, over the spine, right hem.
	var grid: Array=[]
	for shape: Dictionary in shapes:
		var line: Array[Vector3]=[]
		var side_x:=float(shape.width)*float(shape.fit)+CLOTH_OFF
		for k in range(CLOTH_DROP):
			var hang:=1.0-float(k)/CLOTH_DROP
			line.append(Vector3(-side_x-CLOTH_FLARE*pow(hang,1.5),float(shape.y)-CLOTH_HANG*hang,shape.z))
		for step in range(-CLOTH_ARC,CLOTH_ARC+1):
			var angle:=float(step)/CLOTH_ARC*PI*.5
			var reach:=superellipse(absf(angle),shape)*float(shape.fit)+CLOTH_OFF
			line.append(Vector3(sin(angle)*reach,float(shape.y)+cos(angle)*reach,shape.z))
		for k in range(CLOTH_DROP-1,-1,-1):
			var hang:=1.0-float(k)/CLOTH_DROP
			line.append(Vector3(side_x+CLOTH_FLARE*pow(hang,1.5),float(shape.y)-CLOTH_HANG*hang,shape.z))
		grid.append(line)
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var bones:=PackedInt32Array()
	var weights:=PackedFloat32Array()
	var per: int=body.per
	var horse_to_mesh: Transform3D=(body.mesh_to_horse as Transform3D).affine_inverse()
	var columns: int=grid[0].size()
	var grid_normals: Array[Vector3]=[]
	for r in range(grid.size()):
		for c in range(columns):
			var p: Vector3=grid[r][c]
			var across: Vector3=grid[r][mini(c+1,columns-1)]-grid[r][maxi(c-1,0)]
			var along: Vector3=grid[mini(r+1,grid.size()-1)][c]-grid[maxi(r-1,0)][c]
			var normal:=along.cross(across).normalized()
			if normal.dot(Vector3(p.x,p.y-float(shapes[r].y),0))<0: normal=-normal
			grid_normals.append(normal)
			vertices.append(horse_to_mesh*p)
			normals.append((horse_to_mesh.basis*normal).normalized())
			var nearest:=nearest_point(p,.12,under)
			bones.append_array((body.bones as PackedInt32Array).slice(nearest*per,nearest*per+per))
			weights.append_array((body.weights as PackedFloat32Array).slice(nearest*per,nearest*per+per))
	var indices:=PackedInt32Array()
	for r in range(grid.size()-1):
		for c in range(columns-1):
			var a:=r*columns+c
			# Wound clockwise seen from outside, Godot's front face.
			indices.append_array([a,a+1,a+columns,a+1,a+columns+1,a+columns])
	# The shader draws the cloth in metres: UV runs across from the spine and
	# along from the front edge, UV2 holds the distance to the nearer hem and
	# to the nearer end, both measured over the sheet.
	var uv:=PackedVector2Array()
	var edge:=PackedVector2Array()
	uv.resize(vertices.size())
	edge.resize(vertices.size())
	for r in range(grid.size()):
		var run:=PackedFloat32Array([0.0])
		for c in range(1,columns): run.append(run[c-1]+(grid[r][c] as Vector3).distance_to(grid[r][c-1]))
		for c in range(columns):
			uv[r*columns+c]=Vector2(run[c]-run[CLOTH_DROP+CLOTH_ARC],0)
			edge[r*columns+c]=Vector2(minf(run[c],run[columns-1]-run[c]),0)
	var length:=0.0
	for c in range(columns):
		var run:=PackedFloat32Array([0.0])
		for r in range(1,grid.size()): run.append(run[r-1]+(grid[r][c] as Vector3).distance_to(grid[r-1][c]))
		for r in range(grid.size()):
			var i:=r*columns+c
			uv[i]=Vector2(uv[i].x,run[r])
			edge[i]=Vector2(edge[i].x,minf(run[r],run[grid.size()-1]-run[r]))
		if c==CLOTH_DROP: length=run[grid.size()-1]
	# How freely each column hangs: 1 at the hems, 0 from the barrel's widest
	# point up over the back. The shader swings the skirt by it.
	var colors:=PackedColorArray()
	for r in range(grid.size()):
		for c in range(columns):
			var k:=c if c<CLOTH_DROP else columns-1-c if c>=columns-CLOTH_DROP else CLOTH_DROP
			colors.append(Color(1.0-float(k)/CLOTH_DROP,0,0))
	var cloth:={"vertices":vertices,"normals":normals,"bones":bones,"weights":weights,"indices":indices,"uv":uv,"edge":edge,"colors":colors,
		"number_at":Vector2(CLOTH_NUMBER_UP,length*CLOTH_NUMBER_ALONG),"grid":grid,"grid_normals":grid_normals,"columns":columns,"length":length,"horse_to_mesh":horse_to_mesh,"per":per}
	add_cloth_hems(cloth)
	shared.cloth=cloth
	return shared.cloth

# The cloth's thickness: a narrow band turned in from every edge of the sheet,
# so a hem seen edge-on reads as padded cotton rather than a paper-thin shell.
static func add_cloth_hems(cloth: Dictionary) -> void:
	var grid: Array=cloth.grid
	var columns: int=cloth.columns
	var rows: int=grid.size()
	var per: int=cloth.per
	var horse_to_mesh: Transform3D=cloth.horse_to_mesh
	var grid_normals: Array[Vector3]=cloth.grid_normals
	# Each edge as [row, column, inward row, inward column] steps in order.
	var left: Array=[]
	var right: Array=[]
	var front: Array=[]
	var back: Array=[]
	for r in range(rows):
		left.append([r,0,r,1])
		right.append([r,columns-1,r,columns-2])
	for c in range(columns):
		front.append([0,c,1,c])
		back.append([rows-1,c,rows-2,c])
	var vertices: PackedVector3Array=cloth.vertices
	var normals: PackedVector3Array=cloth.normals
	var uv: PackedVector2Array=cloth.uv
	var edge: PackedVector2Array=cloth.edge
	var colors: PackedColorArray=cloth.colors
	var bones: PackedInt32Array=cloth.bones
	var weights: PackedFloat32Array=cloth.weights
	var indices: PackedInt32Array=cloth.indices
	for run: Array in [left,right,front,back]:
		var start:=vertices.size()
		for step: Array in run:
			var i: int=step[0]*columns+step[1]
			var p: Vector3=grid[step[0]][step[1]]
			var inward: Vector3=(grid[step[2]][step[3]] as Vector3)-p
			var n: Vector3=grid_normals[i]
			var out:=(-inward).normalized()
			for depth: float in [0.0,CLOTH_THICK]:
				vertices.append(horse_to_mesh*(p-n*depth))
				normals.append((horse_to_mesh.basis*out).normalized())
				uv.append(uv[i])
				edge.append(Vector2.ZERO)
				colors.append(colors[i])
				bones.append_array(bones.slice(i*per,i*per+per))
				weights.append_array(weights.slice(i*per,i*per+per))
		for k in range(run.size()-1):
			var a:=start+k*2
			indices.append_array([a,a+1,a+2,a+1,a+3,a+2])
	cloth.vertices=vertices
	cloth.normals=normals
	cloth.uv=uv
	cloth.edge=edge
	cloth.colors=colors
	cloth.bones=bones
	cloth.weights=weights
	cloth.indices=indices

# Height of the racing saddle over the cloth at (across, along) in metres: a
# padded seat rising to a pommel at the front and a cantle behind, its flaps a
# single layer of leather down each side. The outline itself is the shader's.
static func saddle_height(a: float, l: float) -> float:
	var seat:=1.0-pow(a/.17,2.0)-pow((l-SADDLE_AT)/.24,2.0)
	var h:=.008
	if seat>0.0: h+=.04*sqrt(seat)
	h+=.03*exp(-pow((l-(SADDLE_AT-.2))/.05,2.0)-pow(a/.1,2.0))
	h+=.022*exp(-pow((l-(SADDLE_AT+.21))/.05,2.0)-pow(a/.12,2.0))
	return h

# The saddle and over-girth, fitted once per model like the cloth.
func tack_shape() -> Dictionary:
	if shared.has("tack"): return shared.tack
	var cloth:=cloth_shape()
	var body:=body_points()
	var grid: Array=cloth.grid
	var columns: int=cloth.columns
	var per: int=cloth.per
	var horse_to_mesh: Transform3D=cloth.horse_to_mesh
	var grid_normals: Array[Vector3]=cloth.grid_normals
	var uv: PackedVector2Array=cloth.uv
	# The saddle: the cloth's grid where the saddle may lie, lifted off it.
	var rows:=PackedInt32Array()
	var cols:=PackedInt32Array()
	for r in range(grid.size()):
		var l: float=uv[r*columns+CLOTH_DROP+CLOTH_ARC].y
		if l>SADDLE_AT-.34 and l<SADDLE_AT+.34: rows.append(r)
	for c in range(columns):
		if absf(uv[c].x)<.58: cols.append(c)
	var saddle:={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"bones":PackedInt32Array(),"weights":PackedFloat32Array(),"indices":PackedInt32Array()}
	var lifted: Dictionary={}
	for r in rows:
		for c in cols:
			var i:=r*columns+c
			var p: Vector3=(grid[r][c] as Vector3)+grid_normals[i]*(saddle_height(uv[i].x,uv[i].y)+.004)
			lifted[i]=p
			saddle.vertices.append(horse_to_mesh*p)
			saddle.normals.append(cloth.normals[i])
			saddle.uv.append(uv[i])
			saddle.bones.append_array((cloth.bones as PackedInt32Array).slice(i*per,i*per+per))
			saddle.weights.append_array((cloth.weights as PackedFloat32Array).slice(i*per,i*per+per))
	for r in range(rows.size()-1):
		for c in range(cols.size()-1):
			var a:=r*cols.size()+c
			saddle.indices.append_array([a,a+1,a+cols.size(),a+1,a+cols.size()+1,a+cols.size()])
	# The over-girth: a band round the barrel at GIRTH_AT, clear of the coat,
	# the cloth and the saddle wherever it passes over them.
	var z0: float=(grid[0][0] as Vector3).z
	var z1: float=(grid[grid.size()-1][0] as Vector3).z
	var girth:={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"bones":PackedInt32Array(),"weights":PackedFloat32Array(),"indices":PackedInt32Array()}
	var spine_l: float=uv[(grid.size()-1)*columns+CLOTH_DROP+CLOTH_ARC].y
	for side: float in [-.5,.5]:
		var z:=lerpf(z0,z1,(GIRTH_AT+side*GIRTH_WIDTH)/spine_l)
		var ring:=girth_ring(z,grid,lifted,columns,z0,z1)
		var run:=0.0
		for k in range(GIRTH_BINS+1):
			var p: Vector3=ring[k%GIRTH_BINS]
			if k>0: run+=p.distance_to(ring[k-1])
			var out: Vector3=Vector3(p.x,p.y-ring_middle.y,0).normalized()
			girth.vertices.append(horse_to_mesh*p)
			girth.normals.append((horse_to_mesh.basis*out).normalized())
			girth.uv.append(Vector2(run,side+.5))
			var nearest:=nearest_point(p,.12)
			girth.bones.append_array((body.bones as PackedInt32Array).slice(nearest*per,nearest*per+per))
			girth.weights.append_array((body.weights as PackedFloat32Array).slice(nearest*per,nearest*per+per))
	for k in range(GIRTH_BINS):
		var a:=k
		var b:=k+GIRTH_BINS+1
		girth.indices.append_array([a,b,a+1,a+1,b,b+1])
	shared.tack={"saddle":saddle,"girth":girth}
	return shared.tack

const GIRTH_BINS := 72
# The barrel's middle at the last girth section, for the band's normals.
var ring_middle := Vector2.ZERO

# A closed loop round the body at z, sampled every 5 degrees about the
# barrel's middle: the farthest of the coat, the cloth and the saddle in each
# direction, smoothed, plus a little clearance. The legs below the belly are
# left out.
func girth_ring(z: float, grid: Array, lifted: Dictionary, columns: int, z0: float, z1: float) -> Array[Vector3]:
	var slab:=section(z)
	var top:=-INF
	for p in slab:
		if absf(p.x)<.1: top=maxf(top,p.y)
	var outline: Array[Vector2]=[]
	for p in slab:
		if p.y>top-.9: outline.append(p)
	var belly:=INF
	for p in outline:
		if absf(p.x)<.15: belly=minf(belly,p.y)
	# Cloth and saddle at this z, between their two nearest rows.
	var t:=(z-z0)/(z1-z0)*(grid.size()-1)
	var r0:=clampi(floori(t),0,grid.size()-2)
	var f:=t-r0
	for c in range(columns):
		for source: int in [0,1]:
			var a: Vector3=grid[r0][c]
			var b: Vector3=grid[r0+1][c]
			if source==1:
				if not lifted.has(r0*columns+c) or not lifted.has((r0+1)*columns+c): continue
				a=lifted[r0*columns+c]
				b=lifted[(r0+1)*columns+c]
			var q:=a.lerp(b,f)
			outline.append(Vector2(q.x,q.y))
	var middle:=Vector2(0,(top+belly)*.5)
	ring_middle=middle
	var reach:=PackedFloat32Array()
	reach.resize(GIRTH_BINS)
	reach.fill(-1.0)
	for p in outline:
		var d:=p-middle
		var k:=posmod(roundi(atan2(d.y,d.x)/TAU*GIRTH_BINS),GIRTH_BINS)
		reach[k]=maxf(reach[k],d.length())
	# Empty directions take a neighbour's reach, then the loop is eased outward.
	for pass_index in range(GIRTH_BINS):
		var done:=true
		for k in range(GIRTH_BINS):
			if reach[k]>=0.0: continue
			done=false
			if reach[(k+1)%GIRTH_BINS]>=0.0: reach[k]=reach[(k+1)%GIRTH_BINS]
			elif reach[(k-1+GIRTH_BINS)%GIRTH_BINS]>=0.0: reach[k]=reach[(k-1+GIRTH_BINS)%GIRTH_BINS]
		if done: break
	for smooth in range(2):
		var eased:=reach.duplicate()
		for k in range(GIRTH_BINS): eased[k]=maxf(reach[k],(reach[(k-1+GIRTH_BINS)%GIRTH_BINS]+reach[k]*2.0+reach[(k+1)%GIRTH_BINS])*.25)
		reach=eased
	var ring: Array[Vector3]=[]
	for k in range(GIRTH_BINS):
		var angle:=TAU*k/GIRTH_BINS
		ring.append(Vector3(middle.x+cos(angle)*(reach[k]+GIRTH_CLEAR),middle.y+sin(angle)*(reach[k]+GIRTH_CLEAR),z))
	return ring

# The body's outline where the plane at `z` cuts it, as (x, y) points.
func section(z: float) -> Array[Vector2]:
	var body:=body_points()
	var points: PackedVector3Array=body.points
	var triangles: PackedInt32Array=body.triangles
	var outline: Array[Vector2]=[]
	for t in range(0,triangles.size(),3):
		for e in range(3):
			var a:=points[triangles[t+e]]
			var b:=points[triangles[t+(e+1)%3]]
			if (a.z-z)*(b.z-z)>=0.0: continue
			var c:=a.lerp(b,(z-a.z)/(b.z-a.z))
			outline.append(Vector2(c.x,c.y))
	return outline

# Distance from the widest point's height to a section's outline, `angle` up
# from level: flat over the back, rounding down the sides (exponent 2.6).
static func superellipse(angle: float, shape: Dictionary) -> float:
	var n:=2.6
	var w:=maxf(float(shape.width),.05)
	var h:=maxf(float(shape.top)-float(shape.y),.05)
	return 1.0/pow(pow(absf(sin(angle))/w,n)+pow(absf(cos(angle))/h,n),1.0/n)

func nearest_point(at: Vector3, within: float, among:=PackedInt32Array()) -> int:
	var points: PackedVector3Array=body_points().points
	var best:=-1
	var distance:=INF
	for i in (among if among.size() else range(points.size())):
		if absf(points[i].z-at.z)>within: continue
		var d:=points[i].distance_squared_to(at)
		if d<distance:
			distance=d
			best=i
	# A sparse low-poly body can leave the window empty; then look everywhere.
	return best if best>=0 or within==INF else nearest_point(at,INF,among)

func add_race_cloth(index: int, color: Color) -> void:
	var shape:=cloth_shape()
	var mat:=ShaderMaterial.new()
	mat.shader=CLOTH
	mat.set_shader_parameter("cloth",color)
	mat.set_shader_parameter("ink",Color("fff7e7") if index in [0,3,7,8,9,11] else Color("202822"))
	mat.set_shader_parameter("number",index+1)
	mat.set_shader_parameter("number_at",shape.number_at)
	mat.set_shader_parameter("digits",DIGITS)
	mat.set_shader_parameter("saddle_at",SADDLE_AT)
	mat.set_shader_parameter("phase",index*1.7)
	mat.set_shader_parameter("along_axis",((shape.horse_to_mesh as Transform3D).basis*Vector3.BACK).normalized())
	cloth_material=mat
	add_skinned(shape,mat)
	var tack:=tack_shape()
	if not shared.has("saddle_material"):
		for part: Array in [["saddle_material",1],["girth_material",2]]:
			var tack_mat:=ShaderMaterial.new()
			tack_mat.shader=CLOTH
			tack_mat.set_shader_parameter("part",part[1])
			tack_mat.set_shader_parameter("saddle_at",SADDLE_AT)
			shared[part[0]]=tack_mat
	add_skinned(tack.saddle,shared.saddle_material)
	add_skinned(tack.girth,shared.girth_material)

# Gives a fitted sheet the body's skin, so it rides every stride with it.
func add_skinned(shape: Dictionary, mat: Material) -> void:
	var body:=body_points()
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=shape.vertices
	arrays[Mesh.ARRAY_NORMAL]=shape.normals
	arrays[Mesh.ARRAY_TEX_UV]=shape.uv
	if shape.has("edge"): arrays[Mesh.ARRAY_TEX_UV2]=shape.edge
	if shape.has("colors"): arrays[Mesh.ARRAY_COLOR]=shape.colors
	arrays[Mesh.ARRAY_BONES]=shape.bones
	arrays[Mesh.ARRAY_WEIGHTS]=shape.weights
	arrays[Mesh.ARRAY_INDEX]=shape.indices
	var sheet_mesh:=ArrayMesh.new()
	sheet_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if body.per==8 else 0)
	sheet_mesh.surface_set_material(0,mat)
	var drawn:=body_mesh()
	var sheet:=MeshInstance3D.new()
	sheet.mesh=sheet_mesh
	sheet.skin=drawn.skin
	sheet.transform=drawn.transform
	sheet.layers=3
	# The body's stand-in already casts the horse's shadow.
	sheet.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(sheet)
	sheet.skeleton=sheet.get_path_to(skeleton)

# The champion's garland: a rope of red roses and leaves round the base of the neck, fitted
# to the neck's cross-section there and carried by the neck's base bone.
var garland_center := Vector3.ZERO
var garland_axes := Basis.IDENTITY
var garland_radii := Vector2.ONE

func add_garland() -> void:
	var base:=skeleton.find_bone("Neck")
	if base<0: base=skeleton.find_bone("Neck1")
	var next:=-1
	for child in skeleton.get_bone_children(base):
		var name:=skeleton.get_bone_name(child)
		if name.begins_with("Neck") or name.begins_with("Head"): next=child
	var from:=horse_from_skeleton*skeleton.get_bone_global_rest(base).origin
	var to:=horse_from_skeleton*skeleton.get_bone_global_rest(next).origin
	var at:=from.lerp(to,.15)
	var along:=(to-from).normalized()
	var side:=Vector3.RIGHT
	var up:=along.cross(side).normalized()
	var low:=Vector2(INF,INF)
	var high:=-low
	for p: Vector3 in body_points().points:
		var d:=p-at
		if absf(d.dot(along))>.05: continue
		var q:=Vector2(d.dot(side),d.dot(up))
		low=low.min(q)
		high=high.max(q)
	var middle:=(low+high)*.5
	garland_center=at+side*middle.x+up*middle.y
	garland_axes=Basis(side,up,along)
	garland_radii=(high-low)*.5+Vector2(.07,.07)
	var attachment := BoneAttachment3D.new()
	attachment.bone_name=skeleton.get_bone_name(base)
	skeleton.add_child(attachment)
	var ring := MeshInstance3D.new()
	ring.mesh=garland_mesh()
	ring.layers=3
	ring.transform=skeleton.get_bone_global_rest(base).affine_inverse()*horse_from_skeleton.affine_inverse()
	attachment.add_child(ring)

# In horse space, round the neck; `a` runs once round the ring.
func garland_point(a: float) -> Vector3:
	return garland_center+garland_axes.x*cos(a)*garland_radii.x+garland_axes.y*sin(a)*garland_radii.y

func garland_mesh() -> ArrayMesh:
	var st := KIT.begin()
	var random := RandomNumberGenerator.new()
	random.seed=5150
	# A rope of dark foliage the roses are bound to.
	var path: Array[Vector3]=[]
	for i in range(64): path.append(garland_point(TAU*i/64.0))
	KIT.sweep(st,path,.035,Color("2d5426"),10,true)
	var roses := 38
	for i in range(roses):
		var a := TAU*(i+random.randf_range(-.18,.18))/roses
		var center := garland_point(a)
		var tangent := (garland_point(a+.01)-garland_point(a-.01)).normalized()
		var out := (center-garland_center).normalized()
		# Each rose faces up the neck toward the head, and a little outward.
		var facing := (out*.6+garland_axes.z*.8+Vector3(random.randf_range(-.2,.2),random.randf_range(-.2,.2),random.randf_range(-.2,.2))).normalized()
		var side := tangent.cross(facing).normalized()
		var basis := Basis(side,facing,side.cross(facing).normalized())
		var red := Color("a31328") if random.randf()<.84 else Color("efe6d6")
		red=red.lightened(random.randf_range(-.05,.06))
		var at := center+out*.012+garland_axes.z*.02
		# Outer petals, the cupped middle and the tight heart, each smaller and darker.
		KIT.ellipsoid(st,at,basis,Vector3(.064,.032,.064),red,5,12)
		KIT.ellipsoid(st,at+facing*.016,basis*Basis(Vector3.UP,.7),Vector3(.044,.034,.044),red.darkened(.1),5,10)
		KIT.ellipsoid(st,at+facing*.03,basis*Basis(Vector3.UP,1.3),Vector3(.026,.03,.026),red.darkened(.28),4,8)
		# Two leaves tucked in either side.
		for s: float in [-1.0,1.0]:
			var leaf_at := center+tangent*s*.055+out*.02
			var leaf_basis := Basis(tangent*s,out,tangent.cross(out).normalized()*s)*Basis(Vector3.RIGHT,.5)
			KIT.ellipsoid(st,leaf_at,leaf_basis.orthonormalized(),Vector3(.05,.008,.026),Color("2f5a2a").lightened(random.randf_range(-.08,.08)),4,8)
	var mat := KIT.painted(.62,.3)
	mat.rim_enabled=true
	mat.rim=.3
	mat.rim_tint=.6
	mat.backlight_enabled=true
	mat.backlight=Color(.35,.05,.05)
	st.set_material(mat)
	return st.commit()

func animate(time: float, motion: float, running: bool, _celebration: bool, delta := .016) -> void:
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
	var moved:=0.0
	if last_position.is_finite(): moved=Vector2(position.x-last_position.x,position.z-last_position.z).length()
	last_position=position
	# A jump of metres is a new phase placing the horse, not a stride.
	if moved>2.0: moved=0.0
	var step:=delta*cadence*(1.0+sin(time*.83+gait_phase*TAU)*.025)
	var cycle:=player.get_animation(current_clip).length
	# Turning on the spot, or held at the off, a horse still steps; a frozen
	# frame (delta 0) holds every leg.
	# Slow motion slows the ground and delta alike, so this is the true pace.
	var pace:=minf(moved/delta,20.0) if delta>0.0 else 0.0
	if current_clip=="Walk":
		step=maxf(moved/walk_stride*cycle,delta*.55)
	elif current_clip=="Gallop":
		step=maxf(delta*GALLOP_TEMPO*pow(pace/GALLOP_PACE,.25)*cadence*cycle,delta*.3)
		if finish_in>0.0 and pace>.5 and shared.has("stride") and (shared.stride as Dictionary).has("stretch"):
			# Motion seconds to the line, and the clip time the stride will have
			# reached by then at this rhythm; the rhythm is bent toward the stretch.
			var lead:=finish_in/pace
			var ahead:=step/delta*lead
			if lead<FINISH_STEER and ahead>.05:
				var landing:=fposmod(player.current_animation_position+ahead,cycle)
				var miss:=fposmod(float(shared.stride.stretch)-landing+cycle*.5,cycle)-cycle*.5
				step*=1.0+clampf(miss/ahead,-STEER_MOST,STEER_MOST)
	player.advance(step)
	if stride_fit!=null:
		stride_fit.fitting=current_clip=="Gallop"
		# A frozen frame keeps the last fit rather than springing back to the clip's stride.
		if delta>0.0:
			stride_fit.pace=pace
			stride_fit.rate=step/delta
	# Bank by the sideways pull of the turn (speed times turning rate), as a
	# rider or a cyclist would; standing turns barely tilt.
	if delta>0.0:
		var turning:=angle_difference(last_heading,rotation.y)/delta if is_finite(last_heading) else 0.0
		last_heading=rotation.y
		if moved==0.0: turning=0.0
		var wanted:=clampf(atan(pace*turning/9.8),-LEAN_MOST,LEAN_MOST)
		lean=lerpf(lean,wanted,1.0-exp(-delta*3.0))
		model.rotation.z=-lean
		if stride_fit!=null: stride_fit.look=lean*LOOK_INTO_TURN
	if cloth_material!=null:
		var stride:=motion_blend*(1.0 if current_clip=="Gallop" else .35)
		if absf(stride-cloth_stride)>.02:
			cloth_stride=stride
			cloth_material.set_shader_parameter("stride",stride)
