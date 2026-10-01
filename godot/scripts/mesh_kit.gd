extends RefCounted

# Procedural building blocks for the racecourse. Shapes write linear vertex
# colours into a shared SurfaceTool, so a whole structure draws with one
# material. Godot treats clockwise triangles as front faces.
const GROUND = preload("res://shaders/ground.gdshader")
const TURF_ALBEDO = preload("res://assets/turf/turf_albedo.png")
const TURF_NORMAL = preload("res://assets/turf/turf_normal.png")
const SAND_ALBEDO = preload("res://assets/turf/sand_albedo.png")
const SAND_NORMAL = preload("res://assets/turf/sand_normal.png")

const STRUCTURE = preload("res://shaders/structure.gdshader")
# What a built surface is made of, carried in its vertex colour's alpha for the
# structure shader (shaders/structure.gdshader). Plain colours are paint.
const PAINT := 1.0
const CONCRETE := .9
const GLAZING := .8
const METAL := .7
const SEAT := .6
const PAVING := .5
const CANVAS := .4
const RUBBER := .3
const GOLD_LEAF := .2
const DAMASK := .125
const MARBLE := .1
const PADDING := .05

static func made_of(color: Color, surface: float) -> Color:
	return Color(color.r,color.g,color.b,surface)

static var structure_materials: Dictionary = {}

# The shared material for built surfaces; `ground_shade` darkens what stands on
# the ground toward its foot (off for parts lifted clear of it).
static func structure(ground_shade := true) -> ShaderMaterial:
	if structure_materials.has(ground_shade): return structure_materials[ground_shade]
	var mat := ShaderMaterial.new()
	mat.shader=STRUCTURE
	mat.set_shader_parameter("ground_shade",ground_shade)
	structure_materials[ground_shade]=mat
	return mat

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

# A profile carried round a closed path on the ground: coping, hedges, kerbs.
# Profile points are (outward offset, height), listed from the inside edge over
# to the outside; normals are smoothed between the profile's segments.
static func loft(st: SurfaceTool, path: Array[Vector3], profile: Array[Vector2], color: Color) -> void:
	var count := path.size()
	var centroid := Vector3.ZERO
	for p in path: centroid+=p/count
	var rings: Array=[]
	var normals: Array=[]
	var seg_normals: Array[Vector2]=[]
	for j in range(profile.size()-1):
		var d := profile[j+1]-profile[j]
		# Inside faces look in, tops look up, outside faces look out.
		seg_normals.append(Vector2(-d.y,d.x).normalized())
	for i in range(count):
		var tangent := (path[(i+1)%count]-path[(i-1+count)%count]).normalized()
		var out := Vector3.UP.cross(tangent).normalized()
		if out.dot(path[i]-centroid)<0.0: out=-out
		var ring: Array[Vector3]=[]
		var ring_normals: Array[Vector3]=[]
		for j in range(profile.size()):
			ring.append(path[i]+out*profile[j].x+Vector3.UP*profile[j].y)
			var n2 := (seg_normals[maxi(j-1,0)]+seg_normals[mini(j,seg_normals.size()-1)]).normalized()
			ring_normals.append((out*n2.x+Vector3.UP*n2.y).normalized())
		rings.append(ring)
		normals.append(ring_normals)
	for i in range(count):
		var k := (i+1)%count
		for j in range(profile.size()-1):
			var a: Vector3=rings[i][j]
			var b: Vector3=rings[i][j+1]
			var c: Vector3=rings[k][j+1]
			var d: Vector3=rings[k][j]
			smooth_triangle(st,[a,b,c],[normals[i][j],normals[i][j+1],normals[k][j+1]],color)
			smooth_triangle(st,[a,c,d],[normals[i][j],normals[k][j+1],normals[k][j]],color)

# A flat outline (in the plane of `u` and `v` from `origin`) extruded by `depth`
# along their cross product: walls with a stepped or raked profile.
static func extrude(st: SurfaceTool, outline: PackedVector2Array, origin: Vector3, u: Vector3, v: Vector3, depth: float, color: Color) -> void:
	var w := u.cross(v).normalized()
	var to_world := func(p: Vector2, side: float) -> Vector3: return origin+u*p.x+v*p.y+w*depth*side
	var caps := Geometry2D.triangulate_polygon(outline)
	for t in range(0,caps.size(),3):
		for side: float in [0.0,1.0]:
			var n := w if side>0.0 else -w
			var points: Array=[to_world.call(outline[caps[t]],side),to_world.call(outline[caps[t+1]],side),to_world.call(outline[caps[t+2]],side)]
			smooth_triangle(st,points,[n,n,n],color)
	var count := outline.size()
	var area := 0.0
	for i in range(count): area+=outline[i].cross(outline[(i+1)%count])
	for i in range(count):
		var a := outline[i]
		var b := outline[(i+1)%count]
		var edge := (b-a).normalized()
		# Outward in the outline's plane, whichever way it winds.
		var out2 := Vector2(edge.y,-edge.x)*(1.0 if area>0.0 else -1.0)
		var n: Vector3=(u*out2.x+v*out2.y).normalized()
		var quad: Array=[to_world.call(a,0.0),to_world.call(b,0.0),to_world.call(b,1.0),to_world.call(a,1.0)]
		smooth_triangle(st,[quad[0],quad[1],quad[2]],[n,n,n],color)
		smooth_triangle(st,[quad[0],quad[2],quad[3]],[n,n,n],color)

