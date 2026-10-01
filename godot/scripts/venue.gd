extends Node3D

# The home-straight main stand faces the winning post; the far side carries the
# giant results screen and hospitality marquees. Buildings are procedural, drawn
# with the shared structure shader (concrete, glazing with rooms behind it,
# steel, seat plastic, paving, canvas), and spectators use Quaternius posed
# people (CC0, see assets/venue/crowd).
const KIT = preload("res://scripts/mesh_kit.gd")
const CROWD_SHADER = preload("res://shaders/spectators.gdshader")
const FLAG_SHADER = preload("res://shaders/flag.gdshader")
const POSES = ["Male_Sitting","Female_Sitting","Male_Sitting_Cheering","Female_Sitting_Cheering","Male_Standing_Waving","Woman_Standing_Waving"]
const HAIR_CENTERS = [Vector3(0,2.82,-.73),Vector3(0,2.72,-.71),Vector3(-.16,2.76,-.88),Vector3(.02,2.72,-.82),Vector3(.09,3.55,-.10),Vector3(.09,3.46,-.07)]
const WHITE = Color("f4f2ec")
const CONCRETE = Color("dcd7cc")
const STONE = Color("d6ccb8")
const STEEL = Color("eef0ee")
const CLADDING = Color("aab0b0")
const SOFFIT = Color("d2d5d2")
const DEEP_GREEN = Color("1d4433")
const SEAT_GREEN = Color("2f7a52")
const GOLD = Color("d6ad55")
const MULLION = Color("c8cdcb")
const STAND_HALF := 52.0
const STAND_FRONT := 44.0
const BAY := 13.0
const ROWS := 10
# The cantilevered roof: its front edge over the promenade, its back on the
# columns behind the boxes; the steel trusses ride on top of it.
const ROOF_FRONT := 41.0
const ROOF_BACK := 59.6
const ROOF_LOW := 17.6
const ROOF_HIGH := 18.9
const SCREEN := Vector3(0,0,-47.5)
# Grid, in model units (a seated figure is about three tall), that the
# power-saving tier welds spectators onto.
const WELD_CELL := .3

var random := RandomNumberGenerator.new()
var meshes: Dictionary = {}
var people: Dictionary = {}
var crowd_material: ShaderMaterial
var spectator_count := 0
var palette: Array = []
var field := 8
var board_title := "SUNNY CUP"
var board_emblem := "sunny"
var reduce_motion := false
var attendance := .88
var coarse := false
# Each flag: where its hoist meets the pole top, its length and depth.
var flags: Array[Dictionary] = []
var seats: Array[Transform3D] = []
var chips: Array[Node3D] = []
var board_round: Label3D
var board_status: Label3D

func build(reduced: bool, colors: Array, sparse := false, runners := 8, title := "SUNNY CUP", emblem := "sunny") -> void:
	random.seed = 247019
	reduce_motion = reduced
	palette = colors
	field = runners
	board_title = title
	board_emblem = emblem
	# The crowd dominates the vertex budget; the power-saving tier seats fewer.
	attendance = .42 if sparse else .88
	coarse = sparse
	crowd_material = ShaderMaterial.new()
	crowd_material.shader = CROWD_SHADER
	crowd_material.set_shader_parameter("reduce_motion",reduced)
	var st := KIT.begin()
	# Fine steelwork on the roof casts no shadow worth its cost on phones.
	var steelwork := KIT.begin()
	main_stand(st)
	roof(st,steelwork)
	promenade(st)
	giant_screen(st)
	for x in [-46.0,-32.0,-18.0,18.0,32.0,46.0]:
		marquee(st,Vector3(x,0,-59.0),8.0 if absf(x)>20.0 else 7.0)
	for x in [-24.5,-19.0,19.0,24.5]: flagpole(st,Vector3(x,0,-41.5),9.5,2.4)
	for x in [-56.0,56.0]: flagpole(st,Vector3(x,0,41.0),11.0,2.6)
	KIT.finish(st,KIT.structure(),self)
	KIT.finish(steelwork,KIT.structure(false),self,not coarse)
	balustrade()
	if not coarse: build_seats()
	build_flags()
	flush_people()

