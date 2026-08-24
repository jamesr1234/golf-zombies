class_name CpuBuddy
extends RefCounted
## Solo partner. Follows the human, boards as shotgun, revives, and shoots.
## Does not golf unless the human holds interact to send them at the ball.
## Plants a shield when the human golfs, draws a sniper, or takes a tower hit.

const FOLLOW_STOP := 2.8
const FOLLOW_SPRINT := 8.0
## Warp if the partner has gone through a doorway or driven off without us.
const CATCH_UP := 22.0
const CATCH_UP_SIDE := 2.2
const SHOOT_ENEMIES := true
const SHOOT_RANGE := 22.0
const MELEE_RANGE := 2.1
const AIM_OK_DEG := 12.0
const LOOK_SCALE := 25.0
const COVER_STANDOFF := 1.55
const COVER_PLANT := 1.25
const CONTACT_CLICK := 0.05
const CART_END := 16.0
const LOOK_AHEAD := 8.0

var shot_requested := false

var _player: Player
var _shot_power := 0.5


func setup(player: Player) -> void:
	_player = player


func request_shot() -> void:
	shot_requested = true


func is_taking_shot() -> bool:
	return shot_requested


func tick(_delta: float) -> void:
	var pad := _player.input as CpuInput
	if pad == null or not _player.health.is_alive():
		if pad != null:
			pad.begin_frame()
		shot_requested = false
		return
	pad.begin_frame()
	var partner := _player.partner
	if partner != null and partner.health.is_downed():
		_revive(pad, partner)
		return
	if shot_requested:
		_play_shot(pad)
		return
	if _player.is_driving():
		_drive(pad)
		return
	if _player.is_riding():
		_ride(pad, partner)
		return
	if _should_board(partner):
		_board(pad)
		return
	_follow_and_fight(pad, partner)


func _play_shot(pad: CpuInput) -> void:
	var golf := _player.golf
	if golf == null or golf.ball == null:
		shot_requested = false
		return
	if golf.ball.is_in_play() or golf.ball.is_holed() or golf.ball.is_stowed() or golf.ball.is_closed():
		if not golf.is_golfing(_player):
			shot_requested = false
		return
	if golf.golfer != null and golf.golfer != _player:
		shot_requested = false
		return
	if golf.is_golfing(_player):
		_swing(pad, golf)
		return
	if not golf.is_available():
		shot_requested = false
		return
	if _player.is_riding():
		pad.tap("interact")
		return
	if golf.can_claim(_player):
		_shot_power = wanted_power(
			_player.global_position, golf.pin(), Shot.can_putt(golf.ball.current_surface()),
			_club_kit(), golf.green_span
		)
		pad.tap("interact")
		return
	_walk_toward(pad, golf.ball.global_position)
	_look_at(pad, golf.ball.global_position)


func _swing(pad: CpuInput, golf: GolfController) -> void:
	var meter := golf.meter
	if meter.state == SwingMeter.State.READY:
		pad.tap("swing")
	elif meter.state == SwingMeter.State.BACKSWING and meter.value >= _shot_power:
		pad.tap("swing")
	elif meter.state == SwingMeter.State.DOWNSWING and meter.value <= CONTACT_CLICK:
		pad.tap("swing")


static func wanted_power(
	from: Vector3, to: Vector3, putting := false, kit: ClubKit = null, green_span := 0.0
) -> float:
	var clubs := kit if kit != null else ClubKit.starter()
	var dist := Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))
	if putting:
		return clampf(dist / maxf(4.0, Shot.putt_run(clubs, green_span)), 0.08, 0.85)
	return clampf(dist / maxf(1.0, clubs.scaled_carry()), 0.12, 0.92)


func _club_kit() -> ClubKit:
	if _player.flow != null and _player.flow.score != null:
		return _player.flow.score.club_kit()
	return ClubKit.starter()


