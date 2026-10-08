extends "res://coop/original_upgrade_ui.gd"

var bridge: Node
var offer_nodes: Array = []
var offer_parents: Array = []

func _ready():
	separator_scene = PackedScene.new()
	separator_scene.pack(separator)
	_setup_audio()
	original_position = position
	_apply_terminal_theme()
	for container in [tab_container, tools_tab_container, products_tab]:
		container.tab_changed.connect(_on_tab_changed)
	for content in [tab_container.get_node("Upgrades/ScrollContainer/Content"), tab_container.get_node("Toys/ScrollContainer/Content"), tab_container.get_node("Combos")]:
		offer_parents.append(content)
	for content in tool_tabs.values() + product_tabs.values() + panel_subtabs.values():
		offer_parents.append(content)
	clear_offers()

func clear_offers():
	clear_tooltip()
	for parent in offer_parents:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	offer_nodes.clear()

# All offers and purchase callbacks come from the authoritative catalog.
func update_ui():
	pass

func hide_menu():
	bridge.close()

func _unhandled_input(event):
	if visible: super._unhandled_input(event)
