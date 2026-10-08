extends Node

var session: Node
var effects: Array[Node3D] = []
var camera: Camera3D
var manager: Node
var applied_settings: Array = []
var host_pixels: Dictionary = {}

func match_host(pixels: Dictionary, enabled: bool):
	if host_pixels == pixels and manager.psx_enabled == enabled: return
	host_pixels = pixels.duplicate()
	manager.psx_enabled = enabled
	manager.pixelation_strength = pixels.strength
	manager.dither_intensity = pixels.dither
	manager.color_levels = pixels.colors
	_apply_resolution()

func copy_effects(world: Node):
	for original in world.find_children("*", "MeshInstance3D", true, false):
		if not original.is_in_group("retro"): continue
		var copy = original.duplicate(0)
		copy.set_script(null)
		copy.add_to_group("retro")
		effects.append(copy)

func _ready():
	manager = get_node("/root/PostProcessManager")
	if session.test_mode and "--postfx-test" in OS.get_cmdline_user_args(): manager.apply_psx_toggle(false)
	process_priority = 200
	_update_camera()
	_apply_resolution()
	get_viewport().size_changed.connect(_apply_resolution)
	if session.test_mode and "--postfx-test" in OS.get_cmdline_user_args(): _qa.call_deferred()

func _process(_delta):
	_update_camera()
	var settings = [get_viewport().size, manager.psx_enabled, manager.render_scale, get_viewport().scaling_3d_scale]
	if settings != applied_settings:
		applied_settings = settings
		_apply_resolution()
	for effect in effects: effect.visible = manager.psx_enabled

func _update_camera():
	var active = get_viewport().get_camera_3d()
	if active == null or active == camera: return
	camera = active
	for effect in effects:
		if effect.get_parent(): effect.reparent(camera, false)
		else: camera.add_child(effect)
		# Keep the original full-screen shader quad in the active camera frustum.
		effect.extra_cull_margin = 16384.0

func _apply_resolution():
	manager.apply_render_scale()
	if manager.psx_enabled and not host_pixels.is_empty():
		# Use the same rendered pixel height even when the monitors differ.
		get_viewport().scaling_3d_scale = clampf(float(host_pixels.height) / maxf(1, get_viewport().size.y), 0.1, 1.0)
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	manager.update_post_processing()

func _qa():
	await get_tree().create_timer(27.0).timeout
	var report = {"effects": effects.size(), "psx": manager.psx_enabled, "scale": get_viewport().scaling_3d_scale, "nearest": get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_NEAREST, "camera": str(camera.get_path()), "passed": effects.size() > 0 and manager.psx_enabled and get_viewport().scaling_3d_scale < 1.0}
	report.host_pixel_height_matches = not host_pixels.is_empty() and absf(get_viewport().size.y * get_viewport().scaling_3d_scale - host_pixels.height) < 1.0
	report.host_pixels = host_pixels
	report.viewport_size = get_viewport().size
	report.host_dither_matches = not host_pixels.is_empty() and manager.dither_intensity == host_pixels.dither
	report.host_colors_match = not host_pixels.is_empty() and manager.color_levels == host_pixels.colors
	get_viewport().scaling_3d_scale = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	report.scale_override_repaired = absf(get_viewport().size.y * get_viewport().scaling_3d_scale - host_pixels.height) < 1.0
	if is_instance_valid(session.view_rig):
		session.view_rig.set_active(true)
		await get_tree().create_timer(0.2).timeout
		report.third_person = camera == session.view_rig.camera and effects[0].get_parent() == camera
		session.view_rig.set_active(false)
		await get_tree().create_timer(0.2).timeout
		report.first_person = effects[0].get_parent() == get_viewport().get_camera_3d()
	manager.apply_psx_toggle(false)
	await get_tree().process_frame
	report.toggle_off = not effects[0].visible
	manager.apply_psx_toggle(true)
	await get_tree().process_frame
	report.toggle_on = effects[0].visible and get_viewport().scaling_3d_scale < 1.0
	report.passed = report.passed and report.get("third_person", false) and report.get("first_person", false) and report.toggle_off and report.toggle_on and report.host_pixel_height_matches and report.host_dither_matches and report.host_colors_match and report.scale_override_repaired
	var directory = OS.get_executable_path().get_base_dir().path_join("../logs")
	var file = FileAccess.open(directory.path_join("postfx.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("postfx.png"))
