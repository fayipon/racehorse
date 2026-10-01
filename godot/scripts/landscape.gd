extends Node3D

# The course's planting, instanced in spatial batches for WebGL: trees, bushes
# and grass tufts grown by scripts/bake_trees.py (flora.gd), Quaternius flowers
# and stones, and the far country in layers: impostor cards for the outer tree
# rows and a continuous wood, then two ridges of forested hills in haze.
const FLORA = preload("res://scripts/flora.gd")
const TREE_NAMES = FLORA.TREES
const GRASS_NAMES = ["tuft_short","tuft_short","tuft_tall"]
const BUSHES = ["bush_green","bush_flowers"]
const FOLIAGE = preload("res://shaders/foliage.gdshader")
const HILLS = preload("res://shaders/hills.gdshader")
const KIT = preload("res://scripts/mesh_kit.gd")
var random := RandomNumberGenerator.new()
var batches: Dictionary = {}
var materials: Dictionary = {}
var plant_count := 0
var batch_count := 0
var reduce_motion := false
static var flat_normal: ImageTexture

func build(course: RefCounted, reduced: bool, sparse := false) -> void:
	reduce_motion = reduced
	FLORA.wind = not reduced
	# The power-saving tier thins the apron tufts and the farthest tree rings.
	var tufts := 220 if sparse else 580
	random.seed = 931705
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(650,650)
	ground.mesh = plane
	ground.position.y = -.045
	ground.material_override = KIT.ground(1,Color("4f6c26"),Color("7f973f"))
	add_child(ground)
	# Informal planted borders follow the infield edge inside the sand track.
	for i in range(136):
		var progress := (i+random.randf_range(-.3,.3))/136.0
		var radius := 13.9-random.randf_range(1.2,2.4)
		var p: Vector3 = course.sample(progress,radius).position
		if i%11 < 9:
			place(BUSHES[1] if i%3==0 else BUSHES[0],p,random.randf_range(.6,.9))
		for j in range(random.randi_range(7,13)):
			var g: Vector3 = course.sample(progress+random.randf_range(-.006,.006),radius+random.randf_range(-1.5,1.1)).position
			place(GRASS_NAMES[j%3],g,random.randf_range(.5,.9))
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
			place(TREE_NAMES[random.randi_range(2,3)],p,random.randf_range(.62,.86))
			understory(p,12)
		place("rock_a",center+Vector3(2,0,-2),random.randf_range(.28,.48))
	# Mixed tree clusters beyond the camera lanes and grandstands: grown trees
	# (phones draw these as impostor cards too).
	var near_tree := "imp:" if sparse else ""
	for side in [-1,1]:
		for i in range(13):
			var z := -66.0+i*11.0+random.randf_range(-3,3)
			var x: float = side*random.randf_range(76,88)
			var p := Vector3(x,0,z)
			place(near_tree+TREE_NAMES[i%4],p,random.randf_range(.85,1.18))
			understory(p,8)
			if i%3==0:
				place(near_tree+TREE_NAMES[(i+2)%4],p+Vector3(side*4.0,0,4.5),random.randf_range(.7,.95))
		for i in range(15):
			var p := Vector3(-73+i*10.5+random.randf_range(-3,3),0,side*random.randf_range(79,91))
			place(near_tree+TREE_NAMES[(i+1)%4],p,random.randf_range(.9,1.2))
			if i%2==0: understory(p,8)
		# A second irregular row closes gaps in the distant skyline.
		for i in range(19):
			var p := Vector3(-105+i*11.5+random.randf_range(-3,3),0,side*random.randf_range(98,111))
			place("imp:"+TREE_NAMES[(i+3)%4],p,random.randf_range(.95,1.3))
	# Small flower/stone groupings in grass, never on the racing surface.
	for center in [Vector3(-7,0,-9),Vector3(10,0,-8),Vector3(-39,0,3),Vector3(39,0,-4)]:
		place("rock_b",center,random.randf_range(.26,.40))
		for i in range(14):
			var p: Vector3 = center+Vector3(random.randf_range(-2.8,2.8),0,random.randf_range(-1.8,1.8))
			place("flowers_a" if i%3==0 else "flowers_b",p,random.randf_range(.16,.32))
			place("tuft_tall",p+Vector3(.4,0,.2),random.randf_range(.5,.8))
	# Sparse tufts break up the flat apron outside the rails, below camera height.
	for i in range(tufts):
		var progress := random.randf()
		var p: Vector3 = course.sample(progress,random.randf_range(35.5,42.5)).position
		if p.z>39.0 and absf(p.x)<58.0: continue # The stand's paved promenade.
		place(GRASS_NAMES[i%3],p,random.randf_range(.55,.95))
	distant_landscape(sparse)
	flush_batches()

func understory(center: Vector3, amount: int) -> void:
	for i in range(amount):
		var p := center+Vector3(random.randf_range(-3,3),0,random.randf_range(-2.5,2.5))
		if i%5==0: place(BUSHES[i%2],p,random.randf_range(.55,.85))
		else: place(GRASS_NAMES[i%3],p,random.randf_range(.6,1.0))
	if random.randf()<.35: place("rock_a",center+Vector3(1.6,0,.8),random.randf_range(.25,.45))

