extends SceneTree
const MOTION=preload("res://scripts/race_motion.gd")
func _initialize() -> void:
	var clock=MOTION.new()
	var plan:=MOTION.preview_plan()
	var lead:=int(plan.winner)
	clock.sync(12.0)
	var previous:=MOTION.plan_progress(plan,lead,clock.seconds)
	var smallest:=INF
	var largest:=0.0
	for frame in range(600):
		# Four snapshots per second with arrival-time jitter.
		if frame%15==0: clock.sync(12.0+frame/60.0+sin(frame*.9)*.035)
		clock.advance(1.0/60.0)
		var current:=MOTION.plan_progress(plan,lead,clock.seconds)
		var distance:=current-previous
		assert(distance>0,"A running horse must move forward on every frame")
		smallest=minf(smallest,distance)
		largest=maxf(largest,distance)
		previous=current
	assert(largest/smallest<2.0,"Snapshot arrival must not create stop-start motion")
	clock.sync(35.0)
	assert(is_equal_approx(clock.seconds,35.0),"Resume from a suspended tab must catch up")
	assert(absf(float(plan.finishTimes[lead])-44.5)<.001,"The winner reaches the post at 44.5 seconds")
	for index in range(8):
		var finish:=float(plan.finishTimes[index])
		assert(MOTION.plan_progress(plan,index,finish-.01)<1.0,"No horse reaches the post before its finish time")
		assert(absf(MOTION.plan_progress(plan,index,finish)-1.0)<.00002,"Each horse reaches the post at its finish time")
		var incoming_speed: float=(MOTION.plan_progress(plan,index,finish)-MOTION.plan_progress(plan,index,finish-.001))/.001
		var outgoing_speed: float=(MOTION.plan_progress(plan,index,finish+.001)-MOTION.plan_progress(plan,index,finish))/.001
		assert(absf(incoming_speed-outgoing_speed)<.0001,"Crossing must preserve each horse's incoming speed")
		var last_position:=MOTION.plan_progress(plan,index,finish)
		for step in range(1,81):
			var continued: float=MOTION.plan_progress(plan,index,finish+step*.1)
			assert(continued>last_position,"Every horse must keep running beyond the finish, even after four seconds")
			assert(absf((continued-last_position)/.1-outgoing_speed)<.0005,"Run-out must not brake to a halt")
			last_position=continued
		var start:=0.0
		for step in range(1,500):
			var now:=MOTION.plan_progress(plan,index,step*.1)
			assert(now>=start,"No horse ever runs backwards")
			start=now
	# The far side runs a touch ahead, banking the time the special-move cut-in
	# spends in slow motion at about a third; the release makes the rest back
	# so the first horse still reaches the post at 44.6 seconds.
	assert(clock.presentation(28.0).is_equal_approx(Vector2(28,1)),"Normal speed until the far side")
	for frame in range(619):
		assert(clock.presentation(28.0+frame/60.0).y<1.14,"Banking time before the cut-in must stay unnoticeable")
	for frame in range(154):
		assert(absf(clock.presentation(38.6+frame/60.0).y-.35)<.02,"The cut-in plays in slow motion for over two and a half seconds")
	assert(clock.presentation(42.5).y>1.2,"The release rushes toward the post")
	var previous_visual:=clock.presentation(28.0).x
	for frame in range(1,1321):
		var time:=28.0+frame/60.0
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
	assert(clock.presentation(50.0).x>float(plan.finishTimes.max()),"All eight horses must cross before settlement")
	print("PASS: continuous movement with 4 Hz jittered snapshots; max/min frame distance=",largest/smallest)
	quit()
