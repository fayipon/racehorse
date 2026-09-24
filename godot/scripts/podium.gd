extends Node3D

# A separate winner's circle leaves the actual race positions and finish order
# intact. Only the top three horses stand here; the champion wears the garland.
const HORSE = preload("res://scripts/asset_horse.gd")
const KIT = preload("res://scripts/mesh_kit.gd")
const LAWN = preload("res://shaders/lawn.gdshader")
const HEDGE = preload("res://shaders/hedge.gdshader")
const MARBLE = Color("f3eee3")
const STONE = Color("e2d9c6")
const GOLD = Color("dcb45c")
const STUDIO = Color("4d8d6c")
const MEDALS = [Color("e2bb55"),Color("c9d2d3"),Color("c98f60")]
var runners: Array[Node3D] = []
var order: Array[int] = []
var shown_round := -1
var slots := [Vector3(0,1.28,0), Vector3(-4.6,.83,0), Vector3(4.6,.53,0)]

func _ready() -> void:
	position=Vector3(0,80,0)
	visible=false
	build_ground()
	build_backdrop()
	build_podium()
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

func build_ground() -> void:
	var lawn := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(60,50)
	lawn.mesh=plane
	lawn.position=Vector3(0,-.01,0)
	var mat := ShaderMaterial.new()
	mat.shader=LAWN
	mat.set_shader_parameter("grass_dark",Color("3d7433"))
	mat.set_shader_parameter("grass_light",Color("6f9d4a"))
	mat.set_shader_parameter("band",3.0)
	lawn.material_override=mat
	add_child(lawn)
	var st := KIT.begin()
	# The winner's circle: a stone ring with a gold inlay around a green carpet.
	KIT.disc(st,Vector3(0,.012,1.2),10.2,STONE,Vector3.UP,64)
	KIT.disc(st,Vector3(0,.018,1.2),9.6,GOLD,Vector3.UP,64)
	KIT.disc(st,Vector3(0,.024,1.2),9.4,Color("3d7d50"),Vector3.UP,64)
	KIT.finish(st,KIT.painted(.9,.15),self,false)

func build_backdrop() -> void:
	var st := KIT.begin()
	var center := Vector3(0,0,11.0)
	var radius := 16.0
	var panels := 14
	# A curved emerald wall wraps the set so no shot sees past its edges. It is
	# unlit and darkens upward, so the sun direction never darkens one side and
	# the overlaid heading keeps its contrast.
	for i in range(panels):
		var a0 := lerpf(-1.1,1.1,float(i)/panels)
		var a1 := lerpf(-1.1,1.1,float(i+1)/panels)
		var p0 := center+Vector3(sin(a0),0,-cos(a0))*radius
		var p1 := center+Vector3(sin(a1),0,-cos(a1))*radius
		var base := STUDIO if i%2==0 else STUDIO.lightened(.03)
		var low := base.darkened(.12)
		var high := base.darkened(.4)
		var normal := (p1-p0).cross(Vector3.UP).normalized()
		for corner: Array in [[p0,low],[p1+Vector3(0,15,0),high],[p1,low],[p0,low],[p0+Vector3(0,15,0),high],[p1+Vector3(0,15,0),high]]:
			KIT.vertex(st,corner[0],normal,corner[1])
		KIT.cylinder(st,p1+Vector3(0,.8,0),p1+Vector3(0,15,0),.05,GOLD.darkened(.1),6)
		KIT.box(st,p0.lerp(p1,.5)+Vector3(0,14.6,0),Vector3(p0.distance_to(p1)+.1,.8,.5),STONE,Basis(Vector3.UP,-(a0+a1)*.5))
	var studio := KIT.painted()
	studio.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	KIT.finish(st,studio,self,false)
	# Clipped topiary in white planters frames the podium.
	var planters := KIT.begin()
	for x in [-9.2,9.2]:
		var pot := Vector3(x,0,-1.2)
		KIT.cylinder(planters,pot,pot+Vector3(0,1.1,0),.62,MARBLE,16,.78)
		KIT.cylinder(planters,pot+Vector3(0,1.1,0),pot+Vector3(0,1.22,0),.84,GOLD,16)
		KIT.cylinder(planters,pot+Vector3(0,1.2,0),pot+Vector3(0,3.9,0),.95,Color("4f8a3a"),12,.05)
	KIT.finish(planters,KIT.painted(.82,.22),self)
	var hedge := KIT.begin()
	for i in range(18):
		var a0 := lerpf(-1.0,1.0,float(i)/18)
		var a1 := lerpf(-1.0,1.0,float(i+1)/18)
		var p0 := center+Vector3(sin(a0),0,-cos(a0))*(radius-.9)
		var p1 := center+Vector3(sin(a1),0,-cos(a1))*(radius-.9)
		var tangent := (p1-p0).normalized()
		KIT.box(hedge,(p0+p1)*.5+Vector3(0,.55,0),Vector3(p0.distance_to(p1)+.08,1.1,1.1),Color.WHITE,Basis(tangent,Vector3.UP,tangent.cross(Vector3.UP)))
	var leaves := ShaderMaterial.new()
	leaves.shader=HEDGE
	leaves.set_shader_parameter("leaf_dark",Color("2a5323"))
	leaves.set_shader_parameter("leaf_light",Color("6c9a45"))
	KIT.finish(hedge,leaves,self)

func build_podium() -> void:
	var st := KIT.begin()
	for rank in range(3):
		var slot: Vector3=slots[rank]
		KIT.box(st,Vector3(slot.x,slot.y*.5,slot.z),Vector3(4.35,slot.y,4.5),MARBLE)
		KIT.box(st,Vector3(slot.x,slot.y-.05,slot.z+2.2),Vector3(4.37,.1,.14),GOLD)
		# Medallions scale with each step so the lowest one stays on its face.
		var radius:=minf(.42,slot.y*.5-.05)
		var medal := Vector3(slot.x,slot.y*.5-.02,slot.z+2.26)
		KIT.disc(st,medal,radius,GOLD,Vector3.BACK,24)
		KIT.disc(st,medal+Vector3(0,0,.012),radius*.86,MEDALS[rank],Vector3.BACK,24)
		var numeral:=Label3D.new()
		numeral.text=str(rank+1)
		numeral.font_size=96
		numeral.pixel_size=radius*1.25/96.0
		numeral.outline_size=0
		numeral.position=medal+Vector3(0,0,.03)
		numeral.modulate=Color("3b3322")
		add_child(numeral)
	KIT.finish(st,KIT.painted(.55,.35),self)

func present(finish_times: Array, colors: Array, round_id: int) -> void:
	visible=true
	if shown_round==round_id: return
	shown_round=round_id
	for horse in runners:
		remove_child(horse)
		horse.queue_free()
	runners.clear()
	order.assign([0,1,2,3,4,5,6,7])
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
