@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_autoload_singleton("PhotoMode", "res://addons/photo_mode/photo_mode.tscn")

	if not ProjectSettings.has_setting("addons/photo_mode/pause_on_screenshot"):
		ProjectSettings.set_setting("addons/photo_mode/pause_on_screenshot", true)

	ProjectSettings.set_initial_value("addons/photo_mode/pause_on_screenshot", true)
	ProjectSettings.add_property_info({
		name = "addons/photo_mode/pause_on_screenshot",
		type = TYPE_BOOL,
	})


func _exit_tree() -> void:
	remove_autoload_singleton("PhotoMode")
	# Don't remove the project setting's value, as the plugin may be re-enabled in the future.
