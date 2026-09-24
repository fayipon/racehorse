extends Node3D

# Racecourse furniture built from the shared course path: turf, an inner sand
# training track, white running rails, the winning post and distance poles.
const KIT = preload("res://scripts/mesh_kit.gd")
const GROUND = preload("res://shaders/ground.gdshader")
const FOLIAGE = preload("res://shaders/foliage.gdshader")
const RAIL_WHITE = Color("f6f4ec")
const POST_WHITE = Color("e9e5d9")
const RACING_RED = Color("c63f36")
const SAND_INNER = 13.9
const SAND_OUTER = 18.7

var course: RefCounted
var inner := 0.0
var outer := 0.0

func build(course_ref: RefCounted) -> void:
	course=course_ref
	inner=float(course.config.innerRadius)
	outer=inner+float(course.config.trackWidth)
	build_surfaces()
	build_rails()
	build_finish()
	build_distance_poles()
	build_hedge()

func build_surfaces() -> void:
	var turf := MeshInstance3D.new()
	turf.mesh=KIT.course_band(course,inner,outer,.012)
	var mat := ShaderMaterial.new()
	mat.shader=GROUND
	mat.set_shader_parameter("pattern",2)
	mat.set_shader_parameter("lap_length",4.0*float(course.config.halfStraight)+TAU*(inner+outer)*.5)
	mat.set_shader_parameter("color_dark",Color("2f672f"))
	mat.set_shader_parameter("color_light",Color("6c9c49"))
	turf.material_override=mat
	add_child(turf)
	var sand := MeshInstance3D.new()
	sand.mesh=KIT.course_band(course,SAND_INNER,SAND_OUTER,.01)
	var dirt := ShaderMaterial.new()
	dirt.shader=GROUND
	dirt.set_shader_parameter("pattern",3)
	dirt.set_shader_parameter("color_dark",Color("b18a61"))
	dirt.set_shader_parameter("color_light",Color("d9bd93"))
	dirt.set_shader_parameter("width",SAND_OUTER-SAND_INNER)
	sand.material_override=dirt
	add_child(sand)

func build_rails() -> void:
	var st := KIT.begin()
	# Main running rail: one continuous tube, carried inward on goose-neck posts.
	KIT.course_tube(st,course,inner-.3,1.02,.055,RAIL_WHITE)
	# Outer rail: top and mid rails on straight posts.
	KIT.course_tube(st,course,outer+.4,1.12,.05,RAIL_WHITE)
	KIT.course_tube(st,course,outer+.4,.6,.04,RAIL_WHITE)
	# The sand track keeps its own lighter rail on the infield side.
	KIT.course_tube(st,course,SAND_INNER-.25,.86,.04,RAIL_WHITE,300)
	KIT.finish(st,KIT.painted(.45,.45),self)
	var goose := KIT.begin()
	KIT.cylinder(goose,Vector3(0,0,-.34),Vector3(0,.8,-.34),.04,POST_WHITE,6)
	KIT.cylinder(goose,Vector3(0,.8,-.34),Vector3(0,1.02,0),.04,POST_WHITE,6)
	var straight := KIT.begin()
	KIT.cylinder(straight,Vector3.ZERO,Vector3(0,1.18,0),.045,POST_WHITE,6)
	var goose_mesh := goose.commit()
	var straight_mesh := straight.commit()
	for mesh: Mesh in [goose_mesh,straight_mesh]: mesh.surface_set_material(0,KIT.painted(.5,.4))
	KIT.multimesh(goose_mesh,posts(inner-.3,3.0),self,false)
	KIT.multimesh(straight_mesh,posts(outer+.4,3.0),self,false)
	KIT.multimesh(straight_mesh,posts(SAND_INNER-.25,3.6,.75),self,false)