func place(asset: String, position: Vector3, size: float) -> void:
	# Quadrant cells around the course keep draw calls low on phones while the
	# half of the course behind the camera is still culled.
	var key := "%s:%d:%d" % [asset,floori(position.x/160),floori(position.z/160)]
	if not batches.has(key): batches[key]={"asset":asset,"transforms":[],"colors":[]}
	var rotation := Basis(Vector3.UP,random.randf()*TAU)
	var proportions := Vector3(random.randf_range(.92,1.12),random.randf_range(.92,1.08),random.randf_range(.92,1.1))*size
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
		if not templates.has(asset) and (asset.begins_with("imp:") or asset.begins_with("far:")):
			templates[asset]=[{"mesh":FLORA.impostor_mesh(asset.substr(4)),"transform":Transform3D.IDENTITY}]
		elif not templates.has(asset) and asset in FLORA.ASSETS:
			templates[asset]=[{"mesh":FLORA.mesh(asset),"transform":Transform3D.IDENTITY}]
		elif not templates.has(asset):
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
			# Cards turn to the view and crowns bend in the wind, beyond their rest bounds.
			group.extra_cull_margin=10.0 if asset.contains(":") else .8 if asset.begins_with("tree_") else .2
			var shadows: bool=asset.begins_with("tree_") or asset.begins_with("rock_") or asset.begins_with("imp:")
			group.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(group)
			batch_count += 1
	batches.clear()

func distant_landscape(sparse: bool) -> void:
	# Irregular clusters between the stands and the wood close the low skyline.
	for i in range(76):
		var angle := i*TAU/76.0+random.randf_range(-.025,.025)
		var distance := random.randf_range(122,147)
		if sparse and i%2==1: continue
		place("imp:"+TREE_NAMES[i%4],Vector3(cos(angle)*distance,0,sin(angle)*distance),random.randf_range(1.0,1.35))
	# A continuous wood round the whole course: staggered rows of tall cards,
	# their tops making an uneven tree line against the hills.
	for row in range(1 if sparse else 3):
		var radius := 168.0+row*16.0
		var count := roundi(TAU*radius/(7.5+row*1.5))
		for i in range(count):
			var angle := (i+row*.37+random.randf_range(-.3,.3))*TAU/count
			var distance := radius+random.randf_range(-5,5)
			place("far:"+TREE_NAMES[random.randi_range(0,2)],Vector3(cos(angle)*distance,0,sin(angle)*distance),random.randf_range(1.0,1.5))
			# Scrub along the front row hides the bare trunks behind it.
			if row==0:
				var front := angle+random.randf_range(-.4,.4)/count*TAU
				place("far:tree_round",Vector3(cos(front),0,sin(front))*(distance-random.randf_range(5,9)),random.randf_range(.32,.5))
	# Two ridges of forested hills: a nearer green one and far blue mountains.
	add_child(hills(222.0,282.0,8.0,30.0,11,Color("27451f"),Color("4a6f30"),.24,false))
	add_child(hills(320.0,455.0,26.0,82.0,23,Color("294a2c"),Color("486e40"),.46,true))

# A ring of rolling hills between two radii. Heights come from noise: `base`
# all round, rising to `peak` on the ridges. The hills shader paints a forest
# canopy with open meadows and fades the ring into blue haze (`haze`), more on
# the far `mountain` ring.
func hills(inner: float, outer: float, base: float, peak: float, seed: int, dark: Color, light: Color, haze: float, mountain: bool) -> MeshInstance3D:
	var noise := FastNoiseLite.new()
	noise.seed=seed
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type=FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves=4
	noise.frequency=.0026 if mountain else .0055
	# Treetops roughen every skyline by a metre or two.
	var canopy := FastNoiseLite.new()
	canopy.seed=seed+1
	canopy.frequency=.09
	var segments := 360
	var rows := 14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments+1):
		var angle := TAU*i/segments
		for j in range(rows+1):
			var t := float(j)/rows
			var radius := lerpf(inner,outer,t)
			var p := Vector3(cos(angle)*radius,0,sin(angle)*radius)
			var n := noise.get_noise_2d(p.x,p.z)*.5+.5
			# Rises out of the plain at the inner edge; the far edge stays high
			# so no gap opens to the sky behind the ridge.
			var rise := smoothstep(0.0,.45,t)
			# Rounded summits: the noise is eased so ridges swell rather than spike.
			var swell := smoothstep(.2,.85,n)
			p.y=-2.0+rise*(base+swell*swell*(3.0-2.0*swell)*(peak-base)+canopy.get_noise_2d(p.x,p.z)*1.6)
			st.set_uv(Vector2(i,j))
			st.add_vertex(p)
	for i in range(segments):
		for j in range(rows):
			var a := i*(rows+1)+j
			var b := (i+1)*(rows+1)+j
			for index: int in [a,b,a+1,a+1,b,b+1]: st.add_index(index)
	st.generate_normals()
	var ring := MeshInstance3D.new()
	ring.mesh=st.commit()
	var mat := ShaderMaterial.new()
	mat.shader=HILLS
	mat.set_shader_parameter("canopy_dark",dark)
	mat.set_shader_parameter("canopy_light",light)
	mat.set_shader_parameter("haze",haze)
	ring.material_override=mat
	ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring
