extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var character := CharacterScene.instantiate()
	var player := character.get_node("Rig/AnimationPlayer") as AnimationPlayer
	var library := player.get_animation_library(&"").duplicate() as AnimationLibrary
	library.remove_animation(&"land")
	player.remove_animation_library(&"")
	player.add_animation_library(&"", library)
	root.add_child(character)
	await process_frame
	var tree := character.get_node("AnimationTree") as AnimationTree
	var driver := character.get_node("AnimationDriver") as Node
	Support.expect_false(tree.active, "missing land clip must leave animation inactive, without a replacement")
	Support.expect_false(driver.is_physics_processing(), "invalid animation setup must stop driver processing")
	Support.expect_equal(driver.configuration_error, "Missing required animation clips: land", "missing-clip diagnostic must name the required clip")
	Support.expect_true(character.get_node("CollisionShape3D").disabled == false, "missing animation must not disable character collision")
	character.free()
	quit(Support.exit_code())
