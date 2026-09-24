extends SceneTree
const MOTION=preload("res://scripts/race_motion.gd")
func _initialize() -> void:
	var clock=MOTION.new()
	clock.sync(12.0)
	var previous:=MOTION.progress(clock.seconds,1,44.5)
	var smallest:=INF
	var largest:=0.0
	for frame in range(600):
		# Four snapshots per second with arrival-time jitter.
		if frame%15==0: clock.sync(12.0+frame/60.0+sin(frame*.9)*.035)
		clock.advance(1.0/60.0)
		var current:=MOTION.progress(clock.seconds,1,44.5)
		var distance:=current-previous
		assert(distance>0,"A running horse must move forward on every frame")
		smallest=minf(smallest,distance)
		largest=maxf(largest,distance)
		previous=current
	assert(largest/smallest<2.0,"Snapshot arrival must not create stop-start motion")
	clock.sync(35.0)
	assert(is_equal_approx(clock.seconds,35.0),"Resume from a suspended tab must catch up")
	for id in range(1,9):
		var finish:=44.5+(id-1)*.65
		assert(MOTION.progress(finish-.01,id,finish)<1.0)
		assert(MOTION.progress(finish,id,finish)==1.0)
		assert(MOTION.track_progress(finish,id,finish)==1.0)
		var incoming_speed: float=(MOTION.progress(finish,id,finish)-MOTION.progress(finish-.001,id,finish))/.001
		var outgoing_speed: float=(MOTION.track_progress(finish+.001,id,finish)-1.0)/.001
		assert(absf(incoming_speed-outgoing_speed)<.0001,"Crossing must preserve each horse's incoming speed")
		var last_position:=1.0
		for step in range(1,81):
			var continued: float=MOTION.track_progress(finish+step*.1,id,finish)
			assert(continued>last_position,"Every horse must keep running beyond the finish, even after four seconds")
			assert(absf((continued-last_position)/.1-outgoing_speed)<.0001,"Run-out must not brake to a halt")
			last_position=continued
	# The special-move cut-in slows the field to about a third, then makes the
	# time back so the first horse still reaches the post at 44.6 seconds.
	assert(clock.presentation(39.5).is_equal_approx(Vector2(39.5,1)),"Normal speed until the cut-in")
	assert(absf(clock.presentation(40.3).y-.35)<.02,"The cut-in plays in slow motion")
	assert(clock.presentation(42.5).y>1.2,"The release rushes toward the post")
	var previous_visual:=clock.presentation(39.0).x
	for frame in range(1,661):
		var time:=39.0+frame/60.0
		var playback: Vector2=clock.presentation(time)
		assert(playback.x>=previous_visual-.00001,"Cinematic playback may hold but must never reverse")
		assert(playback.y>=-.00001 and playback.y<1.901,"Acceleration must stay within the intended playback range")
		previous_visual=playback.x
	for frame in range(73):
		assert(clock.presentation(44.6+frame/60.0).is_equal_approx(Vector2(44.5,0)),"Hold the crossing pose for the full 1.2-second camera orbit")
	var previous_speed:=0.0
	for frame in range(253):
		var playback: Vector2=clock.presentation(45.8+frame/60.0)
		assert(playback.y>=previous_speed-.00001,"The release must keep accelerating, never return to normal speed")
		previous_speed=playback.y
	assert(is_equal_approx(clock.presentation(50.0).y,1.9),"Acceleration reaches 1.9x at settlement")
	assert(clock.presentation(50.0).x>49.05,"All eight horses must cross before settlement")
	print("PASS: continuous movement with 4 Hz jittered snapshots; max/min frame distance=",largest/smallest)
	quit()
