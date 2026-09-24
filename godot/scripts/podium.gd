extends Node3D

# A separate awards set leaves the actual race positions and finish order intact.
const HORSE = preload("res://scripts/asset_horse.gd")
var runners: Array[Node3D] = []
var order: Array[int] = []
var shown_round := -1
var slots := [Vector3(0,1.28,0), Vector3(-4.6,.83,0), Vector3(4.6,.53,0)]

func surface(color: String, metallic := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color(color)
	mat.roughness=.6 if metallic else .95
	mat.metallic=.55 if metallic else 0.0
	return mat

func block(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size=size
	var node := MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=mat
	node.position=pos
	add_child(node)

func _ready() -> void:
	position=Vector3(0,80,0)
	visible=false
	var dark:=surface("152b26")
	var stage:=surface("29483b")
	var gold:=surface("c8a85e",true)
	block(Vector3(0,-.2,0),Vector3(50,.4,45),dark)
	block(Vector3(0,7,-5),Vector3(45,18,.5),dark)
	# Restrained gold architecture frames the three horses, not the surrounding track.
	for x in [-10.0,-7.8,7.8,10.0]:
		block(Vector3(x,4,-4.65),Vector3(.035,8,.04),gold)
	block(Vector3(0,.06,0),Vector3(15.8,.12,6.2),stage)
	block(Vector3(0,.13,3.1),Vector3(15.8,.025,.04),gold)
	var metals: Array[Material]=[gold,surface("a8b8b8",true),surface("b28c68",true)]
	for rank in range(3):
		var slot: Vector3=slots[rank]
		block(Vector3(slot.x,slot.y*.5,slot.z),Vector3(4.35,slot.y,4.5),stage)
		block(Vector3(slot.x,slot.y-.055,2.26),Vector3(4.35,.075,.035),metals[rank])
		var numeral:=Label3D.new()
		numeral.text=str(rank+1)
		numeral.font_size=112
		numeral.pixel_size=.006
		numeral.position=Vector3(slot.x,slot.y*.48,2.28)
		numeral.modulate=[Color("f6d48a"),Color("dce7e4"),Color("d8b291")][rank]
		add_child(numeral)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-35,-28,0)
	key.light_color=Color("ffe7bd")
	key.light_energy=.35
	key.light_cull_mask=2
	add_child(key)
	var rim:=DirectionalLight3D.new()
	rim.rotation_degrees=Vector3(-30,155,0)
	rim.light_color=Color("dfedee")
	rim.light_energy=.25
	rim.light_cull_mask=2
	add_child(rim)

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
		horse.position=slots[rank]
		horse.rotation.y=PI
		runners.append(horse)

func animate(time: float, delta: float) -> void:
	for horse in runners: horse.animate(time,0.0,false,true,delta)
