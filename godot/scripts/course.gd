extends RefCounted

# Shared with React's src/course.ts. A stadium course with two straightaways.
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/course.json"))
var field := 8

# Bigger fields close the lanes up so the outside horse still runs inside the rail.
func lane_spacing() -> float:
	return minf(float(config.laneSpacing),(float(config.maxLaneRadius)-float(config.laneStart))/(field-1))

func lane_radius(lane: float) -> float:
	return float(config.laneStart) + lane * lane_spacing()

# The starting gate always has twelve stalls, centred across the track, whatever
# the field: runners load the stalls in number order and fan out to their lanes.
const STALLS := 12
const STALL_SPACING := 1.05
func stall_spacing() -> float:
	return STALL_SPACING

func stall_radius(stall: float) -> float:
	return float(config.innerRadius) + float(config.trackWidth)*.5 + (stall - (STALLS-1)*.5) * STALL_SPACING

func sample(progress: float, radius: float) -> Dictionary:
	var half := float(config.halfStraight)
	var distance := fposmod(progress,1.0) * (4.0*half + TAU*radius)
	if distance<=half:
		return {"position":Vector3(distance,0,radius),"tangent":Vector3.RIGHT,"outward":Vector3.BACK}
	distance-=half
	if distance<=PI*radius:
		var a := PI/2.0-distance/radius
		return {"position":Vector3(half+cos(a)*radius,0,sin(a)*radius),"tangent":Vector3(sin(a),0,-cos(a)),"outward":Vector3(cos(a),0,sin(a))}
	distance-=PI*radius
	if distance<=2.0*half:
		return {"position":Vector3(half-distance,0,-radius),"tangent":Vector3.LEFT,"outward":Vector3.FORWARD}
	distance-=2.0*half
	if distance<=PI*radius:
		var a := -PI/2.0-distance/radius
		return {"position":Vector3(-half+cos(a)*radius,0,sin(a)*radius),"tangent":Vector3(sin(a),0,-cos(a)),"outward":Vector3(cos(a),0,sin(a))}
	return {"position":Vector3(-half+distance-PI*radius,0,radius),"tangent":Vector3.RIGHT,"outward":Vector3.BACK}
