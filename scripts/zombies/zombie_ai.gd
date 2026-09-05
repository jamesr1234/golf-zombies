class_name ZombieAI
extends RefCounted
## Steering, target pick, melee / ranged attacks, and ally shove. Kept off the
## Zombie body so the chase rules can be read without the hit / death code.

const _ZombieShot := preload("res://scripts/zombies/zombie_shot.gd")
const TURN_SPEED := 8.0

var target: Node3D
var attack_timer := 0.0
var repath_timer := 0.0
var melee_pending := false


func steer(zombie: Zombie) -> Vector3:
	if zombie.stats.stationary:
		return Vector3.ZERO
	if zombie.has_roam() and not zombie.roam_contains(zombie.global_position):
		return _aisle(zombie, zombie.patrol_a if zombie.has_patrol() else zombie.roam_home())
	if target == null:
		if zombie.has_patrol():
			return _patrol(zombie)
		return _clamp_roam(zombie, _wander(zombie)) if zombie.has_roam() else Vector3.ZERO
	if zombie.has_patrol():
		return _aisle(zombie, target.global_position)
	var direct := target.global_position - zombie.global_position
	direct.y = 0.0
	var span := direct.length()
	if zombie.allied:
		if span <= Melee.RANGE * 0.75:
			return Vector3.ZERO
		return _clamp_roam(zombie, path_dir(zombie, direct))
	if zombie.stats.ranged:
		return _clamp_roam(zombie, range_steer_for(zombie, direct, span))
	if span <= zombie.stats.attack_range:
		return Vector3.ZERO
	return _clamp_roam(zombie, path_dir(zombie, direct))


func range_steer_for(zombie: Zombie, direct: Vector3, span: float) -> Vector3:
	if span > zombie.stats.attack_range:
		return path_dir(zombie, direct)
	return range_steer(zombie.stats, direct, span)


## Close in outside shot range, back up if the target is in their face, hold
## the rest of the time so they actually fire.
static func range_steer(stats: ZombieStats, direct: Vector3, span: float) -> Vector3:
	if span > stats.attack_range:
		return direct.normalized()
	if span < stats.preferred_range * 0.75 and span > 0.2:
		return -direct.normalized()
	return Vector3.ZERO


func path_dir(zombie: Zombie, direct: Vector3) -> Vector3:
	var next := zombie.agent.get_next_path_position()
	var to_next := next - zombie.global_position
	to_next.y = 0.0
	# A missing or unbaked navigation mesh returns our own position; walk
	# straight at the target instead of standing still.
	if to_next.length() < 0.2:
		return direct.normalized()
	return to_next.normalized()


