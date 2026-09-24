extends SceneTree

const RACE = preload("res://scripts/race.gd")

func _initialize() -> void:
	call_deferred("verify_run_through")

func verify_run_through() -> void:
	var race = RACE.new()
	root.add_child(race)
	race.set_process(false)
	# Skip the intentional crossing freeze, then follow every frame to settlement.
	race.elapsed=106.2
	race._process(1.0/60.0)
	var finish_camera: Transform3D=race.camera.transform
	var finish_focus: Vector3=race.camera_focus
	var finish_fov: float=race.camera.fov
	var previous: Array[Vector3] = []
	for horse in race.horses: previous.append(horse.position)
	for frame in range(220):
		race._process(1.0/60.0)
		assert(race.phase=="racing")
		assert(race.camera.transform.is_equal_approx(finish_camera),"The finish camera must not chase runners or cut to a winner portrait")
		assert(race.camera_focus.is_equal_approx(finish_focus),"The camera must keep looking at the finish line")
		assert(is_equal_approx(race.camera.fov,finish_fov),"The locked finish shot must not continue zooming")
		for i in range(8):
			var horse=race.horses[i]
			assert(horse.position.distance_to(previous[i])>.05,"Every horse must keep advancing until the podium cut")
			assert(horse.current_clip=="Gallop","Crossing must never switch a racing horse to walk or idle")
			previous[i]=horse.position
		assert(race.dust[0].visible,"The winner must keep kicking up dust after crossing")
	assert(float(race.track_positions[0])>1.13,"The winner must run beyond the old stopping distance")
	assert(float(race.visual_positions[0])==1.0,"Official finish progress must remain clamped")
	race.elapsed=109.99
	race._process(.02)
	assert(race.phase=="result" and race.podium.visible,"Continuous running must still hand off to the podium")
	for horse in race.horses: assert(not horse.visible)
	print("PASS: fixed finish camera; all eight horses keep galloping until the podium")
	race.queue_free()
	quit()
