extends SceneTree

const HORSE = preload("res://scripts/asset_horse.gd")

func _initialize() -> void:
	call_deferred("verify_horse")

func verify_horse() -> void:
	var horse = HORSE.new()
	root.add_child(horse)
	horse.build(0,Color("e75d56"))
	var skeleton: Skeleton3D=horse.model.find_children("*","Skeleton3D",true,false)[0]
	var head := skeleton.find_bone("Head")
	# The CC0 rig names its trunk Body; the textured stallion's is Spine1.
	var body := skeleton.find_bone("Body") if skeleton.find_bone("Body")>=0 else skeleton.find_bone("Spine1")
	var head_world := skeleton.global_transform*skeleton.get_bone_global_pose(head).origin
	assert(head_world.z<-.5,"The imported horse must face along the course's -Z forward axis")
	assert(head_world.y>2.0 and head_world.y<3.1,"Model must fit the existing camera and lane scale")
	var rest := skeleton.get_bone_pose(body)
	var origin: Transform3D=horse.model.transform
	for i in range(61): horse.animate(i/60.0,1.0,true,false,1.0/60.0)
	assert(horse.current_clip=="Gallop","Racing must play the authored gallop")
	assert(not rest.is_equal_approx(skeleton.get_bone_pose(body)),"The rig must actually deform while running")
	for clip in ["Idle","Walk","Gallop"]:
		assert(horse.player.get_animation(clip).loop_mode==Animation.LOOP_LINEAR,"Locomotion must loop")
	for i in range(120): horse.animate(i/60.0,.7,false,false,1.0/60.0)
	assert(horse.current_clip=="Walk","Betting patrol must use the walk animation")
	for i in range(120): horse.animate(i/60.0,0.0,false,false,1.0/60.0)
	assert(horse.current_clip=="Idle","Line-up must settle into idle")
	assert(horse.model.transform.is_equal_approx(origin),"Animation must not move the race root off its lane")
	var other=HORSE.new()
	root.add_child(other)
	other.build(4,Color.WHITE)
	for i in range(120):
		horse.animate(i/60.0,1.0,true,false,1.0/60.0)
		other.animate(i/60.0,1.0,true,false,1.0/60.0)
	assert(absf(horse.player.current_animation_position-other.player.current_animation_position)>.02,"Horse strides must not march in lockstep")
	# At the field's pace a horse gallops at a racehorse's rhythm, not in slow motion.
	var cycle: float=horse.player.get_animation("Gallop").length
	var from: float=horse.player.current_animation_position
	for i in range(60):
		horse.position.z-=HORSE.GALLOP_PACE/60.0
		horse.animate(2.0+i/60.0,1.0,true,false,1.0/60.0)
	var strides: float=HORSE.GALLOP_TEMPO*horse.cadence
	var drift:=fposmod(horse.player.current_animation_position-from-strides*cycle+cycle*.5,cycle)-cycle*.5
	assert(absf(drift)<.01 and strides>1.9,"Racing pace must gallop at about two strides a second")
	other.queue_free()
	print("PASS: horse orientation, scale, authored gallop, walk, idle, loops and stable root")
	horse.queue_free()
	quit()
