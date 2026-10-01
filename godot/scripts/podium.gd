extends Node3D

# A separate winner's circle leaves the actual race positions and finish order
# intact. Only the top three horses stand here; the champion wears the garland.
# The set: polished marble steps edged in gold on an inlaid marble round, a red
# carpet running out toward the lens, and behind them a curved wall of green
# damask between marble pilasters, banked with flowers, the cup's crest over
# the champion. The wall darkens upward so the overlaid heading keeps its
# contrast.
const HORSE = preload("res://scripts/asset_horse.gd")
const KIT = preload("res://scripts/mesh_kit.gd")
const MARBLE = Color("f2ede3")
const VEINED = Color("d8cebd")
const GOLD = Color("d8b25e")
const DAMASK = Color("1e4232")
const FLOOR = Color("9b9283")
const CARPET = Color("8e1a29")
const PLAQUE = Color("173527")
var runners: Array[Node3D] = []
var order: Array[int] = []
var shown_round := -1
var slots := [Vector3(0,1.28,0), Vector3(-4.6,.83,0), Vector3(4.6,.53,0)]
const WALL_CENTER := Vector3(0,0,11.0)
const WALL_RADIUS := 16.0
const WALL_SPAN := 1.1
const PANELS := 11

func _ready() -> void:
	position=Vector3(0,80,0)
	visible=false
	var st := KIT.begin()
	build_ground(st)
	build_wall(st)
	build_podium(st)
	KIT.finish(st,KIT.structure(false),self)
	build_beds()
	# Warm pool of light on the champion; soft key and rim for all three.
	var spot:=SpotLight3D.new()
	spot.position=Vector3(0,11.5,7.5)
	spot.look_at_from_position(spot.position,Vector3(0,1.4,0))
	spot.light_color=Color("ffe2a8")
	spot.light_energy=2.4
	spot.spot_range=24.0
	spot.spot_angle=21.0
	spot.spot_attenuation=.6
	add_child(spot)
	# Wall washers light the damask evenly, whatever the sun is doing.
	for x: float in [-7.0,7.0]:
		var wash:=SpotLight3D.new()
		wash.position=Vector3(x,9.0,4.0)
		wash.look_at_from_position(wash.position,Vector3(x*1.5,3.0,-3.5))
		wash.light_color=Color("fff0d6")
		wash.light_energy=1.6
		wash.spot_range=20.0
		wash.spot_angle=48.0
		wash.spot_attenuation=.8
		wash.light_cull_mask=1
		add_child(wash)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-35,-28,0)
	key.light_color=Color("ffe7bd")
	key.light_energy=.35
	key.light_cull_mask=2
	add_child(key)
	var rim:=DirectionalLight3D.new()
	rim.rotation_degrees=Vector3(-30,155,0)
	rim.light_color=Color("dfedee")
	rim.light_energy=.3
	rim.light_cull_mask=2
	add_child(rim)

func build_ground(st: SurfaceTool) -> void:
	var lawn := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Deep enough toward the camera that a tall phone frame still ends on lawn.
	plane.size=Vector2(140,150)
	lawn.mesh=plane
	lawn.position=Vector3(0,-.01,40)
	var mat := KIT.ground(0,Color("4f7428"),Color("7f9f3f"))
	mat.set_shader_parameter("band",3.0)
	lawn.material_override=mat
	add_child(lawn)
	# An inlaid marble round with a gold ring, and the carpet out to the lens.
	var center := Vector3(0,0,1.2)
	KIT.cylinder(st,center,center+Vector3(0,.05,0),10.2,KIT.made_of(VEINED,KIT.MARBLE),72)
	KIT.disc(st,center+Vector3(0,.05,0),10.2,KIT.made_of(VEINED,KIT.MARBLE),Vector3.UP,72)
	KIT.cylinder(st,center+Vector3(0,.05,0),center+Vector3(0,.056,0),9.75,KIT.made_of(GOLD,KIT.GOLD_LEAF),72)
	KIT.disc(st,center+Vector3(0,.056,0),9.75,KIT.made_of(GOLD,KIT.GOLD_LEAF),Vector3.UP,72)
	KIT.disc(st,center+Vector3(0,.062,0),9.6,KIT.made_of(FLOOR,KIT.MARBLE),Vector3.UP,72)
	KIT.rounded_box(st,Vector3(0,.075,16.0),Vector3(4.4,.03,27.6),.01,KIT.made_of(CARPET,KIT.CANVAS))
	for x: float in [-2.1,2.1]: KIT.rounded_box(st,Vector3(x,.09,16.0),Vector3(.12,.012,27.6),.004,KIT.made_of(GOLD,KIT.GOLD_LEAF))

