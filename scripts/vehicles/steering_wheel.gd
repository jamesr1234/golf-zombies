class_name SteeringWheel
extends Node3D
## Goofy cart wheel. The rim and a pair of chunky hands turn together, so even a
## cartoon twist reads as "I am driving" from the seat.

const MAX_TURN_DEG := 110.0
const TURN_SPEED := 7.0
const RIM_INNER := 0.14
const RIM_OUTER := 0.28

var _rim: Node3D
var _hands: Array[MeshInstance3D] = []
var _angle := 0.0


func _ready() -> void:
	_build()


func angle_deg() -> float:
	return _angle


func turn(steer: float, delta: float) -> void:
	var wanted := angle_for_steer(steer)
	_angle = lerp(_angle, wanted, clampf(TURN_SPEED * delta, 0.0, 1.0))
	if _rim != null:
		_rim.rotation.z = deg_to_rad(_angle)


func show_hands(on: bool, tint := Palette.PLAYER_ONE, layer := PlayerBody.WORLD_LAYER) -> void:
	for hand in _hands:
		hand.visible = on
		hand.layers = layer if on else PlayerBody.WORLD_LAYER
		if on:
			hand.material_override = MeshFactory.material(tint, false, Palette.GLOW_MEDIUM)


func has_hands_on() -> bool:
	return not _hands.is_empty() and _hands[0].visible


func grip_positions() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for hand in _hands:
		pts.append(hand.global_position)
	return pts


## Godot's torus is a doughnut around Y. We pitch it 90 so the hole faces the seat.
func rim_pitch_deg() -> float:
	var rim := _rim.get_node_or_null("Rim") as Node3D
	return 0.0 if rim == null else rad_to_deg(rim.rotation.x)


## Right on the stick twists the wheel clockwise from the driver's seat. Local +Z
## rotation is the other way, so the sign is flipped.
static func angle_for_steer(steer: float) -> float:
	return -clampf(steer, -1.0, 1.0) * MAX_TURN_DEG


func _build() -> void:
	var column := MeshFactory.cylinder(0.035, 0.55, Palette.CART_FRAME)
	column.position = Vector3(0.0, -0.22, 0.04)
	column.rotation.x = deg_to_rad(18.0)
	add_child(column)
	_rim = Node3D.new()
	add_child(_rim)
	var hub := MeshFactory.cylinder(0.07, 0.06, Palette.CART, Palette.GLOW_SOFT)
	hub.rotation.x = deg_to_rad(90.0)
	_rim.add_child(hub)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = RIM_INNER
	torus.outer_radius = RIM_OUTER
	torus.rings = 24
	torus.ring_segments = 24
	rim.mesh = torus
	# Godot's torus is a doughnut around Y. Pitch it so the hole faces the seat,
	# otherwise the driver sees a glowing bar.
	rim.rotation.x = deg_to_rad(90.0)
	rim.material_override = MeshFactory.material(Palette.ICE, false, Palette.GLOW_SOFT)
	_rim.add_child(rim)
	for i in 3:
		var spoke := MeshFactory.box(Vector3(RIM_INNER * 1.7, 0.03, 0.04), Palette.CART_FRAME)
		spoke.rotation.z = deg_to_rad(float(i) * 120.0)
		_rim.add_child(spoke)
	# Mittens sit on the rim at nine and three so a reach lands on the hoop.
	for side: float in [-1.0, 1.0]:
		var hand := MeshFactory.box(
			Vector3(0.13, 0.11, 0.14), Palette.PLAYER_ONE, Palette.GLOW_MEDIUM
		)
		hand.position = Vector3(side * (RIM_INNER + RIM_OUTER) * 0.5, 0.0, 0.05)
		hand.rotation.z = deg_to_rad(-side * 18.0)
		_rim.add_child(hand)
		_hands.append(hand)
		hand.visible = false
