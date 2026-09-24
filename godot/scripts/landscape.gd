extends Node3D

# Free Quaternius nature models, instanced in spatial batches for WebGL.
const TREE_NAMES = ["tree_oak","tree_broadleaf","tree_leaning","tree_round","tree_young"]
const GRASS_NAMES = ["grass","grass_wispy","grass_fine"]
const FOLIAGE = preload("res://shaders/foliage.gdshader")
var random := RandomNumberGenerator.new()
var batches: Dictionary = {}
var materials: Dictionary = {}
var plant_count := 0
var batch_count := 0
var reduce_motion := false
static var flat_normal: ImageTexture

func build(course: RefCounted, reduced: bool, sparse := false) -> void:
	reduce_motion = reduced
	# The power-saving tier thins the apron tufts and the farthest tree rings.
	var tufts := 220 if sparse else 580
	random.seed = 931705
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(650,650)
	ground.mesh = plane
	ground.position.y = -.045
	var meadow := ShaderMaterial.new()
	meadow.shader = preload("res://shaders/ground.gdshader")
	meadow.set_shader_parameter("pattern",1)
	meadow.set_shader_parameter("color_dark",Color("527440"))
	meadow.set_shader_parameter("color_light",Color("799451"))
	ground.material_override = meadow
	add_child(ground)
	# Informal planted borders follow the infield edge inside the sand track.
	for i in range(136):
		var progress := (i+random.randf_range(-.3,.3))/136.0
		var radius := 13.9-random.randf_range(1.2,2.4)
		var p: Vector3 = course.sample(progress,radius).position
		if i%11 < 9:
			place("bush_flowers" if i%7==0 else "bush",p,random.randf_range(.58,.88))
		for j in range(random.randi_range(7,13)):
			var g: Vector3 = course.sample(progress+random.randf_range(-.006,.006),radius+random.randf_range(-1.5,1.1)).position
			place(GRASS_NAMES[j%3],g,random.randf_range(.18,.42))
		if i%4==0:
			place("flowers_a" if i%8==0 else "flowers_b",p+Vector3(random.randf_range(-.9,.9),0,.7),random.randf_range(.20,.34))
	# The topiary garden at the final-bend end: blooms outside its box hedge and
	# on the mulch around the plinth.
	for i in range(40):
		var angle := TAU*i/40.0+random.randf_range(-.04,.04)
		place("flowers_a" if i%2==0 else "flowers_b",Vector3(-31+cos(angle)*5.8,0,sin(angle)*5.8),random.randf_range(.24,.34))
	for i in range(26):
		var angle := TAU*i/26.0+random.randf_range(-.08,.08)
		var reach := random.randf_range(2.1,4.1)
		place("flowers_b" if i%3==0 else "flowers_a",Vector3(-31+cos(angle)*reach,0,sin(angle)*reach),random.randf_range(.22,.32))
	# Small groves frame the pond and the far end; the centre line stays open.
	for center in [Vector3(33,0,-5),Vector3(35,0,6),Vector3(-19,0,-9),Vector3(21,0,8)]:
		for i in range(3):
			var p: Vector3 = center+Vector3(random.randf_range(-3,3),0,random.randf_range(-2,2))
			place(TREE_NAMES[random.randi_range(0,4)],p,random.randf_range(.56,.82))
			understory(p,12)
		place("rock_a",center+Vector3(2,0,-2),random.randf_range(.28,.48))
	# Mixed tree clusters beyond the camera lanes and grandstands.
	for side in [-1,1]:
		for i in range(13):
			var z := -66.0+i*11.0+random.randf_range(-3,3)
			var x: float = side*random.randf_range(76,88)
			var p := Vector3(x,0,z)
			place(TREE_NAMES[i%5],p,random.randf_range(.85,1.5))
			understory(p,8)
			if i%3==0:
				place(TREE_NAMES[(i+2)%5],p+Vector3(side*4.0,0,4.5),random.randf_range(.65,1.0))
		for i in range(15):
			var p := Vector3(-73+i*10.5+random.randf_range(-3,3),0,side*random.randf_range(79,91))
			place(TREE_NAMES[(i+1)%5],p,random.randf_range(.95,1.55))
			if i%2==0: understory(p,8)
		# A second irregular row closes gaps in the distant skyline.
		for i in range(0 if sparse else 19):
			var p := Vector3(-105+i*11.5+random.randf_range(-3,3),0,side*random.randf_range(98,111))
			place(TREE_NAMES[(i+3)%5],p,random.randf_range(1.1,1.7))
	# Small flower/stone groupings in grass, never on the racing surface.
	for center in [Vector3(-7,0,-9),Vector3(10,0,-8),Vector3(-39,0,3),Vector3(39,0,-4)]:
		place("rock_b",center,random.randf_range(.26,.40))
		for i in range(14):
			var p: Vector3 = center+Vector3(random.randf_range(-2.8,2.8),0,random.randf_range(-1.8,1.8))
			place("flowers_a" if i%3==0 else "flowers_b",p,random.randf_range(.16,.32))
			place("grass_wispy",p+Vector3(.4,0,.2),random.randf_range(.22,.40))
	# Sparse tufts break up the flat apron outside the rails, below camera height.
	for i in range(tufts):
		var progress := random.randf()
		var p: Vector3 = course.sample(progress,random.randf_range(35.5,42.5)).position
		if p.z>39.0 and absf(p.x)<58.0: continue # The stand's paved promenade.
		place(GRASS_NAMES[i%3],p,random.randf_range(.20,.36))
	distant_landscape(sparse)
	flush_batches()

