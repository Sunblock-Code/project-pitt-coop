extends Node3D
## Small, faceted industrial intern. Pure geometry keeps the mod asset-free.
const SUIT_NAMES = ["Hazard orange", "Maintenance blue", "Oxide red", "Utility olive", "Concrete", "Night shift"]
const SUITS = [Color("c56628"), Color("356481"), Color("873e38"), Color("626d47"), Color("898c82"), Color("343c4a")]
const HOLD_NAMES = ["Green", "Cyan", "Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "White"]
const HOLD_COLORS = [Color("00ff00"), Color("00eaff"), Color("438cff"), Color("a77bff"), Color("ff69d4"), Color("ff4545"), Color("ff962f"), Color("ffe34b"), Color.WHITE]
const TRIM_NAMES = ["Safety yellow", "Bone white", "Signal cyan", "Warning red", "Acid green"]
const TRIMS = [Color("efd04e"), Color("d6d1b9"), Color("61cbd1"), Color("d86d4a"), Color("a1c867")]
const VISOR_NAMES = ["Smoked", "Amber", "Ice", "Crimson"]
const VISORS = [Color("243138"), Color("956128"), Color("376981"), Color("683837")]
const HELMET_NAMES = ["Safety helmet", "Survey lamp", "Sealed respirator", "Signal antenna", "Party hat"]
const GEAR_NAMES = ["Utility belt", "Air tank", "Field pack"]
const BADGE_NAMES = ["INTERN", "MAINT", "QA", "MINING"]
const BUILD_NAMES = ["Standard", "Compact", "Broad"]
var profile: Dictionary = {}
var assembly: Node3D
var tag: Label3D
var head: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var left_leg: Node3D
var right_leg: Node3D
var phase = 0.0
var stride = 0.0
var last_position = Vector3.ZERO
var first_frame = true
var show_name = true
var preview = false
var crouched = false
var squish = 0.0
var sliding = false
var slide_blend = 0.0
var emote_id = -1
var emote_left = 0.0

static func defaults() -> Dictionary:
	return {"name": "INTERN", "suit": 0, "trim": 0, "visor": 0, "helmet": 0, "gear": 0, "badge": 0, "build": 0, "holding": 0}

static func sanitize(value: Dictionary) -> Dictionary:
	var result = defaults()
	var raw = str(value.get("name", "INTERN")).strip_edges().left(24)
	var clean = ""
	for character in raw:
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127:
			clean += character
	result.name = clean if not clean.is_empty() else "INTERN"
	for key in ["suit", "trim", "visor", "helmet", "gear", "badge", "build", "holding"]:
		var limit = {"suit": 6, "trim": 5, "visor": 4, "helmet": HELMET_NAMES.size(), "gear": 3, "badge": 4, "build": 3, "holding": HOLD_NAMES.size()}[key]
		var number = value.get(key, 0)
		result[key] = clampi(int(number), 0, limit - 1) if number is int or number is float else 0
	return result

func _material(color: Color, metallic = 0.0, emission = false) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.72
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.45
	return material

func _mesh(parent: Node3D, title: String, mesh: Mesh, position_value: Vector3, material: Material) -> MeshInstance3D:
	var item = MeshInstance3D.new()
	item.name = title
	item.mesh = mesh
	item.position = position_value
	item.material_override = material
	parent.add_child(item)
	return item

func _box(parent: Node3D, title: String, size: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	return _mesh(parent, title, mesh, position_value, material)

func _cylinder(parent: Node3D, title: String, radius: float, height: float, position_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius * 0.9
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	return _mesh(parent, title, mesh, position_value, material)

func _pivot(title: String, position_value: Vector3) -> Node3D:
	var item = Node3D.new()
	item.name = title
	item.position = position_value
	assembly.add_child(item)
	return item

func configure(value: Dictionary, name_visible = true):
	profile = sanitize(value)
	show_name = name_visible
	if is_instance_valid(assembly):
		assembly.free()
	if is_instance_valid(tag):
		tag.free()
	assembly = Node3D.new()
	assembly.name = "InternBody"
	add_child(assembly)
	var suit = _material(SUITS[profile.suit])
	var trim = _material(TRIMS[profile.trim], 0.15)
	var rubber = _material(Color("192327"))
	var metal = _material(Color("78817f"), 0.65)
	var visor = _material(VISORS[profile.visor], 0.7)
	var light = _material(TRIMS[profile.trim], 0.0, true)
	_box(assembly, "WorkJacket", Vector3(0.57, 0.59, 0.33), Vector3(0, 1.15, 0), suit)
	_box(assembly, "Waist", Vector3(0.46, 0.22, 0.29), Vector3(0, 0.77, 0), suit)
	_box(assembly, "Belt", Vector3(0.6, 0.09, 0.37), Vector3(0, 0.87, 0), rubber)
	_box(assembly, "Buckle", Vector3(0.1, 0.07, 0.025), Vector3(0, 0.87, -0.196), metal)
	for x in [-0.18, 0.18]:
		_box(assembly, "ReflectiveStrap", Vector3(0.06, 0.43, 0.016), Vector3(x, 1.16, -0.173), trim)
		_box(assembly, "BackStrap", Vector3(0.065, 0.42, 0.018), Vector3(x, 1.15, 0.175), trim)
	_box(assembly, "ChestStripe", Vector3(0.58, 0.055, 0.016), Vector3(0, 1.02, -0.174), trim)
	_box(assembly, "Zipper", Vector3(0.025, 0.51, 0.014), Vector3(0, 1.16, -0.178), rubber)
	_box(assembly, "IDCard", Vector3(0.13, 0.085, 0.025), Vector3(0.083, 1.28, -0.192), metal)
	var badge = Label3D.new()
	badge.name = "DepartmentBadge"
	badge.text = BADGE_NAMES[profile.badge]
	badge.font_size = 32
	badge.pixel_size = 0.00065
	badge.position = Vector3(0.083, 1.28, -0.21)
	badge.rotation.y = PI
	badge.modulate = Color("182024")
	badge.outline_size = 0
	assembly.add_child(badge)
	head = _pivot("Helmet", Vector3(0, 1.57, 0))
	_cylinder(head, "NeckSeal", 0.14, 0.14, Vector3(0, -0.15, 0), rubber)
	var shell = SphereMesh.new()
	shell.radius = 0.25
	shell.height = 0.44
	shell.radial_segments = 12
	shell.rings = 6
	_mesh(head, "HelmetShell", shell, Vector3.ZERO, suit)
	_box(head, "VisorGasket", Vector3(0.407, 0.195, 0.09), Vector3(0, -0.01, -0.183), rubber)
	_box(head, "Visor", Vector3(0.365, 0.148, 0.036), Vector3(0, -0.004, -0.235), visor)
	_box(head, "VisorReflection", Vector3(0.235, 0.013, 0.006), Vector3(-0.035, 0.043, -0.256), light)
	_box(head, "HelmetBrim", Vector3(0.5, 0.04, 0.39), Vector3(0, 0.09, -0.045), trim)
	_box(head, "CrownStripe", Vector3(0.06, 0.025, 0.31), Vector3(0, 0.216, 0), trim)
	for x in [-0.245, 0.245]:
		_box(head, "EarHousing", Vector3(0.055, 0.15, 0.17), Vector3(x, -0.01, 0), rubber)
		_box(head, "EarBolt", Vector3(0.062, 0.04, 0.04), Vector3(x, 0.01, -0.01), metal)
	match profile.helmet:
		1:
			_box(head, "LampMount", Vector3(0.16, 0.12, 0.12), Vector3(0, 0.125, -0.24), rubber)
			_box(head, "SurveyLamp", Vector3(0.115, 0.075, 0.02), Vector3(0, 0.13, -0.307), light)
		2:
			_box(head, "Respirator", Vector3(0.23, 0.14, 0.12), Vector3(0, -0.13, -0.25), metal)
			for x in [-0.14, 0.14]:
				var filter = _cylinder(head, "AirFilter", 0.055, 0.11, Vector3(x, -0.115, -0.25), rubber)
				filter.rotation.x = PI / 2
		3:
			_cylinder(head, "Antenna", 0.013, 0.32, Vector3(0.23, 0.23, 0.035), metal)
			_cylinder(head, "SignalTip", 0.028, 0.05, Vector3(0.23, 0.405, 0.035), light)
		4:
			# Faceted paper cone with alternating safety-color bands.
			for band in range(5):
				var cone = CylinderMesh.new()
				cone.bottom_radius = 0.22 * (1.0 - band / 5.0)
				cone.top_radius = 0.22 * (1.0 - (band + 1) / 5.0)
				cone.height = 0.10
				cone.radial_segments = 10
				_mesh(head, "PartyHatBand%d" % band, cone, Vector3(0, 0.27 + band * 0.10, 0), trim if band % 2 == 0 else suit)
			var pom = SphereMesh.new()
			pom.radius = 0.055
			pom.height = 0.11
			pom.radial_segments = 8
			pom.rings = 4
			_mesh(head, "PartyHatPom", pom, Vector3(0, 0.74, 0), light)
	left_arm = _limb("LeftArm", Vector3(-0.37, 1.36, 0), true, suit, trim, rubber)
	right_arm = _limb("RightArm", Vector3(0.37, 1.36, 0), true, suit, trim, rubber)
	left_elbow = left_arm.get_node("Elbow")
	right_elbow = right_arm.get_node("Elbow")
	left_leg = _limb("LeftLeg", Vector3(-0.15, 0.74, 0), false, suit, trim, rubber)
	right_leg = _limb("RightLeg", Vector3(0.15, 0.74, 0), false, suit, trim, rubber)
	_box(assembly, "UtilityPouch", Vector3(0.17, 0.2, 0.2), Vector3(-0.3, 0.82, 0.015), rubber)
	if profile.gear == 1:
		_box(assembly, "TankHarness", Vector3(0.38, 0.45, 0.1), Vector3(0, 1.16, 0.22), rubber)
		for x in [-0.11, 0.11]:
			_cylinder(assembly, "AirTank", 0.09, 0.49, Vector3(x, 1.18, 0.31), metal)
			_box(assembly, "TankBand", Vector3(0.18, 0.05, 0.185), Vector3(x, 1.23, 0.31), trim)
	elif profile.gear == 2:
		_box(assembly, "FieldPack", Vector3(0.43, 0.44, 0.23), Vector3(0, 1.13, 0.29), rubber)
		_box(assembly, "PackFlap", Vector3(0.44, 0.11, 0.255), Vector3(0, 1.32, 0.3), suit)
		_box(assembly, "PackReflector", Vector3(0.3, 0.045, 0.025), Vector3(0, 1.12, 0.416), trim)
	assembly.scale = [Vector3.ONE, Vector3(0.9, 0.91, 0.93), Vector3(1.15, 1.03, 1.09)][profile.build]
	tag = Label3D.new()
	tag.name = "PlayerName"
	tag.text = profile.name
	tag.position.y = 2.65 if profile.helmet == 4 else 2.18
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.pixel_size = 0.005
	tag.modulate = TRIMS[profile.trim]
	tag.outline_size = 8
	tag.visible = show_name
	add_child(tag)

func _limb(title, origin, arm, suit, trim, rubber) -> Node3D:
	var joint = _pivot(title, origin)
	if arm:
		_box(joint, "Sleeve", Vector3(0.19, 0.23, 0.23), Vector3(0, -0.095, 0), suit)
		var elbow = Node3D.new()
		elbow.name = "Elbow"
		elbow.position.y = -0.21
		joint.add_child(elbow)
		_box(elbow, "Forearm", Vector3(0.19, 0.15, 0.23), Vector3(0, -0.055, 0), suit)
		_box(elbow, "Cuff", Vector3(0.195, 0.06, 0.235), Vector3(0, -0.11, 0), trim)
		_box(elbow, "Glove", Vector3(0.165, 0.21, 0.18), Vector3(0, -0.23, -0.015), rubber)
	else:
		_box(joint, "Trouser", Vector3(0.21, 0.45, 0.27), Vector3(0, -0.2, 0), suit)
		_box(joint, "KneePad", Vector3(0.17, 0.15, 0.04), Vector3(0, -0.28, -0.145), rubber)
		_box(joint, "AnkleBand", Vector3(0.215, 0.05, 0.28), Vector3(0, -0.4, 0), trim)
		_box(joint, "WorkBoot", Vector3(0.245, 0.26, 0.39), Vector3(0, -0.595, -0.06), rubber)
	return joint

func _process(delta):
	if not is_instance_valid(assembly):
		return
	var travel = 0.0 if first_frame else Vector2(global_position.x - last_position.x, global_position.z - last_position.z).length() / maxf(delta, 0.001)
	first_frame = false
	last_position = global_position
	stride = lerpf(stride, clampf(travel / 3.5, 0, 1), minf(delta * 10, 1))
	phase += delta * (8.0 if not preview else 1.8)
	left_elbow.rotation = Vector3.ZERO
	right_elbow.rotation = Vector3.ZERO
	left_arm.rotation.y = 0
	right_arm.rotation.y = 0
	head.rotation = Vector3.ZERO
	assembly.rotation.y = 0
	var swing = sin(phase) * 0.5 * stride
	left_leg.rotation.x = swing
	right_leg.rotation.x = -swing
	left_arm.rotation.x = -swing * 0.8
	right_arm.rotation.x = swing * 0.8
	left_arm.rotation.z = 0.07
	right_arm.rotation.z = -0.07
	assembly.position.y = sin(phase * 2) * 0.015 * stride + sin(phase * 0.4) * 0.004
	squish = lerpf(squish, 1.0 if crouched else 0.0, 1.0 - exp(-16.0 * delta))
	var build_scale: Vector3 = [Vector3.ONE, Vector3(0.9, 0.91, 0.93), Vector3(1.15, 1.03, 1.09)][profile.build]
	# Squash from the feet: a short, wide intern, without widening the collider.
	assembly.scale = build_scale * Vector3(1.0 + 0.3 * squish, 1.0 - 0.5 * squish, 1.0 + 0.2 * squish)
	tag.position.y = (2.65 if profile.helmet == 4 else 2.18) * (1.0 - 0.5 * squish)
	slide_blend = lerpf(slide_blend, 1.0 if sliding else 0.0, 1.0 - exp(-20.0 * delta))
	# Feet-forward floor slide, leaning back with arms out for balance.
	assembly.scale = assembly.scale.lerp(build_scale * Vector3(1.18, 0.65, 1.0), slide_blend)
	assembly.rotation.x = 0.25 * slide_blend
	assembly.rotation.z = sin(phase * 1.6) * 0.035 * slide_blend
	assembly.position.y = lerpf(assembly.position.y, -0.4, slide_blend)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, 1.2, slide_blend)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, 1.35, slide_blend)
	left_leg.rotation.z = 0.1 * slide_blend
	right_leg.rotation.z = -0.1 * slide_blend
	left_arm.rotation.x = lerpf(left_arm.rotation.x, -0.45, slide_blend)
	right_arm.rotation.x = lerpf(right_arm.rotation.x, -0.45, slide_blend)
	left_arm.rotation.z = lerpf(left_arm.rotation.z, 0.65, slide_blend)
	right_arm.rotation.z = lerpf(right_arm.rotation.z, -0.65, slide_blend)
	tag.position.y = lerpf(tag.position.y, 1.3 if profile.helmet == 4 else 1.0, slide_blend)
	_animate_emote(delta, travel)


func start_emote(index: int):
	emote_id = index
	emote_left = 4.0

func _animate_emote(delta: float, travel: float):
	if travel > 0.6 or crouched or sliding: emote_left = 0.0
	emote_left = maxf(0.0, emote_left - delta)
	if emote_left <= 0.0: return
	var t = 4.0 - emote_left
	var blend = smoothstep(0.0, 0.45, t) * smoothstep(0.0, 0.5, emote_left)
	match emote_id:
		0:
			# Shoulder stays raised; the bent forearm makes the greeting readable.
			right_arm.rotation.z = lerpf(right_arm.rotation.z, 1.8, blend)
			right_arm.rotation.x = -0.18 * blend
			right_elbow.rotation.z = (0.9 + sin(t * 6.5) * 0.38) * blend
			head.rotation.z = -0.08 * blend
			assembly.rotation.z += -0.025 * sin(t * 3.25) * blend
		1:
			left_arm.rotation.z = lerpf(left_arm.rotation.z, 2.6, blend)
			right_arm.rotation.z = lerpf(right_arm.rotation.z, -2.6, blend)
			assembly.position.y += absf(sin(t * 8)) * 0.12 * blend
		2:
			left_arm.rotation.z = lerpf(left_arm.rotation.z, 1.1 + sin(t * 7) * 0.5, blend)
			right_arm.rotation.z = lerpf(right_arm.rotation.z, -1.1 + sin(t * 7) * 0.5, blend)
			assembly.rotation.z += sin(t * 7) * 0.16 * blend
			left_leg.rotation.x += sin(t * 7) * 0.6 * blend
			right_leg.rotation.x -= sin(t * 7) * 0.6 * blend
		3:
			left_arm.rotation.z = lerpf(left_arm.rotation.z, 1.2, blend)
			right_arm.rotation.z = lerpf(right_arm.rotation.z, -1.2, blend)
			assembly.position.y += 0.035 * blend

		4: # Salute, pause, lower the hand.
			right_arm.rotation.z = lerpf(right_arm.rotation.z, 2.15, blend)
			right_arm.rotation.x = -0.3 * blend
			right_elbow.rotation.z = 1.5 * blend
			head.rotation.x = -0.07 * blend
		5: # Bow forward, keeping feet planted.
			var bow = sin(clampf((t-0.35)/3.15,0,1)*PI)
			assembly.rotation.x -= 0.65 * bow * blend
			assembly.position.z = 0.0
			left_arm.rotation.x = 0.4 * bow * blend
			right_arm.rotation.x = 0.4 * bow * blend
			head.rotation.x = -0.18 * bow * blend
		6: # Robot: alternating bent arms and deliberate quarter-turns.
			var beat = t * 2.0
			var step = int(floor(beat))
			var change = smoothstep(0.0,0.25,fposmod(beat,1.0))
			var previous = 1.0 if step % 2 == 0 else -1.0
			var pose = lerpf(previous,-previous,change)
			left_arm.rotation.z = lerpf(left_arm.rotation.z,-0.9,blend)
			right_arm.rotation.z = lerpf(right_arm.rotation.z,0.9,blend)
			left_elbow.rotation.x = (-1.2 + pose*0.5)*blend
			right_elbow.rotation.x = (-1.2 - pose*0.5)*blend
			assembly.rotation.y = pose*0.18*blend
			head.rotation.y = -pose*0.3*blend