# Posts face along the path; local -Z points toward the infield.
func posts(radius: float, spacing: float, height_scale := 1.0) -> Array:
	var transforms: Array=[]
	var circumference: float=4.0*float(course.config.halfStraight)+TAU*radius
	var count:=roundi(circumference/spacing)
	for i in range(count):
		var sample: Dictionary=course.sample(float(i)/count,radius)
		var outward: Vector3=sample.outward
		var basis:=Basis(Vector3.UP.cross(outward),Vector3.UP,outward).scaled(Vector3(1,height_scale,1))
		transforms.append(Transform3D(basis,sample.position))
	return transforms

func build_finish() -> void:
	var st := KIT.begin()
	# A painted white finish line runs across the turf at the winning post.
	KIT.quad(st,Vector3(-.09,.02,outer),Vector3(.09,.02,outer),Vector3(.09,.02,inner),Vector3(-.09,.02,inner),Color("f8f6ee"))
	# Winning post on the inside: a white pole carrying the red-ringed disc.
	var post := Vector3(0,0,inner-.85)
	KIT.cylinder(st,post,post+Vector3(0,3.3,0),.08,RAIL_WHITE,10)
	KIT.cylinder(st,post+Vector3(0,3.3,0),post+Vector3(0,3.34,0),.1,Color("d8b25a"),10)
	var disc := post+Vector3(0,3.75,.02)
	KIT.disc(st,disc,.62,RACING_RED,Vector3.BACK,24)
	KIT.disc(st,disc+Vector3(0,0,.012),.4,RAIL_WHITE,Vector3.BACK,24)
	KIT.disc(st,disc+Vector3(0,0,.024),.06,RACING_RED,Vector3.BACK,12)
	KIT.disc(st,disc,.62,RAIL_WHITE,Vector3.FORWARD,24)
	# Nothing stands on the outside of the line: the finish cameras travel there.
	KIT.finish(st,KIT.painted(.6,.3),self)

func build_distance_poles() -> void:
	var st := KIT.begin()
	for k in range(1,6):
		var sample: Dictionary=course.sample(k/6.0,inner-.85)
		var base: Vector3=sample.position
		for band in range(7):
			KIT.cylinder(st,base+Vector3(0,band*.32,0),base+Vector3(0,(band+1)*.32,0),.06,RACING_RED if band%2==0 else RAIL_WHITE,8)
		var outward: Vector3=sample.outward
		var basis:=Basis(Vector3.UP.cross(outward),Vector3.UP,outward)
		KIT.box(st,base+Vector3(0,2.55,0),Vector3(.9,.55,.06),RAIL_WHITE,basis)
		var label := Label3D.new()
		label.text=str(1200-k*200)
		label.font_size=64
		label.pixel_size=.0062
		label.modulate=RACING_RED
		label.outline_size=0
		label.position=base+Vector3(0,2.55,0)+outward*.04
		label.rotation.y=atan2(outward.x,outward.z)
		add_child(label)
	KIT.finish(st,KIT.painted(.6,.3),self)

func build_hedge() -> void:
	# A clipped hedge closes the far straight behind the outer rail.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := outer+2.4
	var segments := 72
	for i in range(segments):
		var a: Dictionary=course.sample(lerpf(.35,.65,float(i)/segments),radius)
		var b: Dictionary=course.sample(lerpf(.35,.65,float(i+1)/segments),radius)
		var pa: Vector3=a.position
		var pb: Vector3=b.position
		var tangent:=(pb-pa).normalized()
		var basis:=Basis(tangent,Vector3.UP,tangent.cross(Vector3.UP))
		KIT.box(st,(pa+pb)*.5+Vector3(0,.62,0),Vector3(pa.distance_to(pb)+.06,1.24,1.1),Color.WHITE,basis)
	var hedge := MeshInstance3D.new()
	hedge.mesh=st.commit()
	var mat := ShaderMaterial.new()
	mat.shader=FOLIAGE
	mat.set_shader_parameter("style",1)
	mat.set_shader_parameter("leaf_dark",Color("27471f"))
	mat.set_shader_parameter("leaf_light",Color("5d8a3a"))
	hedge.material_override=mat
	add_child(hedge)
