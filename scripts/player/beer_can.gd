class_name BeerCan
extends Node3D
## Grey aluminium can with blue "beer" printed on the camera-facing side. Used
## in first person, in the air, and in a zombie's hand.

const VIEW_LAYER := Raygun.VIEW_LAYER
const HIP := Vector3(0.18, -0.12, -0.42)
const DRINK := Vector3(0.06, -0.02, -0.28)
const THROW := Vector3(0.22, -0.04, -0.38)
const DRINK_TIME := 0.55
const THROW_WIND := 0.12
## Opening tips toward the camera. Negative pitch used to pour it into the world.
const DRINK_PITCH_DEG := 58.0
const HIP_YAW_DEG := 22.0

var _drink_left := 0.0
var _throw_left := 0.0


static func create(scale := 1.0) -> BeerCan:
	var can := BeerCan.new()
	can._build(scale)
	return can


func drink() -> void:
	_drink_left = DRINK_TIME
	_throw_left = 0.0


func toss() -> void:
	_throw_left = THROW_WIND
	_drink_left = 0.0


func is_busy() -> bool:
	return _drink_left > 0.0 or _throw_left > 0.0


func paint_view() -> void:
	_paint(self, VIEW_LAYER)


func animate(delta: float, shown: bool) -> void:
	_drink_left = maxf(0.0, _drink_left - delta)
	_throw_left = maxf(0.0, _throw_left - delta)
	visible = shown
	if not shown:
		position = HIP
		rotation = Vector3.ZERO
		return
	var wanted := HIP
	var pitch := 0.0
	var yaw := deg_to_rad(HIP_YAW_DEG)
	if _drink_left > 0.0:
		var t := 1.0 - _drink_left / DRINK_TIME
		wanted = HIP.lerp(DRINK, drink_weight(t))
		pitch = deg_to_rad(DRINK_PITCH_DEG) * drink_weight(t)
		yaw = 0.0
	elif _throw_left > 0.0:
		var t := 1.0 - _throw_left / THROW_WIND
		wanted = HIP.lerp(THROW, t)
		pitch = deg_to_rad(-18.0) * t
	var snap := clampf(delta * 14.0, 0.0, 1.0)
	position = position.lerp(wanted, snap)
	rotation.x = lerp_angle(rotation.x, pitch, snap)
	rotation.y = lerp_angle(rotation.y, yaw, snap)


static func drink_weight(progress: float) -> float:
	var t := clampf(progress, 0.0, 1.0)
	if t < 0.2:
		return t / 0.2
	if t > 0.75:
		return 1.0 - (t - 0.75) / 0.25
	return 1.0


func _build(scale: float) -> void:
	var r := 0.045 * scale
	var h := 0.13 * scale
	add_child(MeshFactory.cylinder(r, h, Palette.BEER_CAN, Palette.GLOW_FAINT))
	var sleeve := MeshFactory.cylinder(
		r * 1.05, h * 0.64, Palette.BEER_CAN.darkened(0.22), Palette.GLOW_FAINT
	)
	add_child(sleeve)
	var stripe := MeshFactory.box(
		Vector3(r * 1.9, 0.03 * scale, 0.005 * scale), Palette.BEER_INK, Palette.GLOW_SOFT
	)
	stripe.position = Vector3(0.0, 0.02 * scale, r * 1.04)
	add_child(stripe)
	var shine := MeshFactory.box(
		Vector3(0.007 * scale, h * 0.7, 0.004 * scale), Palette.BEER_CAN.lightened(0.32)
	)
	shine.position = Vector3(r * 0.7, 0.0, r * 0.58)
	add_child(shine)
	var lip := MeshFactory.cylinder(r * 1.08, 0.016 * scale, Palette.BEER_LID, Palette.GLOW_FAINT)
	lip.position.y = 0.068 * scale
	add_child(lip)
	var well := MeshFactory.cylinder(r * 0.8, 0.006 * scale, Palette.BEER_CAN.darkened(0.42))
	well.position.y = 0.076 * scale
	add_child(well)
	var ring := MeshFactory.cylinder(r * 1.05, 0.012 * scale, Palette.BEER_CAN.darkened(0.3))
	ring.position.y = -0.058 * scale
	add_child(ring)
	var tab := MeshFactory.box(
		Vector3(0.018, 0.004, 0.03) * scale, Palette.BEER_LID, Palette.GLOW_FAINT
	)
	tab.position = Vector3(0.0, 0.082 * scale, 0.008 * scale)
	add_child(tab)
	var pull := MeshFactory.box(
		Vector3(0.014, 0.003, 0.012) * scale, Palette.BEER_LID.darkened(0.12)
	)
	pull.position = Vector3(0.0, 0.086 * scale, 0.018 * scale)
	add_child(pull)
	add_child(_copy(scale, r))


func _copy(scale: float, radius: float) -> Label3D:
	var copy := Label3D.new()
	copy.name = "BeerCopy"
	copy.text = "beer"
	copy.font_size = 36
	copy.pixel_size = 0.0013 * scale
	copy.modulate = Palette.BEER_INK
	copy.outline_size = 10
	copy.outline_modulate = Palette.NIGHT
	copy.double_sided = false
	copy.shaded = false
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.render_priority = 1
	# Label3D is readable from local +Z, same as the tee sign. Sit the print on
	# the camera-facing wall of the can and leave it unspun.
	copy.position = Vector3(0.0, 0.0, radius * 1.12)
	return copy


func _paint(node: Node, layer: int) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = layer
	for child in node.get_children():
		_paint(child, layer)
