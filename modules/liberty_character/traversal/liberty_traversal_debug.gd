class_name LibertyTraversalDebug
extends MeshInstance3D
## Optional runtime diagnostics; all vertices are world-space in a top-level node.
var _lines := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _lines
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
func draw(probe: LibertyTraversalProbe, candidates: Array[LibertyTraversalCandidate], selected: LibertyTraversalCandidate, destination: Transform3D, enabled: bool) -> void:
	_lines.clear_surfaces()
	visible = enabled
	if not enabled: return
	_lines.surface_begin(Mesh.PRIMITIVE_LINES,_material)
	for ray in probe.debug_rays:
		_line(ray.from,ray.to,Color.GREEN if ray.hit else Color(.4,.5,.6))
	for at in probe.debug_capsules:
		_capsule(at.origin,probe.capsule_radius,probe.capsule_height,Color(.3,.5,1))
	for candidate in candidates:
		var color := Color.YELLOW if selected != null and candidate.same_opportunity(selected) else Color.CYAN
		_cross(candidate.destination_transform.origin,.08,color)
		_line(candidate.contact_point,candidate.contact_point+candidate.surface_normal*.35,color)
		for point in [candidate.left_hand_target,candidate.right_hand_target,candidate.left_foot_target,candidate.right_foot_target]:
			_cross(point,.03,color)
	if selected != null:
		_cross(selected.destination_transform.origin,.15,Color.YELLOW)
	_cross(destination.origin,.12,Color.MAGENTA)
	_lines.surface_end()
func _line(a: Vector3,b: Vector3,color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(b)
func _cross(at: Vector3,size: float,color: Color) -> void:
	for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
		_line(at-axis*size,at+axis*size,color)
func _capsule(at: Vector3,radius: float,height: float,color: Color) -> void:
	var cylinder := height*.5-radius
	for i in range(16):
		var a := float(i)*TAU/16
		var b := float(i+1)*TAU/16
		for side in [-1.0,1.0]:
			_line(at+Vector3(cos(a)*radius,cylinder*side,sin(a)*radius),at+Vector3(cos(b)*radius,cylinder*side,sin(b)*radius),color)
	for axis in [Vector3.RIGHT,Vector3.BACK]:
		_line(at+axis*radius-Vector3.UP*cylinder,at+axis*radius+Vector3.UP*cylinder,color)
		_line(at-axis*radius-Vector3.UP*cylinder,at-axis*radius+Vector3.UP*cylinder,color)
	_cross(at+Vector3.UP*height*.5,.04,color)
	_cross(at-Vector3.UP*height*.5,.04,color)
