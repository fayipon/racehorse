extends SceneTree

const RACE = preload("res://scripts/race.gd")

func _initialize() -> void:
	call_deferred("verify_paddock")

func verify_paddock() -> void:
	var race = RACE.new()
	root.add_child(race)
	race.set_process(false)
	race.elapsed=0.0
	race._process(1.0/30.0)
	var previous: Array[Vector3]=[]
	for horse in race.horses: previous.append(horse.position)
	var moods := {}
	var walked := 0
	for frame in range(1,1605):
		race._process(1.0/30.0)
		assert(race.phase=="betting")
		for i in range(8):
			var horse: Node3D=race.horses[i]
			var velocity:=(horse.position-previous[i])*30.0
			previous[i]=horse.position
			moods[horse.idle_clip]=true
			if frame>30 and velocity.length()>.35:
				walked+=1
				var facing:=-horse.basis.z
				if facing.angle_to(velocity.normalized())>=1.75:
					push_error("horse %d moved %.2f m/s at %.0f degrees off its facing at %.2fs" % [i,velocity.length(),rad_to_deg(facing.angle_to(velocity.normalized())),race.betting_clock])
					assert(false,"A walking horse must face where it goes, not back up")
			if frame>30 and horse.current_clip!="Walk" and velocity.length()>=.15:
				push_error("horse %d slid %.2f m/s in %s at %.2fs" % [i,velocity.length(),horse.current_clip,race.betting_clock])
				assert(false,"A standing horse must not slide")
			if i<7:
				var other: Node3D=race.horses[i+1]
				if absf(horse.position.x-other.position.x)<2.2:
					assert(other.position.z-horse.position.z>.95,"Neighbours must not walk through each other")
	assert(walked>2000,"Horses should spend a good part of betting on the move")
	assert(moods.size()>=3,"Standing horses should graze, look around or rest, not only idle")
	for i in range(8):
		var horse: Node3D=race.horses[i]
		assert(absf(horse.position.x+race.NOSE)<.05,"Every nose lines up on the start line")
		assert(absf(horse.position.z-race.course.lane_radius(i))<.02,"Every horse is back in its lane")
		assert(absf(angle_difference(horse.rotation.y,-PI/2))<.35,"Every horse faces down the course")
	print("PASS: natural paddock stroll with %d idle behaviours; no backing up or overlaps; lined up on time" % moods.size())
	race.queue_free()
	quit()
