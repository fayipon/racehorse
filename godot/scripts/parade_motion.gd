extends RefCounted

static func preview_plan(seed_value: int) -> Array:
	var random:=RandomNumberGenerator.new()
	random.seed=seed_value
	var plan: Array=[]
	for lane in range(8):
		var segments: Array=[]
		var time:=0.0
		var x:=random.randf_range(-9,-2)
		while time<47:
			var end:=minf(47,time+random.randf_range(.7,3.8))
			segments.append({"start":time,"end":end,"from":x,"to":x})
			time=end
			if time>=47: break
			end=minf(47,time+random.randf_range(4.8,8.3))
			var destination:=x if 47-time<1.5 else random.randf_range(-4,-1) if x<-5.5 else random.randf_range(-10.5,-7)
			segments.append({"start":time,"end":end,"from":x,"to":destination})
			x=destination
			time=end
		plan.append(segments)
	return plan

# The React-generated per-round itinerary also drives the minimap.
static func sample(time: float, segments: Array) -> Vector2:
	if segments.is_empty(): return Vector2(-5.5,0)
	var segment: Dictionary=segments[-1]
	for entry in segments:
		if minf(time,47.0)<=float(entry.end):
			segment=entry
			break
	var duration:=float(segment.end)-float(segment.start)
	var t:=clampf((minf(time,47.0)-float(segment.start))/duration,0,1)
	var easing:=t*t*t*(10+t*(-15+6*t))
	var distance:=float(segment.to)-float(segment.from)
	var x:=float(segment.from)+distance*easing
	var speed:=distance*30*t*t*(1-t)*(1-t)/duration
	if time>=48.0:
		t=clampf((time-48.0)/5.0,0,1)
		speed=-x*6*t*(1-t)/5.0
		x*=1-t*t*(3-2*t)
	return Vector2(x,speed)