# A triangle with its own corner normals, wound to face the way they point.
static func smooth_triangle(st: SurfaceTool, points: Array, normals: Array, color: Color) -> void:
	var a: Vector3=points[0]
	var b: Vector3=points[1]
	var c: Vector3=points[2]
	var na: Vector3=normals[0]
	var nb: Vector3=normals[1]
	var nc: Vector3=normals[2]
	if (c-a).cross(b-a).dot(na+nb+nc)<0.0:
		vertex(st,a,na,color); vertex(st,c,nc,color); vertex(st,b,nb,color)
	else:
		vertex(st,a,na,color); vertex(st,b,nb,color); vertex(st,c,nc,color)

# A box whose edges are rounded off by `bevel`: each edge is a narrow strip
# whose normals turn from one face to the next, so it catches the light like a
# moulded or eased edge instead of ending in a hard line.
static func rounded_box(st: SurfaceTool, center: Vector3, size: Vector3, bevel: float, color: Color, basis := Basis.IDENTITY) -> void:
	var h := size*.5
	bevel=minf(bevel,minf(h.x,minf(h.y,h.z))*.95)
	var axes: Array[Vector3]=[basis.x.normalized(),basis.y.normalized(),basis.z.normalized()]
	var half: Array[float]=[h.x,h.y,h.z]
	# A point on the face of axis `f`, set in by the bevel along the others.
	var at := func(f: int, signs: Vector3) -> Vector3:
		var p := center
		for k in range(3):
			var s: float=signs[k]
			p+=axes[k]*s*(half[k] if k==f else half[k]-bevel)
		return p
	for f in range(3):
		for sf: float in [-1.0,1.0]:
			var a := (f+1)%3
			var b := (f+2)%3
			var corners: Array=[]
			for pair: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var signs := Vector3.ZERO
				signs[f]=sf
				signs[a]=pair.x
				signs[b]=pair.y
				corners.append(at.call(f,signs))
			var n: Vector3=axes[f]*sf
			smooth_triangle(st,[corners[0],corners[1],corners[2]],[n,n,n],color)
			smooth_triangle(st,[corners[0],corners[2],corners[3]],[n,n,n],color)
	# Edge strips between two faces, running along the third axis.
	for f in range(3):
		var g := (f+1)%3
		var c := (f+2)%3
		for sf: float in [-1.0,1.0]:
			for sg: float in [-1.0,1.0]:
				var points: Array=[]
				var normals: Array=[]
				for sc: float in [-1.0,1.0]:
					var signs := Vector3.ZERO
					signs[f]=sf
					signs[g]=sg
					signs[c]=sc
					points.append(at.call(f,signs))
					normals.append(axes[f]*sf)
					points.append(at.call(g,signs))
					normals.append(axes[g]*sg)
				smooth_triangle(st,[points[0],points[2],points[3]],[normals[0],normals[2],normals[3]],color)
				smooth_triangle(st,[points[0],points[3],points[1]],[normals[0],normals[3],normals[1]],color)
	# Corner triangles where three strips meet.
	for i in range(8):
		var signs := Vector3(1 if i&1 else -1,1 if i&2 else -1,1 if i&4 else -1)
		var points: Array=[]
		var normals: Array=[]
		for f in range(3):
			points.append(at.call(f,signs))
			normals.append(axes[f]*signs[f])
		smooth_triangle(st,points,normals,color)

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

# A smooth ellipsoid with its own axes (`basis` columns scaled by `radii`):
# petals, leaves, urn bowls.
static func ellipsoid(st: SurfaceTool, center: Vector3, basis: Basis, radii: Vector3, color: Color, rings := 6, sides := 10) -> void:
	for r in range(rings):
		var a0 := PI*r/rings-PI*.5
		var a1 := PI*(r+1)/rings-PI*.5
		for s in range(sides):
			var b0 := TAU*s/sides
			var b1 := TAU*(s+1)/sides
			var p: Array=[]
			var n: Array=[]
			for pair: Vector2 in [Vector2(a0,b0),Vector2(a0,b1),Vector2(a1,b1),Vector2(a1,b0)]:
				var d := Vector3(cos(pair.x)*cos(pair.y),sin(pair.x),cos(pair.x)*sin(pair.y))
				p.append(center+basis*(d*radii))
				n.append((basis*(d/radii)).normalized())
			if r>0: smooth_triangle(st,[p[0],p[1],p[2]],[n[0],n[1],n[2]],color)
			if r<rings-1: smooth_triangle(st,[p[0],p[2],p[3]],[n[0],n[2],n[3]],color)

# A smooth ball (finials, knobs); `squash` flattens or stretches it upright.
static func sphere(st: SurfaceTool, center: Vector3, radius: float, color: Color, rings := 6, sides := 12, squash := 1.0) -> void:
	for r in range(rings):
		var a0 := PI*r/rings-PI*.5
		var a1 := PI*(r+1)/rings-PI*.5
		for s in range(sides):
			var b0 := TAU*s/sides
			var b1 := TAU*(s+1)/sides
			var n: Array=[]
			for pair: Vector2 in [Vector2(a0,b0),Vector2(a0,b1),Vector2(a1,b1),Vector2(a1,b0)]:
				n.append(Vector3(cos(pair.x)*cos(pair.y),sin(pair.x),cos(pair.x)*sin(pair.y)))
			var p: Array=n.map(func(d: Vector3) -> Vector3: return center+Vector3(d.x,d.y*squash,d.z)*radius)
			if r>0: smooth_triangle(st,[p[0],p[1],p[2]],[n[0],n[1],n[2]],color)
			if r<rings-1: smooth_triangle(st,[p[0],p[2],p[3]],[n[0],n[2],n[3]],color)

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
