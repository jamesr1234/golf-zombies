class_name SpawnDirector
extends Node
## Feeds zombies into the current hole, or packs the cart path between holes.

signal zombie_killed(bounty: int, killer: Player)

const BASE_INTERVAL := 4.6
const MIN_INTERVAL := 1.3
const INTERVAL_PER_HOLE := 0.35
const GOLFING_PRESSURE := 0.65
const BASE_CAP := 8
const CAP_PER_HOLE := 2
const MAX_CAP := 26
const MIN_PLAYER_DISTANCE := 32.0
const FIRST_SPAWN_DELAY := 3.0
const TRANSIT_CAP := 28
const TRANSIT_INTERVAL := 0.65
const TRANSIT_MIN_DISTANCE := 8.0
const TRANSIT_BURST := 20

const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")
const SNIPER := preload("res://resources/zombies/sniper.tres")

var types: Array[ZombieStats] = [
	preload("res://resources/zombies/walker.tres"),
	preload("res://resources/zombies/runner.tres"),
	preload("res://resources/zombies/brute.tres"),
	preload("res://resources/zombies/gunner.tres"),
]

var container: Node3D
var golf: GolfController
var net_factory: VsSpawner

var _points: Array[Vector3] = []
var _hole_index := 0
var _timer := 0.0
var _running := false
var _transit := false


func begin_hole(hole_index: int, spawn_points: Array[Vector3]) -> void:
	_transit = false
	_hole_index = hole_index
	_points = spawn_points
	_timer = FIRST_SPAWN_DELAY
	_running = true


func place_snipers(perches: Array[Vector3]) -> void:
	if container == null:
		return
	for perch in perches:
		_spawn_at(perch, SNIPER)


## Pack the cart path with walkers so the drive to the next tee is a gauntlet.
func begin_transit(hole_index: int, spawn_points: Array[Vector3]) -> void:
	_transit = true
	_hole_index = hole_index
	_points = spawn_points
	_timer = TRANSIT_INTERVAL
	_running = true
	for _i in TRANSIT_BURST:
		if live_count() >= cap():
			break
		_spawn()


func stop() -> void:
	_running = false


func clear_zombies() -> void:
	for zombie in get_tree().get_nodes_in_group("zombies"):
		zombie.queue_free()


func live_count() -> int:
	return get_tree().get_nodes_in_group("zombies").size()


func cap() -> int:
	var raw := TRANSIT_CAP if _transit else mini(MAX_CAP, BASE_CAP + _hole_index * CAP_PER_HOLE)
	return maxi(1, int(round(float(raw) * GameSettings.spawn_cap_scale())))


func interval() -> float:
	var value := TRANSIT_INTERVAL
	if not _transit:
		value = maxf(MIN_INTERVAL, BASE_INTERVAL - _hole_index * INTERVAL_PER_HOLE)
		if _anyone_golfing():
			value *= GOLFING_PRESSURE
	return value * GameSettings.spawn_interval_scale()


func is_transit() -> bool:
	return _transit


func _process(delta: float) -> void:
	if not _running or _points.is_empty() or container == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval()
	if live_count() >= cap():
		return
	_spawn()


func _spawn() -> void:
	if container == null:
		return
	var candidates := _candidate_points()
	if candidates.is_empty():
		return
	_spawn_at(candidates[randi() % candidates.size()] + Vector3.UP * 0.2, _pick_type())


func _anyone_golfing() -> bool:
	for node in get_tree().get_nodes_in_group("players"):
		if node.has_method("is_golfing") and node.is_golfing():
			return true
	return golf != null and golf.golfer != null


func _spawn_at(at: Vector3, stats: ZombieStats) -> void:
	if container == null or stats == null:
		return
	var zombie: Zombie
	if net_factory != null and NetSession.is_active():
		zombie = net_factory.spawn_zombie_at(at, stats)
	else:
		zombie = ZOMBIE_SCENE.instantiate()
		zombie.stats = stats
		container.add_child(zombie)
		zombie.global_position = at
	if zombie == null:
		return
	if not zombie.died.is_connected(_on_zombie_died):
		zombie.died.connect(_on_zombie_died)


func _on_zombie_died(zombie: Zombie) -> void:
	if zombie.stats == null or zombie.is_allied():
		return
	zombie_killed.emit(zombie.stats.bounty, zombie.last_hit_by)


## Spawn points far enough away that zombies never appear on top of a player.
## A short par three can put every point inside that ring; then use the
## farthest spots so the hole is still under attack.
func _candidate_points() -> Array[Vector3]:
	var players := get_tree().get_nodes_in_group("players")
	var candidates: Array[Vector3] = []
	var keep_away := TRANSIT_MIN_DISTANCE if _transit else MIN_PLAYER_DISTANCE
	for point in _points:
		if _nearest_player_distance(point, players) >= keep_away:
			candidates.append(point)
	if not candidates.is_empty():
		return candidates
	return _farthest_points(players)


func _nearest_player_distance(point: Vector3, players: Array) -> float:
	if players.is_empty():
		return INF
	var closest := INF
	for node in players:
		closest = minf(closest, point.distance_to((node as Node3D).global_position))
	return closest


func _farthest_points(players: Array) -> Array[Vector3]:
	var best: Vector3
	var best_d := -1.0
	for point in _points:
		var distance := _nearest_player_distance(point, players)
		if distance > best_d:
			best_d = distance
			best = point
	if best_d < 0.0:
		return []
	return [best]


func _pick_type() -> ZombieStats:
	var pool: Array[ZombieStats] = []
	var total := 0.0
	for stats in types:
		if not _type_allowed(stats):
			continue
		pool.append(stats)
		total += stats.spawn_weight
	if pool.is_empty():
		return types[0]
	var roll := randf() * total
	for stats in pool:
		roll -= stats.spawn_weight
		if roll <= 0.0:
			return stats
	return pool[pool.size() - 1]


## Gunners wait until after hole one. The cart-path swarm stays melee so you
## run them over instead of eating bolts on the tarmac. Tower snipers are placed
## by place_snipers, never rolled into the walking pack.
func _type_allowed(stats: ZombieStats) -> bool:
	if stats.stationary:
		return false
	var unlock := stats.unlock_hole
	if stats.ranged:
		unlock = GameSettings.gunner_unlock(stats.unlock_hole)
	if unlock > _hole_index:
		return false
	if _transit and stats.ranged:
		return false
	return true
