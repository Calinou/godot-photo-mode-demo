extends Control

## Path to the folder where screenshots are saved.
const SCREENSHOTS_DIR = "user://screenshots"

## Perform super-sample antialiasing by rendering at a higher resolution, then downscaling the final image.
## Unlike MSAA, this also smooths out things such as specular aliasing and shader-induced aliasing.
## Values above 2.0 have no effect.
const SUPERSAMPLE_FACTOR = 2.0

@onready var environment = get_viewport().world_3d.environment

# Graphics settings to be restored at the end of taking a screenshot.

var old_msaa := int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa"))
var old_3d_scale := float(ProjectSettings.get_setting("rendering/scaling_3d/scale"))
var old_debanding := int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding"))

var old_directional_shadow_quality := int(ProjectSettings.get_setting("rendering/shadows/directional_shadow/soft_shadow_quality"))
var old_directional_shadow_size := int(ProjectSettings.get_setting("rendering/shadows/directional_shadow/size"))
var old_directional_shadow_16_bits := bool(ProjectSettings.get_setting("rendering/shadows/directional_shadow/16_bits"))

var old_point_shadow_quality := int(ProjectSettings.get_setting("rendering/shadows/shadows/soft_shadow_quality"))
var old_point_shadow_size := int(ProjectSettings.get_setting("rendering/shadows/shadow_atlas/size"))
var old_point_shadow_16_bits := bool(ProjectSettings.get_setting("rendering/shadows/shadow_atlas/16_bits"))

var old_glow_upscale_mode := int(ProjectSettings.get_setting("rendering/environment/glow/upscale_mode"))
var old_glow_high_quality := bool(ProjectSettings.get_setting("rendering/environment/glow/use_high_quality"))

var old_ssr_quality := int(ProjectSettings.get_setting("rendering/environment/screen_space_reflection/roughness_quality"))
@onready var old_env_ssr_max_steps: int = environment.ss_reflections_max_steps

# TODO: Requires RenderingServer SSAO quality methods to be exposed.
var old_ssao_quality := int(ProjectSettings.get_setting("rendering/environment/ssao/quality"))
var old_ssao_adaptive_target := float(ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target"))

var old_volumetric_fog_volume_size := int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size"))
var old_volumetric_fog_volume_depth := int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth"))
var old_volumetric_fog_filter := int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/use_filter"))

# TODO: Requires RenderingServer GI half resolution method to be exposed.
var old_gi_use_half_resolution := int(ProjectSettings.get_setting("rendering/global_illumination/gi/use_half_resolution"))

var old_sdfgi_probe_ray_count := int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/probe_ray_count"))
var old_sdfgi_frames_to_converge := int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/frames_to_converge"))
@onready var old_env_sdfgi_occlusion: float = environment.sdfgi_use_occlusion
@onready var old_env_sdfgi_num_cascades: RenderingServer.EnvironmentSDFGICascades = environment.sdfgi_cascades
@onready var old_env_sdfgi_min_cell_size: float = environment.sdfgi_min_cell_size


func _ready() -> void:
	if get_viewport().get_camera_3d().effects == null:
		# Required to set depth of field properties in the GUI later on.
		# FIXME: Setting DoF properties appears to have no effect.
		get_viewport().get_camera_3d().effects = CameraEffects.new()

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


## Increase global illumination quality for offline rendering.
## SDFGI settings are applied separately because they require waiting for some frames
### after they have been set to be fully converged.
func apply_high_quality_sdfgi_settings() -> void:
	# We supersample only after SDFGI has fully converged to allow it to converge as fast as possible.
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_128)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	# Disable SDFGI occlusion as it can introduce dark artifacts and is unnecessary with a low cell size.
	environment.sdfgi_use_occlusion = false
	environment.sdfgi_cascades = Environment.SDFGI_CASCADES_8
	# Higher number of cascades makes it possible to decrease the cell size without compromising on maximum distance.
	# This improves GI quality for smaller objects.
	environment.sdfgi_min_cell_size *= 0.25


## Increase rendering quality settings for offline rendering.
func apply_high_quality_settings() -> void:
	# Use high-resolution 24-bit shadows.
	# 16K shadows are technically supported, but tend to require too much memory when supersampling.
	# Therefore, 8K shadows are used instead.
	RenderingServer.directional_shadow_quality_set(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.directional_shadow_atlas_set_size(8192, false)
	RenderingServer.shadows_quality_set(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.viewport_set_shadow_atlas_size(get_viewport(), 8192, false)

	# Increase post-processing effects quality.
	RenderingServer.environment_glow_set_use_bicubic_upscale(true)
	RenderingServer.environment_glow_set_use_high_quality(true)
	RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGNESS_QUALITY_HIGH)
	# Screen-space reflections' length is resolution-dependent, so adjust the number of steps to compensate.
	environment.ss_reflections_max_steps *= SUPERSAMPLE_FACTOR

	RenderingServer.environment_set_volumetric_fog_volume_size(512, 512)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)

	get_viewport().msaa = Viewport.MSAA_8X
	get_viewport().use_debanding = true


