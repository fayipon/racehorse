extends RefCounted

# Snapshots synchronize a continuous clock, never individual horse positions.
# Bounded clock correction avoids the 4 Hz speed pulses of chasing snapshots.
var seconds := 0.0
var target_seconds := 0.0
var initialized := false
var cinematic: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/cinematic.json"))

func presentation(time: float) -> Vector2:
	if time<=float(cinematic[0][0]): return Vector2(time,1)
	if time>=float(cinematic[-1][0]):
		var last: Array=cinematic[-1]
		return Vector2(float(last[1])+(time-float(last[0]))*float(last[2]),float(last[2]))
	for i in range(1,cinematic.size()):
		if time>float(cinematic[i][0]): continue
		var a: Array=cinematic[i-1]
		var b: Array=cinematic[i]
		var span:=float(b[0])-float(a[0])
		var t: float=(time-float(a[0]))/span
		var value: float=(2*t*t*t-3*t*t+1)*a[1]+(t*t*t-2*t*t+t)*span*a[2]+(-2*t*t*t+3*t*t)*b[1]+(t*t*t-t*t)*span*b[2]
		var speed: float=((6*t*t-6*t)*a[1]+(3*t*t-4*t+1)*span*a[2]+(-6*t*t+6*t)*b[1]+(3*t*t-2*t)*span*b[2])/span
		return Vector2(value,speed)
	return Vector2(time,1)

func sync(snapshot: float, reset := false) -> void:
	target_seconds=snapshot
	if reset or not initialized or absf(snapshot-seconds)>1.0:
		seconds=snapshot
		initialized=true

func advance(delta: float) -> void:
	target_seconds+=delta
	seconds+=delta*(1.0+clampf((target_seconds-seconds-delta)*2.0,-.05,.05))

static func progress(time: float, horse_id: int, finish_time: float) -> float:
	# Same deterministic curve as src/game.ts; evaluated each rendered frame.
	var t:=clampf(time/finish_time,0,1)
	var wave:=sin(t*PI*4+horse_id*1.7)*.025*sin(t*PI)
	return clampf(t+wave,0,1)
