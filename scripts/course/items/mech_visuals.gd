class_name MechVisuals
extends Node3D
## Articulated giant suit. Same stride idea as the player robot: pace fades the
## walk in, arms counter-swing, and a parked suit idles with a hydraulic bob.

const MODEL_PATH := "res://assets/mechs/mech_suit.glb"
const SCALE := 4.0
const HEIGHT := 5.0 * SCALE
const WIDTH := 2.4 * SCALE
const HATCH := "Hatch"
const STAIRS := "Stairs"
const RAMP := "StairRamp"
const DECK := "BoardDeck"
const LEFT_POD := "LeftPod"
const RIGHT_POD := "RightPod"
const STEP_RISE := 0.32
const STEP_RUN := 0.38
const STEP_WIDTH := 2.8
const STEP_THICK := 0.12
const PLATFORM_Y := 3.05 * SCALE
const PLATFORM_Z := 3.28
const PLATFORM_SIZE := Vector3(3.2, 0.22, 2.2)

const HIP_Y := 2.22
const STRIDE_RATE := 4.6
const LEG_SWING_DEG := 24.0
const ARM_SWING_DEG := 32.0
const KNEE_DEG := 28.0
const ELBOW_DEG := 22.0
const LEAN_DEG := 7.0
const TWIST_DEG := 8.0
const BOUNCE := 0.1
const IDLE_BOB := 0.035

var hips: Node3D
var torso: Node3D
var head: Node3D
var hatch: Node3D
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var arms: Array[Node3D] = []
var elbows: Array[Node3D] = []
var _phase := 0.0
var _idle := 0.0


static func build() -> MechVisuals:
	var root := MechVisuals.new()
	root.name = "Visuals"
	root._assemble()
	return root


static func attach(suit: CollisionObject3D) -> MechVisuals:
	_fit_body(suit)
	add_stair_collision(suit)
	var root := build()
	suit.add_child(root)
	root._bind_muzzles(suit)
	return root


static func set_closed(root: Node3D, on: bool) -> void:
	var body := root as MechVisuals
	if body != null:
		body.apply_closed(on)
		return
	var hatch_node := root.find_child(HATCH, true, false) as Node3D
	if hatch_node != null:
		hatch_node.rotation.x = deg_to_rad(-8.0 if on else -78.0)
	set_stairs(root, not on)


static func set_stairs(root: Node3D, on: bool) -> void:
	var stairs := root.get_node_or_null(STAIRS) as Node3D
	if stairs != null:
		stairs.visible = on


static func set_stairs_solid(suit: CollisionObject3D, on: bool) -> void:
	for name: String in [RAMP, DECK]:
		var shape := suit.get_node_or_null(name) as CollisionShape3D
		if shape != null:
			shape.disabled = not on


static func mini(parent: Node3D, scale := 0.22) -> Node3D:
	var root := build()
	root.scale = Vector3.ONE * (scale / SCALE)
	parent.add_child(root)
	root.apply_closed(true)
	return root


static func view_local() -> Vector3:
	return Vector3(0.0, 4.55, -0.86) * SCALE


static func seat_local() -> Vector3:
	return Vector3(0.0, 2.55, 0.05) * SCALE


static func cockpit_local() -> Vector3:
	return Vector3(0.0, PLATFORM_Y + 1.1, PLATFORM_Z)


static func muzzle_local(right: bool) -> Vector3:
	var side := 1.12 if right else -1.12
	return Vector3(side, 3.72, -0.58) * SCALE


static func step_count() -> int:
	return maxi(12, ceili(PLATFORM_Y / STEP_RISE))


static func stair_run() -> float:
	return float(step_count()) * STEP_RUN


func apply_closed(on: bool) -> void:
	if hatch != null:
		hatch.rotation.x = deg_to_rad(-8.0 if on else -78.0)
	set_stairs(self, not on)


func animate(delta: float, pace: float) -> void:
	var speed := clampf(pace, 0.0, 1.0)
	_phase = wrapf(_phase + speed * STRIDE_RATE * delta, 0.0, TAU)
	_idle = wrapf(_idle + delta * 1.5, 0.0, TAU)
	pose(speed)


func pose(pace: float) -> void:
	if hips == null or torso == null:
		return
	var bounce := absf(sin(_phase)) * BOUNCE * SCALE * pace
	var idle := sin(_idle) * IDLE_BOB * SCALE * (1.0 - pace)
	hips.position.y = HIP_Y * SCALE + bounce + idle
	torso.rotation.x = deg_to_rad(-LEAN_DEG * pace)
	torso.rotation.y = deg_to_rad(sin(_phase) * TWIST_DEG * pace)
	if head != null:
		head.rotation.y = deg_to_rad(-sin(_phase) * TWIST_DEG * 0.45 * pace)
	_swing_legs(pace)
	_swing_arms(pace)


