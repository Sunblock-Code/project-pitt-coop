extends "res://coop/original_elevator.gd"

func start_sequence():
	var coop = get_node_or_null("/root/PittCoop")
	if coop and coop.role == "host":
		await coop.board_elevator(self)
		if not is_inside_tree():
			return
		coop.elevator_event("ride", self)
	super.start_sequence()

func open_doors(instant = false):
	var was_open = doors_open
	super.open_doors(instant)
	var coop = get_node_or_null("/root/PittCoop")
	if coop and coop.role == "host" and not was_open and doors_open:
		coop.elevator_event("open", self)

func close_doors():
	var coop = get_node_or_null("/root/PittCoop")
	# Let every intern leave before the arrival doors close.
	if coop and coop.role == "host" and not escape_armed and coop.guest_in_elevator(self):
		await get_tree().create_timer(0.25).timeout
		if is_inside_tree() and not player_inside:
			close_doors()
		return
	super.close_doors()
	if coop and coop.role == "host":
		coop.elevator_event("close", self)
