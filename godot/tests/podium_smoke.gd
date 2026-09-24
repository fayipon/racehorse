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
	assert(podium.runners.size()==8,"Every runner must appear at settlement")
	assert(podium.runners[0].position.y>podium.runners[1].position.y)
	assert(podium.runners[1].position.y>podium.runners[2].position.y)
	for rank in range(3,8):
		assert(podium.runners[rank].position.z<podium.runners[0].position.z,"Remaining runners must stand behind the winning three")
		assert(podium.runners[rank].scale.x<podium.runners[0].scale.x,"The top three must retain the prominent close-up")
		assert(podium.field_labels[rank-3].text=="%d · #%d" % [rank+1,podium.order[rank]+1],"Rear-tier numbers must match this race's finish order")
	var champion=podium.runners[0]
	podium.present(times,colors,42)
	assert(podium.runners[0]==champion,"Result updates must preserve the animated horses")
	podium.present([44.5,45.15,45.8,46.45,47.1,47.75,48.4,49.05],colors,43)
	assert(podium.order.slice(0,3)==[0,1,2],"The next round must replace all three ranks")
	assert(podium.runners.size()==8,"A new round must replace the whole field without duplicates")
	podium.animate(1.0,.016)
	print("PASS: all eight runners, featured top three, rear-tier order and next-round reset")
	podium.queue_free()
	quit()
