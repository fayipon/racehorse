extends Node3D

# The home-straight main stand faces the winning post; the far side carries the
# giant results screen and hospitality marquees. Buildings are procedural and
# spectators use Quaternius posed people (CC0, see assets/venue/crowd).
const KIT = preload("res://scripts/mesh_kit.gd")
const CROWD_SHADER = preload("res://shaders/spectators.gdshader")
const PENNANT = preload("res://shaders/pennant.gdshader")
const POSES = ["Male_Sitting","Female_Sitting","Male_Sitting_Cheering","Female_Sitting_Cheering","Male_Standing_Waving","Woman_Standing_Waving"]
const HAIR_CENTERS = [Vector3(0,2.82,-.73),Vector3(0,2.72,-.71),Vector3(-.16,2.76,-.88),Vector3(.02,2.72,-.82),Vector3(.09,3.55,-.10),Vector3(.09,3.46,-.07)]
const CREAM = Color("f2ead8")
const WHITE = Color("fbf9f2")
const STONE = Color("dcd3c0")
const GREEN = Color("2d6b4d")
const DEEP_GREEN = Color("1d4a36")
const GOLD = Color("dcb45c")
const GLASS = Color("3a5360")
const STAND_HALF := 52.0
const STAND_FRONT := 44.0
const BAY := 13.0
const ROWS := 10
const SCREEN := Vector3(0,0,-47.5)

var random := RandomNumberGenerator.new()
var meshes: Dictionary = {}
var people: Dictionary = {}
var crowd_material: ShaderMaterial
var spectator_count := 0
var palette: Array = []
var reduce_motion := false
var flag_tops: Array[Vector3] = []
var chips: Array[Node3D] = []
var board_round: Label3D
var board_status: Label3D

func build(reduced: bool, colors: Array) -> void:
	random.seed = 247019
	reduce_motion = reduced
	palette = colors
	crowd_material = ShaderMaterial.new()
	crowd_material.shader = CROWD_SHADER
	crowd_material.set_shader_parameter("reduce_motion",reduced)
	var paint := KIT.begin()
	var glass := KIT.begin()
	main_stand(paint,glass)
	promenade(paint)
	giant_screen(paint)
	for x in [-46.0,-32.0,-18.0,18.0,32.0,46.0]:
		marquee(paint,Vector3(x,0,-59.0),8.0 if absf(x)>20.0 else 7.0)
	for x in [-24.5,-19.0,19.0,24.5]: flagpole(paint,Vector3(x,0,-41.5),9.5)
	for x in [-56.0,56.0]: flagpole(paint,Vector3(x,0,41.0),11.0)
	KIT.finish(paint,KIT.painted(.84,.16),self)
	KIT.finish(glass,KIT.painted(.16,.65),self,false)
	build_sails()
	build_flags()
	flush_people()

