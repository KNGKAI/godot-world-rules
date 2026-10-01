@tool
extends EditorPlugin
## Registers the World autoload on enable and removes it on disable when owned.

const AutoloadRegistration := preload("res://addons/world_manager/editor/autoload_registration.gd")


func _enable_plugin() -> void:
	var err: Error = AutoloadRegistration.enable(self)
	if err != OK:
		return


func _disable_plugin() -> void:
	var err: Error = AutoloadRegistration.disable(self)
	if err != OK:
		return