func understory(center: Vector3, amount: int) -> void:
	for i in range(amount):
		var p := center+Vector3(random.randf_range(-3,3),0,random.randf_range(-2.5,2.5))
		place("bush" if i%5==0 else GRASS_NAMES[i%3],p,random.randf_range(.28,.55))
	if random.randf()<.35: place("rock_a",center+Vector3(1.6,0,.8),random.randf_range(.25,.45))

func place(asset: String, position: Vector3, size: float) -> void:
	# Quadrant cells around the course keep draw calls low on phones while the
	# half of the course behind the camera is still culled.
	var key := "%s:%d:%d" % [asset,floori(position.x/160),floori(position.z/160)]
	if not batches.has(key): batches[key]={"asset":asset,"transforms":[],"colors":[]}
	var rotation := Basis(Vector3.UP,random.randf()*TAU)
	var proportions := Vector3(random.randf_range(.92,1.12),random.randf_range(.92,1.08),random.randf_range(.92,1.1))*size
	if asset.begins_with("tree_"): proportions *= Vector3(1.30,.92,1.30)
	var transform := Transform3D(rotation.scaled(proportions),position+Vector3(0,-.025,0))
	batches[key].transforms.append(transform)
	var tone := random.randf_range(.88,1.03)
	batches[key].colors.append(Color(tone,random.randf_range(.94,1.03),tone*.94))
	plant_count += 1

func adapt_material(source: StandardMaterial3D, asset: String) -> Material:
	var name := source.resource_name
	var foliage := name.contains("Leaves") or name.contains("Grass") or name=="Flowers"
	var key := name+(":tree" if asset.begins_with("tree_") else ":ground")
	if materials.has(key): return materials[key]
	var result: Material
	if foliage:
		var leaf := ShaderMaterial.new()
		leaf.shader = FOLIAGE
		leaf.set_shader_parameter("leaf_texture",source.albedo_texture)
		leaf.set_shader_parameter("tint",Color("d4e3c8") if name.contains("Leaves") else Color("e1e5ce"))
		leaf.set_shader_parameter("cutout",source.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED)
		leaf.set_shader_parameter("wind_strength",0.0 if reduce_motion else .04 if asset.begins_with("tree_") else .065)
		leaf.set_shader_parameter("soft_normals",.55 if name.contains("Leaves") else .18)
		leaf.set_shader_parameter("green_palette",name=="Leaves_TwistedTree" or name=="Grass")
		leaf.set_shader_parameter("leaf_dark",Color("3c5e28"))
		leaf.set_shader_parameter("leaf_light",Color("83a54e"))
		result=leaf
	else:
		var solid := source.duplicate() as StandardMaterial3D
		solid.roughness=1.0
		solid.metallic_specular=0.08
		solid.vertex_color_use_as_albedo=true
		# A flat normal map on the plain solids keeps every textured solid on one
		# shader, which the web build then compiles only once.
		if not solid.normal_enabled:
			solid.normal_enabled=true
			solid.normal_texture=flat_normal_texture()
		result=solid
	materials[key]=result
	return result