func main_stand(st: SurfaceTool, glass: SurfaceTool) -> void:
	var length := STAND_HALF*2.0
	var front := STAND_FRONT
	# Concourse: a glazed ground floor between white pilasters.
	KIT.box(st,Vector3(0,1.65,front+6.6),Vector3(length,3.3,13.2),CREAM)
	KIT.box(glass,Vector3(0,1.45,front-.03),Vector3(length-.6,2.1,.06),GLASS)
	for i in range(17):
		KIT.box(st,Vector3(-STAND_HALF+i*6.5,1.65,front-.1),Vector3(.5,3.3,.26),WHITE)
	KIT.box(st,Vector3(0,3.38,front),Vector3(length+.5,.22,.46),WHITE)
	# Raked seating: stone risers, racing-green benches, white stair aisles.
	for row in range(ROWS):
		var z := front+.5+row*.95
		var y := 3.4+row*.62
		KIT.box(st,Vector3(0,(y+3.2)*.5,z+.475),Vector3(length,y-3.18,.95),STONE if row%2==0 else STONE.lightened(.05))
		KIT.box(st,Vector3(0,y+.21,z+.62),Vector3(length,.42,.34),GREEN)
		for i in range(1,8):
			KIT.box(st,Vector3(-STAND_HALF+i*BAY,y+.44,z+.475),Vector3(1.2,.06,.96),WHITE)
	var back := front+.5+ROWS*.95
	# Hospitality boxes behind the top row, crowned by a green and gold fascia.
	KIT.box(st,Vector3(0,8.7,back+1.7),Vector3(length,11.0,3.4),CREAM)
	KIT.box(glass,Vector3(0,11.2,back-.03),Vector3(length-.6,3.0,.06),GLASS)
	for i in range(33):
		KIT.box(st,Vector3(-STAND_HALF+i*3.25,11.2,back-.08),Vector3(.16,3.0,.1),WHITE)
	KIT.box(st,Vector3(0,13.75,back-.06),Vector3(length,.9,.14),DEEP_GREEN)
	KIT.box(st,Vector3(0,13.24,back-.08),Vector3(length,.12,.14),GOLD)
	for side in [-1.0,1.0]:
		KIT.box(st,Vector3(side*(STAND_HALF+.25),7.2,front+6.7),Vector3(.5,14.4,13.4),CREAM)
	# Masts carry the fabric roof; cables run to each front corner.
	for i in range(9):
		var x := -STAND_HALF+i*BAY
		var mast := Vector3(x,0,back+4.0)
		KIT.cylinder(st,mast,mast+Vector3(0,22.0,0),.2,WHITE,8,.14)
		KIT.cylinder(st,mast+Vector3(0,21.2,0),Vector3(x,13.9,front-.8),.035,WHITE,4)
		KIT.cylinder(st,mast+Vector3(0,20.0,0),Vector3(x,16.6,back+3.4),.03,WHITE,4)
		flag_tops.append(mast+Vector3(.2,22.0,0))
	# Club sign and golden sun above the centre bay.
	KIT.box(st,Vector3(0,16.0,front-.45),Vector3(15.0,2.6,.35),DEEP_GREEN)
	for y in [14.62,17.38]: KIT.box(st,Vector3(0,y,front-.45),Vector3(15.2,.16,.4),GOLD)
	for x in [-4.5,4.5]: KIT.box(st,Vector3(x,14.1,front-.45),Vector3(.25,1.0,.25),WHITE)
	var sun := Vector3(0,18.9,front-.5)
	KIT.disc(st,sun,1.15,GOLD,Vector3.FORWARD,24)
	var frame := KIT.axis_frame(Vector3.FORWARD)
	for i in range(12):
		var angle := TAU*i/12.0
		var tip: Vector3=sun+(frame[0]*cos(angle)+frame[1]*sin(angle))*2.05
		var left: Vector3=sun+(frame[0]*cos(angle-.16)+frame[1]*sin(angle-.16))*1.32
		var right: Vector3=sun+(frame[0]*cos(angle+.16)+frame[1]*sin(angle+.16))*1.32
		KIT.triangle(st,right,left,tip,GOLD)
	var title := Label3D.new()
	title.text="SUNNY CUP"
	title.font_size=128
	title.pixel_size=.0135
	title.outline_size=0
	title.modulate=Color("f7dc93")
	title.position=Vector3(0,16.0,front-.64)
	title.rotation.y=PI
	add_child(title)
	# Bunting hangs from the balcony rail in the eight racing colours.
	var x := -STAND_HALF+.4
	var index := 0
	while x<STAND_HALF-.3:
		KIT.triangle(st,Vector3(x-.28,3.26,front-.26),Vector3(x+.28,3.26,front-.26),Vector3(x,2.62,front-.26),palette[index%palette.size()] if index%3!=2 else CREAM)
		x+=.7
		index+=1
	# Spectators on the benches; stair aisles stay clear.
	for row in range(ROWS):
		var z := front+.5+row*.95
		var y := 3.4+row*.62
		var seat := -STAND_HALF+.55
		while seat<STAND_HALF-.4:
			var bay_offset := fposmod(seat+STAND_HALF,BAY)
			if bay_offset>.8 and bay_offset<BAY-.8 and random.randf()>.12:
				var pose := random.randi_range(0,1)
				if random.randf()<.22: pose+=2
				var size := random.randf_range(.39,.46)
				person(pose,Vector3(seat+random.randf_range(-.06,.06),y+.42-1.30*size,z+.5),random.randf_range(-.12,.12),size,1)
			seat+=.76

