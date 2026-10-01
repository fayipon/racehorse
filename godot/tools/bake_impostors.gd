extends SceneTree

# Bakes a front picture and normal picture of every grown tree for the far
# rows (assets/trees/<tree>_impostor.png, _impostor_normal.png) and records the
# card each one fills in assets/trees/impostors.json. Needs a window:
#   godot --path godot -s res://tools/bake_impostors.gd
# With -- --preview=DIR it also saves a sunlit look at every grown asset there.
const FLORA = preload("res://scripts/flora.gd")
const BAKE = preload("res://tools/impostor_bake.gdshader")
const PIXELS := 512
const ASSETS = ["tree_oak","tree_elm","tree_round","tree_young","bush_green","bush_flowers","tuft_short","tuft_tall"]

func _initialize() -> void:
	call_deferred("bake")

func view(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size=size
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func snapshot(viewport: SubViewport) -> Image:
	for i in range(3): await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func bake() -> void:
	var preview := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="): preview=arg.trim_prefix("--preview=")
	var cards: Dictionary={}
	for asset: String in FLORA.TREES:
		var mesh: ArrayMesh=FLORA.mesh(asset)
		var box := mesh.get_aabb()
		var width := box.size.x*1.04
		var height := box.size.y*1.04
		var size := Vector2i(roundi(PIXELS*width/height),PIXELS)
		cards[asset]={"width":width,"height":height,"bottom":box.position.y-box.size.y*.02,"offset":box.get_center().x}
		for pass_index in range(2):
			var viewport := view(size)
			var instance := MeshInstance3D.new()
			instance.mesh=mesh
			for surface in range(mesh.get_surface_count()):
				var mat := ShaderMaterial.new()
				mat.shader=BAKE
				var source: Material=mesh.surface_get_material(surface)
				mat.set_shader_parameter("picture",source.albedo_texture if source is StandardMaterial3D else source.get_shader_parameter("leaf_texture"))
				mat.set_shader_parameter("normals",pass_index==1)
				instance.set_surface_override_material(surface,mat)
			viewport.add_child(instance)
			var camera := Camera3D.new()
			camera.projection=Camera3D.PROJECTION_ORTHOGONAL
			camera.keep_aspect=Camera3D.KEEP_HEIGHT
			camera.size=height
			camera.near=.1
			camera.far=200.0
			camera.position=Vector3(box.get_center().x,box.position.y-box.size.y*.02+height*.5,box.end.z+40.0)
			viewport.add_child(camera)
			camera.current=true
			var image: Image=await snapshot(viewport)
			image.save_png("res://assets/trees/%s_impostor%s.png" % [asset,"_normal" if pass_index==1 else ""])
			viewport.queue_free()
	var file := FileAccess.open("res://assets/trees/impostors.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(cards,"\t")+"\n")
	file.close()
	if preview!="":
		for asset: String in ASSETS:
			await look(asset,preview)
	print("baked ",cards.keys())
	quit()

func look(asset: String, folder: String) -> void:
	var viewport := view(Vector2i(640,640))
	viewport.transparent_bg=false
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("9cc2e6")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("c6d2dc")
	env.environment.ambient_light_energy=.4
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-38,-80,0)
	sun.light_color=Color("ffe6c2")
	sun.light_energy=1.05
	sun.shadow_enabled=true
	viewport.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(60,60)
	ground.mesh=plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color=Color("6f8f3a")
	ground.material_override=grass
	viewport.add_child(ground)
	var instance := MeshInstance3D.new()
	instance.mesh=FLORA.mesh(asset)
	viewport.add_child(instance)
	var box := instance.mesh.get_aabb()
	var camera := Camera3D.new()
	camera.fov=40
	var reach := maxf(box.size.y,box.size.x)*1.6+.5
	camera.position=Vector3(reach*.35,box.size.y*.45,reach)
	viewport.add_child(camera)
	camera.look_at(Vector3(0,box.size.y*.45,0))
	camera.current=true
	var image: Image=await snapshot(viewport)
	image.save_png(folder.path_join(asset+".png"))
	viewport.queue_free()
