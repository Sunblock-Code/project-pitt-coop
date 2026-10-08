extends Control
signal saved(profile: Dictionary)
signal cancelled
const Avatar = preload("res://coop/avatar.gd")
const INK = Color("0c151c")
const PANEL = Color("15232c")
const AMBER = Color("efca50")
const PAPER = Color("d4d7c6")
var draft: Dictionary
var name_input: LineEdit
var selectors: Dictionary = {}
var preview_avatar: Node3D
var preview_stage: Node3D
var preview_viewport: SubViewport
var preview_name: Label
var preview_badge: Label
var feedback: Label
var dragging = false
var font: Font

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = load("res://assets/PublicPixel-rv0pA.ttf")
	var theme_value = Theme.new()
	theme_value.default_font = font
	theme_value.default_font_size = 15
	for type in ["Label", "Button", "LineEdit", "OptionButton", "PopupMenu"]:
		theme_value.set_color("font_color", type, PAPER)
	for type in ["Button", "OptionButton", "LineEdit"]:
		theme_value.set_stylebox("normal", type, _style(PANEL, Color("3c4d51")))
		theme_value.set_stylebox("hover", type, _style(Color("273b40"), AMBER))
		theme_value.set_stylebox("pressed", type, _style(Color("354749"), AMBER))
		theme_value.set_stylebox("focus", type, _style(Color(0, 0, 0, 0), AMBER))
		theme_value.set_color("font_hover_color", type, AMBER)
	theme_value.set_stylebox("panel", "PopupMenu", _style(INK, AMBER))
	theme_value.set_stylebox("hover", "PopupMenu", _style(PANEL, AMBER))
	theme_value.set_color("font_hover_color", "PopupMenu", AMBER)
	theme = theme_value
	var dim = ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.04, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(1060, 790)
	card.add_theme_stylebox_override("panel", _style(INK, AMBER, 2, 26))
	center.add_child(card)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	card.add_child(column)
	var eyebrow = _label("P.I.T.T.  /  PERSONNEL DIVISION", 13, AMBER)
	column.add_child(eyebrow)
	var header = HBoxContainer.new()
	column.add_child(header)
	var title = _label("CHARACTER", 30, PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("EMPLOYEE ISSUE 02", 12, Color("83968f")))
	column.add_child(_label("Register your name. Report for your shift.", 13, Color("94a49d")))
	var rule = ColorRect.new()
	rule.color = AMBER
	rule.custom_minimum_size.y = 3
	column.add_child(rule)
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 390
	left.add_theme_constant_override("separation", 13)
	body.add_child(left)
	left.add_child(_label("01  /  UNIFORM INSPECTION", 12, AMBER))
	var preview_frame = PanelContainer.new()
	preview_frame.add_theme_stylebox_override("panel", _style(PANEL, Color("3c4d51")))
	left.add_child(preview_frame)
	var view = SubViewportContainer.new()
	view.custom_minimum_size = Vector2(368, 432)
	view.stretch = true
	preview_frame.add_child(view)
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(368, 432)
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_viewport.msaa_3d = Viewport.MSAA_2X
	view.add_child(preview_viewport)
	view.gui_input.connect(_preview_input)
	_build_preview()
	var rotations = HBoxContainer.new()
	rotations.add_theme_constant_override("separation", 8)
	left.add_child(rotations)
	_button(rotations, "< ROTATE", func(): preview_stage.rotation.y -= PI / 4)
	_button(rotations, "ROTATE >", func(): preview_stage.rotation.y += PI / 4)
	preview_name = _label("INTERN", 20, PAPER)
	left.add_child(preview_name)
	preview_badge = _label("INTERN  /  P.I.T.T.", 12, AMBER)
	left.add_child(preview_badge)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	right.add_child(_label("02  /  EMPLOYEE RECORD", 12, AMBER))
	right.add_child(_label("MULTIPLAYER NAME", 12, PAPER))
	name_input = LineEdit.new()
	name_input.max_length = 24
	name_input.custom_minimum_size.y = 44
	name_input.placeholder_text = "INTERN"
	name_input.text_changed.connect(func(value): draft.name = value; _update_preview())
	right.add_child(name_input)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	right.add_child(grid)
	for row in [["suit", "WORK SUIT", Avatar.SUIT_NAMES], ["trim", "SAFETY TRIM", Avatar.TRIM_NAMES], ["visor", "VISOR", Avatar.VISOR_NAMES], ["helmet", "HEADGEAR", Avatar.HELMET_NAMES], ["gear", "EQUIPMENT", Avatar.GEAR_NAMES], ["badge", "DEPARTMENT", Avatar.BADGE_NAMES], ["build", "BUILD", Avatar.BUILD_NAMES], ["holding", "HOLDING COLOR", Avatar.HOLD_NAMES]]:
		grid.add_child(_label(row[1], 12, Color("94a49d")))
		var options = OptionButton.new()
		options.custom_minimum_size = Vector2(270, 39)
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option in row[2]:
			options.add_item(option)
		var key = row[0]
		options.item_selected.connect(func(index): draft[key] = index; _update_preview())
		selectors[key] = options
		grid.add_child(options)
	feedback = _label("Your crew sees this uniform and name.\nF5 switches your view in-game.", 12, Color("94a49d"))
	feedback.custom_minimum_size.y = 52
	right.add_child(feedback)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_button(actions, "RANDOMIZE", _randomize)
	_button(actions, "CANCEL", _cancel)
	var save = _button(actions, "SAVE CHARACTER", _save)
	save.add_theme_color_override("font_color", AMBER)
	save.add_theme_stylebox_override("normal", _style(Color("303c2d"), AMBER))
	hide()
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _style(background, border, thickness = 1, margin = 10) -> StyleBoxFlat:
	var value = StyleBoxFlat.new()
	value.bg_color = background
	value.border_color = border
	value.set_border_width_all(thickness)
	value.content_margin_left = margin
	value.content_margin_right = margin
	value.content_margin_top = margin
	value.content_margin_bottom = margin
	return value