# A gold shape on a sign facing the track, wound to face it whatever order its corners come in.
func flat_triangle(st: SurfaceTool, z: float, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if (b-a).cross(c-a)>0.0:
		var swap := b
		b = c
		c = swap
	KIT.triangle(st,Vector3(a.x,a.y,z),Vector3(b.x,b.y,z),Vector3(c.x,c.y,z),color)

# The tread height and front edge of a seating row.
func row_y(row: int) -> float: return 3.4+row*.62
func row_z(row: int) -> float: return STAND_FRONT+.5+row*.95

func main_stand(st: SurfaceTool) -> void:
	var length := STAND_HALF*2.0
	var front := STAND_FRONT
	var concrete := KIT.made_of(CONCRETE,KIT.CONCRETE)
	var steel := KIT.made_of(STEEL,KIT.METAL)
	# Ground floor: an arcade of round columns before a glazed concourse, its
	# bars and shops lit behind the glass.
	for i in range(17):
		var x := -STAND_HALF+i*6.5
		var round := 10 if coarse else 18
		KIT.cylinder(st,Vector3(x,0,front+.35),Vector3(x,3.1,front+.35),.3,concrete,round)
		KIT.collar(st,Vector3(x,.12,front+.35),Vector3.UP,.24,.3,.36,KIT.made_of(STONE,KIT.CONCRETE),round)
	KIT.rounded_box(st,Vector3(0,3.28,front+.3),Vector3(length+.6,.44,.9),.06,concrete)
	KIT.box(st,Vector3(0,3.03,front+1.05),Vector3(length,.1,1.5),KIT.made_of(SOFFIT,KIT.PAINT))
	KIT.box(st,Vector3(0,1.62,front+1.8),Vector3(length,2.9,.08),KIT.made_of(MULLION,KIT.GLAZING))
	KIT.rounded_box(st,Vector3(0,.1,front+1.74),Vector3(length,.2,.16),.03,KIT.made_of(STONE,KIT.CONCRETE))
	KIT.box(st,Vector3(0,1.6,front+7.5),Vector3(length,3.2,11.3),concrete)
	# Raked precast terraces: each tread's nosing is eased; stair aisles at every
	# bay climb in half steps beside a handrail.
	for row in range(ROWS):
		var z := row_z(row)
		var y := row_y(row)
		KIT.rounded_box(st,Vector3(0,(y+3.2)*.5,z+.475),Vector3(length,y-3.2,.95),.03,KIT.made_of(CONCRETE.darkened(.04 if row%2 else 0.0),KIT.CONCRETE))
		for i in range(1,8):
			var x := -STAND_HALF+i*BAY
			if coarse: KIT.box(st,Vector3(x,y+.155,z+.71),Vector3(1.2,.31,.48),KIT.made_of(CONCRETE.lightened(.05),KIT.CONCRETE))
			else: KIT.rounded_box(st,Vector3(x,y+.155,z+.71),Vector3(1.2,.31,.48),.02,KIT.made_of(CONCRETE.lightened(.05),KIT.CONCRETE))
	for i in range(1,8):
		var x := -STAND_HALF+i*BAY
		var rail: Array[Vector3]=[Vector3(x,row_y(0)+.95,row_z(0)+.2),Vector3(x,row_y(ROWS-1)+.95,row_z(ROWS-1)+.6)]
		KIT.sweep(st,rail,.028,steel,8)
		for row in range(0,ROWS,3):
			var at := Vector3(x,row_y(row),row_z(row)+.4)
			KIT.cylinder(st,at,at+Vector3(0,.97,0),.022,steel,6)
	# Behind the top row a walkway, then the glazed hospitality boxes between
	# slim white fins, under a deep white fascia.
	var back := row_z(ROWS-1)+.95
	KIT.box(st,Vector3(0,6.1,back+.7),Vector3(length,5.8,1.4),concrete)
	KIT.rounded_box(st,Vector3(0,9.66,back+1.25),Vector3(length+.4,.5,.5),.05,KIT.made_of(WHITE,KIT.PAINT))
	KIT.box(st,Vector3(0,11.55,back+1.55),Vector3(length,3.2,.08),KIT.made_of(MULLION,KIT.GLAZING))
	for i in range(17):
		KIT.rounded_box(st,Vector3(-STAND_HALF+i*6.5,11.55,back+1.42),Vector3(.18,3.3,.3),.04,KIT.made_of(WHITE,KIT.PAINT))
	KIT.rounded_box(st,Vector3(0,13.47,back+1.35),Vector3(length+.4,.64,.9),.06,KIT.made_of(WHITE,KIT.PAINT))
	KIT.box(st,Vector3(0,11.6,back+3.2),Vector3(length,4.2,3.2),concrete)
	# Clad back wall up to the roof, and the raked end walls.
	KIT.box(st,Vector3(0,9.6,ROOF_BACK+.1),Vector3(length+1.4,19.2,.4),KIT.made_of(CLADDING,KIT.PAINT))
	var profile := PackedVector2Array([Vector2(front-.15,0),Vector2(front-.15,3.6),Vector2(back+.2,10.4),Vector2(back+.9,10.4),Vector2(back+.9,13.9),Vector2(ROOF_BACK,13.9),Vector2(ROOF_BACK,0)])
	for side: float in [-1.0,1.0]:
		# Extrusions run toward -x from their origin.
		var x0 := STAND_HALF+.65 if side>0 else -(STAND_HALF+.05)
		KIT.extrude(st,profile,Vector3(x0,0,0),Vector3.BACK,Vector3.UP,.6,concrete)
		var cap := STAND_HALF+.7 if side>0 else -STAND_HALF
		KIT.extrude(st,PackedVector2Array([Vector2(front-.25,3.5),Vector2(front-.25,3.85),Vector2(back+.3,10.65),Vector2(back+.3,10.3)]),Vector3(cap,0,0),Vector3.BACK,Vector3.UP,.7,KIT.made_of(WHITE,KIT.PAINT))
	# Spectators on the seats; stair aisles stay clear.
	for row in range(ROWS):
		var z := row_z(row)
		var y := row_y(row)
		var seat := -STAND_HALF+.55
		while seat<STAND_HALF-.4:
			var bay_offset := fposmod(seat+STAND_HALF,BAY)
			if bay_offset>.8 and bay_offset<BAY-.8:
				seats.append(Transform3D(Basis.IDENTITY,Vector3(seat,y,z+.5)))
				if random.randf()<attendance:
					var pose := random.randi_range(0,1)
					if random.randf()<.22: pose+=2
					var size := random.randf_range(.39,.46)
					person(pose,Vector3(seat+random.randf_range(-.06,.06),y+.42-1.30*size,z+.5),random.randf_range(-.12,.12),size,1)
			seat+=.76

# The roof's underside height at a depth z, and its top surface.
func roof_y(z: float) -> float:
	return lerpf(ROOF_LOW,ROOF_HIGH,(z-ROOF_FRONT)/(ROOF_BACK-ROOF_FRONT))

func roof(st: SurfaceTool, steelwork: SurfaceTool) -> void:
	var half := STAND_HALF+1.6
	var steel := KIT.made_of(STEEL,KIT.METAL)
	var white := KIT.made_of(WHITE,KIT.PAINT)
	var thick := .45
	var soffit := KIT.made_of(SOFFIT,KIT.PAINT)
	# Underside, lit and ribbed; the sheeted top; a deep fascia at the front.
	KIT.quad(st,Vector3(-half,roof_y(ROOF_FRONT),ROOF_FRONT),Vector3(half,roof_y(ROOF_FRONT),ROOF_FRONT),Vector3(half,roof_y(ROOF_BACK),ROOF_BACK),Vector3(-half,roof_y(ROOF_BACK),ROOF_BACK),soffit)
	KIT.quad(st,Vector3(-half,roof_y(ROOF_BACK)+thick,ROOF_BACK),Vector3(half,roof_y(ROOF_BACK)+thick,ROOF_BACK),Vector3(half,roof_y(ROOF_FRONT)+thick,ROOF_FRONT),Vector3(-half,roof_y(ROOF_FRONT)+thick,ROOF_FRONT),KIT.made_of(CLADDING.lightened(.2),KIT.PAINT))
	var slope := Vector3(0,ROOF_HIGH-ROOF_LOW,ROOF_BACK-ROOF_FRONT).normalized()
	var rib_basis := Basis(Vector3.RIGHT,slope.cross(Vector3.RIGHT).normalized(),slope)
	var depth := Vector2(ROOF_FRONT,ROOF_BACK)
	var middle := Vector3(0,(roof_y(depth.x)+roof_y(depth.y))*.5,(depth.x+depth.y)*.5)
	var span: float=Vector2(depth.y-depth.x,ROOF_HIGH-ROOF_LOW).length()
	for i in range(33):
		var x := -STAND_HALF+i*3.25
		KIT.box(st,middle+Vector3(x,-.14,0),Vector3(.1,.26,span),soffit.darkened(.08),rib_basis)
	for k in range(1,6):
		var z := lerpf(ROOF_FRONT,ROOF_BACK,k/6.0)
		KIT.box(st,Vector3(0,roof_y(z)-.18,z),Vector3(half*2.0,.34,.16),soffit.darkened(.12))
	KIT.quad(st,Vector3(half,roof_y(ROOF_FRONT),ROOF_FRONT),Vector3(half,roof_y(ROOF_FRONT)+thick,ROOF_FRONT),Vector3(half,roof_y(ROOF_BACK)+thick,ROOF_BACK),Vector3(half,roof_y(ROOF_BACK),ROOF_BACK),white)
	KIT.quad(st,Vector3(-half,roof_y(ROOF_BACK),ROOF_BACK),Vector3(-half,roof_y(ROOF_BACK)+thick,ROOF_BACK),Vector3(-half,roof_y(ROOF_FRONT)+thick,ROOF_FRONT),Vector3(-half,roof_y(ROOF_FRONT),ROOF_FRONT),white)
	KIT.rounded_box(st,Vector3(0,ROOF_LOW+.18,ROOF_FRONT+.05),Vector3(half*2.0+.1,1.1,.5),.08,white)
	KIT.rounded_box(st,Vector3(0,ROOF_LOW-.36,ROOF_FRONT+.05),Vector3(half*2.0,.06,.52),.02,KIT.made_of(GOLD,KIT.GOLD_LEAF))
	# A bowed steel truss over each bay line, from the back columns out to the
	# fascia; a flag flies from a mast on every crown.
	for i in range(9):
		var x := -STAND_HALF+i*BAY
		var top: Array[Vector3]=[]
		var bottom: Array[Vector3]=[]
		for k in range(17):
			var s := k/16.0
			var z := lerpf(ROOF_FRONT+.4,ROOF_BACK-.3,s)
			var base := roof_y(z)+thick+.12
			bottom.append(Vector3(x,base,z))
			top.append(Vector3(x,base+2.4*pow(sin(PI*pow(s,1.15)),.8)+.1,z))
		KIT.sweep(steelwork,top,.12,steel,6 if coarse else 10)
		KIT.sweep(steelwork,bottom,.09,steel,6 if coarse else 8)
		for k in range(1,16):
			var a: Vector3=bottom[k]
			var b: Vector3=top[k+(1 if k%2 else -1)]
			KIT.cylinder(steelwork,a,b,.04,steel,4 if coarse else 6)
		var crown: Vector3=top[0]
		for p in top:
			if p.y>crown.y: crown=p
		KIT.cylinder(steelwork,crown,crown+Vector3(0,3.6,0),.06,steel,6,.04)
		KIT.sphere(steelwork,crown+Vector3(0,3.68,0),.1,KIT.made_of(GOLD,KIT.GOLD_LEAF),4,8)
		flags.append({"top":crown+Vector3(.05,3.55,0),"length":2.6,"depth":1.5})
		# The truss bears on a round column rising behind the boxes.
		KIT.cylinder(st,Vector3(x,13.8,ROOF_BACK-.55),Vector3(x,roof_y(ROOF_BACK),ROOF_BACK-.55),.36,KIT.made_of(WHITE,KIT.PAINT),14)
	cup_crest(st)

# The cup's crest stands on the roof fascia over the winning post: a racing-green
# panel framed in gold, its emblem over its name.
func cup_crest(st: SurfaceTool) -> void:
	var z := ROOF_FRONT-.42
	var center := Vector3(0,ROOF_LOW+1.85,z)
	KIT.rounded_box(st,center,Vector3(15.0,3.9,.42),.16,KIT.made_of(DEEP_GREEN,KIT.PAINT))
	var gold := KIT.made_of(GOLD,KIT.GOLD_LEAF)
	for y: float in [-1.68,1.68]: KIT.rounded_box(st,center+Vector3(0,y,-.2),Vector3(14.2,.09,.06),.03,gold)
	for x: float in [-6.95,6.95]: KIT.rounded_box(st,center+Vector3(x,0,-.2),Vector3(.09,3.45,.06),.03,gold)
	emblem(st,Vector2(0,center.y+.65),z-.23,.42,gold)
	var title := Label3D.new()
	title.text=board_title
	title.font_size=128
	title.pixel_size=.0098
	title.outline_size=0
	title.modulate=Color("f2d48a")
	title.position=Vector3(0,center.y-.75,z-.23)
	title.rotation.y=PI
	add_child(title)

# The cup's emblem drawn flat on a sign facing the track (-z), at `scale`.
func emblem(st: SurfaceTool, at: Vector2, z: float, scale: float, color: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return at+Vector2(x,y)*scale
	match board_emblem:
		"thunder":
			# A lightning bolt from two overlapping wedges; -x is the viewer's right.
			flat_triangle(st,z,p.call(-.75,2.0),p.call(.95,-.05),p.call(-.35,-.05),color)
			flat_triangle(st,z,p.call(.35,.25),p.call(-.95,.25),p.call(.75,-1.5),color)
		"royal":
			# A three-point crown with a rose jewel on the band.
			KIT.box(st,Vector3(at.x,at.y-.7*scale,z),Vector3(3.6,.8,.2)*Vector3(scale,scale,1.0),color)
			for peak: Array in [[-1.8,-.5,Vector2(-1.45,1.2)],[-.75,.75,Vector2(0,1.8)],[.5,1.8,Vector2(1.45,1.2)]]:
				var tip: Vector2=p.call(peak[2].x,peak[2].y)
				flat_triangle(st,z,p.call(peak[0],-.35),p.call(peak[1],-.35),tip,color)
				KIT.disc(st,Vector3(tip.x,tip.y,z-.01),.24*scale,color,Vector3.FORWARD,12)
			KIT.disc(st,Vector3(at.x,at.y-.7*scale,z-.12),.28*scale,Color("b8475e"),Vector3.FORWARD,16)
		_:
			var sun := Vector3(at.x,at.y,z)
			KIT.disc(st,sun,1.15*scale,color,Vector3.FORWARD,24)
			var frame := KIT.axis_frame(Vector3.FORWARD)
			for i in range(12):
				var angle := TAU*i/12.0
				var tip: Vector3=sun+(frame[0]*cos(angle)+frame[1]*sin(angle))*2.05*scale
				var left: Vector3=sun+(frame[0]*cos(angle-.16)+frame[1]*sin(angle-.16))*1.32*scale
				var right: Vector3=sun+(frame[0]*cos(angle+.16)+frame[1]*sin(angle+.16))*1.32*scale
				KIT.triangle(st,right,left,tip,color)

# Glass balustrade along the front of the terrace, under a steel handrail.
func balustrade() -> void:
	var st := KIT.begin()
	var z := STAND_FRONT+.08
	KIT.quad(st,Vector3(STAND_HALF,3.5,z),Vector3(-STAND_HALF,3.5,z),Vector3(-STAND_HALF,4.5,z),Vector3(STAND_HALF,4.5,z),Color(.78,.86,.88))
	var glass := StandardMaterial3D.new()
	glass.vertex_color_use_as_albedo=true
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color=Color(1,1,1,.16)
	glass.roughness=.04
	glass.metallic_specular=.7
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	KIT.finish(st,glass,self,false)
	var rail := KIT.begin()
	var steel := KIT.made_of(STEEL,KIT.METAL)
	KIT.sweep(rail,[Vector3(-STAND_HALF,4.56,z),Vector3(STAND_HALF,4.56,z)] as Array[Vector3],.035,steel,10)
	var x := -STAND_HALF
	while x<=STAND_HALF+.01:
		KIT.rounded_box(rail,Vector3(x,4.0,z),Vector3(.05,1.12,.08),.015,steel)
		x+=1.625
	KIT.finish(rail,KIT.structure(false),self,false)

# One moulded seat on every place of every row (the people sit on them).
func build_seats() -> void:
	var st := KIT.begin()
	var green := KIT.made_of(SEAT_GREEN,KIT.SEAT)
	KIT.rounded_box(st,Vector3(0,.41,-.02),Vector3(.46,.06,.4),.025,green)
	KIT.rounded_box(st,Vector3(0,.66,.2),Vector3(.46,.44,.05),.025,green,Basis(Vector3.RIGHT,.18))
	KIT.rounded_box(st,Vector3(0,.2,.12),Vector3(.08,.4,.08),.02,KIT.made_of(CLADDING,KIT.METAL))
	var mesh := st.commit()
	mesh.surface_set_material(0,KIT.structure(false))
	KIT.multimesh(mesh,seats,self,false)

func promenade(st: SurfaceTool) -> void:
	KIT.quad(st,Vector3(-57,.02,STAND_FRONT+1.75),Vector3(57,.02,STAND_FRONT+1.75),Vector3(57,.02,39.6),Vector3(-57,.02,39.6),KIT.made_of(STONE,KIT.PAVING))
	KIT.rounded_box(st,Vector3(0,.04,39.65),Vector3(114,.1,.18),.03,KIT.made_of(STONE.darkened(.08),KIT.CONCRETE))
	# Garden parasols stay clear of the finish-line camera positions.
	var spots: Array[Vector3]=[]
	for x in [-47.0,-41.0,-35.0,-29.0,-23.0,27.0,33.0,39.0,45.0,51.0]:
		spots.append(Vector3(x,0,41.4 if int(x)%2==0 else 42.6))
	var steel := KIT.made_of(STEEL,KIT.METAL)
	for i in range(spots.size()):
		var p: Vector3=spots[i]
		KIT.cylinder(st,p,p+Vector3(0,2.55,0),.035,steel,8)
		var cloth: Color=KIT.made_of(Color("f3efe6"),KIT.CANVAS)
		var trim: Color=KIT.made_of(DEEP_GREEN,KIT.CANVAS)
		KIT.canopy(st,p+Vector3(0,2.25,0),p+Vector3(0,2.85,0),1.55,[cloth,cloth.darkened(.03)],12)
		# A scalloped green valance under the canopy's rim.
		for k in range(12):
			var a0 := TAU*k/12.0
			var a1 := TAU*(k+1)/12.0
			var r := 1.55
			var q0 := p+Vector3(cos(a0)*r,2.25,sin(a0)*r)
			var q1 := p+Vector3(cos(a1)*r,2.25,sin(a1)*r)
			KIT.quad(st,q0,q1,q1-Vector3(0,.16,0),q0-Vector3(0,.16,0),trim)
			KIT.quad(st,q1,q0,q0-Vector3(0,.16,0),q1-Vector3(0,.16,0),trim)
		KIT.sphere(st,p+Vector3(0,2.9,0),.05,KIT.made_of(GOLD,KIT.GOLD_LEAF),4,8)
		KIT.cylinder(st,p,p+Vector3(0,.72,0),.04,steel,8)
		KIT.cylinder(st,p+Vector3(0,.72,0),p+Vector3(0,.76,0),.52,KIT.made_of(WHITE,KIT.PAINT),20)
		KIT.disc(st,p+Vector3(0,.76,0),.52,KIT.made_of(WHITE,KIT.PAINT),Vector3.UP,20)
		for k in range(2):
			if random.randf()<.7:
				var size := random.randf_range(.40,.45)
				var offset := Vector3(random.randf_range(-1.4,1.4),0,random.randf_range(-.9,.9))
				person(4+random.randi_range(0,1),p+offset,random.randf_range(-.5,.5),size,1)

func giant_screen(st: SurfaceTool) -> void:
	var c := SCREEN
	var steel := KIT.made_of(Color("8d9592"),KIT.METAL)
	var frame := KIT.made_of(Color("2b302e"),KIT.PAINT)
	for x in [-9.0,9.0]:
		KIT.rounded_box(st,c+Vector3(x,2.8,-.3),Vector3(1.1,5.6,1.1),.08,steel)
		KIT.rounded_box(st,c+Vector3(x,.1,-.3),Vector3(1.8,.2,1.8),.04,KIT.made_of(CONCRETE,KIT.CONCRETE))
	KIT.rounded_box(st,c+Vector3(0,10.6,-.3),Vector3(31.0,10.7,1.0),.12,frame)
	for y in [5.2,16.0]: KIT.rounded_box(st,c+Vector3(0,y,-.2),Vector3(31.3,.26,1.2),.08,KIT.made_of(WHITE,KIT.PAINT))
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size=Vector2(29.8,9.9)
	face.mesh=quad
	face.position=c+Vector3(0,10.6,.21)
	face.material_override=unlit(Color("0f211c"))
	face.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	var header := MeshInstance3D.new()
	var band := QuadMesh.new()
	band.size=Vector2(29.8,.12)
	header.mesh=band
	header.position=c+Vector3(0,12.85,.26)
	header.material_override=unlit(GOLD)
	add_child(header)
	label(board_title,c+Vector3(-7.4,14.25,.32),150,.0098,Color("f5d98f"))
	board_round=label("RACE 01",c+Vector3(9.0,14.25,.32),150,.0098,Color("f3efe2"))
	board_status=label("PLACE YOUR BETS",c+Vector3(0,11.7,.32),96,.0085,Color("9fd6ae"))
	var scale:=chip_step()/3.5
	for i in range(field):
		var chip := Node3D.new()
		chip.position=c+Vector3(chip_x(i),8.5,.3)
		var tile := MeshInstance3D.new()
		var tile_mesh := QuadMesh.new()
		tile_mesh.size=Vector2(2.9,2.9)*scale
		tile.mesh=tile_mesh
		tile.material_override=unlit(palette[i])
		chip.add_child(tile)
		var number := Label3D.new()
		number.text=str(i+1)
		number.font_size=150
		number.pixel_size=.0125*scale
		number.outline_size=0
		number.modulate=Color("fffaf0") if i in [0,3,7,8,9,11] else Color("1b2420")
		number.position.z=.05
		chip.add_child(number)
		add_child(chip)
		chips.append(chip)
		label(str(i+1),c+Vector3(chip_x(i),6.35,.32),72,.009*maxf(scale,.8),Color("c9c4b3"))

# Eight chips sit 3.5 apart; bigger fields share the same width.
func chip_step() -> float:
	return minf(3.5,28.0/field)

func chip_x(rank: int) -> float:
	return (rank-(field-1)*.5)*chip_step()

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
		chip.position.x=lerpf(chip.position.x,SCREEN.x+chip_x(rank),ease)

# A hospitality marquee: a peaked canvas roof on white poles, its eaves hung
# with a scalloped valance in club green, a pennant on the king pole.
func marquee(st: SurfaceTool, c: Vector3, size: float) -> void:
	var half := size*.5
	var eave := 2.7
	var apex := c+Vector3(0,eave+size*.36,0)
	var canvas := KIT.made_of(Color("f5f2ea"),KIT.CANVAS)
	var trim := KIT.made_of(Color("2c6a4e"),KIT.CANVAS)
	var steel := KIT.made_of(STEEL,KIT.METAL)
	var corners: Array[Vector3]=[c+Vector3(-half,eave,half),c+Vector3(half,eave,half),c+Vector3(half,eave,-half),c+Vector3(-half,eave,-half)]
	for i in range(4):
		var a: Vector3=corners[i]
		var b: Vector3=corners[(i+1)%4]
		KIT.cylinder(st,Vector3(a.x,0,a.z),a,.06,steel,8)
		# The roof sags a little between its seams: each face is a shallow fan.
		var mid := (a+b)*.5
		var outward := mid-c
		outward.y=0
		outward=outward.normalized()
		var belly := (mid+apex)*.5-outward*.12
		KIT.triangle(st,a,mid,belly,canvas)
		KIT.triangle(st,mid,b,belly,canvas)
		KIT.triangle(st,b,apex,belly,canvas)
		KIT.triangle(st,apex,a,belly,canvas)
		for tri: Array in [[a,mid,belly],[mid,b,belly],[b,apex,belly],[apex,a,belly]]:
			KIT.triangle(st,tri[1],tri[0],tri[2],KIT.made_of(Color("dcd8cd"),KIT.CANVAS))
		# Scalloped valance in club stripes under each eave.
		for k in range(8):
			var p0 := a.lerp(b,k/8.0)+outward*.03
			var p1 := a.lerp(b,(k+1)/8.0)+outward*.03
			var color: Color=trim if k%2==0 else canvas
			KIT.quad(st,p0-Vector3(0,.36,0),p1-Vector3(0,.36,0),p1,p0,color)
			for j in range(6):
				var t0 := j/6.0
				var t1 := (j+1)/6.0
				var q0 := p0.lerp(p1,t0)-Vector3(0,.36+sin(PI*t0)*.14,0)
				var q1 := p0.lerp(p1,t1)-Vector3(0,.36+sin(PI*t1)*.14,0)
				KIT.quad(st,q0,q1,p0.lerp(p1,t1)-Vector3(0,.36,0),p0.lerp(p1,t0)-Vector3(0,.36,0),color)
	KIT.cylinder(st,apex,apex+Vector3(0,1.6,0),.04,steel,6)
	KIT.sphere(st,apex+Vector3(0,1.66,0),.07,KIT.made_of(GOLD,KIT.GOLD_LEAF),4,8)
	flags.append({"top":apex+Vector3(.04,1.55,0),"length":1.5,"depth":.85})

func flagpole(st: SurfaceTool, base: Vector3, height: float, flag_length: float) -> void:
	var steel := KIT.made_of(STEEL,KIT.METAL)
	KIT.rounded_box(st,base+Vector3(0,.12,0),Vector3(.6,.24,.6),.04,KIT.made_of(CONCRETE,KIT.CONCRETE))
	KIT.cylinder(st,base,base+Vector3(0,height,0),.085,steel,10,.05)
	KIT.sphere(st,base+Vector3(0,height+.1,0),.12,KIT.made_of(GOLD,KIT.GOLD_LEAF),5,10)
	flags.append({"top":base+Vector3(.05,height-.12,0),"length":flag_length,"depth":flag_length*.56})

# Every flag in one mesh: a grid per flag, its hoist at the pole and its fly
# downwind; flag.gdshader waves and lights them.
func build_flags() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fly := Vector3(.92,0,.39).normalized()
	const ALONG := 18
	const DOWN := 7
	for i in range(flags.size()):
		var flag: Dictionary=flags[i]
		var top: Vector3=flag.top
		var length: float=flag.length
		var depth: float=flag.depth
		var color: Color=palette[i%palette.size()]
		color=Color.from_hsv(color.h,minf(color.s*1.25,1.0),color.v*.86)
		var phase := random.randf()
		for a in range(ALONG):
			for d in range(DOWN):
				var corners: Array[Vector2]=[Vector2(a,d),Vector2(a+1,d),Vector2(a+1,d+1),Vector2(a,d+1)]
				for index: int in [0,2,1,0,3,2]:
					var uv := Vector2(corners[index].x/ALONG,corners[index].y/DOWN)
					st.set_color(Color(color.srgb_to_linear().r,color.srgb_to_linear().g,color.srgb_to_linear().b,phase))
					st.set_normal(Vector3(-fly.z,0,fly.x))
					st.set_uv(uv)
					st.set_uv2(Vector2(length,depth))
					st.add_vertex(top+fly*uv.x*length-Vector3(0,uv.y*depth,0))
	var mesh := MeshInstance3D.new()
	mesh.mesh=st.commit()
	var mat := ShaderMaterial.new()
	mat.shader=FLAG_SHADER
	mat.set_shader_parameter("wind",.3 if reduce_motion else 1.0)
	mesh.material_override=mat
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cloth moves beyond its rest bounds.
	mesh.extra_cull_margin=2.0
	add_child(mesh)

func person(pose: int,p: Vector3,yaw: float,size: float,side: int) -> void:
	var hair := random.randi_range(0,1)
	var key := "%d:%d:%d" % [pose,hair,side]
	if not people.has(key): people[key]={"pose":pose,"hair":hair,"transforms":[],"colors":[]}
	people[key].transforms.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(size*random.randf_range(.92,1.10),size,size)),p))
	people[key].colors.append(Color(random.randf(),random.randf_range(.15,1),random.randf(),1.0 if random.randf()<.13 else 0.0))
	spectator_count+=1

