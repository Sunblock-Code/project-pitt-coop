extends "res://coop/original_duck.gd"

# The original frame callback only counts down impact-audio cooldown.
# Run it while needed; keep physics, collision response and sounds native.
func _ready():
	set_process(collision_cooldown > 0.0)
	sleeping_state_changed.connect(_sleep_changed)
	_sleep_changed()

func _sleep_changed():
	# Stationary ducks need no per-tick velocity sampling. Jolt wakes them
	# normally; the wake signal restores the original callback immediately.
	set_physics_process(not sleeping)
	if sleeping: last_velocity = Vector3.ZERO

func _physics_process(delta):
	if sleeping:
		_sleep_changed()
		return
	super._physics_process(delta)

func _process(delta):
	super._process(delta)
	if collision_cooldown <= 0.0: set_process(false)

func _on_body_entered(body):
	# Explicit wakes by tools need not emit sleeping_state_changed.
	if not sleeping: set_physics_process(true)
	var was_cooling = collision_cooldown > 0.0
	super._on_body_entered(body)
	if not was_cooling and collision_cooldown > 0.0 and collision_audio.playing:
		var coop = get_node_or_null("/root/PittCoop")
		if coop and coop.role == "host": coop.publish_body_audio(self, collision_audio)
	if collision_cooldown > 0.0: set_process(true)

func on_pool_spawn():
	super.on_pool_spawn()
	set_physics_process(true)
	set_process(collision_cooldown > 0.0)
