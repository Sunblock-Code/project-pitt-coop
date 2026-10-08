extends "res://coop/original_controls_menu.gd"
var grab_mode: OptionButton

func _ready():
	super._ready()
	var row = HBoxContainer.new()
	row.name = "PersonalGrabMode"
	row.add_theme_constant_override("separation", 20)
	var label = Label.new()
	label.text = "LEFT CLICK GRAB"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", load("res://assets/PublicPixel-rv0pA.ttf"))
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	grab_mode = OptionButton.new()
	grab_mode.add_item("Hold (default)")
	grab_mode.add_item("Press to pick up / drop")
	grab_mode.add_theme_font_override("font", load("res://assets/PublicPixel-rv0pA.ttf"))
	grab_mode.add_theme_font_size_override("font_size", 16)
	grab_mode.tooltip_text = "Personal setting. Other players are unaffected. Machines still require holding."
	row.add_child(grab_mode)
	var container = spin_box_sensitivity.get_parent().get_parent()
	container.add_child(row)
	container.move_child(row, spin_box_sensitivity.get_parent().get_index() + 1)
	grab_mode.select(0 if get_node("/root/PittCoop").grab_settings.hold_to_grab else 1)
	grab_mode.item_selected.connect(_grab_changed)

func _grab_changed(index: int):
	get_node("/root/PittCoop").grab_settings.set_hold(index == 0)

func _on_reset_pressed():
	super._on_reset_pressed()
	if is_instance_valid(grab_mode):
		grab_mode.select(0)
		_grab_changed(0)
