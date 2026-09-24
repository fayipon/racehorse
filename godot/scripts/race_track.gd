extends Node3D

const RAIL = preload("res://assets/equestrian/arena_rail.glb")
const TURF = preload("res://shaders/racing_turf.gdshader")

func build(course: RefCounted) -> void:
	build_turf(course)
	var template: Node3D=RAIL.instantiate()
	var parts: Array=[]
	collect_parts(template,Transform3D.IDENTITY,parts)
	for radius in [float(course.config.innerRadius)-.4,float(course.config.innerRadius)+float(course.config.trackWidth)+.4]:
		var circumference: float=4.0*float(course.config.halfStraight)+TAU*radius
		var count:=roundi(circumference/3.0)
		for part in parts:
			var instances:=MultiMesh.new()
			instances.transform_format=MultiMesh.TRANSFORM_3D
			instances.mesh=part.mesh
			instances.instance_count=count
			for i in range(count):
				var a: Vector3=course.sample(float(i)/count,radius).position
				var b: Vector3=course.sample(float(i+1)/count,radius).position
				var direction: Vector3=(b-a).normalized()
				# Face the kick board inward on both sides of the racing surface.
				if radius>float(course.config.innerRadius): direction=-direction
				var basis:=Basis(direction*a.distance_to(b)/3.0,Vector3.UP,direction.cross(Vector3.UP))
				instances.set_instance_transform(i,Transform3D(basis,(a+b)*.5)*part.transform)
			var batch:=MultiMeshInstance3D.new()
			batch.multimesh=instances
			add_child(batch)
	template.free()

func collect_parts(node: Node3D, parent_transform: Transform3D, parts: Array) -> void:
	var transform:=parent_transform*node.transform
	if node is MeshInstance3D:
		var mesh: ArrayMesh=node.mesh.duplicate()
		for surface in range(mesh.get_surface_count()):
			var mat:=node.get_active_material(surface).duplicate() as StandardMaterial3D
			mat.roughness=.92
			mat.metallic_specular=.12
			# Retain the model's two materials with a warm painted finish.
			mat.albedo_color=Color("e4e3d8") if mat.resource_name=="white" else Color("aaa68d")
			mesh.surface_set_material(surface,mat)
		parts.append({"mesh":mesh,"transform":transform})
	for child in node.get_children():
		if child is Node3D: collect_parts(child,transform,parts)

func build_turf(course: RefCounted) -> void:
	var inner:=float(course.config.innerRadius)
	var width:=float(course.config.trackWidth)
	var circumference:=4.0*float(course.config.halfStraight)+TAU*(inner+width*.5)
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(384):
		var a:=float(i)/384.0
		var b:=float(i+1)/384.0
		var points: Array[Vector3]=[course.sample(a,inner).position,course.sample(a,inner+width).position,course.sample(b,inner).position,course.sample(b,inner+width).position]
		var uv: Array[Vector2]=[Vector2(a*circumference,0),Vector2(a*circumference,width),Vector2(b*circumference,0),Vector2(b*circumference,width)]
		for index in [0,2,1,1,2,3]:
			var point:=points[index]
			point.y=.012
			surface.set_normal(Vector3.UP)
			surface.set_uv(uv[index])
			surface.add_vertex(point)
	var turf:=MeshInstance3D.new()
	turf.mesh=surface.commit()
	var mat:=ShaderMaterial.new()
	mat.shader=TURF
	mat.set_shader_parameter("lap_length",circumference)
	mat.set_shader_parameter("grass_dark",Color("3f703c"))
	mat.set_shader_parameter("grass_light",Color("70934e"))
	turf.material_override=mat
	add_child(turf)
