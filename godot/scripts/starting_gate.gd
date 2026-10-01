extends Node3D

# The starting gate across the home straight at the line: twelve stalls whatever
# the field. Runners stand with their noses at the front doors, which spring
# open as the race starts; the gate is cleared away at the first camera cut, so
# the field comes home to an open line.
# Sized for the current horse (about 0.9 m wide, 3.5 m nose to tail and 2.9 m
# to the ears, so it stands inside the frame); a new horse model only needs
# DEPTH and the heights below adjusted, and the stall width in course.gd.
# Built like a real one: a green steel frame with lattice beams front and back,
# padded partitions between the stalls, doors padded below and barred above,
# and open end towers on pneumatic tyres. Everything but the doors is one mesh
# in the shared structure shader.
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
const FRAME := Color("2a5a43")
const PADDING := Color("ebe5d5")
const STEEL := Color("dfe2de")
const TYRE := Color("1f201f")
# Numbers stay light on the darker stall colours, as on the runners' cloths.
const LIGHT_NUMBERS = [0,3,7,8,9,11]

var doors: Array[Node3D] = []
# Sides on each tube.
var tube := 8
var opened := -1.0

# Phones (`low_power`) build the tubes with fewer sides, and the doors cast
# no shadow.
func build(course: RefCounted, colors: Array, low_power := false) -> void:
	tube=5 if low_power else 8
	var stalls: int=course.STALLS
	var width: float=course.stall_spacing()
	var first: float=course.stall_radius(0)-width*.5
	var last: float=course.stall_radius(stalls-1)+width*.5
	var back := FRONT-DEPTH
	var middle := FRONT-DEPTH*.5
	var st := KIT.begin()
	var frame := KIT.made_of(FRAME,KIT.PAINT)
	var padding := KIT.made_of(PADDING,KIT.PADDING)
	var steel := KIT.made_of(STEEL,KIT.METAL)
	# Partitions: a post front and back, a padded panel in a tubular frame, open
	# rails above it and a rail over the top.
	for j in range(stalls+1):
		var z := first+j*width
		for x: float in [FRONT-.06,back+.06]:
			KIT.rounded_box(st,Vector3(x,(TOP+.1)*.5,z),Vector3(.11,TOP+.1,.11),.025,frame)
		KIT.rounded_box(st,Vector3(middle,(PANEL_LOW+PANEL_HIGH)*.5,z),Vector3(DEPTH-.32,PANEL_HIGH-PANEL_LOW,.1),.04,padding)
		for y: float in [PANEL_LOW-.04,PANEL_HIGH+.04,2.9,TOP]:
			KIT.sweep(st,[Vector3(FRONT-.06,y,z),Vector3(back+.06,y,z)] as Array[Vector3],.032 if y<TOP else .045,frame,tube)
		KIT.cylinder(st,Vector3(middle,PANEL_HIGH+.04,z),Vector3(middle,TOP,z),.025,frame,maxi(tube-2,4))
	# Lattice beams across the top, front and back, with skids along the ground.
	for x: float in [FRONT-.06,back+.06]:
		for y: float in [TOP-.02,TOP+.42]:
			KIT.sweep(st,[Vector3(x,y,first-.55),Vector3(x,y,last+.55)] as Array[Vector3],.06,frame,tube)
		var z := first-.55
		var up := true
		while z<last+.5:
			var z1 := minf(z+.35,last+.55)
			KIT.cylinder(st,Vector3(x,TOP-.02 if up else TOP+.42,z),Vector3(x,TOP+.42 if up else TOP-.02,z1),.022,frame,maxi(tube-2,4))
			z=z1
			up=not up
		KIT.sweep(st,[Vector3(x,.12,first-.55),Vector3(x,.12,last+.55)] as Array[Vector3],.05,frame,tube)
	# A board over each stall in its runner's colour, framed in white.
	for k in range(stalls):
		var z: float=course.stall_radius(k)
		KIT.rounded_box(st,Vector3(FRONT+.005,BOARD_Y,z),Vector3(.04,BOARD_HEIGHT+.07,width-.1),.015,KIT.made_of(Color("f4f1e8"),KIT.PAINT))
		KIT.rounded_box(st,Vector3(FRONT+.025,BOARD_Y,z),Vector3(.03,BOARD_HEIGHT,width-.17),.012,KIT.made_of(colors[k],KIT.PAINT))
	# Open end towers on two pneumatic tyres each, braced on their outer face.
	for side: float in [-1.0,1.0]:
		var edge: float=(first if side<0 else last)
		var outer := edge+side*.6
		for x: float in [FRONT-.06,back+.06]:
			KIT.rounded_box(st,Vector3(x,(TOP+.45)*.5+.25,outer),Vector3(.14,TOP+.45-.5,.14),.03,frame)
			KIT.sweep(st,[Vector3(x,TOP+.42,edge),Vector3(x,TOP+.42,outer)] as Array[Vector3],.05,frame,tube)
		for y: float in [.75,1.9,3.0]:
			KIT.sweep(st,[Vector3(FRONT-.06,y,outer),Vector3(back+.06,y,outer)] as Array[Vector3],.045,frame,tube)
		KIT.cylinder(st,Vector3(FRONT-.06,.75,outer),Vector3(back+.06,3.0,outer),.035,frame,maxi(tube-2,4))
		KIT.cylinder(st,Vector3(back+.06,.75,outer),Vector3(FRONT-.06,3.0,outer),.035,frame,maxi(tube-2,4))
		# Chassis rail and axle housings carrying the wheels outside the tower.
		KIT.rounded_box(st,Vector3(middle,.62,outer),Vector3(DEPTH+.2,.22,.24),.04,frame)
		for x: float in [back+.75,FRONT-.75]:
			wheel(st,Vector3(x,.52,outer+side*.32),side)
	KIT.finish(st,KIT.structure(false),self)
	for k in range(stalls):
		var number := Label3D.new()
		number.text=str(k+1)
		number.font_size=96
		number.pixel_size=.0046
		number.outline_size=0
		number.shaded=true
		number.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		number.modulate=Color("fff7e7") if k in LIGHT_NUMBERS else Color("202822")
		number.position=Vector3(FRONT+.046,BOARD_Y,course.stall_radius(k))
		number.rotation.y=PI/2
		add_child(number)
	# Bi-parting front doors, hinged at the partitions, swing forward down the
	# track: padded below, barred above, banded in the stall's colour.
	var leaf := width*.5-.06
	for k in range(stalls):
		for side: float in [-1.0,1.0]:
			var hinge := Node3D.new()
			hinge.position=Vector3(FRONT,0,course.stall_radius(k)+side*(width*.5-.04))
			hinge.set_meta("side",side)
			var door := KIT.begin()
			var across := -side
			var mid_z := across*leaf*.5
			KIT.rounded_box(door,Vector3(0,(DOOR_LOW+1.45)*.5,mid_z),Vector3(.07,1.45-DOOR_LOW,leaf),.025,padding)
			KIT.rounded_box(door,Vector3(.01,1.52,mid_z),Vector3(.06,.14,leaf+.02),.02,KIT.made_of(colors[k],KIT.PAINT))
			KIT.sweep(door,[Vector3(0,DOOR_HIGH,0),Vector3(0,DOOR_HIGH,across*leaf)] as Array[Vector3],.025,frame,tube)
			KIT.sweep(door,[Vector3(0,1.45,across*leaf),Vector3(0,DOOR_HIGH,across*leaf)] as Array[Vector3],.025,frame,tube)
			KIT.sweep(door,[Vector3(0,DOOR_LOW,0),Vector3(0,DOOR_HIGH,0)] as Array[Vector3],.03,frame,tube)
			for b in range(1,4):
				var z: float=across*leaf*b/4.0
				KIT.cylinder(door,Vector3(0,1.58,z),Vector3(0,DOOR_HIGH,z),.014,steel,maxi(tube-2,4))
			KIT.finish(door,KIT.structure(false),hinge,tube>5)
			add_child(hinge)
			doors.append(hinge)
	set_open(0.0)

