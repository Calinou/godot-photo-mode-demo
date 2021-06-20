extends Control

## Path to the folder where screenshots are saved.
const SCREENSHOTS_DIR = "user://screenshots"


func _ready() -> void:
	# Create folder as soon as possible so that it can be opened using the
	# Open Screenshots Folder button.
	var dir := Directory.new()
	dir.make_dir_recursive(SCREENSHOTS_DIR)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_photo_mode"):
		visible = not visible
		
	if event.is_action_pressed("take_screenshot"):
		# Normal quality screenshot (as seen from current in-game viewport). Faster to render.
		await take_screenshot(false)
	
	if event.is_action_pressed("take_screenshot_photo"):
		# Shorthand to take high-quality screenshots during gameplay,
		# without having to go through the photo mode menu.
		await take_screenshot(true)


func take_screenshot(high_quality: bool = true) -> void:
	var viewport := get_viewport()
	
	# Perform super-sample antialiasing by rendering at a higher resolution, then downscaling the final image.
	# Unlike MSAA, this smooths out things such as specular aliasing.
	const SUPERSAMPLE_FACTOR = 2
	viewport.size *= SUPERSAMPLE_FACTOR

	# Wait some frames to get an up-to-date screenshot.
	await get_tree().process_frame
	await get_tree().process_frame

	#viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	var image: Image = viewport.get_texture().get_image()
	image.resize(image.get_width() / SUPERSAMPLE_FACTOR, image.get_height() / SUPERSAMPLE_FACTOR, Image.INTERPOLATE_CUBIC)
	#viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	
	viewport.size /= SUPERSAMPLE_FACTOR

	# Screenshot file name with ISO 8601-like date.
	var datetime := Time.get_datetime_dict_from_system()
	var error := image.save_png(
		"%s/%02d-%02d-%02d_%02d.%02d.%02d.png" % [SCREENSHOTS_DIR, datetime["year"], datetime["month"], datetime["day"], datetime["hour"], datetime["minute"], datetime["second"]]
	)

	if error != OK:
		push_error("Couldn't save screenshot.")


func _on_take_screenshot_pressed(high_quality: bool = true) -> void:
	await take_screenshot(high_quality)


func _on_open_screenshots_folder_pressed() -> void:
	OS.shell_open(ProjectSettings.globalize_path(SCREENSHOTS_DIR))