func build_sails() -> void:
	var st := KIT.begin()
	var back := STAND_FRONT+.5+ROWS*.95+3.4
	for bay in range(8):
		var x0 := -STAND_HALF+bay*BAY
		for gx in range(10):
			for gz in range(6):
				var corners: Array[Vector2]=[Vector2(gx,gz),Vector2(gx+1,gz),Vector2(gx+1,gz+1),Vector2(gx,gz+1)]
				var points: Array[Vector3]=[]
				var normals: Array[Vector3]=[]
				for corner in corners:
					var u := corner.x/10.0
					var w := corner.y/6.0
					points.append(sail_point(x0,back,u,w))
					var du := sail_point(x0,back,u+.01,w)-sail_point(x0,back,u-.01,w)
					var dw := sail_point(x0,back,u,w+.01)-sail_point(x0,back,u,w-.01)
					normals.append(du.cross(dw).normalized())
				for i: int in [0,2,1,0,3,2]: KIT.vertex(st,points[i],normals[i],WHITE)
	var mat := KIT.painted(.72,.25)
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	KIT.finish(st,mat,self)

# Tensioned fabric dips between the masts and toward the open front edge.
func sail_point(x0: float, back: float, u: float, w: float) -> Vector3:
	var y := lerpf(16.6,13.9,w)-sin(PI*u)*(.3+.5*w)
	return Vector3(x0+u*BAY,y,lerpf(back,STAND_FRONT-.8,w))

func promenade(st: SurfaceTool) -> void:
	KIT.quad(st,Vector3(-57,.02,STAND_FRONT),Vector3(57,.02,STAND_FRONT),Vector3(57,.02,39.6),Vector3(-57,.02,39.6),STONE)
	# Garden parasols stay clear of the finish-line camera positions.
	var spots: Array[Vector3]=[]
	for x in [-47.0,-41.0,-35.0,-29.0,-23.0,27.0,33.0,39.0,45.0,51.0]:
		spots.append(Vector3(x,0,41.4 if int(x)%2==0 else 42.6))
	for i in range(spots.size()):
		var p: Vector3=spots[i]
		KIT.cylinder(st,p,p+Vector3(0,2.5,0),.04,WHITE,6)
		KIT.canopy(st,p+Vector3(0,2.3,0),p+Vector3(0,3.0,0),1.5,[WHITE,palette[i%palette.size()]],8)
		KIT.cylinder(st,p,p+Vector3(0,.74,0),.06,Color("6f6a5f"),6)
		KIT.disc(st,p+Vector3(0,.75,0),.5,WHITE)
		for k in range(2):
			if random.randf()<.7:
				var size := random.randf_range(.40,.45)
				var offset := Vector3(random.randf_range(-1.4,1.4),0,random.randf_range(-.9,.9))
				person(4+random.randi_range(0,1),p+offset,random.randf_range(-.5,.5),size,1)

