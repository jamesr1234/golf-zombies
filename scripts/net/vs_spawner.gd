class_name VsSpawner
extends Node
## Host-side spawn of pawns, balls, carts, and zombies for online VS.

const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const BALL_SCENE := preload("res://scenes/golf/ball.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")
const MECH_SCENE := preload("res://scenes/course/items/mech_suit.tscn")

@onready var players_root: Node3D = $"../Players"
@onready var balls_root: Node3D = $"../Balls"
@onready var carts_root: Node3D = $"../Carts"
@onready var zombies_root: Node3D = $"../Zombies"
@onready var mechs_root: Node3D = $"../Mechs"
@onready var player_spawner: MultiplayerSpawner = $"../PlayerSpawner"
@onready var ball_spawner: MultiplayerSpawner = $"../BallSpawner"
@onready var zombie_spawner: MultiplayerSpawner = $"../ZombieSpawner"
@onready var mech_spawner: MultiplayerSpawner = $"../MechSpawner"


func _ready() -> void:
	add_to_group("vs_spawner")
	player_spawner.spawn_function = _spawn_player
	ball_spawner.spawn_function = _spawn_ball
	zombie_spawner.spawn_function = _spawn_zombie
	if mech_spawner != null:
		mech_spawner.spawn_function = _spawn_mech
		mech_spawner.spawn_path = mech_spawner.get_path_to(mechs_root)
	player_spawner.spawn_path = player_spawner.get_path_to(players_root)
	ball_spawner.spawn_path = ball_spawner.get_path_to(balls_root)
	zombie_spawner.spawn_path = zombie_spawner.get_path_to(zombies_root)


func spawn_match(flow: VsMatchFlow) -> void:
	if not multiplayer.is_server():
		return
	player_spawner.spawn_path = player_spawner.get_path_to(players_root)
	ball_spawner.spawn_path = ball_spawner.get_path_to(balls_root)
	zombie_spawner.spawn_path = zombie_spawner.get_path_to(zombies_root)
	if mech_spawner != null and mechs_root != null:
		mech_spawner.spawn_path = mech_spawner.get_path_to(mechs_root)
	var count := maxi(1, NetSession.player_count())
	for peer_id in NetSession.peer_ids():
		var seat := NetSession.seat_for(peer_id)
		var payload := {"peer_id": peer_id, "seat": seat}
		if flow != null and flow.course != null and flow.course.hole != null:
			payload.merge(flow.course.player_pose(seat, count))
		player_spawner.spawn(payload)
		ball_spawner.spawn({"peer_id": peer_id, "seat": seat})
	for cart in carts_root.get_children():
		if cart is GolfCart:
			cart.set_multiplayer_authority(1)
			NetSync.attach_cart(cart)
	flow.bind_spawned()


func spawn_zombie_at(at: Vector3, stats: ZombieStats) -> Zombie:
	if not multiplayer.is_server() or stats == null:
		return null
	return zombie_spawner.spawn({
		"stats": stats.resource_path,
		"at": at,
	}) as Zombie


func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data
	var player: Player = PLAYER_SCENE.instantiate()
	var peer_id := int(info.get("peer_id", 1))
	var seat := int(info.get("seat", 0))
	player.name = "P%d" % peer_id
	player.peer_id = peer_id
	player.net_driven = true
	player.input_prefix = "p1"
	player.uses_mouse = true
	player.body_color = Palette.seat_color(seat)
	player.set_multiplayer_authority(peer_id)
	var health := player.get_node_or_null("Health") as Health
	if health != null:
		health.set_multiplayer_authority(1)
		NetSync.attach_health(health)
	NetSync.attach_pawn(player, peer_id)
	if info.has("at"):
		player.spawn_at(info["at"] as Vector3, float(info.get("yaw", 0.0)))
	return player


func _spawn_ball(data: Variant) -> Node:
	var info: Dictionary = data
	var ball: GolfBall = BALL_SCENE.instantiate()
	var peer_id := int(info.get("peer_id", 1))
	var seat := int(info.get("seat", 0))
	ball.name = "Ball%d" % peer_id
	ball.owner_peer = peer_id
	ball.apply_color(Palette.seat_color(seat))
	ball.set_multiplayer_authority(1)
	var session := GolfSession.new()
	session.name = "Golf"
	ball.add_child(session)
	session.setup(ball, Vector3.ZERO)
	NetSync.attach_ball(ball)
	return ball


func _spawn_zombie(data: Variant) -> Node:
	var info: Dictionary = data
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	var path := String(info.get("stats", ""))
	if ResourceLoader.exists(path):
		zombie.stats = load(path)
	zombie.set_multiplayer_authority(1)
	NetSync.attach_zombie(zombie)
	var at: Vector3 = info.get("at", Vector3.ZERO)
	zombie.position = at
	return zombie


func spawn_mech(at: Vector3, yaw_deg: float, owner_peer: int) -> MechSuit:
	if not multiplayer.is_server() or mech_spawner == null:
		return null
	return mech_spawner.spawn({
		"at": at,
		"yaw": yaw_deg,
		"owner_peer": owner_peer,
	}) as MechSuit


func _spawn_mech(data: Variant) -> Node:
	var info: Dictionary = data
	var mech: MechSuit = MECH_SCENE.instantiate()
	var owner_peer := int(info.get("owner_peer", 0))
	mech.name = "Mech%d" % owner_peer
	mech.owner_peer = owner_peer
	var at: Vector3 = info.get("at", Vector3.ZERO)
	var yaw := deg_to_rad(float(info.get("yaw", 0.0)))
	var pose := Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), at)
	mech.transform = pose
	mech.sync_xform = pose
	NetSync.attach_mech(mech)
	mech.set_multiplayer_authority(1)
	return mech


func publish_mech(mech: MechSuit) -> void:
	if not multiplayer.is_server() or mech == null or not mech.is_inside_tree():
		return
	_wire_mech.rpc(
		mech.get_path(),
		mech.global_transform,
		mech.sync_stick,
		mech.sync_sprint,
		mech.closed,
		0 if mech.pilot == null else mech.pilot.peer_id
	)


func publish_mech_seal(mech: MechSuit) -> void:
	if not multiplayer.is_server() or mech == null or not mech.is_inside_tree():
		return
	_wire_mech_seal.rpc(
		mech.get_path(),
		mech.global_transform,
		mech.sync_stick,
		mech.sync_sprint,
		mech.closed,
		0 if mech.pilot == null else mech.pilot.peer_id
	)


@rpc("authority", "call_remote", "unreliable")
func _wire_mech(
	path: NodePath, pose: Transform3D, stick: Vector2, sprint: bool, sealed: bool, pilot_id: int
) -> void:
	_apply_wire(path, pose, stick, sprint, sealed, pilot_id)


@rpc("authority", "call_remote", "reliable")
func _wire_mech_seal(
	path: NodePath, pose: Transform3D, stick: Vector2, sprint: bool, sealed: bool, pilot_id: int
) -> void:
	_apply_wire(path, pose, stick, sprint, sealed, pilot_id)


func _apply_wire(
	path: NodePath, pose: Transform3D, stick: Vector2, sprint: bool, sealed: bool, pilot_id: int
) -> void:
	var mech := get_tree().root.get_node_or_null(path) as MechSuit
	if mech != null:
		mech.take_wire(pose, stick, sprint, sealed, pilot_id)
