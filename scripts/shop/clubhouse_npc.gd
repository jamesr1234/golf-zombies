class_name ClubhouseNpc
extends Node3D
## A lounge regular. They talk to each other until you walk up, then they turn
## and talk to you.

const USE_RANGE := 2.3

var comedy := false
var npc_name := "Golfer"
var sitting := false
var partner: ClubhouseNpc

var _last_line := ""
var _body: PlayerBody
var _audience: Node3D
var _phase := 0.0
var _rest_yaw := 0.0


static func create(index: int, at: Vector3, yaw: float, sit := false) -> ClubhouseNpc:
	var npc := ClubhouseNpc.new()
	npc.comedy = GolfAdvice.is_comedy_index(index)
	npc.npc_name = GolfAdvice.name_at(index)
	npc.sitting = sit
	npc.name = npc.npc_name
	npc.position = at
	npc.rotation.y = deg_to_rad(yaw)
	npc._rest_yaw = npc.rotation.y
	npc._phase = float(index) * 0.9
	npc._build(index)
	return npc


static func pair(a: ClubhouseNpc, b: ClubhouseNpc) -> void:
	a.partner = b
	b.partner = a


func can_use(who: Node3D) -> bool:
	if who == null or not is_inside_tree():
		return false
	var offset := who.global_position - global_position
	offset.y = 0.0
	return offset.length() <= USE_RANGE


func next_line() -> String:
	_last_line = GolfAdvice.pick(comedy, _last_line)
	return _last_line


func address(who: Node3D) -> void:
	_audience = who


func stop_address() -> void:
	_audience = null


func is_addressing() -> bool:
	return _audience != null and is_instance_valid(_audience)


func is_paired() -> bool:
	return partner != null and is_instance_valid(partner)


func gesture_deg() -> float:
	if _body == null or _body.arms.is_empty():
		return 0.0
	return rad_to_deg(_body.arms[PlayerBody.FREE_ARM].rotation.x)


func _build(index: int) -> void:
	_body = PlayerBody.new()
	add_child(_body)
	var palette := [Palette.ICE, Palette.VIOLET, Palette.LIME, Palette.HOT_PINK, Palette.CYAN, Palette.AMBER]
	_body.build(palette[posmod(index, palette.size())])
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.62, 0.28)
	lamp.light_energy = 0.14
	lamp.omni_range = 2.4
	lamp.position.y = 1.4
	add_child(lamp)


func _process(delta: float) -> void:
	_phase += delta
	if is_addressing():
		_face(_audience.global_position, delta * 5.0)
		_talk_pose(1.35)
	elif is_paired():
		_face(partner.global_position, delta * 2.4)
		_talk_pose(0.7)
	else:
		rotation.y = lerp_angle(rotation.y, _rest_yaw, delta * 2.0)
		_talk_pose(0.35)


func _face(at: Vector3, rate: float) -> void:
	var to := at - global_position
	to.y = 0.0
	if to.length_squared() < 0.04:
		return
	var wanted := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, wanted, clampf(rate, 0.0, 1.0))


func _talk_pose(energy: float) -> void:
	if sitting:
		_body.sit(false)
	else:
		_body.pose(0.0)
	var wave := sin(_phase * 2.4) * 22.0 * energy
	var other := sin(_phase * 1.7 + 1.1) * 12.0 * energy
	_body.torso.rotation.y = deg_to_rad(sin(_phase * 1.2) * 10.0 * energy)
	_body.torso.rotation.x = deg_to_rad(-6.0 * energy + sin(_phase * 3.1) * 4.0)
	_body.arms[PlayerBody.FREE_ARM].rotation.x = deg_to_rad(38.0 + wave)
	_body.arms[PlayerBody.FREE_ARM].rotation.z = deg_to_rad(-8.0)
	_body.arms[PlayerBody.GUN_ARM].rotation.x = deg_to_rad(16.0 + other)
	_body.arms[PlayerBody.GUN_ARM].rotation.z = 0.0
	if sitting:
		_body.arms[PlayerBody.FREE_ARM].rotation.x = deg_to_rad(48.0 + wave)
		_body.arms[PlayerBody.GUN_ARM].rotation.x = deg_to_rad(28.0 + other * 0.5)
