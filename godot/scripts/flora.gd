extends RefCounted

# Trees, bushes and grass tufts grown by scripts/bake_trees.py, with their
# shared materials. A loaded mesh has its surfaces dressed by material name:
# Bark, Leaves (tree and bush cards from the leaf atlas) or Grass.
const FOLIAGE = preload("res://shaders/foliage.gdshader")
const IMPOSTOR = preload("res://shaders/impostor.gdshader")
const LEAVES = preload("res://assets/trees/leaves.png")
const GRASS = preload("res://assets/trees/grass.png")
const BARK = preload("res://assets/trees/bark.png")
const BARK_NORMAL = preload("res://assets/trees/bark_normal.png")
const TREES = ["tree_oak","tree_elm","tree_round","tree_young"]
const ASSETS = TREES+["bush_green","bush_flowers","tuft_short","tuft_tall"]
# Wind per kind of plant: [lean in metres at the reference height, that
# height, leaf flutter in metres]. See the sway uniforms in foliage.gdshader.
const WIND = {"tree":[.16,10.0,.035],"bush":[.06,1.5,.02],"tuft":[.13,.7,0.0]}

static var materials: Dictionary = {}
static var meshes: Dictionary = {}
# Off for players who ask for reduced motion.
static var wind := true

static func kind(asset: String) -> String:
	return "tree" if asset.begins_with("tree_") else "bush" if asset.begins_with("bush_") else "tuft"

static func blow(mat: ShaderMaterial, plant: String) -> void:
	var settings: Array=WIND[plant]
	mat.set_shader_parameter("sway",float(settings[0]) if wind else 0.0)
	mat.set_shader_parameter("sway_height",float(settings[1]))
	mat.set_shader_parameter("flutter",float(settings[2]) if wind else 0.0)

static func leaf_material(texture: Texture2D, plant: String) -> ShaderMaterial:
	var key := "leaves:%s:%s" % [texture.resource_path,plant]
	if materials.has(key): return materials[key]
	var mat := ShaderMaterial.new()
	mat.shader=FOLIAGE
	mat.set_shader_parameter("leaf_texture",texture)
	mat.set_shader_parameter("tint",Color.WHITE)
	mat.set_shader_parameter("cutout",true)
	mat.set_shader_parameter("soft_normals",0.0)
	mat.set_shader_parameter("crown_normals",true)
	mat.set_shader_parameter("backlight",.22)
	mat.set_shader_parameter("wind_strength",0.0)
	blow(mat,plant)
	materials[key]=mat
	return mat

# Bark shares the foliage shader (no extra program for the web build to
# compile) and the trees' wind, so trunk and crown bend together.
static func bark_material() -> ShaderMaterial:
	if materials.has("bark"): return materials.bark
	var mat := ShaderMaterial.new()
	mat.shader=FOLIAGE
	mat.set_shader_parameter("style",3)
	mat.set_shader_parameter("leaf_texture",BARK)
	mat.set_shader_parameter("bark_normal",BARK_NORMAL)
	mat.set_shader_parameter("wind_strength",0.0)
	blow(mat,"tree")
	materials.bark=mat
	return mat

# The grown mesh for a tree, bush or tuft, dressed with the shared materials.
static func mesh(asset: String) -> ArrayMesh:
	if meshes.has(asset): return meshes[asset]
	var scene := load("res://assets/trees/%s.gltf" % asset) as PackedScene
	var root := scene.instantiate() as Node3D
	var source: MeshInstance3D=root.find_children("*","MeshInstance3D",true,false)[0]
	var result: ArrayMesh=source.mesh.duplicate()
	for surface in range(result.get_surface_count()):
		var name := result.surface_get_material(surface).resource_name if result.surface_get_material(surface) else ""
		if name=="Bark": result.surface_set_material(surface,bark_material())
		elif name=="Grass": result.surface_set_material(surface,leaf_material(GRASS,kind(asset)))
		else: result.surface_set_material(surface,leaf_material(LEAVES,kind(asset)))
	root.free()
	meshes[asset]=result
	return result

# A far tree drawn as one camera-facing card from its baked picture and normals.
static func impostor_material(asset: String) -> ShaderMaterial:
	var key := "impostor:"+asset
	if materials.has(key): return materials[key]
	var mat := ShaderMaterial.new()
	mat.shader=IMPOSTOR
	mat.set_shader_parameter("albedo_texture",load("res://assets/trees/%s_impostor.png" % asset))
	mat.set_shader_parameter("normal_texture",load("res://assets/trees/%s_impostor_normal.png" % asset))
	mat.set_shader_parameter("sway",float(WIND.tree[0]) if wind else 0.0)
	mat.set_shader_parameter("sway_height",float(WIND.tree[1]))
	materials[key]=mat
	return mat

# The card for an impostor: width and height of the baked picture, base at y=0.
static func impostor_mesh(asset: String) -> ArrayMesh:
	var key := "impostor:"+asset
	if meshes.has(key): return meshes[key]
	var info: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/trees/impostors.json"))[asset]
	var quad := QuadMesh.new()
	quad.size=Vector2(float(info.width),float(info.height))
	quad.center_offset=Vector3(float(info.offset),float(info.height)*.5+float(info.bottom),0)
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,quad.get_mesh_arrays())
	result.surface_set_material(0,impostor_material(asset))
	meshes[key]=result
	return result
