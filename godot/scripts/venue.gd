extends Node3D

# Original CC0 Kenney buildings and Quaternius posed people; see assets/venue.
const CROWD_SHADER = preload("res://shaders/spectators.gdshader")
const SEAT_Y = [.2834,.3415,.3996,.4576,.5157,.5738,.6318]
const POSES = ["Male_Sitting","Female_Sitting","Male_Sitting_Cheering","Female_Sitting_Cheering","Male_Standing_Waving","Woman_Standing_Waving"]
const HAIR_CENTERS = [Vector3(0,2.82,-.73),Vector3(0,2.72,-.71),Vector3(-.16,2.76,-.88),Vector3(.02,2.72,-.82),Vector3(.09,3.55,-.10),Vector3(.09,3.46,-.07)]
var random := RandomNumberGenerator.new()
var meshes: Dictionary = {}
var people: Dictionary = {}
var crowd_material: ShaderMaterial
var spectator_count := 0

func build(reduced: bool) -> void:
	random.seed = 247019
	crowd_material = ShaderMaterial.new()
	crowd_material.shader = CROWD_SHADER
	crowd_material.set_shader_parameter("reduce_motion",reduced)
	for side in [-1,1]:
		var facing := 0.0 if side==1 else PI
		for section in range(5):
			var center := Vector3((section-2)*17.5,0,side*55.0)
			var stand_type := "grandStandCovered" if section==2 else "grandStandAwning" if section%2==0 else "grandStand"
			asset(stand_type,center,Vector3(16,9,14),facing,section%2)
			# Seven real bench rows; people sit at bench height, feet on the lower step.
			for row in range(7):
				for seat in range(19):
					if random.randf()<.13: continue
					var pose := random.randi_range(0,1)
					if random.randf()<.20: pose += 2
					var size := random.randf_range(.39,.46)
					var local := Vector3(-6.85+seat*.76+random.randf_range(-.07,.07),float(SEAT_Y[row])*9-1.30*size,(.145+row*.0644)*14)
					person(pose,center+Basis(Vector3.UP,facing)*local,facing+random.randf_range(-.12,.12),size,side)
			# A few standing spectators occupy the rear terrace, away from seated heads.
			for i in range(6):
				var p := Vector3(-6+i*2.4,.6318*9,.60*14)
				person(4+i%2,center+Basis(Vector3.UP,facing)*p,facing,random.randf_range(.41,.46),side)
		# Imported tents, office modules and light towers make the concourse readable.
		for x in [-52.0,52.0]:
			asset("tentLong",Vector3(x,0,side*64),Vector3(6,6,6),facing,1)
			asset("pitsOffice",Vector3(x,0,side*74),Vector3(9,11,9),facing,0)
			asset("bannerTowerGreen",Vector3(x,0,side*49),Vector3(6,6,6),facing,0)
		for x in [-43.5,-8.75,8.75,43.5]:
			asset("lightPostLarge",Vector3(x,0,side*69.5),Vector3(14,14,14),facing,0)
	flush_people()

func asset(asset_name: String, p: Vector3, size: Vector3, yaw: float, palette: int) -> void:
	var key := asset_name+str(palette)
	if not meshes.has(key):
		var model := (load("res://assets/venue/kenney/%s.obj" % asset_name) as ArrayMesh).duplicate() as ArrayMesh
		for surface in range(model.get_surface_count()):
			var original := model.surface_get_material(surface) as StandardMaterial3D
			var mat := StandardMaterial3D.new()
			mat.roughness=1.0
			mat.metallic_specular=.08
			match original.resource_name:
				"red", "green": mat.albedo_color=Color("627f78") if palette==0 else Color("b18d68")
				"grey": mat.albedo_color=Color("c2bba6")
				"_defaultMat", "white": mat.albedo_color=Color("d0c9b5")
				"road", "black": mat.albedo_color=Color("63675e")
				"glass": mat.albedo_color=Color("607d87")
				_: mat.albedo_color=original.albedo_color.darkened(.12)
			model.surface_set_material(surface,mat)
		meshes[key]=model
	var model: ArrayMesh=meshes[key]
	var bounds := model.get_aabb()
	var instance := MeshInstance3D.new()
	instance.mesh=model
	instance.basis=Basis(Vector3.UP,yaw).scaled(size)
	# Place at front-center; original Kenney pivots sit at the front-right corner.
	instance.position=p-instance.basis*Vector3(bounds.get_center().x,bounds.position.y,0)
	add_child(instance)

func person(pose: int,p: Vector3,yaw: float,size: float,side: int) -> void:
	var hair := random.randi_range(0,1)
	var key := "%d:%d:%d" % [pose,hair,side]
	if not people.has(key): people[key]={"pose":pose,"hair":hair,"transforms":[],"colors":[]}
	people[key].transforms.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(size*random.randf_range(.92,1.10),size,size)),p))
	people[key].colors.append(Color(random.randf(),random.randf_range(.15,1),random.randf(),1.0 if random.randf()<.13 else 0.0))
	spectator_count+=1

func append_mesh(st: SurfaceTool,mesh: ArrayMesh,offset: Vector3,hair: bool) -> void:
	for surface in range(mesh.get_surface_count()):
		var category := .8
		if not hair:
			match mesh.surface_get_material(surface).resource_name:
				"Skin": category=0.0
				"Shirt": category=.2
				"Pants": category=.4
				_: category=.6
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(indices.size() if not indices.is_empty() else vertices.size()):
			var idx := indices[i] if not indices.is_empty() else i
			st.set_normal(normals[idx])
			st.set_uv(Vector2(category,0))
			st.set_color(Color.WHITE)
			st.add_vertex(vertices[idx]+offset)

func person_mesh(pose: int,hair: int) -> ArrayMesh:
	var key := "person:%d:%d" % [pose,hair]
	if meshes.has(key): return meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	append_mesh(st,load("res://assets/venue/crowd/%s.obj" % POSES[pose]),Vector3.ZERO,false)
	var hair_name := "%s_Hairstyle_%d" % ["Male" if pose%2==0 else "Female",1 if hair==0 else 3]
	append_mesh(st,load("res://assets/venue/crowd/%s.obj" % hair_name),HAIR_CENTERS[pose],true)
	st.index()
	st.set_material(crowd_material)
	var mesh := st.commit()
	meshes[key]=mesh
	return mesh

func flush_people() -> void:
	for batch in people.values():
		var instances := MultiMesh.new()
		instances.transform_format=MultiMesh.TRANSFORM_3D
		instances.use_custom_data=true
		instances.mesh=person_mesh(batch.pose,batch.hair)
		instances.instance_count=batch.transforms.size()
		for i in range(instances.instance_count):
			instances.set_instance_transform(i,batch.transforms[i])
			instances.set_instance_custom_data(i,batch.colors[i])
		var group := MultiMeshInstance3D.new()
		group.multimesh=instances
		group.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.extra_cull_margin=.1
		add_child(group)
	people.clear()