func _assemble() -> void:
	_build_rig()
	add_child(_stairs())
	pose(0.0)


func _ready() -> void:
	_skin()


func _build_rig() -> void:
	hips = Node3D.new()
	hips.name = "Hips"
	hips.position.y = HIP_Y * SCALE
	add_child(hips)
	torso = Node3D.new()
	torso.name = "Torso"
	hips.add_child(torso)
	head = Node3D.new()
	head.position = Vector3(0.0, 1.95, -0.06) * SCALE
	torso.add_child(head)
	var visor := Node3D.new()
	visor.name = "Visor"
	head.add_child(visor)
	hatch = Node3D.new()
	hatch.name = HATCH
	hatch.position = Vector3(0.0, 0.82, 0.62) * SCALE
	torso.add_child(hatch)
	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.58, 0.0, 0.0) * SCALE
		hips.add_child(leg)
		legs.append(leg)
		var knee := Node3D.new()
		knee.position = Vector3(0.0, -1.28, 0.0) * SCALE
		leg.add_child(knee)
		knees.append(knee)
		var arm := Node3D.new()
		arm.name = "RightArm" if side > 0.0 else "LeftArm"
		arm.position = Vector3(side * 1.18, 1.48, -0.04) * SCALE
		torso.add_child(arm)
		arms.append(arm)
		var elbow := Node3D.new()
		elbow.position = Vector3(0.0, -1.02, 0.0) * SCALE
		arm.add_child(elbow)
		elbows.append(elbow)


func _skin() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return
	var model: Node = packed.instantiate()
	add_child(model)
	var root := model.find_child("MechRoot", true, false) as Node3D
	if root == null and model.name == "MechRoot":
		root = model as Node3D
	if root == null:
		model.free()
		return
	root.position = Vector3.ZERO
	root.rotation.y = PI
	_steal(_part(root, "Torso"), torso, ["Head", "Hatch", "LArm", "RArm"])
	_steal(_part(root, "Head"), head, ["Visor"])
	_steal(_part(root, "Visor"), head.get_node("Visor"))
	_steal(_part(root, "Hatch"), hatch)
	_steal(_part(root, "RLeg"), legs[0], ["RKnee"])
	_steal(_part(root, "LLeg"), legs[1], ["LKnee"])
	_steal(_part(root, "RKnee"), knees[0])
	_steal(_part(root, "LKnee"), knees[1])
	_steal(_part(root, "RArm"), arms[0], ["RElbow"])
	_steal(_part(root, "LArm"), arms[1], ["LElbow"])
	_steal(_part(root, "RElbow"), elbows[0])
	_steal(_part(root, "LElbow"), elbows[1])
	_rename(arms[0].find_child("RightPod", true, false), LEFT_POD)
	_rename(arms[1].find_child("LeftPod", true, false), RIGHT_POD)
	model.free()
	_paint()


func _part(from: Node, node_name: String) -> Node3D:
	return from.find_child(node_name, true, false) as Node3D


func _rename(node: Node, node_name: String) -> void:
	if node != null:
		node.name = node_name


func _steal(from: Node, to: Node3D, skip: Array[String] = []) -> void:
	if from == null or to == null:
		return
	var kids: Array[Node] = []
	kids.assign(from.get_children())
	for child in kids:
		if skip.has(child.name):
			continue
		var node := child as Node3D
		if node != null:
			_take(node, to)


func _take(node: Node3D, to: Node3D) -> void:
	var xf := node.global_transform
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.owner = null
	to.add_child(node)
	node.global_transform = xf


func _paint() -> void:
	var looks := {
		"MechArmor": MeshFactory.material(Palette.MECH, false, Palette.GLOW_FAINT),
		"MechFrame": MeshFactory.material(Palette.MECH_FRAME, false, Palette.GLOW_FAINT),
		"MechIce": MeshFactory.material(Palette.ICE, false, Palette.GLOW_FAINT),
		"MechAmber": MeshFactory.material(Palette.AMBER, false, Palette.GLOW_MEDIUM),
		"MechLed": MeshFactory.material(Palette.LED_RED, false, Palette.GLOW_STRONG),
		"MechWell": MeshFactory.material(Palette.MECH_FRAME),
	}
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var src := mesh.get_active_material(0)
		if src == null:
			continue
		var key := src.resource_name
		if key.is_empty():
			key = src.get_name()
		var painted: Material = looks.get(key)
		if painted != null:
			mesh.material_override = painted


func _swing_legs(pace: float) -> void:
	for i in legs.size():
		var phase := _phase if i == 0 else _phase + PI
		legs[i].rotation.x = deg_to_rad(PlayerBody.limb_angle_deg(phase, pace, LEG_SWING_DEG))
		if i < knees.size():
			var bend := KNEE_DEG * 0.35 + absf(sin(phase)) * KNEE_DEG * pace
			knees[i].rotation.x = deg_to_rad(bend)


