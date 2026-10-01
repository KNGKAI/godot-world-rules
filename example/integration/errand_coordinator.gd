class_name ErrandCoordinator
extends Node

signal progress_changed
signal status_changed(message: String)

const RULE_BOOK: RERuleBook = preload("res://example/rules/errand.tres")
const PACKAGE_KEY: StringName = &"errand.package_collected"
const DELIVERED_KEY: StringName = &"errand.delivered"
const UNLOCK_KEY: StringName = &"errand.vehicle_unlocked"
const TOUR_KEY: StringName = &"errand.tour_complete"

var rule_engine := RERuleEngine.new()
var ready_for_delivery := false


func _ready() -> void:
	rule_engine.event_received.connect(_on_rule_event)
	var result := rule_engine.load_book(RULE_BOOK)
	if result != OK:
		push_error("Errand rule book failed to load: %s" % error_string(result))
		return
	ready_for_delivery = true
	World.state.state_restored.connect(sync_from_world_state)
	sync_from_world_state()


func pick_up_package() -> bool:
	if bool(World.state.get_value(PACKAGE_KEY, false)):
		return false
	if World.state.set_value(PACKAGE_KEY, true) != OK:
		return false
	rule_engine.emit_event(&"package_picked_up", {})
	status_changed.emit("Package collected. Cross the wall and deliver it.")
	progress_changed.emit()
	return true


func deliver_package() -> bool:
	if not ready_for_delivery or not bool(World.state.get_value(PACKAGE_KEY, false)):
		return false
	if bool(World.state.get_value(DELIVERED_KEY, false)):
		return false
	rule_engine.emit_event(&"package_delivered", {&"package_collected": true})
	if not bool(World.state.get_value(UNLOCK_KEY, false)):
		return false
	if World.state.set_value(DELIVERED_KEY, true) != OK:
		return false
	status_changed.emit("Delivery complete. The blue sedan is unlocked. Drive it to the amber bay.")
	progress_changed.emit()
	return true


func park_sedan() -> bool:
	if not ready_for_delivery or not bool(World.state.get_value(UNLOCK_KEY, false)):
		return false
	if bool(World.state.get_value(TOUR_KEY, false)):
		return false
	rule_engine.emit_event(&"sedan_parked", {&"vehicle_unlocked": true})
	if not bool(World.state.get_value(TOUR_KEY, false)):
		return false
	status_changed.emit("Delivery complete. The sedan is parked. Tour finished.")
	progress_changed.emit()
	return true


func sync_from_world_state() -> void:
	progress_changed.emit()


func _on_rule_event(event: RERuleEvent) -> void:
	if event.name == &"vehicle_unlock_requested" and not bool(World.state.get_value(UNLOCK_KEY, false)):
		World.state.set_value(UNLOCK_KEY, true)
	elif event.name == &"tour_completed" and not bool(World.state.get_value(TOUR_KEY, false)):
		World.state.set_value(TOUR_KEY, true)
