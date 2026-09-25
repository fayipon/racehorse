extends SceneTree

const HORSE = preload("res://scripts/asset_horse.gd")
# The whole stable, as in src/game.ts; the biggest cup runs all twelve.
const RUNNERS := 12
var views: Array[SubViewport] = []

func _initialize() -> void:
	call_deferred("render_portraits")

func render_portraits() -> void:
	for index in range(RUNNERS):
		var view:=SubViewport.new()
		view.size=Vector2i(384,320)
		view.transparent_bg=true
		view.own_world_3d=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		view.msaa_3d=Viewport.MSAA_4X
		root.add_child(view)
		views.append(view)
		var horse=HORSE.new()
		view.add_child(horse)
		horse.build(index,Color.WHITE)
		horse.player.play("Gallop")
		horse.player.seek(.15,true)
		var env:=WorldEnvironment.new()
		env.environment=Environment.new()
		env.environment.background_mode=Environment.BG_COLOR
		env.environment.background_color=Color(0,0,0,0)
		env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color=Color("dddfe3")
		env.environment.ambient_light_energy=.45
		view.add_child(env)
		var sun:=DirectionalLight3D.new()
		sun.rotation_degrees=Vector3(-35,-30,0)
		sun.light_energy=.85
		view.add_child(sun)
		var fill:=DirectionalLight3D.new()
		fill.rotation_degrees=Vector3(-20,130,0)
		fill.light_energy=.35
		view.add_child(fill)
		var camera:=Camera3D.new()
		view.add_child(camera)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=3.85
		camera.position=Vector3(-5.8,3.0,-6.5)
		camera.look_at(Vector3(0,1.45,0))
		camera.current=true
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var atlas:=Image.create(1536,320*ceili(RUNNERS/4.0),false,Image.FORMAT_RGBA8)
	for i in range(RUNNERS):
		var picture:=views[i].get_texture().get_image()
		picture.save_png(ProjectSettings.globalize_path("res://../public/assets/horse-%d.png" % (i+1)))
		atlas.blit_rect(picture,Rect2i(0,0,384,320),Vector2i((i%4)*384,(i/4)*320))
	var output:=ProjectSettings.globalize_path("res://../public/assets/horse-coats.png")
	var error:=atlas.save_png(output)
	print("PORTRAITS ",output," error=",error)
	quit(error)