func _revive(pad: CpuInput, partner: Player) -> void:
	_walk_toward(pad, partner.global_position)
	_look_at(pad, partner.global_position + Vector3.UP)
	if _player._distance_to(partner) <= Player.REVIVE_RANGE:
		pad.move = Vector2.ZERO
		pad.hold("revive")


func _drive(pad: CpuInput) -> void:
	if _near_clubhouse():
		pad.tap("interact")
		return
	var along := _drive_heading()
	_look_at(pad, _player.global_position + along * LOOK_AHEAD)
	pad.move = local_move(_player.global_transform.basis, along)
	pad.hold("shoot")


func _drive_heading() -> Vector3:
	var flow := _player.flow as MatchFlow
	if flow != null and flow.cart_path != null and flow.cart_path.centerline.size() >= 2:
		var along := CartPathTrack.along(flow.cart_path.centerline, _player.global_position)
		return CartPathTrack.heading_at(flow.cart_path.centerline, along)
	if flow != null and flow.hole != null:
		return flow._along_hole()
	var nose := -_player.global_transform.basis.z
	nose.y = 0.0
	return nose.normalized() if nose.length_squared() > 0.0001 else Vector3.FORWARD


func _near_clubhouse() -> bool:
	var flow := _player.flow as MatchFlow
	if flow == null:
		return false
	if flow.cart_path != null:
		return _player.global_position.distance_to(flow.cart_path.tee) < CART_END
	if flow.clubhouse != null and is_instance_valid(flow.clubhouse):
		return _player.global_position.distance_to(flow.clubhouse.door_point()) < CART_END
	return false


func _ride(pad: CpuInput, partner: Player) -> void:
	if partner == null or not partner.is_riding():
		pad.tap("interact")
		return
	_fight(pad, false)


func _should_board(partner: Player) -> bool:
	if partner == null or not partner.is_riding() or _player.cart == null:
		return false
	return not _player.cart.is_riding(_player)


func _board(pad: CpuInput) -> void:
	if _player.cart.can_board(_player):
		pad.tap("interact")
		return
	if _player._distance_to(_player.cart) > CATCH_UP:
		_join_at(
			_player.cart.global_position + Vector3.UP * 1.0,
			rad_to_deg(_player.cart.rotation.y)
		)
		if _player.cart.can_board(_player):
			_player.cart.board(_player)
		return
	_walk_toward(pad, _player.cart.global_position)


func _follow_and_fight(pad: CpuInput, partner: Player) -> void:
	if partner != null and partner.needs_cover():
		var threat := _cover_threat(partner)
		if threat != null:
			_cover(pad, partner, threat)
			return
		partner.wants_cover = false
	if partner != null:
		var gap := _player._distance_to(partner)
		if gap > CATCH_UP:
			_join(partner)
			return
		if gap > FOLLOW_STOP:
			_walk_toward(pad, partner.global_position)
			pad.hold("sprint", gap > FOLLOW_SPRINT)
	_fight(pad, true)


func _join(partner: Player) -> void:
	var side := partner.global_transform.basis.x
	side.y = 0.0
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	_join_at(partner.global_position + side * CATCH_UP_SIDE, rad_to_deg(partner.rotation.y))


func _join_at(at: Vector3, yaw: float) -> void:
	_player.spawn_at(at, yaw)


func _cover(pad: CpuInput, partner: Player, gunner: Zombie) -> void:
	var cover := cover_point(partner.global_position, gunner.global_position, partner)
	var gap := _player.global_position.distance_to(cover)
	if gap > COVER_PLANT:
		_walk_toward(pad, cover)
	_look_at(pad, gunner.global_position + Vector3.UP * 1.1)
	if gap <= COVER_PLANT:
		pad.hold("shield")


