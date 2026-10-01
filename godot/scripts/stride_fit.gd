extends SkeletonModifier3D

# Fits the gallop's stride to the ground the horse is really covering.
#
# The course is about a third of real size, so the field gallops at 6-7 m/s,
# and the gallop plays at a racehorse's rhythm (asset_horse.gd GALLOP_TEMPO)
# so it never looks like slow motion. At that rhythm the clip's 6.4 m stride
# would sweep each planted hoof back twice as fast as the ground goes by, and
# the hooves would skate. After the clip has posed the skeleton, this narrows
# every leg's fore-and-aft swing about its own middle by just enough that a
# planted hoof stands still on the ground, keeping its height, and bends the
# stifle or elbow to reach it (two-bone IK; the hoof keeps the clip's angle).
# The legs then take the shorter, quicker strides a horse uses at this pace.
#
# asset_horse.gd tells it each frame how fast the horse is going (`pace`, m/s)
# and how fast the clip is playing (`rate`, clip seconds per second).
#
# Through a bend the horse also looks into the turn: `look` (radians, positive
# to the left) turns the neck, half at its base and half above.
const LEGS = [["L_Thing","L_Calf","L_Toe0"],["R_Thing","R_Calf","R_Toe0"],["L_UpperArm","l_Forearm","L_Finger0"],["R_UpperArm","R_Forearm","R_Finger0"]]
const SAMPLES := 48
# How far the swing may narrow; below this the legs would barely move.
const NARROWEST := .3

var pace := 0.0
var rate := 0.0
var fitting := false
var look := 0.0
const NECK = ["Neck","Neck1"]
# Per model: each leg's bones, the middle of its swing and how fast a planted
# hoof sweeps back in the clip; and the horse's forward axis, all in skeleton space.
var legs: Array = []
var forward := Vector3.FORWARD
var up := Vector3.UP
var neck: Array[int] = []
var narrow: Array[float] = [1.0,1.0,1.0,1.0]

# Studies the gallop on this skeleton once per model: the AnimationPlayer must
# be free to pose it, before the race starts playing clips.
static func study(skeleton: Skeleton3D, player: AnimationPlayer, horse_from_skeleton: Transform3D) -> Dictionary:
	var forward:=(horse_from_skeleton.basis.inverse()*Vector3.FORWARD).normalized()
	var up:=(horse_from_skeleton.basis.inverse()*Vector3.UP).normalized()
	# Skeleton units to metres along the horse's forward axis, and 3 cm in skeleton units.
	var metres:=(horse_from_skeleton.basis*forward).length()
	var tolerance:=.03/(horse_from_skeleton.basis*up).length()
	var bones: Array=[]
	for names: Array in LEGS:
		var leg: Array[int]=[]
		for name: String in names: leg.append(skeleton.find_bone(name))
		if leg.has(-1): return {}
		bones.append(leg)
	var along: Array=[]
	var height: Array=[]
	for leg in bones:
		along.append(PackedFloat32Array())
		height.append(PackedFloat32Array())
	var clip:=player.get_animation("Gallop")
	player.play("Gallop",0.0)
	for i in range(SAMPLES):
		player.seek(clip.length*i/SAMPLES,true)
		for k in range(bones.size()):
			var root:=skeleton.get_bone_global_pose(bones[k][0]).origin
			var hoof:=skeleton.get_bone_global_pose(bones[k][2]).origin
			along[k].append((hoof-root).dot(forward))
			height[k].append(hoof.dot(up))
	var legs: Array=[]
	for k in range(bones.size()):
		var low: float=Array(height[k]).min()
		var sweep:=0.0
		var planted:=0
		for i in range(SAMPLES):
			var j:=(i+1)%SAMPLES
			if height[k][i]<low+tolerance and height[k][j]<low+tolerance:
				sweep+=along[k][i]-along[k][j]
				planted+=1
		legs.append({"bones":bones[k],"middle":(Array(along[k]).min()+Array(along[k]).max())*.5,
			# Metres a planted hoof travels back per clip second.
			"speed":sweep/maxf(planted,1)*SAMPLES/clip.length*metres})
	var neck: Array[int]=[]
	for name: String in NECK:
		if skeleton.find_bone(name)>=0: neck.append(skeleton.find_bone(name))
	# The moment of full stretch: forelegs reaching furthest forward and hind
	# legs furthest back, the pose of every finish-line photograph.
	var stretch:=0
	var widest:=-INF
	for i in range(SAMPLES):
		var spread:=maxf(along[2][i],along[3][i])-minf(along[0][i],along[1][i])
		if spread>widest:
			widest=spread
			stretch=i
	return {"legs":legs,"forward":forward,"up":up,"neck":neck,"stretch":clip.length*stretch/SAMPLES}