func face(zombie: Zombie, direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.01:
		return
	var wanted := atan2(-direction.x, -direction.z)
	zombie.visual.rotation.y = lerp_angle(zombie.visual.rotation.y, wanted, TURN_SPEED * delta)


func bash_fort(zombie: Zombie) -> bool:
	if zombie.allied or attack_timer > 0.0 or zombie.stats.ranged:
		return false
	for i in zombie.get_slide_collision_count():
		var col := zombie.get_slide_collision(i)
		var body := col.get_collider()
		if body == null or not body.has_method("take_hit"):
			continue
		begin_melee(zombie)
		return true
	return false


func try_attack(zombie: Zombie) -> void:
	if zombie.allied:
		ally_shove(zombie)
		return
	if attack_timer > 0.0 or target == null:
		return
	var offset := target.global_position - zombie.global_position
	offset.y = 0.0
	if offset.length() > zombie.stats.attack_range:
		return
	attack_timer = zombie.stats.attack_cooldown
	if zombie.stats.ranged:
		fire_at(zombie, target)
		return
	begin_melee(zombie)


func begin_melee(zombie: Zombie) -> void:
	attack_timer = zombie.stats.attack_cooldown
	melee_pending = true
	zombie.visual.start_melee()
	zombie._sfx("zombie_attack")


func resolve_melee_contact(zombie: Zombie) -> void:
	if not melee_pending:
		return
	if zombie.visual.melee_progress() < Melee.CONTACT_T:
		return
	melee_pending = false
	land_melee(zombie)


func land_melee(zombie: Zombie) -> void:
	if try_bash_fort(zombie):
		return
	if target == null:
		return
	var offset := target.global_position - zombie.global_position
	offset.y = 0.0
	if offset.length() > zombie.stats.attack_range * 1.35:
		return
	var player := target as Player
	if player != null:
		var at := Melee.hit_point(
			zombie.global_position + Vector3.UP * zombie.stats.height * 0.7,
			player.global_position, 1.8, Player.BODY_RADIUS
		)
		player.apply_hit(zombie.stats.damage, zombie.global_position, at)
		return
	var foe := target as Zombie
	if foe != null:
		foe.take_damage(zombie.stats.damage, offset.normalized())


func try_bash_fort(zombie: Zombie) -> bool:
	for i in zombie.get_slide_collision_count():
		var col := zombie.get_slide_collision(i)
		var body := col.get_collider()
		if body == null or not body.has_method("take_hit"):
			continue
		body.take_hit(col.get_position())
		return true
	return false


func ally_shove(zombie: Zombie) -> void:
	if zombie._melee == null or target == null:
		return
	var offset := target.global_position - zombie.global_position
	offset.y = 0.0
	if offset.length() > Melee.RANGE:
		return
	var origin := zombie.global_position + Vector3.UP * zombie.stats.height * 0.72
	var forward := offset
	if forward.length_squared() < 0.0001:
		forward = -zombie.visual.global_transform.basis.z
	if not zombie._melee.shove(origin, forward):
		return
	zombie.visual.start_melee()
	zombie._sfx("melee_swing")


func fire_at(zombie: Zombie, aim_at: Node3D) -> void:
	var aim := aim_at.global_position + Vector3.UP * 1.1
	var muzzle := zombie.global_position + Vector3.UP * zombie.stats.height * 0.72
	var fly := aim - muzzle
	if fly.length_squared() < 0.01:
		return
	var root := zombie.get_tree().get_first_node_in_group("fx_root")
	if root == null:
		root = zombie.get_parent()
	_ZombieShot.spawn(
		root, muzzle, fly, zombie.stats.damage, zombie.stats.projectile_speed,
		zombie.stats.attack_range + 8.0, zombie.allied,
		shot_color(zombie), shot_radius(zombie), shot_streak(zombie), zombie.stats.stationary
	)
	zombie._sfx("zombie_shot" if not zombie.stats.stationary else "sniper_fire")


func shot_color(zombie: Zombie) -> Color:
	return Palette.SNIPER if zombie.stats.stationary else _ZombieShot.COLOR


func shot_radius(zombie: Zombie) -> float:
	return 0.045 if zombie.stats.stationary else _ZombieShot.RADIUS


func shot_streak(zombie: Zombie) -> float:
	return 3.4 if zombie.stats.stationary else 0.0


func nearest_player(zombie: Zombie) -> Player:
	var best: Player = null
	var best_distance := INF
	for node in zombie.get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player == null or not player.health.is_alive():
			continue
		var distance := zombie.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func pick_target(zombie: Zombie) -> Node3D:
	var best: Node3D
	var best_d := INF
	if Zombie.hunts(zombie.allied, true, false):
		for node in zombie.get_tree().get_nodes_in_group("players"):
			var player := node as Player
			if player == null or not player.health.is_alive():
				continue
			if zombie.has_roam() and not zombie.roam_contains(player.global_position):
				continue
			var maze := zombie.home_maze()
			if maze != null and not maze.contains_world(player.global_position):
				continue
			var dist := zombie.global_position.distance_to(player.global_position)
			if zombie.aggro_range > 0.0 and dist > zombie.aggro_range:
				continue
			if dist < best_d:
				best = player
				best_d = dist
	for node in zombie.get_tree().get_nodes_in_group("zombies"):
		var other := node as Zombie
		if other == null or other == zombie or other.is_dying():
			continue
		if not Zombie.hunts(zombie.allied, false, other.is_allied()):
			continue
		if zombie.has_roam() and not zombie.roam_contains(other.global_position):
			continue
		var dist := zombie.global_position.distance_to(other.global_position)
		if zombie.aggro_range > 0.0 and dist > zombie.aggro_range:
			continue
		if dist < best_d:
			best = other
			best_d = dist
	return best


func _home(zombie: Zombie) -> Vector3:
	var home := zombie.roam_home() - zombie.global_position
	home.y = 0.0
	if home.length_squared() < 0.0001:
		return Vector3.ZERO
	return home.normalized()


func _patrol(zombie: Zombie) -> Vector3:
	var goal := zombie.patrol_b if zombie.patrol_goal_b else zombie.patrol_a
	var offset := goal - zombie.global_position
	offset.y = 0.0
	if offset.length() < Maze.CELL * 0.45:
		zombie.patrol_goal_b = not zombie.patrol_goal_b
		goal = zombie.patrol_b if zombie.patrol_goal_b else zombie.patrol_a
		offset = goal - zombie.global_position
		offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	return offset.normalized()


func _aisle(zombie: Zombie, toward: Vector3) -> Vector3:
	var maze := zombie.home_maze()
	if maze == null:
		var fallback := toward - zombie.global_position
		fallback.y = 0.0
		return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector3.ZERO
	var next := maze.next_toward(zombie.global_position, toward)
	if not next.is_finite():
		return _patrol(zombie) if zombie.has_patrol() else Vector3.ZERO
	var offset := next - zombie.global_position
	offset.y = 0.0
	if offset.length() < 0.2:
		var last := toward - zombie.global_position
		last.y = 0.0
		if last.length() <= zombie.stats.attack_range:
			return Vector3.ZERO
		return last.normalized() if last.length_squared() > 0.0001 else Vector3.ZERO
	return offset.normalized()


func _wander(zombie: Zombie) -> Vector3:
	if zombie.wander_at == Vector3.ZERO or zombie.global_position.distance_to(zombie.wander_at) < 1.8:
		zombie.wander_at = zombie.roam_sample()
	var direct := zombie.wander_at - zombie.global_position
	direct.y = 0.0
	return path_dir(zombie, direct)


func _clamp_roam(zombie: Zombie, direction: Vector3) -> Vector3:
	if not zombie.has_roam() or direction.length_squared() < 0.0001:
		return direction
	var next := zombie.global_position + direction.normalized() * 1.2
	if zombie.roam_contains(next):
		return direction
	return _home(zombie)
