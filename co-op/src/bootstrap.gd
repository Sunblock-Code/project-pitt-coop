extends "res://coop/original_splash.gd"

func _ready():
	var coop = load("res://coop/coop.gd").new()
	coop.name = "PittCoop"
	get_tree().root.add_child.call_deferred(coop)
	super._ready()
