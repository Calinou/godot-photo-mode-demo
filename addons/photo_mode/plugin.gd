@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_autoload_singleton("PhotoMode", "res://addons/photo_mode/photo_mode.tscn")


func _exit_tree() -> void:
	remove_autoload_singleton("PhotoMode")
