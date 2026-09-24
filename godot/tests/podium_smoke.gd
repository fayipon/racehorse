extends SceneTree
const PODIUM=preload("res://scripts/podium.gd")

func _initialize() -> void:
	call_deferred("verify_podium")

func verify_podium() -> void:
	var podium=PODIUM.new()
	root.add_child(podium)
	assert(not podium.visible,"Awards must not reveal results before settlement")
	var colors: Array=[Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE]
	var times: Array=[47.75,45.8,48.4,46.45,45.15,49.05,44.5,47.1]
	podium.present(times,colors,42)
	assert(podium.order.slice(0,3)==[6,4,1],"Podium ranks must come from actual finish times, not lane order")
	assert(podium.runners.size()==3,"Show exactly three horses")
	assert(podium.runners[0].position.y>podium.runners[1].position.y)
	assert(podium.runners[1].position.y>podium.runners[2].position.y)
	var champion=podium.runners[0]
	podium.present(times,colors,42)
	assert(podium.runners[0]==champion,"Result updates must preserve the animated horses")
	podium.present([44.5,45.15,45.8,46.45,47.1,47.75,48.4,49.05],colors,43)
	assert(podium.order.slice(0,3)==[0,1,2],"The next round must replace all three ranks")
	assert(podium.runners.size()==3)
	podium.animate(1.0,.016)
	print("PASS: podium visibility, actual top three, rank heights and next-round reset")
	podium.queue_free()
	quit()