static func cover_point(partner_at: Vector3, threat_at: Vector3, partner: Player = null) -> Vector3:
	var away := threat_at - partner_at
	away.y = 0.0
	if away.length_squared() < 0.01:
		if partner != null:
			away = -partner.global_transform.basis.z
			away.y = 0.0
		else:
			away = Vector3.FORWARD
	return partner_at + away.normalized() * COVER_STANDOFF


func _fight(pad: CpuInput, can_melee: bool) -> void:
	if _player.weapon.mag() <= 0:
		pad.tap("reload")
	var zombie := _nearest_zombie()
	if zombie == null:
		if _player.partner != null:
			_look_at(pad, _player.partner.global_position + Vector3.UP)
		return
	var aim_at := zombie.global_position + Vector3.UP * 1.1
	var yaw_err := yaw_error(_player.rotation.y, _player.head.global_position, aim_at)
	var pitch_err := pitch_error(_player.head.rotation.x, _player.head.global_position, aim_at)
	pad.look = look_stick(yaw_err, pitch_err)
	var range := _player.global_position.distance_to(zombie.global_position)
	var on_target := absf(yaw_err) < AIM_OK_DEG and absf(pitch_err) < AIM_OK_DEG
	if SHOOT_ENEMIES and on_target and range <= SHOOT_RANGE:
		pad.hold("shoot")
	if can_melee and on_target and range <= MELEE_RANGE:
		pad.tap("melee")


func _walk_toward(pad: CpuInput, world_point: Vector3) -> void:
	var dir := world_point - _player.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		return
	pad.move = local_move(_player.global_transform.basis, dir.normalized())


func _look_at(pad: CpuInput, world_point: Vector3) -> void:
	var from := _player.head.global_position
	pad.look = look_stick(
		yaw_error(_player.rotation.y, from, world_point),
		pitch_error(_player.head.rotation.x, from, world_point)
	)


func _nearest_zombie() -> Zombie:
	var best: Zombie
	var best_dist := SHOOT_RANGE
	for node in _player.get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not is_instance_valid(zombie):
			continue
		var dist := _player.global_position.distance_to(zombie.global_position)
		if dist < best_dist:
			best = zombie
			best_dist = dist
	return best


func _cover_threat(partner: Player) -> Zombie:
	var snipers_only := partner.wants_cover and not partner.is_golfing() and not partner.is_holding_sniper()
	var best: Zombie
	var best_dist := INF
	for node in _player.get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not is_instance_valid(zombie) or zombie.stats == null:
			continue
		if zombie.is_dying() or not zombie.stats.ranged:
			continue
		if snipers_only and not zombie.stats.stationary:
			continue
		var dist := partner.global_position.distance_to(zombie.global_position)
		if dist < best_dist:
			best = zombie
			best_dist = dist
	return best


## Stick so local -Z (forward) matches the world direction.
static func local_move(basis: Basis, world_dir: Vector3) -> Vector2:
	var local := basis.inverse() * world_dir
	return Vector2(local.x, local.z).limit_length(1.0)


## Player yaw decreases when look.x is positive, pitch decreases when look.y is.
static func look_stick(yaw_error_deg: float, pitch_error_deg: float) -> Vector2:
	return Vector2(
		clampf(-yaw_error_deg / LOOK_SCALE, -1.0, 1.0),
		clampf(-pitch_error_deg / LOOK_SCALE, -1.0, 1.0)
	)


static func yaw_error(yaw_rad: float, from: Vector3, to: Vector3) -> float:
	var dir := to - from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return 0.0
	var wanted := rad_to_deg(atan2(-dir.x, -dir.z))
	return wrapf(wanted - rad_to_deg(yaw_rad), -180.0, 180.0)


static func pitch_error(pitch_rad: float, from: Vector3, to: Vector3) -> float:
	var dir := to - from
	var horiz := Vector2(dir.x, dir.z).length()
	var wanted := rad_to_deg(atan2(dir.y, horiz))
	return wrapf(wanted - rad_to_deg(pitch_rad), -180.0, 180.0)