func setup(study_result: Dictionary) -> void:
	legs=study_result.legs
	forward=study_result.forward
	up=study_result.up
	neck.assign(study_result.neck)

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton:=get_skeleton()
	if absf(look)>.002:
		for bone in neck:
			var pose:=skeleton.get_bone_global_pose(bone)
			skeleton.set_bone_global_pose(bone,Transform3D(Basis(up,look/neck.size())*pose.basis,pose.origin))
	if not fitting or legs.is_empty(): return
	for i in range(legs.size()):
		var leg: Dictionary=legs[i]
		var speed: float=leg.speed
		if speed<=0.0: continue
		if rate>0.0: narrow[i]=clampf(pace/(speed*rate),NARROWEST,1.0)
		if narrow[i]>.995: continue
		fit_leg(skeleton,leg,narrow[i])

func fit_leg(skeleton: Skeleton3D, leg: Dictionary, k: float) -> void:
	var bones: Array[int]=leg.bones
	var root_pose:=skeleton.get_bone_global_pose(bones[0])
	var knee_pose:=skeleton.get_bone_global_pose(bones[1])
	var hoof_pose:=skeleton.get_bone_global_pose(bones[2])
	var root:=root_pose.origin
	var knee:=knee_pose.origin
	var hoof:=hoof_pose.origin
	var along:=(hoof-root).dot(forward)
	var target:=hoof+forward*((float(leg.middle)+(along-float(leg.middle))*k)-along)
	var a:=root.distance_to(knee)
	var b:=knee.distance_to(hoof)
	var reach:=target-root
	var d:=clampf(reach.length(),absf(a-b)+.001,a+b-.001)
	var aim:=reach.normalized()
	# The knee keeps bending the way the clip bends it.
	var line:=(hoof-root).normalized()
	var bend:=(knee-root)-line*(knee-root).dot(line)
	bend=bend-aim*bend.dot(aim)
	if bend.length_squared()<1e-10: return
	bend=bend.normalized()
	var cos_root:=clampf((a*a+d*d-b*b)/(2.0*a*d),-1.0,1.0)
	var new_knee:=root+a*(aim*cos_root+bend*sqrt(1.0-cos_root*cos_root))
	var turn_root:=Quaternion((knee-root).normalized(),(new_knee-root).normalized())
	skeleton.set_bone_global_pose(bones[0],Transform3D(Basis(turn_root)*root_pose.basis,root))
	var moved_knee:=skeleton.get_bone_global_pose(bones[1])
	var moved_hoof:=skeleton.get_bone_global_pose(bones[2]).origin
	var turn_knee:=Quaternion((moved_hoof-moved_knee.origin).normalized(),(root+aim*d-moved_knee.origin).normalized())
	skeleton.set_bone_global_pose(bones[1],Transform3D(Basis(turn_knee)*moved_knee.basis,moved_knee.origin))
	# The hoof meets the ground at the clip's angle.
	var placed:=skeleton.get_bone_global_pose(bones[2]).origin
	skeleton.set_bone_global_pose(bones[2],Transform3D(hoof_pose.basis,placed))
