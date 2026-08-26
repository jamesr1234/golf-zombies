class_name WarpDoor
extends Area3D
## Planted neon doorway. Walk through and you stand next to your ball.

const COLOR: Color = Palette.DOOR
const WIDTH := 1.15
const HEIGHT := 2.2
const DEPTH := 0.28
const ARM_TIME := 0.35
const STAND_GAP := 1.8
const GROUP := "warp_doors"

var duration := 20.0
var shooter_peer := 0
var visual_only := false
var _left := 0.0
var _arm := ARM_TIME
var _pane: MeshInstance3D


static func spawn(
	root: Node, at: Vector3, normal: Vector3, incoming: Vector3, hold: float,
	peer_id := 0, p_visual_only := false
) -> WarpDoor:
	var face := facing_from_hit(normal, incoming)
	return spawn_facing(root, plant_point(at, normal), face, hold, peer_id, p_visual_only)


static func spawn_facing(
	root: Node, at: Vector3, face: Vector3, hold: float, peer_id := 0,
	p_visual_only := false
) -> WarpDoor:
	if root == null:
		return null
	clear_for(root.get_tree(), peer_id)
	var door := WarpDoor.new()
	door.duration = hold
	door._left = hold
	door.shooter_peer = peer_id
	door.visual_only = p_visual_only
	door.add_to_group(GROUP)
	root.add_child(door)
	door.global_position = at
	var look := face if face.length_squared() > 0.0001 else Vector3.FORWARD
	door.look_at(door.global_position + look.normalized())
	door._build()
	Sfx.play("door_open", door)
	return door


static func clear_for(tree: SceneTree, peer_id: int) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		var door := node as WarpDoor
		if door != null and door.shooter_peer == peer_id:
			door.queue_free()


static func facing_from_hit(normal: Vector3, incoming: Vector3) -> Vector3:
	var face := Vector3(normal.x, 0.0, normal.z)
	if normal.y > 0.6:
		face = Vector3(-incoming.x, 0.0, -incoming.z)
	if face.length_squared() < 0.0001:
		return Vector3.FORWARD
	return face.normalized()


static func plant_point(at: Vector3, normal: Vector3) -> Vector3:
	var origin := at
	var face := Vector3(normal.x, 0.0, normal.z)
	if normal.y > 0.6:
		origin += normal.normalized() * 0.08
		origin.y = at.y
	else:
		if face.length_squared() > 0.0001:
			origin += face.normalized() * 0.08
		origin.y = at.y - HEIGHT * 0.5
	return origin


static func ball_for(player: Player) -> GolfBall:
	if player == null or player.golf == null:
		return null
	return player.golf.ball


static func can_warp(player: Player) -> bool:
	if player == null or player.health == null or not player.health.is_alive():
		return false
	if player.state != Player.State.NORMAL:
		return false
	var ball := ball_for(player)
	if ball == null or not is_instance_valid(ball):
		return false
	return not (ball.is_holed() or ball.is_stowed() or ball.is_closed() or ball.is_carried())


static func stand_point(ball: GolfBall, from: Vector3) -> Vector3:
	var lie := ball.global_position
	var away := from - lie
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	return lie - Vector3.UP * GolfBall.RADIUS + away.normalized() * STAND_GAP


static func face_yaw(from: Vector3, toward: Vector3) -> float:
	var delta := toward - from
	delta.y = 0.0
	if delta.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(-delta.x, -delta.z))


func facing() -> Vector3:
	return -global_transform.basis.z


func try_warp(player: Player) -> bool:
	if _arm > 0.0 or not can_warp(player):
		return false
	if NetSession.is_active() and not player.is_multiplayer_authority():
		return false
	var ball := ball_for(player)
	var at := stand_point(ball, player.global_position)
	player.stand_at(at, face_yaw(at, ball.global_position))
	Sfx.play("door_warp", player)
	return true


func _build() -> void:
	name = "WarpDoor"
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, DEPTH)
	shape.shape = box
	shape.position.y = HEIGHT * 0.5
	add_child(shape)
	_frame()
	_pane = MeshFactory.box(Vector3(WIDTH - 0.22, HEIGHT - 0.28, 0.04), COLOR, Palette.GLOW_STRONG)
	_pane.position.y = HEIGHT * 0.5
	add_child(_pane)
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 3.6
	lamp.omni_range = 8.0
	lamp.position.y = HEIGHT * 0.55
	add_child(lamp)
	body_entered.connect(_on_body_entered)


func _frame() -> void:
	var post := 0.08
	var lintel := WIDTH
	for x: float in [-WIDTH * 0.5, WIDTH * 0.5]:
		var post_mesh := MeshFactory.box(Vector3(post, HEIGHT, post), COLOR, Palette.GLOW_MEDIUM)
		post_mesh.position = Vector3(x, HEIGHT * 0.5, 0.0)
		add_child(post_mesh)
	var top := MeshFactory.box(Vector3(lintel, post, post), COLOR, Palette.GLOW_MEDIUM)
	top.position.y = HEIGHT - post * 0.5
	add_child(top)
	var sill := MeshFactory.box(Vector3(lintel, post, post), COLOR, Palette.GLOW_SOFT)
	sill.position.y = post * 0.5
	add_child(sill)


func _physics_process(delta: float) -> void:
	_arm = maxf(0.0, _arm - delta)
	_left -= delta
	if _pane != null:
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
		_pane.scale = Vector3(1.0, pulse, 1.0)
	if _left <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	try_warp(body as Player)