func wall_point(a: float, inset := 0.0) -> Vector3:
	return WALL_CENTER+Vector3(sin(a),0,-cos(a))*(WALL_RADIUS-inset)

func build_wall(st: SurfaceTool) -> void:
	var gold := KIT.made_of(GOLD,KIT.GOLD_LEAF)
	var marble := KIT.made_of(MARBLE,KIT.MARBLE)
	for i in range(PANELS):
		var a0 := lerpf(-WALL_SPAN,WALL_SPAN,float(i)/PANELS)
		var a1 := lerpf(-WALL_SPAN,WALL_SPAN,float(i+1)/PANELS)
		var p0 := wall_point(a0)
		var p1 := wall_point(a1)
		var normal := (p1-p0).cross(Vector3.UP).normalized()
		# Damask, darkening upward into shadow above the cornice.
		for band: Array in [[0.0,9.2,1.0,.9],[9.2,16.0,.62,.3]]:
			var low: Color=KIT.made_of(DAMASK*float(band[2]),KIT.DAMASK)
			var high: Color=KIT.made_of(DAMASK*float(band[3]),KIT.DAMASK)
			var y0: float=band[0]
			var y1: float=band[1]
			for corner: Array in [[p0,y0,low],[p1+Vector3(0,y1,0),y1,high],[p1,y0,low],[p0,y0,low],[p0+Vector3(0,y1,0),y1,high],[p1+Vector3(0,y1,0),y1,high]]:
				KIT.vertex(st,Vector3(corner[0].x,corner[1],corner[0].z),normal,corner[2])
		# A gold moulding frames each panel between the pilasters.
		var mid := (a0+a1)*.5
		var half := (a1-a0)*.5-.07
		var frame_y := [1.6,8.3]
		for y: float in frame_y:
			var arc: Array[Vector3]=[]
			for k in range(7): arc.append(wall_point(lerpf(mid-half,mid+half,k/6.0),.06)+Vector3(0,y,0))
			KIT.sweep(st,arc,.035,gold,6)
		for edge: float in [mid-half,mid+half]:
			var at := wall_point(edge,.06)
			KIT.sweep(st,[at+Vector3(0,1.6,0),at+Vector3(0,8.3,0)] as Array[Vector3],.035,gold,6)
	# Marble pilasters with gilded capitals; a marble cornice above.
	for i in range(PANELS+1):
		var a := lerpf(-WALL_SPAN,WALL_SPAN,float(i)/PANELS)
		var at := wall_point(a,.18)
		var basis := Basis(Vector3.UP,-a)
		KIT.rounded_box(st,at+Vector3(0,4.6,0),Vector3(.62,9.2,.36),.05,marble,basis)
		KIT.rounded_box(st,at+Vector3(0,.25,0),Vector3(.8,.5,.48),.05,marble,basis)
		KIT.rounded_box(st,at+Vector3(0,8.75,.0),Vector3(.8,.3,.46),.06,gold,basis)
	for i in range(PANELS*2):
		var a0 := lerpf(-WALL_SPAN,WALL_SPAN,float(i)/(PANELS*2))
		var a1 := lerpf(-WALL_SPAN,WALL_SPAN,float(i+1)/(PANELS*2))
		var mid := wall_point((a0+a1)*.5,.3)
		var length := wall_point(a0).distance_to(wall_point(a1))+.06
		KIT.rounded_box(st,mid+Vector3(0,9.45,0),Vector3(length,.5,.6),.08,marble,Basis(Vector3.UP,-(a0+a1)*.5))
		KIT.rounded_box(st,mid+Vector3(0,9.16,.02),Vector3(length,.08,.66),.03,gold,Basis(Vector3.UP,-(a0+a1)*.5))
	# The cup's crest on the central panels, over the champion.
	var crest_at := wall_point(0.0,.1)
	KIT.rounded_box(st,crest_at+Vector3(0,6.9,0),Vector3(2.8,1.15,.08),.04,gold)
	KIT.rounded_box(st,crest_at+Vector3(0,6.9,.05),Vector3(2.64,.99,.08),.05,KIT.made_of(PLAQUE,KIT.PAINT))
	var title := Label3D.new()
	title.text="WINNER"
	title.font_size=96
	title.pixel_size=.0058
	title.outline_size=0
	title.modulate=Color("f0d48c")
	title.position=crest_at+Vector3(0,6.9,.1)
	add_child(title)