func giant_screen(st: SurfaceTool) -> void:
	var c := SCREEN
	for x in [-9.0,9.0]: KIT.box(st,c+Vector3(x,2.8,-.2),Vector3(1.3,5.6,1.3),Color("59605c"))
	KIT.box(st,c+Vector3(0,10.6,-.25),Vector3(31.0,10.6,1.1),Color("27302d"))
	for y in [5.15,16.05]: KIT.box(st,c+Vector3(0,y,-.2),Vector3(31.4,.3,1.3),WHITE)
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size=Vector2(29.8,9.9)
	face.mesh=quad
	face.position=c+Vector3(0,10.6,.31)
	face.material_override=unlit(Color("0f211c"))
	face.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	var header := MeshInstance3D.new()
	var band := QuadMesh.new()
	band.size=Vector2(29.8,.12)
	header.mesh=band
	header.position=c+Vector3(0,12.85,.36)
	header.material_override=unlit(GOLD)
	add_child(header)
	label("SUNNY CUP",c+Vector3(-7.4,14.25,.42),150,.0098,Color("f5d98f"))
	board_round=label("RACE 01",c+Vector3(9.0,14.25,.42),150,.0098,Color("f3efe2"))
	board_status=label("PLACE YOUR BETS",c+Vector3(0,11.7,.42),96,.0085,Color("9fd6ae"))
	for i in range(8):
		var chip := Node3D.new()
		chip.position=c+Vector3(-12.25+i*3.5,8.5,.4)
		var tile := MeshInstance3D.new()
		var tile_mesh := QuadMesh.new()
		tile_mesh.size=Vector2(2.9,2.9)
		tile.mesh=tile_mesh
		tile.material_override=unlit(palette[i])
		chip.add_child(tile)
		var number := Label3D.new()
		number.text=str(i+1)
		number.font_size=150
		number.pixel_size=.0125
		number.outline_size=0
		number.modulate=Color("fffaf0") if i in [0,3,7] else Color("1b2420")
		number.position.z=.05
		chip.add_child(number)
		add_child(chip)
		chips.append(chip)
		label(str(i+1),c+Vector3(-12.25+i*3.5,6.35,.42),72,.009,Color("c9c4b3"))

func unlit(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=color
	return mat

func label(text: String, at: Vector3, size: int, pixel: float, color: Color) -> Label3D:
	var node := Label3D.new()
	node.text=text
	node.font_size=size
	node.pixel_size=pixel
	node.outline_size=0
	node.modulate=color
	node.position=at
	add_child(node)
	return node

# Live standings slide into place; the board never jumps between orders.
func update_board(phase: String, round_id: int, order: Array, delta: float) -> void:
	var round_text := "RACE %02d" % round_id
	if board_round.text!=round_text: board_round.text=round_text
	var status: String={"betting":"PLACE YOUR BETS","racing":"LIVE STANDINGS","result":"OFFICIAL RESULT"}.get(phase,"")
	if board_status.text!=status: board_status.text=status
	var ease := 1.0-exp(-delta*6.0)
	for rank in range(order.size()):
		var chip: Node3D=chips[int(order[rank])]
		chip.position.x=lerpf(chip.position.x,SCREEN.x-12.25+rank*3.5,ease)

func marquee(st: SurfaceTool, c: Vector3, size: float) -> void:
	var half := size*.5
	var eave := 2.7
	var apex := c+Vector3(0,eave+size*.38,0)
	var corners: Array[Vector3]=[c+Vector3(-half,eave,half),c+Vector3(half,eave,half),c+Vector3(half,eave,-half),c+Vector3(-half,eave,-half)]
	for i in range(4):
		var a: Vector3=corners[i]
		var b: Vector3=corners[(i+1)%4]
		KIT.cylinder(st,Vector3(a.x,0,a.z),a,.07,WHITE,6)
		KIT.triangle(st,a,b,apex,WHITE)
		KIT.triangle(st,b,a,apex,Color("d8d4c8"))
		# Scalloped valance in club stripes under each eave.
		for k in range(6):
			var p0 := a.lerp(b,k/6.0)
			var p1 := a.lerp(b,(k+1)/6.0)
			var outward := (a+b)*.5-c
			outward.y=0
			outward=outward.normalized()*.04
			KIT.quad(st,p0+outward+Vector3(0,-.55,0),p1+outward+Vector3(0,-.55,0),p1+outward,p0+outward,GREEN if k%2==0 else WHITE)
	KIT.cylinder(st,apex,apex+Vector3(0,1.4,0),.04,WHITE,4)
	flag_tops.append(apex+Vector3(.04,1.4,0))

func flagpole(st: SurfaceTool, base: Vector3, height: float) -> void:
	KIT.cylinder(st,base,base+Vector3(0,height,0),.08,WHITE,6,.05)
	KIT.cylinder(st,base+Vector3(0,height,0),base+Vector3(0,height+.14,0),.12,GOLD,6)
	flag_tops.append(base+Vector3(.06,height-.1,0))

func build_flags() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(flag_tops.size()):
		var top: Vector3=flag_tops[i]
		var color: Color=palette[i%palette.size()]
		var width := 2.4 if top.y>10.0 else 1.4
		var height := width*.55
		for k in range(6):
			var u0 := k/6.0
			var u1 := (k+1)/6.0
			var points: Array[Vector3]=[top+Vector3(u0*width,-height*(1.0-.6*u0),0),top+Vector3(u1*width,-height*(1.0-.6*u1),0),top+Vector3(u1*width,0,0),top+Vector3(u0*width,0,0)]
			var uvs: Array[float]=[u0,u1,u1,u0]
			for index: int in [0,2,1,0,3,2]:
				st.set_color(color.srgb_to_linear())
				st.set_normal(Vector3.BACK)
				st.set_uv(Vector2(uvs[index],0))
				st.add_vertex(points[index])
	var flags := MeshInstance3D.new()
	flags.mesh=st.commit()
	var mat := ShaderMaterial.new()
	mat.shader=PENNANT
	mat.set_shader_parameter("wind",.25 if reduce_motion else 1.0)
	flags.material_override=mat
	flags.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flags)

