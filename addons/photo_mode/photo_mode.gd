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
var old_screen_space_aa := int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa"))
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

var old_dof_bokeh_shape = int(ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_shape"))
# TODO: Needs bokeh quality and jitter setters to be exposed in RenderingServer.
var old_dof_bokeh_quality = int(ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_quality"))
var old_dof_bokeh_jitter = bool(ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_use_jitter"))

var old_subsurface_scattering_quality := int(ProjectSettings.get_setting("rendering/environment/subsurface_scattering/subsurface_scattering_quality"))

var old_ssr_quality := int(ProjectSettings.get_setting("rendering/environment/screen_space_reflection/roughness_quality"))
@onready var old_env_ssr_max_steps: int = environment.ss_reflections_max_steps

var old_ssao_quality := int(ProjectSettings.get_setting("rendering/environment/ssao/quality"))
var old_ssao_half_size := bool(ProjectSettings.get_setting("rendering/environment/ssao/half_size"))
var old_ssao_adaptive_target := float(ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target"))
var old_ssao_blur_passes := int(ProjectSettings.get_setting("rendering/environment/ssao/blur_passes"))
var old_ssao_fadeout_from := float(ProjectSettings.get_setting("rendering/environment/ssao/fadeout_from"))
var old_ssao_fadeout_to := float(ProjectSettings.get_setting("rendering/environment/ssao/fadeout_to"))

var old_volumetric_fog_volume_size := int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size"))
var old_volumetric_fog_volume_depth := int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth"))
var old_volumetric_fog_filter := int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/use_filter"))

# TODO: Needs half-resolution GI setter to be exposed in RenderingServer.
var old_gi_use_half_resolution := int(ProjectSettings.get_setting("rendering/global_illumination/gi/use_half_resolution"))

var old_voxel_gi_quality := int(ProjectSettings.get_setting("rendering/global_illumination/voxel_gi/quality"))

var old_sdfgi_probe_ray_count := int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/probe_ray_count"))
var old_sdfgi_frames_to_converge := int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/frames_to_converge"))
var old_sdfgi_frames_to_update_lights := int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/frames_to_update_lights"))
@onready var old_env_sdfgi_occlusion: float = environment.sdfgi_use_occlusion
@onready var old_env_sdfgi_num_cascades: RenderingServer.EnvironmentSDFGICascades = environment.sdfgi_cascades
@onready var old_env_sdfgi_min_cell_size: float = environment.sdfgi_min_cell_size

# TODO: High-quality settings for environment sky filtering. Requires setters to be exposed in RenderingServer
# (which will also have to force regeneration of the sky radiance map).


func _ready() -> void:
	if get_viewport().get_camera_3d().effects == null:
		# Required to set depth of field properties in the GUI later on.
		# FIXME: This doesn't work; setting DoF properties appears to have no effect if no CameraEffects
		# resource is present (i.e. if this code branch runs).
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
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_1_FRAME)
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

	RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_HIGH)

	# Increase post-processing effects quality.
	RenderingServer.environment_glow_set_use_bicubic_upscale(true)
	RenderingServer.environment_glow_set_use_high_quality(true)
	RenderingServer.camera_effects_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	# Depth of field amount is resolution-dependent, so adjust the amount to compensate.
	get_viewport().get_camera_3d().effects.dof_blur_amount *= SUPERSAMPLE_FACTOR

	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH)
	# Keep the existing SSAO fadeout values as they can be used for artistic control.
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA, false, 1.0, 2, old_ssao_fadeout_from, old_ssao_fadeout_to)
	RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGNESS_QUALITY_HIGH)
	# Screen-space reflections' length is resolution-dependent, so adjust the number of steps to compensate.
	environment.ss_reflections_max_steps *= SUPERSAMPLE_FACTOR

	RenderingServer.environment_set_volumetric_fog_volume_size(512, 512)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)

	get_viewport().msaa = Viewport.MSAA_8X
	# Since the rendering is supersampled, we don't lose much sharpness (if any)
	# by enabling FXAA. FXAA will still help further reduce shader-induced aliasing
	# even when supersampling.
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	get_viewport().use_debanding = true


## Restore original quality settings (both SDFGI and other settings).
func restore_old_quality_settings() -> void:
	# Restore original shadow quality.
	RenderingServer.directional_shadow_quality_set(old_directional_shadow_quality)
	RenderingServer.directional_shadow_atlas_set_size(old_directional_shadow_size, old_directional_shadow_16_bits)
	RenderingServer.shadows_quality_set(old_point_shadow_quality)
	RenderingServer.viewport_set_shadow_atlas_size(get_viewport(), old_point_shadow_size, old_point_shadow_16_bits)

	RenderingServer.voxel_gi_set_quality(old_voxel_gi_quality)

	# Restore original post-processing effects quality.
	RenderingServer.environment_glow_set_use_bicubic_upscale(old_glow_upscale_mode)
	RenderingServer.environment_glow_set_use_high_quality(old_glow_high_quality)
	RenderingServer.camera_effects_set_dof_blur_bokeh_shape(old_dof_bokeh_shape)
	get_viewport().get_camera_3d().effects.dof_blur_amount /= SUPERSAMPLE_FACTOR
	RenderingServer.sub_surface_scattering_set_quality(old_subsurface_scattering_quality)
	RenderingServer.environment_set_ssao_quality(
			old_ssao_quality,
			old_ssao_half_size,
			old_ssao_adaptive_target,
			old_ssao_blur_passes,
			old_ssao_fadeout_from,
			old_ssao_fadeout_to
	)
	RenderingServer.environment_set_ssr_roughness_quality(old_ssr_quality)
	environment.ss_reflections_max_steps = old_env_ssr_max_steps

	RenderingServer.environment_set_volumetric_fog_volume_size(old_volumetric_fog_volume_size, old_volumetric_fog_volume_depth)
	RenderingServer.environment_set_volumetric_fog_filter_active(old_volumetric_fog_filter)

	# Restore original global illumination quality.
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_128)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(old_sdfgi_frames_to_update_lights)
	environment.sdfgi_use_occlusion = old_env_sdfgi_occlusion
	environment.sdfgi_cascades = old_env_sdfgi_num_cascades
	environment.sdfgi_min_cell_size = old_env_sdfgi_min_cell_size

	get_viewport().msaa = old_msaa
	get_viewport().screen_space_aa = old_screen_space_aa
	get_viewport().use_debanding = old_debanding


func take_screenshot(high_quality: bool = true) -> void:
	var viewport := get_viewport()

	if high_quality and environment.sdfgi_enabled:
		apply_high_quality_sdfgi_settings()
		# Downscale rendering to the minimum allowed value to make rendering happen as fast as possible,
		# which makes SDFGI converge faster.
		viewport.scaling_3d_scale = 0.1

		for i in 30:
			# Wait for SDFGI to fully converge.
			# Do this before enabling supersampling and high-quality settings to make SDFGI converge faster.
			await get_tree().process_frame

	viewport.scaling_3d_scale = SUPERSAMPLE_FACTOR

	if high_quality:
		apply_high_quality_settings()

	# Hide photo mode HUD so that it's not present on the screenshot.
	visible = false

	for i in 3:
		# Wait some frames to get an up-to-date screenshot
		# (3 frames are required to have correct sky rendering).
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
	get_viewport().get_camera_3d().effects.dof_blur_near_distance = value
	$Panel/VBoxContainer/DOFNearDistance/Value.text = str(value)


func _on_dof_near_transition_value_changed(value: float) -> void:
	get_viewport().get_camera_3d().effects.dof_blur_near_transition = value
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
