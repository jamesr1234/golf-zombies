class_name PlayerGlide
extends RefCounted
## Gear-select the packed suit, then jump off a drop. Flat attitude keeps
## adding forward speed; look pitches height against real gravity.

const MIN_HEIGHT := 2.5
const RANGE := 80.0
const STALL_SPEED := 6.0
const DEPLOY_SPEED := 9.0
const THRUST := 11.0
const LIFT_K := 0.026
const DRAG_K := 0.014
const CLIMB_K := 7.0
const BANK_RAD := 0.7
const STICK_PITCH := 18.0
const LOOK_AHEAD := 2.2
const GROUND_MASK := Layers.WORLD | Layers.PROP | Layers.SURFACE

var active := false
var equipped := false


func is_active() -> bool:
	return active


func owns(player: Player) -> bool:
	var card = player.wallet()
	return card != null and card.glide_bought


func equip(player: Player) -> void:
	if not owns(player):
		return
	equipped = true
	_refresh_wings(player)


func unequip(player: Player) -> void:
	equipped = false
	if active:
		cut(player)
	else:
		_refresh_wings(player)


func can_start(player: Player) -> bool:
	if active or not equipped or not owns(player):
		return false
	if player.health == null or not player.health.is_alive():
		return false
	if player.state != Player.State.NORMAL and player.state != Player.State.PLACING:
		return false
	if player.shopping or player.is_celebrating():
		return false
	return (
		not player.is_golfing()
		and not player.is_riding()
		and not player.is_swimming()
		and not player.is_climbing()
		and not player.is_shielding()
		and not player.is_in_mech()
		and not player.is_grappling()
		and not player.is_milling()
		and not player.is_poker_seated()
		and drop_height(player) >= MIN_HEIGHT
	)


func try_deploy(player: Player) -> bool:
	if player.motion.walks_from_wire(player):
		return false
	var drop := drop_height(player)
	var ok := can_start(player)
	# #region agent log
	_dbg("A", "player_glide.gd:try_deploy", "deploy attempt", {
		"ok": ok, "equipped": equipped, "owns": owns(player), "active": active,
		"drop": drop, "min": MIN_HEIGHT, "on_floor": player.is_on_floor(),
		"under": _cast_drop(player, Vector3.ZERO, true),
		"ahead": _cast_drop(player, _look_flat(player) * LOOK_AHEAD, false),
		"state": int(player.state), "vel_y": player.velocity.y,
		"pos_y": player.global_position.y,
	})
	# #endregion
	if not ok:
		return false
	start(player)
	return true


func start(player: Player) -> void:
	active = true
	var look := _look_flat(player)
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if flat.length() < 4.0:
		player.velocity.x = look.x * DEPLOY_SPEED
		player.velocity.z = look.z * DEPLOY_SPEED
	_refresh_wings(player)
	Sfx.play("glide_open", player)


func cut(player: Player) -> void:
	if not active:
		return
	cancel(player)
	Sfx.play("glide_cut", player)


func cancel(player: Player) -> void:
	if not active:
		return
	active = false
	_refresh_wings(player)


func landed(player: Player) -> bool:
	return player.is_on_floor() and player.velocity.y <= 0.0


func apply_replicated(player: Player, flying: bool, worn := false) -> void:
	active = flying
	equipped = worn or flying
	_refresh_wings(player)


func tick(player: Player, delta: float) -> void:
	if player.motion.walks_from_wire(player):
		apply_replicated(player, player.sync_glide, player.sync_glide_worn)
		return
	if not _can_keep(player):
		cancel(player)
		return
	var fwd := _wing_forward(player)
	var along := _look_flat(player)
	var flatness := clampf(1.0 - absf(fwd.y), 0.0, 1.0)
	var speed := player.velocity.length()
	var vel_dir := along if speed < 0.05 else player.velocity / speed
	var drag := -vel_dir * (DRAG_K * speed * speed)
	var lift := Vector3.ZERO
	var thrust := Vector3.ZERO
	var climb := Vector3.ZERO
	if speed >= STALL_SPEED:
		lift = Vector3.UP * (LIFT_K * speed * speed * flatness)
		var stick := player.motion.walk_stick(player)
		if absf(stick.x) > 0.01:
			var axis := fwd if fwd.length_squared() > 0.0001 else along
			lift = lift.rotated(axis, -clampf(stick.x, -1.0, 1.0) * BANK_RAD)
		thrust = along * (THRUST * flatness * flatness)
		var pitch := clampf(player.look_pitch() + stick.y * STICK_PITCH, -PlayerLook.PITCH_LIMIT, PlayerLook.PITCH_LIMIT)
		climb = Vector3.UP * (CLIMB_K * clampf(speed / 12.0, 0.0, 1.6) * clampf(pitch / 40.0, -1.0, 1.0))
	else:
		drag *= 2.0
	player.velocity += (player.get_gravity() + lift + drag + thrust + climb) * delta


