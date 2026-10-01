extends Node3D

# Racecourse furniture built from the shared course path: turf, an inner sand
# training track, white running rails, the winning post and distance poles.
const KIT = preload("res://scripts/mesh_kit.gd")
const FOLIAGE = preload("res://shaders/foliage.gdshader")
const RAIL_WHITE = Color("f6f4ec")
const POST_WHITE = Color("e9e5d9")
const RACING_RED = Color("c63f36")
const SAND_INNER = 13.9
const SAND_OUTER = 18.7

var course: RefCounted
var inner := 0.0
var outer := 0.0

# Grass shells: how many stacked layers, and how tall the mown blades stand.
# They are cut into pieces of the lap, and only pieces near the camera draw:
# farther out the blades are smaller than a pixel and the shader drops them.
const SHELLS := 12
const BLADE_HEIGHT := .095
const SHELL_PIECES := 28
const SHELL_RANGE := 26.0

func build(course_ref: RefCounted, low_power := false, still := false) -> void:
	course=course_ref
	inner=float(course.config.innerRadius)
	outer=inner+float(course.config.trackWidth)
	build_surfaces(low_power,still)
	build_rails(10 if low_power else 16)
	build_finish()
	build_distance_poles()
	build_hedge()

func build_surfaces(low_power: bool, still: bool) -> void:
	var turf := MeshInstance3D.new()
	turf.mesh=KIT.course_band(course,inner,outer,.012)
	var mat := KIT.ground(2,Color("486a24"),Color("779838"))
	mat.set_shader_parameter("width",outer-inner)
	mat.set_shader_parameter("half_straight",float(course.config.halfStraight))
	turf.material_override=mat
	# The ground casts nothing; only the horses, rails and buildings need shadows.
	turf.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(turf)
	# Phones skip the shells: the turf texture alone reads well at their size.
	if not low_power:
		var shell_mat: ShaderMaterial=mat.duplicate()
		shell_mat.set_shader_parameter("blade_height",BLADE_HEIGHT)
		shell_mat.set_shader_parameter("breeze",0.0 if still else .55)
		for piece in range(SHELL_PIECES):
			var from:=float(piece)/SHELL_PIECES
			var to:=float(piece+1)/SHELL_PIECES
			var middle: Vector3=course.sample((from+to)*.5,(inner+outer)*.5).position
			var blades := MeshInstance3D.new()
			blades.mesh=KIT.course_band(course,inner,outer,.012,384/SHELL_PIECES,SHELLS,from,to,middle)
			blades.position=middle
			blades.material_override=shell_mat
			blades.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			blades.visibility_range_end=SHELL_RANGE
			add_child(blades)
	var sand := MeshInstance3D.new()
	sand.mesh=KIT.course_band(course,SAND_INNER,SAND_OUTER,.01)
	var dirt := KIT.ground(3,Color("b38c64"),Color("d8bb93"))
	dirt.set_shader_parameter("width",SAND_OUTER-SAND_INNER)
	dirt.set_shader_parameter("half_straight",float(course.config.halfStraight))
	sand.material_override=dirt
	add_child(sand)

# Rails: [height, tube radius] at each run of posts.
const INNER_RAIL := [1.02,.055]
const OUTER_RAILS := [[1.12,.05],[.6,.04]]
const SAND_RAIL := [.86,.04]

func build_rails(sides: int) -> void:
	var st := KIT.begin()
	# Main running rail: one continuous tube, carried inward on goose-neck posts.
	KIT.course_tube(st,course,inner-.3,INNER_RAIL[0],INNER_RAIL[1],RAIL_WHITE,420,sides)
	# Outer rail: top and mid rails on straight posts.
	for rail: Array in OUTER_RAILS:
		KIT.course_tube(st,course,outer+.4,rail[0],rail[1],RAIL_WHITE,420,sides)
	# The sand track keeps its own lighter rail on the infield side.
	KIT.course_tube(st,course,SAND_INNER-.25,SAND_RAIL[0],SAND_RAIL[1],RAIL_WHITE,300,sides)
	st.index()
	KIT.finish(st,KIT.painted(.45,.45),self)
	KIT.multimesh(goose_post(sides),posts(inner-.3,3.0),self,false)
	KIT.multimesh(straight_post(OUTER_RAILS,.04,sides),posts(outer+.4,3.0),self,false)
	KIT.multimesh(straight_post([SAND_RAIL],.034,sides),posts(SAND_INNER-.25,3.6),self,false)

# The running rail's goose-neck: a round post on the infield side whose neck
# bows over and meets the rail square from behind, held in a moulded sleeve.
# Local X runs along the rail, -Z toward the infield; the rail is at the origin.
func goose_post(sides: int) -> ArrayMesh:
	var st := KIT.begin()
	var height: float=INNER_RAIL[0]
	var tube: float=INNER_RAIL[1]
	var foot := Vector3(0,-.05,-.34)
	var neck := Vector3(0,height-.32,-.34)
	var neck_path: Array[Vector3]=[foot,neck]
	var c1 := Vector3(0,height-.02,-.34)
	var c2 := Vector3(0,height,-.16)
	var end := Vector3(0,height,0)
	for k in range(1,13):
		var t := k/12.0
		var u := 1.0-t
		neck_path.append(neck*u*u*u+c1*3.0*u*u*t+c2*3.0*u*t*t+end*t*t*t)
	KIT.sweep(st,neck_path,.034,POST_WHITE,sides)
	KIT.collar(st,Vector3(0,height,0),Vector3.RIGHT,.17,tube,tube+.011,RAIL_WHITE,sides)
	# A socket where the post enters the turf.
	KIT.collar(st,Vector3(0,.03,-.34),Vector3.UP,.1,.034,.048,POST_WHITE,sides)
	return post_mesh(st)

# A straight round post under one or more rails (top first): it ends inside the
# top rail, and a sleeve holds each rail where it crosses the post.
func straight_post(rails: Array, radius: float, sides: int) -> ArrayMesh:
	var st := KIT.begin()
	var top: float=rails[0][0]
	KIT.sweep(st,[Vector3(0,-.05,0),Vector3(0,top,0)] as Array[Vector3],radius,POST_WHITE,sides)
	for rail: Array in rails:
		var tube: float=rail[1]
		KIT.collar(st,Vector3(0,rail[0],0),Vector3.RIGHT,.15,tube,tube+.01,RAIL_WHITE,sides)
	KIT.collar(st,Vector3(0,.03,0),Vector3.UP,.1,radius,radius+.014,POST_WHITE,sides)
	return post_mesh(st)

func post_mesh(st: SurfaceTool) -> ArrayMesh:
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0,KIT.painted(.5,.4))
	return mesh

# Posts face along the path; local -Z points toward the infield.
func posts(radius: float, spacing: float) -> Array:
	var transforms: Array=[]
	var circumference: float=4.0*float(course.config.halfStraight)+TAU*radius
	var count:=roundi(circumference/spacing)
	for i in range(count):
		var sample: Dictionary=course.sample(float(i)/count,radius)
		var outward: Vector3=sample.outward
		var basis:=Basis(Vector3.UP.cross(outward),Vector3.UP,outward)
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
	mat.set_shader_parameter("leafy",true)
	mat.set_shader_parameter("leaf_texture",preload("res://assets/trees/leaves.png"))
	mat.set_shader_parameter("leaf_dark",Color("27471f"))
	mat.set_shader_parameter("leaf_light",Color("5d8a3a"))
	hedge.material_override=mat
	add_child(hedge)
