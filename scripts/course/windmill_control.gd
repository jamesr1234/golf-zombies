@tool
class_name WindmillControl
extends StaticBody3D
## Table with a world joystick. Interact, then the analog stick is the mill:
## however many degrees you turn the stick, the blades and the stick both sit.

const _SCRIPT := preload("res://scripts/course/windmill_control.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")

const USE_RANGE := 2.4
const FIND := 8.0
const STAND_Z := 1.15
const TABLE := Vector3(1.15, 0.92, 0.72)
const DEADZONE := 0.35
const MAX_TILT := deg_to_rad(28.0)
const SHAFT_H := 0.42

## Wire this to a mill in the overlay. Empty uses the nearest windmill.
@export var mill_path: NodePath

@export var sync_stick := Vector2.ZERO

var operator: Node = null
var _angle := 0.0
var _last := 0.0
var _latched := false
var _pivot: Node3D
var _knob: Node3D
var _wire_left := 0.0


static func create(prop: Dictionary) -> WindmillControl:
	var desk = _SCRIPT.new()
	desk.name = "WindmillControl"
	desk.position = prop["position"]
	desk.rotation.y = deg_to_rad(float(prop.get("yaw", 0.0)))
	var path := String(prop.get("mill_path", ""))
	if not path.is_empty():
		desk.mill_path = NodePath(path)
	desk._build()
	return desk


func to_prop() -> Dictionary:
	return {
		"kind": "mill_control",
		"position": Vector3(position.x, 0.0, position.z),
		"size": TABLE,
		"yaw": rad_to_deg(rotation.y),
		"mill_path": mill_path,
	}


static func nearest(who: Node3D) -> WindmillControl:
	var best: WindmillControl
	var best_d := INF
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("mill_controls"):
		var desk := node as WindmillControl
		if desk == null or not desk.can_use(who):
			continue
		var d := who.global_position.distance_to(desk.global_position)
		if d < best_d:
			best = desk
			best_d = d
	return best


## Stick-right is 0, forward is +PI/2. Same sense the mill rotor uses.
static func angle_of(stick: Vector2) -> float:
	return atan2(-stick.y, stick.x)


