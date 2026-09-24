extends Node3D

# The infield garden behind the runners: a diamond-mown lawn, a fountain pond
# on the centre line and a planted sun emblem at the final-bend end.
const KIT = preload("res://scripts/mesh_kit.gd")
const LAWN = preload("res://shaders/lawn.gdshader")
const WATER = preload("res://shaders/water.gdshader")
const BED = preload("res://shaders/flower_bed.gdshader")
const STONE = Color("e4dccb")
const POOL = Color("8fc3c9")
const POND := Vector2(12.5,4.3)
const SUN_BED := Vector3(-31,0,0)

func build(course: RefCounted, reduced: bool) -> void:
	var lawn := MeshInstance3D.new()
	lawn.mesh=KIT.course_band(course,.02,13.9,.008,256)
	var lawn_mat := ShaderMaterial.new()
	lawn_mat.shader=LAWN
	lawn_mat.set_shader_parameter("grass_dark",Color("4b843b"))
	lawn_mat.set_shader_parameter("grass_light",Color("80ad56"))
	lawn.material_override=lawn_mat
	add_child(lawn)
	build_pond()
	build_fountain(reduced)
	var bed := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(12.4,12.4)
	bed.mesh=plane
	bed.position=SUN_BED+Vector3(0,.03,0)
	var bed_mat := ShaderMaterial.new()
	bed_mat.shader=BED
	bed.material_override=bed_mat
	add_child(bed)

func build_pond() -> void:
	var water := KIT.begin()
	var rim := KIT.begin()
	var segments := 64
	for i in range(segments):
		var a := Vector3(cos(TAU*i/segments)*POND.x,.035,sin(TAU*i/segments)*POND.y)
		var b := Vector3(cos(TAU*(i+1)/segments)*POND.x,.035,sin(TAU*(i+1)/segments)*POND.y)
		KIT.triangle(water,b,a,Vector3(0,.035,0),Color.WHITE)
		var tangent := (b-a).normalized()
		KIT.box(rim,(a+b)*.5+Vector3(0,.09,0),Vector3(a.distance_to(b)+.08,.2,.5),STONE,Basis(tangent,Vector3.UP,tangent.cross(Vector3.UP)))
	var surface := MeshInstance3D.new()
	surface.mesh=water.commit()
	var mat := ShaderMaterial.new()
	mat.shader=WATER
	surface.material_override=mat
	surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	KIT.finish(rim,KIT.painted(.9,.15),self)

func build_fountain(reduced: bool) -> void:
	var st := KIT.begin()
	KIT.cylinder(st,Vector3.ZERO,Vector3(0,.55,0),1.8,STONE,24)
	KIT.cylinder(st,Vector3(0,.55,0),Vector3(0,.62,0),1.9,STONE,24)
	KIT.disc(st,Vector3(0,.6,0),1.72,POOL,Vector3.UP,24)
	KIT.cylinder(st,Vector3(0,.55,0),Vector3(0,1.55,0),.3,STONE,12,.22)
	KIT.cylinder(st,Vector3(0,1.55,0),Vector3(0,1.8,0),.25,STONE,16,.95)
	KIT.disc(st,Vector3(0,1.8,0),.95,POOL,Vector3.UP,16)
	KIT.finish(st,KIT.painted(.85,.2),self)
	var spray := spray_mesh()
	var density := .5 if reduced else 1.0
	jet(spray,Vector3(0,1.8,0),Vector3.UP,9.0,roundi(110*density),3.0,.55)
	for i in range(6):
		var angle := TAU*i/6.0
		var outward := Vector3(cos(angle),0,sin(angle))
		jet(spray,outward*1.55+Vector3(0,.62,0),(outward+Vector3(0,1.5,0)).normalized(),4.6,roundi(30*density),4.0,.3)

func spray_mesh() -> QuadMesh:
	var gradient := Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,.45,1.0])
	gradient.colors=PackedColorArray([Color(1,1,1,.9),Color(1,1,1,.35),Color(1,1,1,0)])
	var soft := GradientTexture2D.new()
	soft.gradient=gradient
	soft.width=32
	soft.height=32
	soft.fill=GradientTexture2D.FILL_RADIAL
	soft.fill_from=Vector2(.5,.5)
	soft.fill_to=Vector2(.5,1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture=soft
	mat.vertex_color_use_as_albedo=true
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size=Vector2(.5,.5)
	quad.material=mat
	return quad

func jet(mesh: Mesh, origin: Vector3, direction: Vector3, speed: float, amount: int, spread: float, size: float) -> void:
	var fade := Gradient.new()
	fade.offsets=PackedFloat32Array([0.0,.7,1.0])
	fade.colors=PackedColorArray([Color(.97,.99,1,.75),Color(.93,.97,1,.5),Color(.9,.96,1,0)])
	var particles := CPUParticles3D.new()
	particles.mesh=mesh
	particles.amount=amount
	particles.lifetime=2.0*speed*direction.y/9.8+.15
	particles.preprocess=particles.lifetime
	particles.position=origin
	particles.direction=direction
	particles.spread=spread
	particles.gravity=Vector3(0,-9.8,0)
	particles.initial_velocity_min=speed*.93
	particles.initial_velocity_max=speed
	particles.scale_amount_min=size*.6
	particles.scale_amount_max=size
	particles.color_ramp=fade
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