# A pneumatic tyre on a steel wheel, its outer face toward `side` (+-z).
func wheel(st: SurfaceTool, center: Vector3, side: float) -> void:
	var axis := Vector3(0,0,side)
	var tyre := KIT.made_of(TYRE,KIT.RUBBER)
	var rim := KIT.made_of(Color("b8bdb9"),KIT.METAL)
	var half := axis*.13
	var round := 14 if tube<8 else 24
	# Tread, rounded shoulders and sidewalls.
	KIT.cylinder(st,center-half*.7,center+half*.7,.5,tyre,round)
	KIT.cylinder(st,center+half*.7,center+half,.5,tyre,round,.44)
	KIT.cylinder(st,center-half,center-half*.7,.44,tyre,round,.5)
	for s: float in [-1.0,1.0]:
		KIT.collar(st,center+half*s,axis,.02,.27,.44,tyre,round)
	# Dished wheel and hub cap.
	KIT.cylinder(st,center+half*.95,center+half*.6,.27,rim,round,.2)
	KIT.disc(st,center+half*.6,.2,rim,axis,round)
	KIT.cylinder(st,center+half*.6,center+half*1.05,.07,rim,10)
	KIT.disc(st,center+half*1.05,.07,rim,axis,10)
	KIT.disc(st,center-half*.95,.27,rim,-axis,round)

# 0 shut, 1 wide open.
func set_open(amount: float) -> void:
	if is_equal_approx(amount,opened): return
	opened=amount
	var angle := deg_to_rad(DOOR_ANGLE)*amount
	for hinge in doors: hinge.rotation.y=-float(hinge.get_meta("side"))*angle
