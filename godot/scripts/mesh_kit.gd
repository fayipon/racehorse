extends RefCounted

# Procedural building blocks for the racecourse. Shapes write linear vertex
# colours into a shared SurfaceTool, so a whole structure draws with one
# material. Godot treats clockwise triangles as front faces.
const GROUND = preload("res://shaders/ground.gdshader")
const TURF_ALBEDO = preload("res://assets/turf/turf_albedo.png")
const TURF_NORMAL = preload("res://assets/turf/turf_normal.png")
const SAND_ALBEDO = preload("res://assets/turf/sand_albedo.png")
const SAND_NORMAL = preload("res://assets/turf/sand_normal.png")

static func painted(roughness := .8, specular := .2) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo=true
	mat.roughness=roughness
	mat.metallic_specular=specular
	return mat

# Every lawn, the racing turf and the sand share the ground shader; pattern 0 is
# the infield's diamonds, 1 the meadow, 2 the racing turf and 3 the sand track.
static func ground(pattern: int, dark: Color, light: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader=GROUND
	mat.set_shader_parameter("pattern",pattern)
	mat.set_shader_parameter("color_dark",dark)
	mat.set_shader_parameter("color_light",light)
	mat.set_shader_parameter("turf_albedo",TURF_ALBEDO)
	mat.set_shader_parameter("turf_normal",TURF_NORMAL)
	mat.set_shader_parameter("sand_albedo",SAND_ALBEDO)
	mat.set_shader_parameter("sand_normal",SAND_NORMAL)
	return mat

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func finish(st: SurfaceTool, mat: Material, parent: Node3D, shadows := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh=st.commit()
	node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func vertex(st: SurfaceTool, p: Vector3, n: Vector3, color: Color) -> void:
	st.set_color(color.srgb_to_linear())
	st.set_normal(n)
	st.add_vertex(p)

# a, b, c and d run counter-clockwise when seen from the lit side.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var n := (b-a).cross(c-a).normalized()
	for p: Vector3 in [a,c,b,a,d,c]: vertex(st,p,n,color)

static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b-a).cross(c-a).normalized()
	for p: Vector3 in [a,c,b]: vertex(st,p,n,color)

const BOX_FACES = [[1,3,7,5],[4,6,2,0],[2,6,7,3],[4,0,1,5],[5,7,6,4],[0,2,3,1]]

static func box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var corners: Array[Vector3]=[]
	for i in range(8):
		corners.append(center+basis*Vector3((1 if i&1 else -1)*size.x*.5,(1 if i&2 else -1)*size.y*.5,(1 if i&4 else -1)*size.z*.5))
	for face: Array in BOX_FACES:
		quad(st,corners[face[0]],corners[face[1]],corners[face[2]],corners[face[3]],color)

static func axis_frame(axis: Vector3) -> Array[Vector3]:
	var helper := Vector3.UP if absf(axis.y)<.95 else Vector3.RIGHT
	var u := axis.cross(helper).normalized()
	return [u,axis.cross(u)]

# Smooth-shaded open cylinder; an end radius turns it into a tapered pole.
static func cylinder(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, color: Color, sides := 8, end_radius := -1.0) -> void:
	var frame := axis_frame((b-a).normalized())
	var top := radius if end_radius<0.0 else end_radius
	for i in range(sides):
		var n0 := frame[0]*cos(TAU*i/sides)+frame[1]*sin(TAU*i/sides)
		var n1 := frame[0]*cos(TAU*(i+1)/sides)+frame[1]*sin(TAU*(i+1)/sides)
		var pa := a+n0*radius
		var pb := a+n1*radius
		var pc := b+n1*top
		var pd := b+n0*top
		vertex(st,pa,n0,color); vertex(st,pc,n1,color); vertex(st,pb,n1,color)
		vertex(st,pa,n0,color); vertex(st,pd,n0,color); vertex(st,pc,n1,color)

static func disc(st: SurfaceTool, center: Vector3, radius: float, color: Color, normal := Vector3.UP, sides := 16) -> void:
	var frame := axis_frame(normal)
	for i in range(sides):
		var a := center+(frame[0]*cos(TAU*i/sides)+frame[1]*sin(TAU*i/sides))*radius
		var b := center+(frame[0]*cos(TAU*(i+1)/sides)+frame[1]*sin(TAU*(i+1)/sides))*radius
		triangle(st,a,b,center,color)

# Parasol or tent canopy: alternating panels, with a darker underside for low cameras.
static func canopy(st: SurfaceTool, base: Vector3, apex: Vector3, radius: float, colors: Array, sides := 8) -> void:
	var frame := axis_frame((apex-base).normalized())
	for i in range(sides):
		var a := base+(frame[0]*cos(TAU*i/sides)+frame[1]*sin(TAU*i/sides))*radius
		var b := base+(frame[0]*cos(TAU*(i+1)/sides)+frame[1]*sin(TAU*(i+1)/sides))*radius
		var color: Color=colors[i%colors.size()]
		triangle(st,a,b,apex,color)
		triangle(st,b,a,apex,color.darkened(.28))

# A rail tube that follows the course at a fixed radius and height. A whole
# lap closes on itself, so the rail runs on without a joint anywhere.
static func course_tube(st: SurfaceTool, course: RefCounted, radius: float, height: float, tube: float, color: Color, samples := 420, sides := 12, from := 0.0, to := 1.0) -> void:
	var closed := is_equal_approx(to-from,1.0)
	var points: Array[Vector3]=[]
	for i in range(samples if closed else samples+1):
		points.append(course.sample(lerpf(from,to,float(i)/samples),radius).position+Vector3(0,height,0))
	sweep(st,points,tube,color,sides,closed)

# A smooth round tube along a path of points. Neighbouring segments share their
# rings, so bends have no seams, and each ring's orientation is carried on from
# the last (parallel transport), so the tube never twists.
static func sweep(st: SurfaceTool, points: Array[Vector3], radius: float, color: Color, sides := 12, closed := false) -> void:
	var count := points.size()
	var rings: Array=[]
	var across := Vector3.ZERO
	for i in range(count):
		var before: Vector3=points[(i-1+count)%count] if closed or i>0 else points[i]
		var after: Vector3=points[(i+1)%count] if closed or i<count-1 else points[i]
		var tangent := (after-before).normalized()
		if i==0:
			across=axis_frame(tangent)[0]
		else:
			across=(across-tangent*across.dot(tangent)).normalized()
		var up := tangent.cross(across)
		var ring: Array[Vector3]=[]
		for k in range(sides):
			var angle := TAU*k/sides
			ring.append(across*cos(angle)+up*sin(angle))
		rings.append(ring)
	for i in range(count if closed else count-1):
		var j := (i+1)%count
		var pa: Vector3=points[i]
		var pb: Vector3=points[j]
		var ra: Array[Vector3]=rings[i]
		var rb: Array[Vector3]=rings[j]
		for k in range(sides):
			var l := (k+1)%sides
			vertex(st,pa+ra[k]*radius,ra[k],color); vertex(st,pb+rb[l]*radius,rb[l],color); vertex(st,pa+ra[l]*radius,ra[l],color)
			vertex(st,pa+ra[k]*radius,ra[k],color); vertex(st,pb+rb[k]*radius,rb[k],color); vertex(st,pb+rb[l]*radius,rb[l],color)

# A fitting sleeve slid over a tube: a short shell with closed ring ends, its
# edges eased so it reads as a moulded joint rather than a cut pipe.
static func collar(st: SurfaceTool, center: Vector3, axis: Vector3, length: float, inner: float, outer: float, color: Color, sides := 12) -> void:
	axis=axis.normalized()
	var half := axis*length*.5
	var ease := minf(length*.2,(outer-inner)*.8)
	var lip := outer-ease*.6
	cylinder(st,center-half+axis*ease,center+half-axis*ease,outer,color,sides)
	cylinder(st,center-half,center-half+axis*ease,lip,color,sides,outer)
	cylinder(st,center+half-axis*ease,center+half,outer,color,sides,lip)
	for end: int in [-1,1]:
		var face := center+half*end
		var frame := axis_frame(axis)
		for k in range(sides):
			var a0 := frame[0]*cos(TAU*k/sides)+frame[1]*sin(TAU*k/sides)
			var a1 := frame[0]*cos(TAU*(k+1)/sides)+frame[1]*sin(TAU*(k+1)/sides)
			# The ring tucks a little inside the tube it grips, so no sliver shows.
			var quad_points: Array[Vector3]=[face+a0*inner*.96,face+a1*inner*.96,face+a1*lip,face+a0*lip]
			# Rounded-edge normals light the ring like the sleeve, not as a dark rim.
			var normals: Array[Vector3]=[(axis*end+a0).normalized(),(axis*end+a1).normalized(),(axis*end+a1).normalized(),(axis*end+a0).normalized()]
			# Seen from outside each end, the ring must run counter-clockwise.
			if end>0:
				quad_points.reverse()
				normals.reverse()
			for index: int in [0,2,1,0,3,2]: vertex(st,quad_points[index],normals[index],color)

# A flat ribbon between two radii, following the course (turf, sand and paths).
# With layers it is stacked that many times for grass shells, each copy's
# height fraction (1/layers to 1) in UV2.x; the ground shader lifts them.
# A piece of the lap (from/to) can be built around its own origin.
static func course_band(course: RefCounted, inner: float, outer: float, y: float, samples := 384, layers := 0, from := 0.0, to := 1.0, origin := Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 4.0*float(course.config.halfStraight)+TAU*(inner+outer)*.5
	for layer in range(maxi(layers,1)):
		var lift := float(layer+1)/layers if layers>0 else 0.0
		for i in range(samples):
			var a := lerpf(from,to,float(i)/samples)
			var b := lerpf(from,to,float(i+1)/samples)
			var points: Array[Vector3]=[course.sample(a,inner).position,course.sample(a,outer).position,course.sample(b,inner).position,course.sample(b,outer).position]
			var uvs: Array[Vector2]=[Vector2(a*length,0),Vector2(a*length,outer-inner),Vector2(b*length,0),Vector2(b*length,outer-inner)]
			for index: int in [0,2,1,1,2,3]:
				var point: Vector3=points[index]-origin
				point.y=y
				st.set_normal(Vector3.UP)
				st.set_uv(uvs[index])
				if layers>0: st.set_uv2(Vector2(lift,0))
				st.add_vertex(point)
	return st.commit()

static func multimesh(mesh: Mesh, transforms: Array, parent: Node3D, shadows := true) -> MultiMeshInstance3D:
	var instances := MultiMesh.new()
	instances.transform_format=MultiMesh.TRANSFORM_3D
	instances.mesh=mesh
	instances.instance_count=transforms.size()
	for i in range(transforms.size()): instances.set_instance_transform(i,transforms[i])
	var group := MultiMeshInstance3D.new()
	group.multimesh=instances
	group.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(group)
	return group