func _swing_arms(pace: float) -> void:
	for i in arms.size():
		var phase := _phase + PI if i == 0 else _phase
		arms[i].rotation.x = deg_to_rad(PlayerBody.limb_angle_deg(phase, pace, ARM_SWING_DEG))
		arms[i].rotation.z = deg_to_rad((-8.0 if i == 0 else 8.0) * (0.35 + pace * 0.65))
		if i < elbows.size():
			elbows[i].rotation.x = deg_to_rad(10.0 + absf(sin(phase)) * ELBOW_DEG * pace)


func _bind_muzzles(suit: Node) -> void:
	_mount_muzzle(suit, "LeftMuzzle", LEFT_POD)
	_mount_muzzle(suit, "RightMuzzle", RIGHT_POD)


func _mount_muzzle(suit: Node, marker: String, pod_name: String) -> void:
	var muzzle := suit.get_node_or_null(marker) as Node3D
	var pod := find_child(pod_name, true, false) as Node3D
	if muzzle == null or pod == null:
		return
	var world := muzzle.global_transform
	muzzle.get_parent().remove_child(muzzle)
	pod.add_child(muzzle)
	muzzle.global_transform = world


func _stairs() -> Node3D:
	var root := Node3D.new()
	root.name = STAIRS
	var top_z := _stair_top_z()
	var count := step_count()
	for i in count:
		var step := MeshFactory.box(
			Vector3(STEP_WIDTH, STEP_THICK, STEP_RUN * 0.92),
			Palette.MECH_FRAME,
			Palette.GLOW_FAINT
		)
		step.position = Vector3(
			0.0,
			STEP_RISE * (float(i) + 0.5),
			top_z + STEP_RUN * (float(count - i) - 0.5)
		)
		root.add_child(step)
	var deck := MeshFactory.box(PLATFORM_SIZE, Palette.MECH_FRAME, Palette.GLOW_SOFT)
	deck.position = Vector3(0.0, PLATFORM_Y, PLATFORM_Z)
	root.add_child(deck)
	for side: float in [-1.0, 1.0]:
		var rail := MeshFactory.box(
			Vector3(0.08, 0.9, PLATFORM_SIZE.z), Palette.ICE, Palette.GLOW_FAINT
		)
		rail.position = Vector3(
			side * (PLATFORM_SIZE.x * 0.5 - 0.08),
			PLATFORM_Y + 0.45,
			PLATFORM_Z
		)
		root.add_child(rail)
	return root


static func add_stair_collision(suit: CollisionObject3D) -> void:
	var run := stair_run()
	var rise := float(step_count()) * STEP_RISE
	var length := Vector2(run, rise).length()
	var ramp := CollisionShape3D.new()
	ramp.name = RAMP
	var ramp_box := BoxShape3D.new()
	ramp_box.size = Vector3(STEP_WIDTH, 0.28, length)
	ramp.shape = ramp_box
	ramp.rotation.x = atan2(rise, run)
	ramp.position = Vector3(0.0, rise * 0.5, _stair_top_z() + run * 0.5)
	suit.add_child(ramp)
	var deck := CollisionShape3D.new()
	deck.name = DECK
	var deck_box := BoxShape3D.new()
	deck_box.size = PLATFORM_SIZE
	deck.shape = deck_box
	deck.position = Vector3(0.0, PLATFORM_Y, PLATFORM_Z)
	suit.add_child(deck)


static func _stair_top_z() -> float:
	return PLATFORM_Z + PLATFORM_SIZE.z * 0.5


static func _fit_body(suit: CollisionObject3D) -> void:
	_shape(suit, "Hull", Vector3(2.2, 3.8, 1.45) * SCALE, Vector3(0.0, 2.15, -0.18) * SCALE)
	_shape(suit, "Crush/Shape", Vector3(2.5, 0.9, 2.3) * SCALE, Vector3(0.0, 0.4, 0.0) * SCALE)
	var cockpit := suit.get_node_or_null("Cockpit") as Node3D
	if cockpit != null:
		cockpit.position = cockpit_local()
	_shape(suit, "Cockpit/Shape", Vector3(2.4, 2.2, 2.4), Vector3.ZERO)
	_marker(suit, "PilotSeat", seat_local())
	_marker(suit, "PilotView", view_local())
	_marker(suit, "LeftMuzzle", muzzle_local(false))
	_marker(suit, "RightMuzzle", muzzle_local(true))


static func _shape(suit: Node, path: String, size: Vector3, at: Vector3) -> void:
	var node := suit.get_node_or_null(path) as CollisionShape3D
	if node == null:
		return
	var box := BoxShape3D.new()
	box.size = size
	node.shape = box
	node.position = at


static func _marker(suit: Node, path: String, at: Vector3) -> void:
	var node := suit.get_node_or_null(path) as Node3D
	if node != null:
		node.position = at
