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
	var previous_visual:=42.0
	for frame in range(1,481):
		var time:=42.0+frame/60.0
		var playback: Vector2=clock.presentation(time)
		assert(playback.x>previous_visual,"Cinematic playback must never reverse")
		assert(playback.y>.4 and playback.y<1.8,"Cinematic speed must change within natural bounds")
		previous_visual=playback.x
	assert(is_equal_approx(clock.presentation(44.7).x,43.9))
	assert(clock.presentation(50.0)==Vector2(50,1),"Cinematic playback must rejoin the settlement clock")
	print("PASS: continuous movement with 4 Hz jittered snapshots; max/min frame distance=",largest/smallest)
	quit()