static func flat_normal_texture() -> ImageTexture:
	if flat_normal==null:
		var image := Image.create(1,1,false,Image.FORMAT_RGB8)
		image.fill(Color(.5,.5,1.0))
		flat_normal=ImageTexture.create_from_image(image)
	return flat_normal

# Gives a single placed nature model the planted ones' materials, and shaders.
func dress(model: Node3D, asset: String) -> void:
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			mesh.set_surface_override_material(surface,adapt_material(mesh.get_active_material(surface),asset))

func mesh_parts(node: Node3D, parent_transform: Transform3D, parts: Array) -> void:
	var transform := parent_transform*node.transform
	if node is MeshInstance3D: parts.append({"node":node,"transform":transform})
	for child in node.get_children():
		if child is Node3D: mesh_parts(child,transform,parts)

func flush_batches() -> void:
	var templates: Dictionary={}
	for batch in batches.values():
		var asset: String=batch.asset
		if not templates.has(asset):
			var scene := load("res://assets/nature/%s.gltf" % asset) as PackedScene
			var template := scene.instantiate() as Node3D
			var parts: Array=[]
			mesh_parts(template,Transform3D.IDENTITY,parts)
			var meshes: Array=[]
			for part in parts:
				var mesh: ArrayMesh=part.node.mesh.duplicate()
				for surface in range(mesh.get_surface_count()):
					mesh.surface_set_material(surface,adapt_material(part.node.get_active_material(surface),asset))
				meshes.append({"mesh":mesh,"transform":part.transform})
			templates[asset]=meshes
			template.free()
		for part in templates[asset]:
			var instances := MultiMesh.new()
			instances.transform_format=MultiMesh.TRANSFORM_3D
			instances.use_colors=true
			instances.mesh=part.mesh
			instances.instance_count=batch.transforms.size()
			for i in range(instances.instance_count):
				instances.set_instance_transform(i,batch.transforms[i]*part.transform)
				instances.set_instance_color(i,batch.colors[i])
			var group := MultiMeshInstance3D.new()
			group.multimesh=instances
			group.extra_cull_margin=.2
			group.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if asset.begins_with("tree_") or asset.begins_with("rock_") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(group)
			batch_count += 1
	batches.clear()

func distant_landscape(sparse: bool) -> void:
	# Reuse the actual Quaternius rock meshes as broad, overlapping distant ridges.
	# Muted materials and fog separate them from the nearer planted tree belt.
	for layer in range(2):
		for i in range(17):
			var angle := i*TAU/17.0+layer*.14+random.randf_range(-.06,.06)
			var distance := 215.0+layer*72+random.randf_range(-12,12)
			var mountain := (load("res://assets/nature/rock_%s.gltf" % ("a" if i%2==0 else "b")) as PackedScene).instantiate() as Node3D
			mountain.position=Vector3(cos(angle)*distance,-5.0,sin(angle)*distance)
			mountain.rotation.y=random.randf()*TAU
			mountain.scale=Vector3(random.randf_range(30,44),random.randf_range(9,13)+layer*5,random.randf_range(25,36))
			var parts: Array=[]
			mesh_parts(mountain,Transform3D.IDENTITY,parts)
			var mat := StandardMaterial3D.new()
			mat.albedo_color=(Color("7b968b") if layer==0 else Color("91a8a5")).darkened(random.randf_range(0,.025))
			# At this distance haze suppresses hard rock-face lighting.
			mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.roughness=1.0
			mat.metallic_specular=0.0
			for part in parts:
				part.node.material_override=mat
				part.node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mountain)
	# Irregular clusters between the stands and hills close the low skyline.
	for i in range(76):
		var angle := i*TAU/76.0+random.randf_range(-.025,.025)
		var distance := random.randf_range(122,147)
		if sparse and i%2==1: continue
		place(TREE_NAMES[i%5],Vector3(cos(angle)*distance,0,sin(angle)*distance),random.randf_range(1.35,2.0))
