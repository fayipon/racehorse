extends RefCounted

# Native preview only: mirrors makeParadePlan in src/course.ts. In the browser
# React sends its per-round plan, which also drives the minimap.
static func preview_plan(seed_value: int, field: int) -> Array:
	var random:=RandomNumberGenerator.new()
	random.seed=seed_value
	var plan: Array=[]
	for lane in range(field):
		var segments: Array=[]
		var time:=0.0
		var x:=random.randf_range(-10,-2)
		var lat:=0.0
		var heading:=1.0 if random.randf()<.5 else -1.0
		while time<47:
			var mood:=random.randi_range(0,3)
			var pause_end:=minf(47,time+(random.randf_range(3.5,6.0) if mood==3 else random.randf_range(1.0,4.0)))
			segments.append({"start":time,"end":pause_end,"from":x,"to":x,"lat":lat,"mood":mood})
			time=pause_end
			if time>=47: break
			if random.randf()<.35: heading=-heading
			var distance:=random.randf_range(1.6,6.2)
			var destination:=clampf(x+heading*distance,-10.5,-1)
			if absf(destination-x)<1.2:
				heading=-heading
				destination=clampf(x+heading*distance,-10.5,-1)
			var next_lat:=random.randf_range(-.45,.45)
			var end:=minf(47,time+absf(destination-x)/random.randf_range(.6,.85))
			var hold:=47-time<1.5
			segments.append({"start":time,"end":end,"from":x,"to":x if hold else destination,"lat":lat if hold else next_lat,"mood":0})
			if not hold:
				x=destination
				lat=next_lat
			time=end
		plan.append(segments)
	return plan

# The shared x of the minimap, plus Godot's own lateral wander: each walk bows
# into a gentle arc, and standing horses know which way their next walk heads.
static func pose(time: float, segments: Array) -> Dictionary:
	var result:={"x":-5.5,"lat":0.0,"velocity":Vector2.ZERO,"mood":0,"next_heading":Vector2.ZERO,"until_move":INF}
	if segments.is_empty(): return result
	var clock:=minf(time,47.0)
	var index:=segments.size()-1
	for i in range(segments.size()):
		if clock<=float(segments[i].end):
			index=i
			break
	var segment: Dictionary=segments[index]
	var start_lat:=float(segments[index-1].get("lat",0.0)) if index>0 else 0.0
	var shape:=walk_shape(segment,start_lat)
	var duration:=maxf(float(segment.end)-float(segment.start),.001)
	var t:=clampf((clock-float(segment.start))/duration,0,1)
	var ease:=t*t*t*(10+t*(-15+6*t))
	var rate:=30*t*t*(1-t)*(1-t)/duration
	var x:=float(segment.from)+shape.x*ease
	var lat:=start_lat+shape.y*ease+sin(PI*ease)*shape.z
	var velocity:=Vector2(shape.x,shape.y+PI*cos(PI*ease)*shape.z)*rate
	if is_zero_approx(shape.x):
		result.mood=int(segment.get("mood",0))
		for j in range(index+1,segments.size()):
			var next: Dictionary=segments[j]
			if is_equal_approx(float(next.from),float(next.to)): continue
			var next_shape:=walk_shape(next,float(segments[j-1].get("lat",0.0)))
			result.next_heading=Vector2(next_shape.x,next_shape.y+PI*next_shape.z).normalized()
			result.until_move=float(next.start)-clock
			break
	# Lining up: walk to the start line and back to the middle of the lane in
	# one diagonal, so nobody slides sideways while standing.
	if time>=48.0:
		var u:=clampf((time-48.0)/5.0,0,1)
		var closing:=6*u*(1-u)/5.0
		velocity=Vector2(-x*closing,-lat*closing)
		x*=1-u*u*(3-2*u)
		lat*=1-u*u*(3-2*u)
	result.x=x
	result.lat=lat
	result.velocity=velocity
	return result

# x distance, lateral distance and sideways bow of one walk.
static func walk_shape(segment: Dictionary, start_lat: float) -> Vector3:
	var dx:=float(segment.to)-float(segment.from)
	var bow:=clampf(absf(dx)*.07,0,.3)*(1.0 if int(float(segment.start)*7.0)%2==0 else -1.0)
	return Vector3(dx,float(segment.get("lat",start_lat))-start_lat,bow if not is_zero_approx(dx) else 0.0)

# Kept for callers that only need the shared x and its speed.
static func sample(time: float, segments: Array) -> Vector2:
	var state:=pose(time,segments)
	return Vector2(state.x,state.velocity.x)
