@tool
extends EditorScenePostImport

## glTF has no standard loop flag. Apply the portable pack's sidecar policy
## during import so every consumer (not just the preview) gets correct loops.
func _post_import(scene: Node) -> Object:
	var manifest_path := get_source_file().get_base_dir().path_join("animation_manifest.json")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not manifest.has("clips"):
		push_error("Mannequin import requires its animation_manifest.json sidecar")
		return scene
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for key in player.get_animation_list():
			var clip := String(key).get_file()
			if manifest["clips"].has(clip):
				var animation := player.get_animation(key)
				animation.loop_mode = Animation.LOOP_LINEAR if manifest["clips"][clip]["loop"] else Animation.LOOP_NONE
	return scene
