extends Control

## Path to the folder where screenshots are saved.
const SCREENSHOTS_DIR = "user://screenshots"

# Graphics settings to be restored at the end of taking a screenshot.
var old_msaa := int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa"))
var old_shadow_quality := int(ProjectSettings.get_setting("rendering/shadows/directional_shadow/soft_shadow_quality"))
var old_shadow_size := int(ProjectSettings.get_setting("rendering/shadows/directional_shadow/size"))
var old_shadow_16_bits := bool(ProjectSettings.get_setting("rendering/shadows/directional_shadow/16_bits"))
# TODO: Requires RenderingServer SSAO quality methods to be exposed.
var old_ssao_quality := int(ProjectSettings.get_setting("rendering/environment/ssao/quality"))
var old_ssao_adaptive_target := float(ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target"))


func _ready() -> void:
	# Create folder as soon as possible so that it can be opened using the
	# Open Screenshots Folder button.
	var dir := Directory.new()
	dir.make_dir_recursive(SCREENSHOTS_DIR)


func _input(event: InputEvent) -> void:
	# TODO: Implement shortcuts.
	return
	
	if event.is_action_pressed("toggle_photo_mode"):
		visible = not visible
		
	if event.is_action_pressed("take_screenshot"):
		# Normal quality screenshot (as seen from current in-game viewport). Faster to render.
		await take_screenshot(false)
	
	if event.is_action_pressed("take_screenshot_photo"):
		# Shorthand to take high-quality screenshots during gameplay,
		# without having to go through the photo mode menu.
		await take_screenshot(true)


func apply_high_quality_settings() -> void:
	RenderingServer.directional_shadow_quality_set(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.directional_shadow_atlas_set_size(8192, false)
	# 16× MSAA causes various issues and may freeze the system entirely.
	# Stick to 8× MSAA which looks nearly as good.
	get_viewport().msaa = Viewport.MSAA_8X


func restore_old_quality_settings() -> void:
	RenderingServer.directional_shadow_quality_set(old_shadow_quality)
	RenderingServer.directional_shadow_atlas_set_size(old_shadow_size, old_shadow_16_bits)
	get_viewport().msaa = old_msaa


func take_screenshot(high_quality: bool = true) -> void:
	var viewport := get_viewport()
	
	# Perform super-sample antialiasing by rendering at a higher resolution, then downscaling the final image.
	# Unlike MSAA, this smooths out things such as specular aliasing.
	# FIXME: Window size changes when increasing viewport size, which looks strange
	# and doesn't work in fullscreen.
	const SUPERSAMPLE_FACTOR = 1
	viewport.size *= SUPERSAMPLE_FACTOR
	
	if high_quality:
		apply_high_quality_settings()

	# Wait some frames to get an up-to-date screenshot.
	await get_tree().process_frame
	await get_tree().process_frame

	#viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	var image: Image = viewport.get_texture().get_image()
	image.resize(image.get_width() / SUPERSAMPLE_FACTOR, image.get_height() / SUPERSAMPLE_FACTOR, Image.INTERPOLATE_CUBIC)
	#viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	
	if high_quality:
		restore_old_quality_settings()
	
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
