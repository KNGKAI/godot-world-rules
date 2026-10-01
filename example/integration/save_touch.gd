extends RefCounted
## Touch save and load for the example slot. On-foot and driving overlays both
## consume screen touches, so the same actions are registered on each.

const SAVE_COLOR := Color(0.18, 0.42, 0.68, 0.85)
const LOAD_COLOR := Color(0.32, 0.36, 0.44, 0.85)


static func attach(player: Node, on_save: Callable, on_load: Callable) -> void:
	var on_foot := player.get_node_or_null("MobileControls") as LibertyMobileControls
	if on_foot != null and on_foot.get_custom_button("SAVE") == null:
		on_foot.add_custom_button("SAVE", SAVE_COLOR, on_save)
		on_foot.add_custom_button("LOAD", LOAD_COLOR, on_load)
	var driving := player.get_node_or_null("VehicleMobileControls") as LibertyVehicleMobileControls
	if driving != null and driving.get_custom_button("SAVE") == null:
		driving.add_custom_button("SAVE", SAVE_COLOR, on_save)
		driving.add_custom_button("LOAD", LOAD_COLOR, on_load)
