extends Node3D

# A separate awards set leaves the actual race positions and finish order intact.
const HORSE = preload("res://scripts/asset_horse.gd")
var runners: Array[Node3D] = []
var order: Array[int] = []
var shown_round := -1
var slots := [Vector3(0,1.28,0), Vector3(-4.6,.83,0), Vector3(4.6,.53,0),
	Vector3(-6.4,3.6,-5),Vector3(-3.2,3.6,-5),Vector3(0,3.6,-5),Vector3(3.2,3.6,-5),Vector3(6.4,3.6,-5)]
var field_labels: Array[Label3D] = []

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
	block(Vector3(0,7,-9),Vector3(45,18,.5),dark)
	# Restrained gold architecture frames the three horses, not the surrounding track.
	for x in [-10.0,-7.8,7.8,10.0]:
		block(Vector3(x,4,-8.65),Vector3(.035,8,.04),gold)
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
	# A raised second tier keeps the rest of the field visible above the
	# foreground winners without widening their close-up composition.
	block(Vector3(0,1.8,-5),Vector3(17,3.6,3.6),dark)
	block(Vector3(0,3.56,-3.18),Vector3(17,.035,.035),stage)
	for rank in range(3,8):
		var label:=Label3D.new()
		label.font_size=64
		label.pixel_size=.004
		label.position=Vector3(slots[rank].x+.6,3.5,-3.16)
		label.modulate=Color("b9c7b2")
		add_child(label)
		field_labels.append(label)
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
	for rank in range(8):
		var horse:=HORSE.new()
		add_child(horse)
		horse.build(order[rank],colors[order[rank]])
		horse.position=slots[rank]
		horse.rotation.y=PI
		if rank>=3:
			horse.scale=Vector3.ONE*.72
			field_labels[rank-3].text="%d · #%d" % [rank+1,order[rank]+1]
		runners.append(horse)

func animate(time: float, delta: float) -> void:
	for horse in runners: horse.animate(time,0.0,false,true,delta)
