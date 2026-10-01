extends Node3D

# The infield behind the runners, kept like a park: a diamond-mown lawn, a long
# still lake in a dressed-stone coping on the centre line, a clipped box hedge
# all the way round inside the sand track, and carpet-bedded borders either
# side of the lake. Specimen trees stand at both bends (landscape.gd).
const KIT = preload("res://scripts/mesh_kit.gd")
const WATER = preload("res://shaders/water.gdshader")
const FOLIAGE = preload("res://shaders/foliage.gdshader")
const LEAVES = preload("res://assets/trees/leaves.png")
const STONE = Color("e0d8c7")
const LAKE_CENTER := Vector3(-2,0,0)
const LAKE_HALF := Vector2(20.0,6.2)
const HEDGE_RADIUS := 12.9
const SAMPLES := 96
# Carpet beds: centre, half-length and half-depth, leaf and bloom colours.
const BEDS = [
	[Vector3(-11,0,9.3),Vector2(7.5,1.45),Color("2a4521"),Color("b8273b")],
	[Vector3(8.5,0,9.3),Vector2(7.5,1.45),Color("2c4a24"),Color("f1ece0")],
	[Vector3(-11,0,-9.3),Vector2(7.5,1.45),Color("2c4a24"),Color("f1ece0")],
	[Vector3(8.5,0,-9.3),Vector2(7.5,1.45),Color("2a4521"),Color("d9a530")],
]

func build(course: RefCounted, reduced: bool) -> void:
	var lawn := MeshInstance3D.new()
	lawn.mesh=KIT.course_band(course,.02,13.9,.008,256)
	lawn.material_override=KIT.ground(0,Color("4c6e24"),Color("7c9a3a"))
	add_child(lawn)
	build_lake(reduced)
	var hedge := KIT.begin()
	var round: Array[Vector3]=[]
	for i in range(360): round.append(course.sample(float(i)/360,HEDGE_RADIUS).position)
	KIT.loft(hedge,round,hedge_profile(.7,.78),Color.WHITE)
	for bed: Array in BEDS:
		build_bed(bed)
		KIT.loft(hedge,outline(bed[0],bed[1],2.4,72,1.0,.22),hedge_profile(.3,.32),Color.WHITE)
	KIT.finish(hedge,box_leaves(),self)

# The clipped box: rounded shoulders on a straight-sided hedge.
func hedge_profile(width: float, height: float) -> Array[Vector2]:
	var w := width*.5
	var r := minf(w*.6,.14)
	return [Vector2(-w,0),Vector2(-w,height-r),Vector2(-w+r*.3,height-r*.3),Vector2(-w+r,height),Vector2(w-r,height),Vector2(w-r*.3,height-r*.3),Vector2(w,height-r),Vector2(w,0)]

func box_leaves() -> ShaderMaterial:
	var leaves := ShaderMaterial.new()
	leaves.shader=FOLIAGE
	leaves.set_shader_parameter("style",1)
	leaves.set_shader_parameter("leafy",true)
	leaves.set_shader_parameter("leaf_texture",LEAVES)
	leaves.set_shader_parameter("leaf_dark",Color("27471f"))
	leaves.set_shader_parameter("leaf_light",Color("5f8c3c"))
	return leaves

# A smooth closed outline round `center`: a superellipse of half-sizes `half`
# (exponent `power`; 2 is an ellipse, more is squarer), its banks bowed by a
# slow wave of `wave` metres.
func outline(center: Vector3, half: Vector2, power: float, samples: int, scale := 1.0, wave := 0.0) -> Array[Vector3]:
	var points: Array[Vector3]=[]
	for i in range(samples):
		var a := TAU*i/samples
		var c := cos(a)
		var s := sin(a)
		var x := signf(c)*pow(absf(c),2.0/power)*half.x
		var z := signf(s)*pow(absf(s),2.0/power)*half.y
		var bow := wave*sin(a*2.0+.7)*absf(s)
		points.append(center+Vector3(x,0,z+bow)*scale)
	return points

func build_lake(reduced: bool) -> void:
	var shore := outline(LAKE_CENTER,LAKE_HALF,2.6,SAMPLES,1.0,.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rings in from the coping; the outer ones are shallows.
	var rings := [0.0,.45,.72,.86,.94,1.0]
	for r in range(rings.size()-1):
		for i in range(SAMPLES):
			var j := (i+1)%SAMPLES
			var corners: Array=[]
			for pair: Array in [[i,rings[r]],[j,rings[r]],[j,rings[r+1]],[i,rings[r+1]]]:
				var p: Vector3=LAKE_CENTER.lerp(shore[int(pair[0])],float(pair[1]))
				corners.append([Vector3(p.x,.03,p.z),smoothstep(.55,1.0,float(pair[1]))])
			for index: int in [0,2,1,0,3,2]:
				st.set_color(Color(corners[index][1],0,0))
				st.set_normal(Vector3.UP)
				st.add_vertex(corners[index][0])
	var water := MeshInstance3D.new()
	water.mesh=st.commit()
	var mat := ShaderMaterial.new()
	mat.shader=WATER
	mat.set_shader_parameter("ripple",0.0 if reduced else 1.0)
	water.material_override=mat
	water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# A low dressed-stone coping with a rounded nosing over the water.
	var coping := KIT.begin()
	var profile: Array[Vector2]=[Vector2(-.04,0),Vector2(-.02,.12),Vector2(.04,.17),Vector2(.34,.17),Vector2(.4,.12),Vector2(.42,0)]
	KIT.loft(coping,shore,profile,KIT.made_of(STONE,KIT.CONCRETE))
	KIT.finish(coping,KIT.structure(false),self)

# A carpet bed: a low dome of bedding plants inside its own little box hedge.
func build_bed(bed: Array) -> void:
	var center: Vector3=bed[0]
	var half: Vector2=bed[1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge := outline(center,half,2.4,72,1.0,.22)
	var steps := [0.0,.35,.6,.8,.93,1.0]
	for r in range(steps.size()-1):
		for i in range(edge.size()):
			var j := (i+1)%edge.size()
			var corners: Array=[]
			for pair: Array in [[i,steps[r]],[j,steps[r]],[j,steps[r+1]],[i,steps[r+1]]]:
				var t: float=pair[1]
				var p: Vector3=center.lerp(edge[int(pair[0])],t)
				corners.append(Vector3(p.x,.03+.24*(1.0-t*t),p.z))
			for index: int in [0,2,1,0,3,2]:
				st.set_normal(Vector3.UP)
				st.add_vertex(corners[index])
	var mesh := MeshInstance3D.new()
	mesh.mesh=st.commit()
	mesh.material_override=KIT.ground(4,bed[2],bed[3])
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
