extends Node3D

# The starting gate across the home straight at the line: twelve stalls whatever
# the field. Runners stand with their noses at the front doors, which spring
# open as the race starts; the gate is cleared away at the first camera cut, so
# the field comes home to an open line.
# Sized for the current horse (about 0.9 m wide, 3.5 m nose to tail and 2.9 m
# to the ears, so it stands inside the frame); a new horse model only needs
# DEPTH and the heights below adjusted, and the stall width in course.gd.
const KIT = preload("res://scripts/mesh_kit.gd")
const FRONT := .02
const DEPTH := 3.9
const PANEL_LOW := .4
const PANEL_HIGH := 2.3
const DOOR_LOW := .35
const DOOR_HIGH := 2.15
const TOP := 3.6
# Number boards sit above the runners' ears.
const BOARD_Y := 3.22
const BOARD_HEIGHT := .44
const DOOR_ANGLE := 105.0
const FRAME := Color("2f5d46")
const PADDING := Color("e7e1cf")
const DOOR := Color("f4f1e8")
const WHEEL := Color("2b2d2a")
# Numbers stay light on the darker stall colours, as on the runners' cloths.
const LIGHT_NUMBERS = [0,3,7,8,9,11]

var doors: Array[Node3D] = []
var opened := -1.0

func build(course: RefCounted, colors: Array) -> void:
	var stalls: int=course.STALLS
	var width: float=course.stall_spacing()
	var first: float=course.stall_radius(0)-width*.5
	var last: float=course.stall_radius(stalls-1)+width*.5
	var back := FRONT-DEPTH
	var middle := FRONT-DEPTH*.5
	var st := KIT.begin()
	# Padded partitions between and beside the stalls, each on a post front and
	# back with a rail over the top.
	for j in range(stalls+1):
		var z := first+j*width
		KIT.box(st,Vector3(middle,(PANEL_LOW+PANEL_HIGH)*.5,z),Vector3(DEPTH-.12,PANEL_HIGH-PANEL_LOW,.06),PADDING)
		for x: float in [FRONT-.04,back]:
			KIT.box(st,Vector3(x,TOP*.5,z),Vector3(.08,TOP,.08),FRAME)
		KIT.box(st,Vector3(middle,TOP,z),Vector3(DEPTH,.08,.08),FRAME)
	# Beams across the top, front and back.
	for x: float in [FRONT-.04,back]:
		KIT.box(st,Vector3(x,TOP+.12,(first+last)*.5),Vector3(.2,.3,last-first+.5),FRAME)
	# End towers on the wheels the gate is towed on.
	for side: float in [-1.0,1.0]:
		var z: float=(first if side<0 else last)+side*.24
		KIT.box(st,Vector3(middle,(.5+TOP+.25)*.5,z),Vector3(DEPTH+.3,TOP-.25,.3),FRAME)
		for x: float in [back+.6,FRONT-.6]:
			KIT.cylinder(st,Vector3(x,.46,z+side*.15),Vector3(x,.46,z+side*.38),.46,WHEEL,14)
			KIT.disc(st,Vector3(x,.46,z+side*.38),.46,WHEEL,Vector3(0,0,side),14)
	# A board over each stall in its runner's colour.
	for k in range(stalls):
		KIT.box(st,Vector3(FRONT+.03,BOARD_Y,course.stall_radius(k)),Vector3(.04,BOARD_HEIGHT,width-.14),colors[k])
	KIT.finish(st,KIT.painted(.6,.3),self)
	for k in range(stalls):
		var number := Label3D.new()
		number.text=str(k+1)
		number.font_size=96
		number.pixel_size=.0046
		number.outline_size=0
		number.shaded=true
		number.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		number.modulate=Color("fff7e7") if k in LIGHT_NUMBERS else Color("202822")
		number.position=Vector3(FRONT+.056,BOARD_Y,course.stall_radius(k))
		number.rotation.y=PI/2
		add_child(number)
	# Bi-parting front doors, hinged at the partitions, swing forward down the track.
	var door_material := KIT.painted(.55,.3)
	var leaf := width*.5-.05
	for k in range(stalls):
		for side: float in [-1.0,1.0]:
			var hinge := Node3D.new()
			hinge.position=Vector3(FRONT,0,course.stall_radius(k)+side*(width*.5-.035))
			hinge.set_meta("side",side)
			var door := KIT.begin()
			KIT.box(door,Vector3(0,(DOOR_LOW+DOOR_HIGH)*.5,-side*leaf*.5),Vector3(.05,DOOR_HIGH-DOOR_LOW,leaf),DOOR)
			KIT.box(door,Vector3(.03,DOOR_HIGH-.28,-side*leaf*.5),Vector3(.012,.18,leaf),colors[k])
			KIT.finish(door,door_material,hinge)
			add_child(hinge)
			doors.append(hinge)
	set_open(0.0)

# 0 shut, 1 wide open.
func set_open(amount: float) -> void:
	if is_equal_approx(amount,opened): return
	opened=amount
	var angle := deg_to_rad(DOOR_ANGLE)*amount
	for hinge in doors: hinge.rotation.y=-float(hinge.get_meta("side"))*angle