func _label(text_value: String, size: int, color: Color) -> Label:
	var label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(parent, text_value, callback) -> Button:
	var button = Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_preview():
	var world = Node3D.new()
	preview_viewport.add_child(world)
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182b35")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c7d4de")
	environment.environment.ambient_light_energy = 0.55
	world.add_child(environment)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color("ffdf9b")
	key.light_energy = 1.6
	world.add_child(key)
	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 145, 0)
	rim.light_color = Color("7cb2cc")
	rim.light_energy = 1.1
	world.add_child(rim)
	var camera = Camera3D.new()
	camera.position = Vector3(0, 1.16, -4.2)
	world.add_child(camera)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.7
	preview_stage = Node3D.new()
	preview_stage.rotation.y = -0.3
	world.add_child(preview_stage)
	preview_avatar = Avatar.new()
	preview_avatar.preview = true
	preview_stage.add_child(preview_avatar)
	var platform = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.7
	mesh.bottom_radius = 0.73
	mesh.height = 0.06
	mesh.radial_segments = 32
	platform.mesh = mesh
	platform.position.y = -0.035
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("536361")
	platform.material_override = material
	world.add_child(platform)

func open(profile_value: Dictionary):
	draft = Avatar.sanitize(profile_value)
	name_input.text = draft.name
	for key in selectors:
		selectors[key].select(draft[key])
	preview_stage.rotation.y = -0.3
	_update_preview()
	show()
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	name_input.grab_focus()

func _update_preview():
	preview_avatar.configure(draft, false)
	var clean = Avatar.sanitize(draft)
	preview_name.text = clean.name
	preview_badge.text = Avatar.BADGE_NAMES[clean.badge] + "  /  HOLD: " + Avatar.HOLD_NAMES[clean.holding].to_upper()
	preview_badge.add_theme_color_override("font_color", Avatar.HOLD_COLORS[clean.holding])

func _preview_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		preview_stage.rotation.y += event.relative.x * 0.013

func _randomize():
	for key in selectors:
		draft[key] = randi_range(0, selectors[key].item_count - 1)
		selectors[key].select(draft[key])
	_update_preview()

func _save():
	saved.emit(Avatar.sanitize(draft))

func _cancel():
	cancelled.emit()

func close():
	hide()
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
