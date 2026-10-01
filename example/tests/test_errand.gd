extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var script: Script = load("res://example/integration/errand_coordinator.gd")
	if script == null:
		quit(1)
		return
	var coordinator: Node = script.new()
	root.add_child(coordinator)
	assert(coordinator.pick_up_package())
	assert(coordinator.deliver_package())
	assert(bool(root.get_node("World").state.get_value(&"errand.vehicle_unlocked", false)))
	assert(not coordinator.deliver_package())
	assert(coordinator.park_sedan())
	assert(bool(root.get_node("World").state.get_value(&"errand.tour_complete", false)))
	assert(not coordinator.park_sedan())
	quit()