# Appends a mesh's triangles as [position, normal, category] corners.
func append_mesh(corners: Array,mesh: ArrayMesh,offset: Vector3,hair: bool) -> void:
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
			corners.append([vertices[idx]+offset,normals[idx],category])

# Vertex clustering: every corner moves to the mean of its grid cell, and
# triangles that collapse or repeat are dropped. At phone resolution a spectator
# is a few pixels tall, so this keeps the silhouette and colours at a small
# fraction of the triangles.
static func weld(corners: Array,cell: float) -> Array:
	var sums: Dictionary = {}
	for corner in corners:
		var key := Vector3i((corner[0]/cell).floor())
		sums[key]=sums.get(key,Vector4.ZERO)+Vector4(corner[0].x,corner[0].y,corner[0].z,1.0)
	var welded: Array = []
	var seen: Dictionary = {}
	for t in range(0,corners.size(),3):
		var keys: Array = []
		for i in range(3): keys.append(Vector3i((corners[t+i][0]/cell).floor()))
		if keys[0]==keys[1] or keys[1]==keys[2] or keys[0]==keys[2]: continue
		# The same cells in the same winding are one triangle; the reverse
		# winding is the back of a thin part and stays.
		var names: Array = keys.map(func(key: Vector3i) -> String: return str(key))
		var first: int = names.find(names.min())
		var id: String = names[first]+names[(first+1)%3]+names[(first+2)%3]
		if seen.has(id): continue
		seen[id]=true
		var points: Array = keys.map(func(key: Vector3i) -> Vector3: var sum: Vector4=sums[key]; return Vector3(sum.x,sum.y,sum.z)/sum.w)
		var normal: Vector3 = corners[t][1]+corners[t+1][1]+corners[t+2][1]
		for i in range(3): welded.append([points[i],normal.normalized(),corners[t][2]])
	return welded

func person_mesh(pose: int,hair: int) -> ArrayMesh:
	var key := "person:%d:%d" % [pose,hair]
	if meshes.has(key): return meshes[key]
	var corners: Array = []
	append_mesh(corners,load("res://assets/venue/crowd/%s.obj" % POSES[pose]),Vector3.ZERO,false)
	var hair_name := "%s_Hairstyle_%d" % ["Male" if pose%2==0 else "Female",1 if hair==0 else 3]
	append_mesh(corners,load("res://assets/venue/crowd/%s.obj" % hair_name),HAIR_CENTERS[pose],true)
	if coarse: corners=weld(corners,WELD_CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner in corners:
		st.set_normal(corner[1])
		st.set_uv(Vector2(corner[2],0))
		st.set_color(Color.WHITE)
		st.add_vertex(corner[0])
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
