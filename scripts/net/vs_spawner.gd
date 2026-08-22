class_name VsSpawner
extends Node
## Host-side spawn of pawns, balls, carts, and zombies for online VS.

const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const BALL_SCENE := preload("res://scenes/golf/ball.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")

@onready var players_root: Node3D = $"../Players"
@onready var balls_root: Node3D = $"../Balls"
@onready var carts_root: Node3D = $"../Carts"
@onready var zombies_root: Node3D = $"../Zombies"
@onready var player_spawner: MultiplayerSpawner = $"../PlayerSpawner"
@onready var ball_spawner: MultiplayerSpawner = $"../BallSpawner"
@onready var zombie_spawner: MultiplayerSpawner = $"../ZombieSpawner"


func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	ball_spawner.spawn_function = _spawn_ball
	zombie_spawner.spawn_function = _spawn_zombie
	player_spawner.spawn_path = player_spawner.get_path_to(players_root)
	ball_spawner.spawn_path = ball_spawner.get_path_to(balls_root)
	zombie_spawner.spawn_path = zombie_spawner.get_path_to(zombies_root)


func spawn_match(flow: VsMatchFlow) -> void:
	if not multiplayer.is_server():
		return
	player_spawner.spawn_path = player_spawner.get_path_to(players_root)
	ball_spawner.spawn_path = ball_spawner.get_path_to(balls_root)
	zombie_spawner.spawn_path = zombie_spawner.get_path_to(zombies_root)
	for peer_id in NetSession.peer_ids():
		player_spawner.spawn({"peer_id": peer_id, "seat": NetSession.seat_for(peer_id)})
		ball_spawner.spawn({"peer_id": peer_id, "seat": NetSession.seat_for(peer_id)})
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
	NetSync.attach_pawn(player)
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