static func turn_delta(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


## One sample of analog motion. Deadzone freezes the mill; coming back out
## latches without a jump, then every degree of stick is a degree of mill.
static func steer_angle(angle: float, last: float, latched: bool, stick: Vector2) -> Dictionary:
	if stick.length() < DEADZONE:
		return {"angle": angle, "last": last, "latched": false}
	var now := angle_of(stick)
	if latched:
		angle -= turn_delta(last, now)
	return {"angle": angle, "last": now, "latched": true}


func _ready() -> void:
	add_to_group("mill_controls")
	if get_child_count() == 0:
		collision_layer = Layers.PROP
		collision_mask = 0
		_build()
	_wire_mill()
	if Engine.is_editor_hint():
		# Pose once for the overlay; do not tick NetSession every physics frame.
		set_physics_process(false)
		_pose_from_sync()
		return
	if NetSession.is_active():
		NetSync.attach(self, PackedStringArray([":sync_stick"]))


func mill() -> CartPathWindmill:
	if mill_path != NodePath():
		var wired := get_node_or_null(mill_path) as CartPathWindmill
		if wired != null:
			return wired
	return _nearest_mill()


func can_use(who: Node3D) -> bool:
	if who == null or not is_inside_tree() or mill() == null:
		return false
	if who.get("health") != null and who.health.has_method("is_alive"):
		if not who.health.is_alive():
			return false
	if who.get("shopping") == true or who.get("talking") == true:
		return false
	if who.get("state") != null and int(who.state) != 0:
		return false
	var offset := who.global_position - global_position
	offset.y = 0.0
	return offset.length() <= USE_RANGE


func is_used_by(who: Node) -> bool:
	return operator == who


func try_toggle(player: Node) -> void:
	if not Engine.is_editor_hint() and NetSession.is_active() and not multiplayer.is_server():
		_request_toggle.rpc_id(1, player.peer_id)
	_toggle(player)


func _toggle(player: Node) -> void:
	if operator == player:
		_clear()
		return
	if operator != null or not can_use(player):
		return
	_claim(player)


func tick(player: Node, _delta: float) -> void:
	if player == null or operator != player:
		return
	var stick := _stick_of(player)
	sync_stick = stick
	if not Engine.is_editor_hint() and NetSession.defers_world():
		_report_stick.rpc_id(1, stick)
		_pose_joystick(stick, _angle)
		return
	_steer(stick)


func release(player: Node) -> void:
	if operator != player:
		return
	_clear()


func stand_at() -> Vector3:
	return global_position + global_transform.basis.z * STAND_Z


func take_wire(stick: Vector2, rotor: float, driven: bool) -> void:
	sync_stick = stick
	_angle = rotor
	var mill := mill()
	if mill != null:
		mill.take_wire(rotor, driven)
	_pose_joystick(stick, rotor)


static func take_replicated(
	tree: SceneTree, at: Vector3, stick: Vector2, rotor: float, driven: bool
) -> WindmillControl:
	var desk := nearest_at(tree, at)
	if desk != null:
		desk.take_wire(stick, rotor, driven)
	return desk


static func nearest_at(tree: SceneTree, at: Vector3) -> WindmillControl:
	if tree == null:
		return null
	var best: WindmillControl
	var best_d := INF
	for node in tree.get_nodes_in_group("mill_controls"):
		var desk := node as WindmillControl
		if desk == null or not desk.is_inside_tree():
			continue
		var d := desk.global_position.distance_to(at)
		if d < best_d:
			best = desk
			best_d = d
	return best if best_d <= FIND * 8.0 else null


func _claim(player: Node) -> void:
	var mill := mill()
	if mill == null or player == null:
		return
	if operator != null and operator != player:
		return
	operator = player
	_latched = false
	_angle = mill.rotor_rad()
	_last = _angle
	mill.drive(true)
	if player.has_method("begin_mill"):
		player.begin_mill(self)
	_park(player)
	_pose_joystick(Vector2.ZERO, _angle)
	_publish_pose(0.0, true)


func _clear() -> void:
	var who := operator
	operator = null
	_latched = false
	sync_stick = Vector2.ZERO
	var mill := mill()
	if mill != null:
		mill.drive(false)
	if who != null and who.has_method("end_mill"):
		who.end_mill(self)
	_pose_joystick(Vector2.ZERO, _angle)
	_publish_pose(0.0, true)


func _steer(stick: Vector2) -> void:
	var mill := mill()
	if mill == null:
		return
	var next := steer_angle(_angle, _last, _latched, stick)
	_angle = next["angle"]
	_last = next["last"]
	_latched = next["latched"]
	mill.set_rotor_rad(_angle)
	_pose_joystick(stick, _angle)


func _physics_process(delta: float) -> void:
	# @tool runs this in the editor; NetSession is only a placeholder there.
	if Engine.is_editor_hint():
		_pose_from_sync()
		return
	if _watching():
		_pose_from_sync()
		return
	if operator == null:
		_pose_from_sync()
	_publish_pose(delta)


func _pose_from_sync() -> void:
	var mill := mill()
	if mill != null:
		_angle = mill.rotor_rad()
	_pose_joystick(sync_stick, _angle)


func _watching() -> bool:
	if Engine.is_editor_hint():
		return false
	return NetSession.is_active() and not multiplayer.is_server()


func _publish_pose(delta: float, reliable := false) -> void:
	if Engine.is_editor_hint():
		return
	if not is_inside_tree() or not NetSession.is_active():
		return
	if not multiplayer.is_server():
		return
	if reliable:
		_wire_left = NetSync.CART_HZ
	else:
		_wire_left -= delta
		if _wire_left > 0.0:
			return
		_wire_left = NetSync.CART_HZ
	var mill := mill()
	var rotor := mill.rotor_rad() if mill != null else _angle
	_WorldFx.announce_mill(
		self, global_position, sync_stick, rotor, mill != null and mill.is_driven(), reliable
	)


func _wire_mill() -> void:
	if mill_path != NodePath():
		return
	var parent := get_parent()
	if parent == null:
		return
	if parent.get_node_or_null("Windmill") is CartPathWindmill:
		mill_path = NodePath("../Windmill")


func _pose_joystick(stick: Vector2, mill_rad: float) -> void:
	if _pivot == null or _knob == null:
		_pivot = get_node_or_null("StickPivot") as Node3D
		_knob = get_node_or_null("StickPivot/Shaft/Knob") as Node3D
	if _pivot == null:
		return
	_pivot.rotation.x = stick.y * MAX_TILT
	_pivot.rotation.y = 0.0
	_pivot.rotation.z = -stick.x * MAX_TILT
	if _knob != null:
		_knob.rotation.y = mill_rad


func _park(player: Node) -> void:
	if player == null or not player.has_method("face_mill"):
		return
	player.face_mill(stand_at(), rotation.y)


func _stick_of(player: Node) -> Vector2:
	if player == null or player.input == null:
		return Vector2.ZERO
	return player.input.move_vector()


func _nearest_mill() -> CartPathWindmill:
	if not is_inside_tree():
		return null
	var best: CartPathWindmill
	var best_d := INF
	for node in get_tree().get_nodes_in_group("cart_path_windmills"):
		var mill := node as CartPathWindmill
		if mill == null:
			continue
		var d := global_position.distance_to(mill.global_position)
		if d < FIND * 8.0 and d < best_d:
			best = mill
			best_d = d
	return best


@rpc("any_peer", "reliable")
func _request_toggle(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not NetSession.rpc_speaks_for(multiplayer.get_remote_sender_id(), peer_id):
		return
	var who := _player_for(peer_id)
	if who != null:
		_toggle(who)


@rpc("any_peer", "unreliable")
func _report_stick(stick: Vector2) -> void:
	if not multiplayer.is_server() or operator == null:
		return
	# Only the peer at the desk steers. Anyone else reporting a stick is spinning
	# a mill they are not standing at, which blocks the path and mows the green.
	if not NetSession.rpc_speaks_for(
		multiplayer.get_remote_sender_id(), int(operator.get("peer_id"))
	):
		return
	_steer(stick)


func _player_for(peer_id: int) -> Node:
	for node in get_tree().get_nodes_in_group("players"):
		if int(node.get("peer_id")) == peer_id:
			return node
	return null


func _build() -> void:
	collision_layer = Layers.PROP
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = TABLE
	shape.shape = box
	shape.position.y = TABLE.y * 0.5
	add_child(shape)
	var desk := MeshFactory.box(TABLE, Palette.WALL, Palette.GLOW_FAINT)
	desk.position.y = TABLE.y * 0.5
	add_child(desk)
	var top := MeshFactory.box(
		Vector3(TABLE.x + 0.08, 0.05, TABLE.z + 0.08), Palette.CYAN, Palette.GLOW_SOFT
	)
	top.position.y = TABLE.y + 0.03
	add_child(top)
	var well := MeshFactory.cylinder(0.22, 0.08, Palette.CART_FRAME, Palette.GLOW_FAINT)
	well.position.y = TABLE.y + 0.08
	add_child(well)
	var ring := MeshFactory.torus(0.16, 0.26, Palette.CYAN, Palette.GLOW_MEDIUM)
	ring.position.y = TABLE.y + 0.1
	add_child(ring)
	_pivot = Node3D.new()
	_pivot.name = "StickPivot"
	_pivot.position.y = TABLE.y + 0.1
	add_child(_pivot)
	var shaft := MeshFactory.cylinder(0.04, SHAFT_H, Palette.CART_FRAME, Palette.GLOW_FAINT)
	shaft.name = "Shaft"
	shaft.position.y = SHAFT_H * 0.5
	_pivot.add_child(shaft)
	_knob = MeshFactory.sphere(0.11, Palette.MAGENTA, Palette.GLOW_STRONG)
	_knob.name = "Knob"
	_knob.position.y = SHAFT_H
	shaft.add_child(_knob)
	var fin := MeshFactory.box(Vector3(0.16, 0.035, 0.04), Palette.ICE, Palette.GLOW_STRONG)
	fin.position = Vector3(0.1, 0.0, 0.0)
	_knob.add_child(fin)
	var sign := Label3D.new()
	sign.text = "MILL"
	sign.font_size = 28
	sign.modulate = Palette.CYAN
	sign.outline_size = 6
	sign.outline_modulate = Palette.NIGHT
	sign.position = Vector3(0.0, TABLE.y + 0.18, TABLE.z * 0.5 + 0.02)
	add_child(sign)
	_pose_joystick(Vector2.ZERO, 0.0)
