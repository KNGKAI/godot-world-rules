extends SceneTree
## Phase 8 pre-flight: engine assumptions the editor tooling depends on.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")


func _initialize() -> void: call_deferred("run")


func run() -> void:
	var Probe: Script = load("res://modules/liberty_character/traversal/liberty_traversal_probe.gd")
	var Motor: Script = load("res://modules/liberty_character/traversal/liberty_traversal_motor.gd")
	var PhysicalAnimation: Script = load("res://modules/liberty_character/ragdoll/liberty_physical_animation.gd")
	# Script defaults are readable without instancing the (non-tool) runtime scripts.
	Support.expect_equal(Probe.get_property_default_value(&"forward_reach"), 0.9, "probe default forward_reach")
	var angular = Motor.get_property_default_value(&"max_angular_correction")
	print("motor max_angular_correction default: ", angular, " (", type_string(typeof(angular)), ")")
	Support.expect_true(angular is float and is_equal_approx(angular, deg_to_rad(25.0)), "deg_to_rad default folds to a float")
	var multipliers = PhysicalAnimation.get_property_default_value(&"bone_multipliers")
	print("bone_multipliers default: ", multipliers)
	Support.expect_true(multipliers is Dictionary and multipliers.size() == 13, "bone_multipliers default dictionary")
	# Static helpers and consts on class_name scripts are callable from other scripts.
	var hinge := LibertyRagdoll.joint_basis(&"LeftLowerArm")
	Support.expect_true(hinge.z.is_equal_approx(Vector3.UP), "hinge joint basis Z follows HINGE_AXES")
	Support.expect_equal(LibertyRagdoll.BONE_LAYOUT.size(), 14, "BONE_LAYOUT readable")
	Support.expect_equal(LibertyPhysicalAnimation.drive_frame(&"LeftUpperArm"), LibertyPhysicalAnimation.ARM_DRIVE_FRAME, "drive_frame readable")
	# Editor classes in a plain --script run.
	for name in [&"EditorPlugin", &"EditorInspectorPlugin", &"EditorNode3DGizmoPlugin"]:
		print(name, " exists: ", ClassDB.class_exists(name), " instantiable: ", ClassDB.can_instantiate(name))
	quit(Support.exit_code())
