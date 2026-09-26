extends SceneTree

const RACE = preload("res://scripts/race.gd")

func _initialize() -> void:
	call_deferred("verify_gate")

func verify_gate() -> void:
	var race = RACE.new()
	root.add_child(race)
	race.set_process(false)
	# Loaded and waiting: every horse in its own stall behind shut doors.
	race.elapsed=58.0
	race._process(1.0/60.0)
	assert(race.gate.visible and race.gate.doors.size()==24,"Twelve stalls stand at the line before the off")
	assert(is_zero_approx(race.gate.opened),"The doors stay shut until the off")
	for i in range(8):
		var horse: Node3D=race.horses[i]
		assert(absf(horse.position.z-race.course.stall_radius(i))<.02,"Each runner waits in its own stall")
	# The off: the doors spring open before the field has moved a stride.
	race.elapsed=59.99
	for frame in range(20): race._process(1.0/60.0)
	assert(race.phase=="racing" and race.gate.opened>.99,"The doors are wide open within a third of a second")
	# Clear of the stalls, each runner fans out to its own lane on the straight.
	for frame in range(250): race._process(1.0/60.0)
	var checked:=0
	for i in range(8):
		var p:=float(race.track_positions[i])
		if p<=.06 or p>=.09: continue
		assert(absf(race.horses[i].position.z-race.course.lane_radius(i))<.02,"Each runner has reached its lane")
		checked+=1
	assert(checked>=5,"Most of the field is out on the straight")
	# The first cut away leaves the line open for the finish.
	race.elapsed=67.5
	race._process(1.0/60.0)
	assert(not race.gate.visible,"The gate is cleared at the first cut")
	race.elapsed=110.5
	race._process(1.0/60.0)
	assert(not race.gate.visible,"No gate on the line at the podium")
	race.elapsed=121.0
	race._process(1.0/60.0)
	assert(race.gate.visible and is_zero_approx(race.gate.opened),"The next round's gate is back, shut")
	print("PASS: twelve-stall gate loads, springs open at the off, and is cleared before the finish")
	race.queue_free()
	quit()