func person(pose: int,p: Vector3,yaw: float,size: float,side: int) -> void:
	var hair := random.randi_range(0,1)
	var key := "%d:%d:%d" % [pose,hair,side]
	if not people.has(key): people[key]={"pose":pose,"hair":hair,"transforms":[],"colors":[]}
	people[key].transforms.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(size*random.randf_range(.92,1.10),size,size)),p))
	people[key].colors.append(Color(random.randf(),random.randf_range(.15,1),random.randf(),1.0 if random.randf()<.13 else 0.0))
	spectator_count+=1

func append_mesh(st: SurfaceTool,mesh: ArrayMesh,offset: Vector3,hair: bool) -> void:
	for surface in range(mesh.get_surface_count()):
		var category := .8
		if not hair:
			match mesh.surface_get_material(surface).resource_name:
				"Skin": category=0.0
				"Shirt": category=.2
				"Pants": category=.4
				_: category=.6
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(indices.size() if not indices.is_empty() else vertices.size()):
			var idx := indices[i] if not indices.is_empty() else i
			st.set_normal(normals[idx])
			st.set_uv(Vector2(category,0))
			st.set_color(Color.WHITE)
			st.add_vertex(vertices[idx]+offset)

func person_mesh(pose: int,hair: int) -> ArrayMesh:
	var key := "person:%d:%d" % [pose,hair]
	if meshes.has(key): return meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	append_mesh(st,load("res://assets/venue/crowd/%s.obj" % POSES[pose]),Vector3.ZERO,false)
	var hair_name := "%s_Hairstyle_%d" % ["Male" if pose%2==0 else "Female",1 if hair==0 else 3]
	append_mesh(st,load("res://assets/venue/crowd/%s.obj" % hair_name),HAIR_CENTERS[pose],true)
	st.index()
	st.set_material(crowd_material)
	var mesh := st.commit()
	meshes[key]=mesh
	return mesh

func flush_people() -> void:
	for batch in people.values():
		var instances := MultiMesh.new()
		instances.transform_format=MultiMesh.TRANSFORM_3D
		instances.use_custom_data=true
		instances.mesh=person_mesh(batch.pose,batch.hair)
		instances.instance_count=batch.transforms.size()
		for i in range(instances.instance_count):
			instances.set_instance_transform(i,batch.transforms[i])
			instances.set_instance_custom_data(i,batch.colors[i])
		var group := MultiMeshInstance3D.new()
		group.multimesh=instances
		group.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.extra_cull_margin=.1
		add_child(group)
	people.clear()
