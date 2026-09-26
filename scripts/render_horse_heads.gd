extends SceneTree

# Head-and-neck close-ups for the results cut-ins, rendered from the race model
# so coats and cloths match. The head faces left, toward the band's text.
const HORSE = preload("res://scripts/asset_horse.gd")
const SIZE := 512
# The whole stable, as in src/game.ts; the biggest cup runs all twelve.
const RUNNERS := 12
var views: Array[SubViewport] = []

func _initialize() -> void:
	call_deferred("render_heads")

func render_heads() -> void:
	for index in range(RUNNERS):
		var view:=SubViewport.new()
		view.size=Vector2i(SIZE,SIZE)
		view.transparent_bg=true
		view.own_world_3d=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		view.msaa_3d=Viewport.MSAA_4X
		root.add_child(view)
		views.append(view)
		var horse=HORSE.new()
		view.add_child(horse)
		horse.build(index,Color.WHITE)
		horse.player.play("Idle")
		horse.player.seek(0.0,true)
		var env:=WorldEnvironment.new()
		env.environment=Environment.new()
		env.environment.background_mode=Environment.BG_COLOR
		env.environment.background_color=Color(0,0,0,0)
		env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color=Color("dde2ea")
		env.environment.ambient_light_energy=.38
		view.add_child(env)
		var key:=DirectionalLight3D.new()
		key.rotation_degrees=Vector3(-30,-40,0)
		key.light_color=Color("fff1d6")
		key.light_energy=1.0
		view.add_child(key)
		# A cool rim from behind picks the head out against the band.
		var rim:=DirectionalLight3D.new()
		rim.rotation_degrees=Vector3(-15,150,0)
		rim.light_color=Color("d8ecff")
		rim.light_energy=.9
		view.add_child(rim)
		var camera:=Camera3D.new()
		view.add_child(camera)
		camera.fov=26.0
		camera.current=true
	for frame in range(4): await process_frame
	for index in range(RUNNERS):
		var horse=views[index].get_child(0)
		var poll: Vector3=horse.horse_from_skeleton*horse.skeleton.get_bone_global_pose(horse.head_bone).origin
		var neck: Vector3=horse.horse_from_skeleton*horse.skeleton.get_bone_global_pose(horse.skeleton.find_bone("Neck1")).origin
		var muzzle: Vector3=horse.muzzle_position()
		var reach:=maxf(poll.distance_to(muzzle),poll.distance_to(neck))
		# Framed from the ear tips to below the chin, so the whole face shows
		# wherever the picture is set.
		var focus:=poll.lerp(muzzle,.3).lerp(neck,.24)+Vector3.UP*reach*.07
		var distance:=reach*.86/tan(deg_to_rad(13.0))
		var camera: Camera3D=views[index].get_child(views[index].get_child_count()-1)
		camera.look_at_from_position(focus+Vector3(-.6,.02,-1.0).normalized()*distance,focus)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var error:=OK
	for i in range(RUNNERS):
		var picture:=views[i].get_texture().get_image()
		var output:=ProjectSettings.globalize_path("res://../public/assets/horse-head-%d.webp" % (i+1))
		error=maxi(error,picture.save_webp(output,true,.9))
	print("HEADS error=",error)
	quit(error)
