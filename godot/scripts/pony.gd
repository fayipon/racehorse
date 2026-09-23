extends Node3D

const BODY = preload("res://assets/pony_body.obj")
const HEAD = preload("res://assets/pony_head.obj")
const KNIT = preload("res://shaders/knit.gdshader")
var limbs: Array[Node3D] = []
var knees: Array[Node3D] = []
var head: Node3D
var tail: Node3D
var torso: Node3D
var ears: Array[Node3D] = []
var eyes: Array[Node3D] = []
var horse_index := 0
var stride_clock := 0.0
var motion_blend := 0.0
var run_blend := 0.0

func fabric(color: Color, density := 22.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = KNIT
	mat.set_shader_parameter("color",color)
	mat.set_shader_parameter("stitch_scale",density)
	return mat

func solid(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic_specular = 0.22
	return mat

func mesh_node(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.layers = 3 # Layer 2 receives the soft camera fill, without brightening the course.
	parent.add_child(node)
	return node

func ball(parent: Node3D, pos: Vector3, radius: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 14
	var node := mesh_node(parent,mesh,mat,pos)
	node.scale = radius*2.0
	return node

func cord(parent: Node3D, points: PackedVector3Array, radius: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in range(points.size()):
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]).normalized()
		var axis := Vector3.UP if absf(tangent.dot(Vector3.UP))<0.92 else Vector3.RIGHT
		var side := tangent.cross(axis).normalized()
		var up := tangent.cross(side).normalized()
		var ring_points := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for j in range(8):
			var normal := side*cos(j*TAU/8.0)+up*sin(j*TAU/8.0)
			ring_points.append(points[i]+normal*radius)
			ring_normals.append(normal)
		rings.append(ring_points)
		normals.append(ring_normals)
	for i in range(points.size()-1):
		for j in range(8):
			for corner in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,(j+1)%8),Vector2i(i,(j+1)%8),Vector2i(i+1,j),Vector2i(i+1,(j+1)%8)]:
				st.set_normal(normals[corner.x][corner.y])
				st.add_vertex(rings[corner.x][corner.y])
	mesh_node(parent,st.commit(),mat)

func build(index: int, color: Color) -> void:
	horse_index = index
	var body_mat := fabric(color,25.0)
	var mane_mat := fabric(color.darkened(0.23),32.0)
	var mane_light := fabric(color.darkened(0.14),32.0)
	var cream := fabric(Color("c6b797"),27.0)
	var hoof := fabric(Color("645348"),30.0)
	torso = Node3D.new()
	add_child(torso)
	mesh_node(torso,BODY,body_mat)
	head = Node3D.new()
	head.position = Vector3(0,2.23,-0.78)
	torso.add_child(head)
	mesh_node(head,HEAD,body_mat)
	ball(head,Vector3(0,-0.045,-0.68),Vector3(0.355,0.235,0.22),cream)
	for side in [-1,1]:
		var ear := Node3D.new()
		ear.position = Vector3(side*0.28,0.57,0.035)
		ear.rotation.z = side*-0.22
		head.add_child(ear)
		ball(ear,Vector3(0,0.12,0),Vector3(0.135,0.23,0.12),body_mat)
		ball(ear,Vector3(0,0.12,-0.09),Vector3(0.067,0.14,0.032),cream)
		ears.append(ear)
		var eye := ball(head,Vector3(side*0.402,0.27,-0.325),Vector3(0.075,0.089,0.068),solid(Color("171b1c"),0.2))
		eyes.append(eye)
		ball(head,Vector3(side*0.444,0.305,-0.355),Vector3(0.019,0.021,0.016),solid(Color("e4e0d0"),0.3))
		ball(head,Vector3(side*0.175,0.03,-0.873),Vector3(0.029,0.039,0.014),solid(Color("756653")))
		# Embroidered short mouth stitches, not a painted cartoon grin.
		var mouth := PackedVector3Array()
		for k in range(7): mouth.append(Vector3(side*(0.06+k*.032),-0.155-sin(k/6.0*PI)*.018,-0.843+k*.006))
		cord(head,mouth,0.008,solid(Color("958365")))
	# Long yarn locks drape over the right side of the neck. Each lock is
	# made from two twisting filaments, with a loose end rather than beads.
	for k in range(10):
		for filament in range(2):
			var strand := PackedVector3Array()
			var root := Vector3(.015,2.88-k*.085,-.63+k*.065)
			for j in range(25):
				var t := j/24.0
				var twist := t*TAU*3.4+filament*PI
				var center := root+Vector3(.45*sin(t*PI*.5),-.67*t+.065*sin(t*PI),.18*t)
				strand.append(center+Vector3(cos(twist)*.025,sin(twist)*.025,0))
			cord(torso,strand,.040,mane_mat if filament==0 else mane_light)
	for k in range(5):
		var forelock := PackedVector3Array()
		for j in range(19):
			var t := j/18.0
			forelock.append(Vector3((k-2)*.075+sin(t*6+k)*.023,.64-.38*t,-.09-.46*t))
		cord(head,forelock,.044,mane_mat if k%2==0 else mane_light)
	tail = Node3D.new()
	tail.position = Vector3(0,1.67,1.02)
	torso.add_child(tail)
	for k in range(7):
		for filament in range(2):
			var strand := PackedVector3Array()
			for j in range(30):
				var t := j/29.0
				var twist := t*TAU*4+filament*PI
				var center := Vector3((k-3)*.052+sin(t*5+k)*.065,.19*sin(t*PI)-.88*t,.12+1.13*t)
				strand.append(center+Vector3(cos(twist)*.025,sin(twist)*.025,0))
			cord(tail,strand,.040,mane_mat if filament==0 else mane_light)
	for x in [-0.40,0.40]:
		for z in [-0.51,0.64]:
			var limb := Node3D.new()
			limb.position = Vector3(x,1.09,z)
			add_child(limb)
			ball(limb,Vector3(0,-.23,0),Vector3(.22,.35,.24),body_mat)
			var knee := Node3D.new()
			knee.position = Vector3(0,-.52,0)
			limb.add_child(knee)
			ball(knee,Vector3(0,-.19,0),Vector3(.17,.29,.18),body_mat)
			ball(knee,Vector3(0,-.48,-.04),Vector3(.205,.16,.235),hoof)
			limbs.append(limb)
			knees.append(knee)
	build_saddle(torso,index,cream,solid(color.darkened(.28)))

func build_saddle(parent: Node3D, index: int, mat: Material, trim: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(26):
		for k in range(5):
			for corner in [Vector2i(i,k),Vector2i(i+1,k),Vector2i(i,k+1),Vector2i(i,k+1),Vector2i(i+1,k),Vector2i(i+1,k+1)]:
				var a: float = -1.88+corner.x/26.0*3.76
				var z: float = -.10+corner.y*.14
				st.set_normal(Vector3(sin(a),cos(a),0))
				st.add_vertex(Vector3(sin(a)*.655,1.36+cos(a)*.678,z))
	mesh_node(parent,st.commit(),mat)
	for z in [-.105,.605]:
		var seam := PackedVector3Array()
		for i in range(36):
			var a := -1.88+i/35.0*3.76
			seam.append(Vector3(sin(a)*.665,1.36+cos(a)*.686,z))
		cord(parent,seam,.012,trim)
	for side in [-1,1]:
		var number := Label3D.new()
		number.text = str(index+1)
		number.font_size = 96
		number.pixel_size = .0055
		number.outline_size = 0
		number.no_depth_test = false
		number.shaded = true
		number.layers = 3
		number.modulate = Color("343431")
		number.position = Vector3(side*.675,1.48,.22)
		number.rotation.y = side*PI/2.0
		parent.add_child(number)

func animate(time: float, motion: float, running: bool, _celebration: bool, delta := .016) -> void:
	# Keep phase continuous when changing between running, walking and standing.
	motion_blend=lerpf(motion_blend,clampf(motion,0,1),1.0-exp(-delta*8.0))
	run_blend=lerpf(run_blend,1.0 if running else 0.0,1.0-exp(-delta*4.0))
	stride_clock+=delta*lerpf(.85,1.8,run_blend)*smoothstep(0.0,.65,motion_blend)
	var stride := stride_clock+horse_index*.12
	var weight := motion_blend
	var breath := sin(time*1.4+horse_index*.7)*.006*(1.0-weight)
	var body_bob := sin(stride*TAU*2)*lerpf(.012,.045,run_blend)*weight+breath
	torso.position.y=body_bob
	torso.rotation.x=sin(stride*TAU)*.018*weight
	torso.rotation.z=sin(stride*TAU)*.012*weight
	for j in range(4):
		# Front legs lead in a pair; hind legs follow half a stride later.
		var offset := lerpf([0.0,.5,.5,0.0][j],[0.0,.49,.10,.59][j],run_blend)
		var cycle := fposmod(stride+offset,1.0)
		var stance := lerpf(.66,.55,run_blend)
		var reach := lerpf(.21,.37,run_blend)*weight
		var foot_z: float
		var lift := 0.0
		if cycle<stance:
			# Planted feet move backwards relative to the travelling body.
			foot_z=lerpf(-reach,reach,cycle/stance)
		else:
			var swing := (cycle-stance)/(1.0-stance)
			foot_z=lerpf(reach,-reach,smoothstep(0,1,swing))
			lift=sin(swing*PI)*lerpf(.13,.30,run_blend)*weight
		limbs[j].position.y=1.09+body_bob
		var foot_y := .18-limbs[j].position.y+lift
		var upper := .52
		var lower := .48
		var distance := clampf(Vector2(foot_z,foot_y).length(),.25,upper+lower-.006)
		var base := atan2(-foot_z,-foot_y)
		var bend := acos(clampf((upper*upper+distance*distance-lower*lower)/(2*upper*distance),-1,1))
		var joint := PI-acos(clampf((upper*upper+lower*lower-distance*distance)/(2*upper*lower),-1,1))
		var direction := 1.0 if j%2==0 else -1.0
		limbs[j].rotation.x=base-direction*bend
		knees[j].rotation.x=direction*joint
	head.rotation.x=sin(stride*TAU+.5)*.030*weight+sin(time*1.2+horse_index)*.012
	head.rotation.y=sin(time*.8+horse_index*1.3)*.055*(1.0-run_blend)
	tail.rotation.z=sin(time*1.8+horse_index)*lerpf(.035,.12,weight)
	tail.rotation.x=lerpf(sin(time*1.0)*.035,-.10,run_blend)
	for j in range(2): ears[j].rotation.x=sin(time*1.8+j*2+horse_index)*.050
	var blink := fmod(time+horse_index*.67,5.4)<.12
	for eye in eyes: eye.scale.y=.025 if blink else .178