# Banked flowers along the foot of the wall: crimson, then white in front.
func build_beds() -> void:
	for bed: Array in [[.85,2.75,Color("2a4521"),Color("b31d33"),.75],[3.5,1.7,Color("2c4a24"),Color("f1ece0"),.3]]:
		var inset: float=bed[0]
		var depth: float=bed[1]
		var height: float=bed[4]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := 40
		for i in range(steps):
			var a0 := lerpf(-WALL_SPAN+.04,WALL_SPAN-.04,float(i)/steps)
			var a1 := lerpf(-WALL_SPAN+.04,WALL_SPAN-.04,float(i+1)/steps)
			for k in range(4):
				var t0 := k/4.0
				var t1 := (k+1)/4.0
				var corners: Array=[]
				for pair: Array in [[a0,t0],[a1,t0],[a1,t1],[a0,t1]]:
					var t: float=pair[1]
					var p := wall_point(float(pair[0]),inset+t*depth)
					corners.append(Vector3(p.x,.06+height*pow(1.0-t,.6),p.z))
				for index: int in [0,2,1,0,3,2]:
					st.set_normal(Vector3.UP)
					st.add_vertex(corners[index])
		var mesh := MeshInstance3D.new()
		mesh.mesh=st.commit()
		mesh.material_override=KIT.ground(4,bed[2],bed[3])
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

func build_podium(st: SurfaceTool) -> void:
	var gold := KIT.made_of(GOLD,KIT.GOLD_LEAF)
	for rank in range(3):
		var slot: Vector3=slots[rank]
		var h: float=slot.y
		KIT.rounded_box(st,Vector3(slot.x,.07,slot.z),Vector3(4.6,.14,4.75),.04,KIT.made_of(VEINED,KIT.MARBLE))
		KIT.rounded_box(st,Vector3(slot.x,h*.5,slot.z),Vector3(4.35,h,4.5),.06,KIT.made_of(MARBLE,KIT.MARBLE))
		# A gilded fillet under the top edge, and a plaque on the face.
		KIT.rounded_box(st,Vector3(slot.x,h-.09,slot.z+2.253),Vector3(4.2,.05,.02),.008,gold)
		var plaque_h := minf(.62,h-.24)
		var plaque_y := (h-.1)*.5+.02
		KIT.rounded_box(st,Vector3(slot.x,plaque_y,slot.z+2.26),Vector3(plaque_h*1.5,plaque_h,.03),.012,gold)
		KIT.rounded_box(st,Vector3(slot.x,plaque_y,slot.z+2.272),Vector3(plaque_h*1.5-.06,plaque_h-.06,.03),.01,KIT.made_of(PLAQUE,KIT.PAINT))
		var numeral:=Label3D.new()
		numeral.text=str(rank+1)
		numeral.font_size=96
		numeral.pixel_size=plaque_h*.8/96.0
		numeral.outline_size=0
		numeral.position=Vector3(slot.x,plaque_y,slot.z+2.29)
		numeral.modulate=Color("f0d48c")
		add_child(numeral)

func present(finish_times: Array, colors: Array, round_id: int) -> void:
	visible=true
	if shown_round==round_id: return
	shown_round=round_id
	for horse in runners:
		remove_child(horse)
		horse.queue_free()
	runners.clear()
	order.assign(range(finish_times.size()))
	order.sort_custom(func(a: int,b: int) -> bool: return float(finish_times[a])<float(finish_times[b]))
	for rank in range(3):
		var horse:=HORSE.new()
		add_child(horse)
		horse.build(order[rank],colors[order[rank]])
		if rank==0: horse.add_garland()
		horse.position=slots[rank]
		horse.rotation.y=PI
		runners.append(horse)

func animate(time: float, delta: float) -> void:
	for horse in runners: horse.animate(time,0.0,false,true,delta)