func drop_height(player: Player) -> float:
	if player == null or not player.is_inside_tree():
		return 0.0
	var under := _cast_drop(player, Vector3.ZERO, true)
	var ahead := _cast_drop(player, _look_flat(player) * LOOK_AHEAD, false)
	return maxf(under, ahead)


func _can_keep(player: Player) -> bool:
	if player.health == null or not player.health.is_alive():
		return false
	return (
		(player.state == Player.State.NORMAL or player.state == Player.State.PLACING)
		and not player.shopping
		and not player.is_celebrating()
		and not player.is_swimming()
		and not player.is_climbing()
		and not player.is_shielding()
		and not player.is_grappling()
		and not player.is_milling()
		and not player.is_poker_seated()
	)


func _look_forward(player: Player) -> Vector3:
	var pitch := deg_to_rad(player.look_pitch())
	var yaw := deg_to_rad(player.look_yaw())
	return Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch)).normalized()


func _look_flat(player: Player) -> Vector3:
	var dir := Vector3(_look_forward(player).x, 0.0, _look_forward(player).z)
	if dir.length_squared() < 0.0001:
		dir = -player.transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()


func _wing_forward(player: Player) -> Vector3:
	var extra := player.motion.walk_stick(player).y * STICK_PITCH
	var pitch := deg_to_rad(clampf(player.look_pitch() + extra, -PlayerLook.PITCH_LIMIT, PlayerLook.PITCH_LIMIT))
	var yaw := deg_to_rad(player.look_yaw())
	return Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch)).normalized()


func _cast_drop(player: Player, offset: Vector3, punch: bool) -> float:
	var space := player.get_world_3d().direct_space_state
	var origin := player.global_position + Vector3.UP * 0.35 + offset
	var exclude: Array[RID] = [player.get_rid()]
	var first_y := INF
	for hop in 2:
		var hit := space.intersect_ray(_ray(origin, origin + Vector3.DOWN * RANGE, exclude))
		if hit.is_empty():
			return RANGE if hop == 0 else _fall(player, first_y)
		if hop == 0:
			first_y = hit.position.y
			if not punch:
				return player.global_position.y - hit.position.y
			var body := hit.collider as CollisionObject3D
			if body == null:
				return player.global_position.y - hit.position.y
			exclude.append(body.get_rid())
			origin = hit.position + Vector3.DOWN * 0.08
			continue
		return player.global_position.y - hit.position.y
	return _fall(player, first_y)


func _ray(from: Vector3, to: Vector3, exclude: Array[RID]) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GROUND_MASK
	query.exclude = exclude
	query.collide_with_areas = false
	return query


func _fall(player: Player, first_y: float) -> float:
	if first_y == INF:
		return 0.0
	return player.global_position.y - first_y


func _refresh_wings(player: Player) -> void:
	if player.body == null:
		return
	var mode := PlayerBody.WINGS_OFF
	if active:
		mode = PlayerBody.WINGS_OPEN
	elif equipped:
		mode = PlayerBody.WINGS_PACKED
	player.body.show_wings(mode)


func _dbg(hypothesis_id: String, location: String, message: String, data: Dictionary) -> void:
	var path := "/Users/jamesritchie/golf-zombies/.cursor/debug-735403.log"
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	else:
		file.seek_end()
	if file == null:
		return
	file.store_line(JSON.stringify({
		"sessionId": "735403",
		"hypothesisId": hypothesis_id,
		"location": location,
		"message": message,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
	}))
	file.close()
