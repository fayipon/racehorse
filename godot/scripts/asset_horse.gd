extends Node3D

# The race horse. The imported rig supplies all poses and skin deformation; this
# adapter keeps race.gd independent of the model, so timing and results stay put.
# With the licensed Viverna stallion prepared locally (scripts/prepare_viverna_horse.py,
# never committed) the stable wears textured coats; a checkout without it runs
# the CC0 Quaternius horse instead, as does `-- --cc0-horse` on the command line.
const VIVERNA := "res://assets/viverna/stallion.glb"
const QUATERNIUS := "res://assets/quaternius/horse.glb"
const KIT = preload("res://scripts/mesh_kit.gd")
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
	player.play("Idle")
	player.advance(0)
	player.seek(index*.19,true)
	add_race_cloth(index,Color(style.number))
	find_muzzle()

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
# colours it.
const CLOTH_SPAN := Vector2(.46,.75) # of the body's length, from the muzzle back
const CLOTH_OFF := .035
const CLOTH_HANG := .24
const CLOTH_ROWS := 20
const CLOTH_ARC := 16 # steps over each side of the back, from the spine to the widest point
const CLOTH_DROP := 5
# The number's centre: up from the hem, and along the flank from the front.
const CLOTH_NUMBER_UP := .25
const CLOTH_NUMBER_ALONG := .58
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
			line.append(Vector3(-side_x,float(shape.y)-CLOTH_HANG*(1.0-float(k)/CLOTH_DROP),shape.z))
		for step in range(-CLOTH_ARC,CLOTH_ARC+1):
			var angle:=float(step)/CLOTH_ARC*PI*.5
			var reach:=superellipse(absf(angle),shape)*float(shape.fit)+CLOTH_OFF
			line.append(Vector3(sin(angle)*reach,float(shape.y)+cos(angle)*reach,shape.z))
		for k in range(CLOTH_DROP-1,-1,-1):
			line.append(Vector3(side_x,float(shape.y)-CLOTH_HANG*(1.0-float(k)/CLOTH_DROP),shape.z))
		grid.append(line)
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var bones:=PackedInt32Array()
	var weights:=PackedFloat32Array()
	var per: int=body.per
	var horse_to_mesh: Transform3D=(body.mesh_to_horse as Transform3D).affine_inverse()
	var columns: int=grid[0].size()
	for r in range(grid.size()):
		for c in range(columns):
			var p: Vector3=grid[r][c]
			var across: Vector3=grid[r][mini(c+1,columns-1)]-grid[r][maxi(c-1,0)]
			var along: Vector3=grid[mini(r+1,grid.size()-1)][c]-grid[maxi(r-1,0)][c]
			var normal:=along.cross(across).normalized()
			if normal.dot(Vector3(p.x,p.y-float(shapes[r].y),0))<0: normal=-normal
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
	shared.cloth={"vertices":vertices,"normals":normals,"bones":bones,"weights":weights,"indices":indices,"uv":uv,"edge":edge,"number_at":Vector2(CLOTH_NUMBER_UP,length*CLOTH_NUMBER_ALONG)}
	return shared.cloth

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
	var body:=body_points()
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=shape.vertices
	arrays[Mesh.ARRAY_NORMAL]=shape.normals
	arrays[Mesh.ARRAY_TEX_UV]=shape.uv
	arrays[Mesh.ARRAY_TEX_UV2]=shape.edge
	arrays[Mesh.ARRAY_BONES]=shape.bones
	arrays[Mesh.ARRAY_WEIGHTS]=shape.weights
	arrays[Mesh.ARRAY_INDEX]=shape.indices
	var sheet_mesh:=ArrayMesh.new()
	sheet_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if body.per==8 else 0)
	var mat:=ShaderMaterial.new()
	mat.shader=CLOTH
	mat.set_shader_parameter("cloth",color)
	mat.set_shader_parameter("ink",Color("fff7e7") if index in [0,3,7,8,9,11] else Color("202822"))
	mat.set_shader_parameter("number",index+1)
	mat.set_shader_parameter("number_at",shape.number_at)
	mat.set_shader_parameter("digits",DIGITS)
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

# The champion's garland: a ring of blooms round the base of the neck, fitted
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
				var side:=tangent.cross(garland_axes.z).normalized()
				var up:=side.cross(tangent)
				var normal:=side*cos(b)+up*sin(b)
				# Each pair of segments swells into one round bloom.
				var bloom:=absf(sin(a*major*.5))
				normals.append(normal)
				points.append(center+normal*.11*(.72+.5*bloom))
			var color: Color=colors[(i/2)*(minor/2)+j/2]
			for index: int in [0,2,1,0,3,2]: KIT.vertex(st,points[index],normals[index],color)
	var mat := KIT.painted(.85,.2)
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
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
	if current_clip=="Walk":
		step=maxf(moved/walk_stride*cycle,delta*.55)
	elif current_clip=="Gallop":
		# Slow motion slows the ground and delta alike, so this is the true pace.
		var pace:=minf(moved/delta,20.0) if delta>0.0 else 0.0
		step=maxf(delta*GALLOP_TEMPO*pow(pace/GALLOP_PACE,.25)*cadence*cycle,delta*.3)
	player.advance(step)