## Restore original quality settings (both SDFGI and other settings).
func restore_old_quality_settings() -> void:
	# Restore original shadow quality.
	RenderingServer.directional_shadow_quality_set(old_directional_shadow_quality)
	RenderingServer.directional_shadow_atlas_set_size(old_directional_shadow_size, old_directional_shadow_16_bits)
	RenderingServer.shadows_quality_set(old_point_shadow_quality)
	RenderingServer.viewport_set_shadow_atlas_size(get_viewport(), old_point_shadow_size, old_point_shadow_16_bits)

	# Restore original post-processing effects quality.
	RenderingServer.environment_glow_set_use_bicubic_upscale(old_glow_upscale_mode)
	RenderingServer.environment_glow_set_use_high_quality(old_glow_high_quality)
	RenderingServer.environment_set_ssr_roughness_quality(old_ssr_quality)
	environment.ss_reflections_max_steps = old_env_ssr_max_steps

	RenderingServer.environment_set_volumetric_fog_volume_size(old_volumetric_fog_volume_size, old_volumetric_fog_volume_depth)
	RenderingServer.environment_set_volumetric_fog_filter_active(old_volumetric_fog_filter)

	# Restore original global illumination quality.
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_128)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	environment.sdfgi_use_occlusion = old_env_sdfgi_occlusion
	environment.sdfgi_cascades = old_env_sdfgi_num_cascades
	environment.sdfgi_min_cell_size = old_env_sdfgi_min_cell_size

	get_viewport().msaa = old_msaa
	get_viewport().use_debanding = old_debanding


func take_screenshot(high_quality: bool = true) -> void:
	var viewport := get_viewport()

	if high_quality and environment.sdfgi_enabled:
		apply_high_quality_sdfgi_settings()
		# Downscale rendering to make it happen as fast as possible, which makes SDFGI converge faster.
		viewport.scaling_3d_scale = 0.25

		for i in 30:
			# Wait for SDFGI to fully converge.
			# Do this before enabling supersampling to make SDFGI converge faster.
			await get_tree().process_frame

	viewport.scaling_3d_scale = SUPERSAMPLE_FACTOR

	if high_quality:
		apply_high_quality_settings()

	# Hide photo mode HUD so that it's not present on the screenshot.
	visible = false

	# Wait some frames to get an up-to-date screenshot.
	await get_tree().process_frame
	await get_tree().process_frame

	var image: Image = viewport.get_texture().get_image()

	if high_quality:
		restore_old_quality_settings()

	# Restore photo mode HUD after taking the screenshot.
	visible = true

	viewport.scaling_3d_scale = old_3d_scale

	# Screenshot file name with ISO 8601-like date.
	var datetime := Time.get_datetime_dict_from_system()
	var error := image.save_png(
		"%s/%02d-%02d-%02d_%02d.%02d.%02d.png" % [SCREENSHOTS_DIR, datetime["year"], datetime["month"], datetime["day"], datetime["hour"], datetime["minute"], datetime["second"]]
	)

	if error != OK:
		push_error("Couldn't save screenshot.")


func _on_dof_near_enabled_toggled(button_pressed: bool) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_near_enabled = button_pressed


func _on_dof_near_distance_value_changed(value: float) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_far_distance = value
	$Panel/VBoxContainer/DOFNearDistance/Value.text = str(value)


func _on_dof_near_transition_value_changed(value: float) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_far_transition = value
	$Panel/VBoxContainer/DOFNearTransition/Value.text = str(value)


func _on_dof_far_enabled_toggled(button_pressed: bool) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_far_enabled = button_pressed


func _on_dof_far_distance_value_changed(value: float) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_far_distance = value
	$Panel/VBoxContainer/DOFFarDistance/Value.text = str(value)


func _on_dof_far_transition_value_changed(value: float) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_far_transition = value
	$Panel/VBoxContainer/DOFFarTransition/Value.text = str(value)


func _on_dof_amount_value_changed(value: float) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_amount = value
	$Panel/VBoxContainer/DOFAmount/Value.text = str(value)


func _on_adjustments_brightness_value_changed(value: float) -> void:
	environment.adjustment_enabled = true
	environment.adjustment_brightness = value
	$Panel/VBoxContainer/AdjustmentsBrightness/Value.text = str(value)


func _on_adjustments_contrast_value_changed(value: float) -> void:
	environment.adjustment_enabled = true
	environment.adjustment_contrast = value
	$Panel/VBoxContainer/AdjustmentsContrast/Value.text = str(value)


func _on_adjustments_saturation_value_changed(value: float) -> void:
	environment.adjustment_enabled = true
	environment.adjustment_saturation = value
	$Panel/VBoxContainer/AdjustmentsSaturation/Value.text = str(value)


func _on_reset_to_defaults_pressed() -> void:
	$Panel/VBoxContainer/DOFNearEnabled.pressed = false
	$Panel/VBoxContainer/DOFNearDistance/HSlider.value = 5.0
	$Panel/VBoxContainer/DOFNearTransition/HSlider.value = 5.0
	$Panel/VBoxContainer/DOFFarDistance/HSlider.value = 30.0
	$Panel/VBoxContainer/DOFFarTransition/HSlider.value = 15.0
	$Panel/VBoxContainer/DOFFarEnabled.pressed = false
	$Panel/VBoxContainer/DOFAmount/HSlider.value = 0.1
	$Panel/VBoxContainer/AdjustmentsBrightness/HSlider.value = 1.0
	$Panel/VBoxContainer/AdjustmentsContrast/HSlider.value = 1.0
	$Panel/VBoxContainer/AdjustmentsSaturation/HSlider.value = 1.0


func _on_take_screenshot_pressed(high_quality: bool = true) -> void:
	await take_screenshot(high_quality)


func _on_open_screenshots_folder_pressed() -> void:
	OS.shell_open(ProjectSettings.globalize_path(SCREENSHOTS_DIR))
