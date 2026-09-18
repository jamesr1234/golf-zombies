@tool
class_name WindmillControl
extends Area3D
## Handheld mill remote. Walk in and it goes in the bag. Select it and the
## analog stick is the mill: however many degrees you turn the stick, the
## blades and the knob both sit. You can still run.

const _SCRIPT := preload("res://scripts/course/windmill_control.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")
const STATS := preload("res://resources/course/mill_remote.tres")
const MODEL_PATH := "res://assets/weapons/mill_remote.glb"

const FIND := 8.0
const DEADZONE := 0.35
const MAX_TILT := deg_to_rad(28.0)
const SHAFT_H := 0.09
const HOVER := 0.55
const WORLD_SCALE := 2.4
const SPIN_SPEED := 1.1
const HAND := Vector3(0.4, 0.32, 0.48)

## Wire this to a mill in the overlay. Empty uses the nearest windmill.
@export var mill_path: NodePath

@export var sync_stick := Vector2.ZERO

var operator: Node = null
var carrier: Node = null
var _angle := 0.0
var _last := 0.0
var _latched := false
var _pivot: Node3D
var _knob: Node3D
var _wire_left := 0.0


static func create(prop: Dictionary) -> WindmillControl:
	var desk = _SCRIPT.new()
	desk.name = "WindmillControl"
	desk.position = Vector3(prop["position"].x, HOVER, prop["position"].z)
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
		"size": HAND,
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
		if desk == null or not desk.can_pick(who):
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


static func make_mesh(scale := 1.0) -> Node3D:
	var packed := load(MODEL_PATH) as PackedScene
	if packed != null:
		var model := packed.instantiate() as Node3D
		model.name = "Mesh"
		model.scale = Vector3.ONE * scale
		return model
	return _fallback_mesh(scale)


static func pose_model(root: Node3D, stick: Vector2, mill_rad: float) -> void:
	if root == null:
		return
	var pivot := root.find_child("StickPivot", true, false) as Node3D
	if pivot == null:
		return
	pivot.rotation.x = stick.y * MAX_TILT
	pivot.rotation.y = 0.0
	pivot.rotation.z = -stick.x * MAX_TILT
	var knob := pivot.find_child("Knob", true, false) as Node3D
	if knob != null:
		knob.rotation.y = mill_rad


func _ready() -> void:
	add_to_group("mill_controls")
	if get_child_count() == 0:
		_build()
	_wire_mill()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(false)
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


func can_pick(who: Node3D) -> bool:
	if who == null or carrier != null or not is_inside_tree() or mill() == null:
		return false
	if who.get("health") != null and who.health.has_method("is_alive"):
		if not who.health.is_alive():
			return false
	return true


func can_use(who: Node3D) -> bool:
	if who == null or mill() == null:
		return false
	if who.get("health") != null and who.health.has_method("is_alive"):
		if not who.health.is_alive():
			return false
	if who.get("shopping") == true or who.get("talking") == true:
		return false
	return carrier == who and _holding_mill(who)


func is_used_by(who: Node) -> bool:
	return operator == who


func is_carried_by(who: Node) -> bool:
	return carrier == who


func try_pick(player: Node) -> bool:
	if player == null or carrier != null:
		return false
	var bag = player.get("weapon")
	if bag == null or STATS == null:
		return false
	if bag.has_gun(STATS):
		return false
	if not bag.add_gun(STATS):
		return false
	carrier = player
	if player.has_method("bind_mill"):
		player.bind_mill(self)
	var mesh := get_node_or_null("Mesh") as Node3D
	if mesh != null:
		mesh.visible = false
	_stop_monitoring.call_deferred()
	Sfx.play("pickup_ammo", player)
	return true


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
		_pose_held(player, stick, _angle)
		return
	_steer(stick)
	_pose_held(player, stick, _angle)


func release(player: Node) -> void:
	if operator != player:
		return
	_clear()


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
	_pose_held(who, Vector2.ZERO, _angle)
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


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or carrier != null:
		return
	var mesh := get_node_or_null("Mesh") as Node3D
	if mesh != null:
		mesh.rotate_y(SPIN_SPEED * delta)


func _physics_process(delta: float) -> void:
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
	if _pivot == null:
		_pivot = find_child("StickPivot", true, false) as Node3D
	if _knob == null:
		_knob = find_child("Knob", true, false) as Node3D
	pose_model(self, stick, mill_rad)


func _pose_held(player: Node, stick: Vector2, mill_rad: float) -> void:
	if player == null or not player.has_method("pose_mill"):
		return
	player.pose_mill(stick, mill_rad)


func _stick_of(player: Node) -> Vector2:
	if player == null or player.input == null:
		return Vector2.ZERO
	return player.input.move_vector()


func _holding_mill(who: Node) -> bool:
	return who != null and who.has_method("is_holding_mill") and who.is_holding_mill()


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


func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if NetSession.is_active() and not multiplayer.is_server():
		return
	try_pick(body)


func _stop_monitoring() -> void:
	monitoring = false
	monitorable = false
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)


@rpc("any_peer", "reliable")
func _request_toggle(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who != null:
		_toggle(who)


@rpc("any_peer", "unreliable")
func _report_stick(stick: Vector2) -> void:
	if not multiplayer.is_server() or operator == null:
		return
	_steer(stick)
	if operator != null:
		_pose_held(operator, stick, _angle)


func _player_for(peer_id: int) -> Node:
	for node in get_tree().get_nodes_in_group("players"):
		if int(node.get("peer_id")) == peer_id:
			return node
	return null


func _build() -> void:
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.85
	shape.shape = sphere
	add_child(shape)
	add_child(make_mesh(WORLD_SCALE))
	_pose_joystick(Vector2.ZERO, 0.0)


static func _fallback_mesh(scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Mesh"
	root.scale = Vector3.ONE * scale
	var body := MeshFactory.box(Vector3(0.18, 0.07, 0.28), Palette.WALL, Palette.GLOW_FAINT)
	body.position.y = 0.055
	root.add_child(body)
	var well := MeshFactory.cylinder(0.038, 0.016, Palette.CART_FRAME, Palette.GLOW_FAINT)
	well.position = Vector3(0.0, 0.108, -0.055)
	root.add_child(well)
	var ring := MeshFactory.torus(0.028, 0.046, Palette.CYAN, Palette.GLOW_MEDIUM)
	ring.position = Vector3(0.0, 0.116, -0.055)
	root.add_child(ring)
	var pivot := Node3D.new()
	pivot.name = "StickPivot"
	pivot.position = Vector3(0.0, 0.116, -0.055)
	root.add_child(pivot)
	var shaft := MeshFactory.cylinder(0.011, SHAFT_H, Palette.CART_FRAME, Palette.GLOW_FAINT)
	shaft.name = "Shaft"
	shaft.position.y = SHAFT_H * 0.5
	pivot.add_child(shaft)
	var knob := MeshFactory.sphere(0.026, Palette.ORANGE, Palette.GLOW_STRONG)
	knob.name = "Knob"
	knob.position.y = SHAFT_H
	shaft.add_child(knob)
	var fin := MeshFactory.box(Vector3(0.038, 0.008, 0.01), Palette.ICE, Palette.GLOW_STRONG)
	fin.position = Vector3(0.024, 0.0, 0.0)
	knob.add_child(fin)
	return root
