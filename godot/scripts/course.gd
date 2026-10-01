extends RefCounted

# Shared with React's src/course.ts. A stadium course with two straightaways.
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/course.json"))
var field := 8

# Bigger fields close the lanes up so the outside horse still runs inside the rail.
func lane_spacing() -> float:
	return minf(float(config.laneSpacing),(float(config.maxLaneRadius)-float(config.laneStart))/(field-1))

func lane_radius(lane: float) -> float:
	return float(config.laneStart) + lane * lane_spacing()

# Each field has a gate of its own size. Eight and ten runners load a gate of
# eight or ten stalls set right on their lanes, so they gallop straight out of
# it; the full field of twelve loads a gate of 1.05 m stalls across the middle
# of the track and fans out to its lanes (the lanes there are closer than the
# stalls, so the fan is slight).
const FULL_GATE := 12
const STALL_SPACING := 1.05
func stall_count() -> int:
	return field

func stall_spacing() -> float:
	return STALL_SPACING if field>=FULL_GATE else lane_spacing()

func stall_radius(stall: float) -> float:
	if field<FULL_GATE: return lane_radius(stall)
	return float(config.innerRadius) + float(config.trackWidth)*.5 + (stall - (FULL_GATE-1)*.5) * STALL_SPACING

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
