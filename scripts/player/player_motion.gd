class_name PlayerMotion
extends RefCounted
## On-foot walking, flings, climb latching, and knockback. Swimming and cart
## carriage stay on their own helpers; this only moves the capsule when those
## are not owning the body.

const WALK_SPEED := 5.4
const SPRINT_SPEED := 8.2
const ACCELERATION := 14.0
const JUMP_VELOCITY := 8.0
const GRAVITY_SCALE := 2.35
const HIT_KNOCK := 6.5
const FLOOR_SNAP := 0.45
const FLOOR_MAX_DEG := 60.0
const SAFE_MARGIN := 0.04

const _Boost := preload("res://scripts/course/cart_path_boost.gd")

var fling_left := 0.0
var boost_count := 0
var boost_along := Vector3.ZERO
var escalator
var seen_jumps := 0

# #region agent log
var _dbg_air := 0
# #endregion


func configure(player: Player) -> void:
	player.floor_snap_length = FLOOR_SNAP
	player.floor_max_angle = deg_to_rad(FLOOR_MAX_DEG)
	player.floor_constant_speed = true
	player.safe_margin = SAFE_MARGIN


func tick(player: Player, delta: float) -> void:
	# Riders are carried by the cart. Golfers are planted at address. Either one
	# calling move_and_slide inside the heightmap is how a seat can freeze.
	if (
		player.state == Player.State.RIDING
		or player.state == Player.State.GOLFING
		or player.state == Player.State.MECH
	):
		player.slide.cancel(player)
		player.glide.cancel(player)
		return
	if player.is_climbing():
		player.slide.cancel(player)
		player.glide.cancel(player)
		if not player.climber.tick(player, delta):
			player._drop_climb()
		return
	if player.is_grappling():
		player.slide.cancel(player)
		player.glide.cancel(player)
		if not player.grappler.tick(player, delta):
			player._drop_grapple()
		return
	if player.is_ziplining():
		player.slide.cancel(player)
		player.glide.cancel(player)
		if not player.zipliner.tick(player, delta):
			player._drop_zipline()
		return
	if player.is_milling():
		player.slide.cancel(player)
		player.glide.cancel(player)
		player.mill_desk.tick(player, delta)
		player.velocity = Vector3.ZERO
		return
	if player.is_poker_seated():
		player.slide.cancel(player)
		player.glide.cancel(player)
		player.velocity = Vector3.ZERO
		return
	if try_latch_climb(player):
		return
	if fling_left > 0.0:
		player.glide.cancel(player)
		fling_left = maxf(0.0, fling_left - delta)
		if not player.is_on_floor():
			player.velocity += player.get_gravity() * GRAVITY_SCALE * delta
		player.move_and_slide()
		return
	var wading := player.swim.water_depth(player)
	if player.swim.should_swim(player, wading):
		player.slide.cancel(player)
		player.glide.cancel(player)
		player.swim.tick(player, delta)
		return
	if player.state == Player.State.SWIMMING:
		player.swim.leave(player)
	if player.glide.active:
		_tick_glide(player, delta, true)
		return
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * GRAVITY_SCALE * delta
	var mobile := can_walk(player)
	var wish := Vector3.ZERO
	if mobile:
		var stick := walk_stick(player)
		wish = (player.transform.basis * Vector3(stick.x, 0.0, stick.y))
		wish.y = 0.0
		wish = wish.normalized() * minf(1.0, stick.length())
		if jumped(player):
			# #region agent log
			player.glide._dbg("D", "player_motion.gd:jump", "jump pressed", {
				"on_floor": player.is_on_floor(),
				"equipped": player.glide.equipped,
				"active": player.glide.active,
				"state": int(player.state),
			})
			# #endregion
			if player.is_on_floor():
				player.slide.try_stand(player)
				player.velocity.y = JUMP_VELOCITY
				Sfx.play("jump", player)
				player.glide.try_deploy(player)
			else:
				player.glide.try_deploy(player)
	if player.glide.active:
		_tick_glide(player, delta, false)
		return
	player.slide.tick(player, delta, wish, mobile)
	var speed := SPRINT_SPEED if mobile and sprinting(player) else WALK_SPEED
	if player.slide.active and not player.slide.bursting():
		speed = PlayerSlide.CRAWL_SPEED
	if wading > PlayerSwim.WADE_DRAG_DEPTH:
		speed *= PlayerSwim.WADE_SPEED_SCALE
	var target := wish * speed
	if player.slide.bursting():
		target = player.slide.along * PlayerSlide.SLIDE_SPEED
	var carry := Vector3.ZERO
	var on_floor := player.is_on_floor()
	if escalator != null and on_floor:
		carry = escalator.carry_along()
	player.velocity.x = move_toward(player.velocity.x, target.x + carry.x, ACCELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, target.z + carry.z, ACCELERATION * delta)
	if boost_count > 0:
		player.velocity = _Boost.player_velocity(player.velocity, boost_along, delta)
	# The belt only drives Y downhill. Pushing Y up makes move_and_slide skip
	# floor snap, so the rider leaves the ramp and the on_floor gate above then
	# cuts the carry. Uphill rides on the horizontal push and the slope lifts.
	if escalator != null and on_floor and carry.y < 0.0:
		player.velocity.y = carry.y
	# #region agent log
	if escalator != null:
		_dbg_air = 0 if on_floor else _dbg_air + 1
	if escalator != null and Engine.get_physics_frames() % 20 == 0:
		var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-75b629.log", FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-75b629.log", FileAccess.WRITE)
		else:
			f.seek_end()
		if f != null:
			f.store_line(JSON.stringify({
				"sessionId": "75b629",
				"hypothesisId": "C",
				"location": "player_motion.gd:tick",
				"message": "ride tick",
				"data": {
					"on_floor": on_floor,
					"applied": on_floor,
					"runId": "post-fix",
					"dir": int(escalator.sync_dir),
					"air_streak": _dbg_air,
					"carry": [carry.x, carry.y, carry.z],
					"vel": [player.velocity.x, player.velocity.y, player.velocity.z],
					"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
				},
				"timestamp": Time.get_ticks_msec(),
			}))
			f.close()
	# #endregion
	player.move_and_slide()


func _tick_glide(player: Player, delta: float, can_cut: bool) -> void:
	var mobile := can_walk(player)
	if can_cut and mobile and jumped(player):
		player.glide.cut(player)
		if not player.glide.active:
			player.velocity += player.get_gravity() * GRAVITY_SCALE * delta
			player.move_and_slide()
			return
	player.glide.tick(player, delta)
	if boost_count > 0:
		player.velocity = _Boost.player_velocity(player.velocity, boost_along, delta)
	var snap := player.floor_snap_length
	player.floor_snap_length = 0.0
	player.move_and_slide()
	player.floor_snap_length = snap
	var will_land := player.glide.landed(player)
	if will_land or not player.glide.active:
		# #region agent log
		player.glide._dbg("C", "player_motion.gd:_tick_glide", "cancel after slide", {
			"on_floor": player.is_on_floor(),
			"active_before": player.glide.active,
			"can_cut": can_cut,
			"vel_y": player.velocity.y,
			"will_land": will_land,
		})
		# #endregion
		player.glide.cancel(player)


func walks_from_wire(player: Player) -> bool:
	return player.net_driven and not player.is_multiplayer_authority()


## On your feet and free to steer. Downed waits on a partner, floored rights
## itself, and both take the stick away while they last.
static func can_walk(player: Player) -> bool:
	return (
		player.health.is_alive() and not player.is_floored()
		and (player.state == Player.State.NORMAL or player.state == Player.State.PLACING)
		and not player.is_celebrating()
		and not player.shopping
	)


func walk_stick(player: Player) -> Vector2:
	return player.sync_stick if walks_from_wire(player) else player.input.move_vector()


func sprinting(player: Player) -> bool:
	return player.sync_sprint if walks_from_wire(player) else player.input.pressed("sprint")


## Consumed on read, the same way a press is, so one jump is taken once.
func jumped(player: Player) -> bool:
	if walks_from_wire(player):
		var fresh := player.sync_jumps != seen_jumps
		seen_jumps = player.sync_jumps
		return fresh
	if not player.input.just_pressed("jump"):
		return false
	player.sync_jumps += 1
	return true


func apply_fling(
	player: Player, direction: Vector3, speed: float, lift := 14.0, lock := 1.0
) -> void:
	if player.net_driven and not player.is_multiplayer_authority():
		player._receive_fling.rpc_id(maxi(1, player.peer_id), direction, speed, lift, lock)
		return
	fling(player, direction, speed, lift, lock)


func fling(player: Player, direction: Vector3, speed: float, lift := 14.0, lock := 1.0) -> void:
	if player.is_riding():
		return
	player._drop_grapple()
	player._drop_zipline()
	player.glide.cancel(player)
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		dir = -player.transform.basis.z
	dir = dir.normalized()
	player.velocity = dir * speed
	player.velocity.y = maxf(player.velocity.y, lift)
	fling_left = lock
	if player.golf != null and player.is_golfing():
		player.golf.cancel_swing()


func apply_knockback(player: Player, from: Vector3, speed := 10.0) -> void:
	if player.net_driven and not player.is_multiplayer_authority():
		player._receive_knockback.rpc_id(maxi(1, player.peer_id), from, speed)
		return
	do_knockback(player, from, speed)


func do_knockback(player: Player, from: Vector3, speed: float) -> void:
	var away := player.global_position - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = -player.transform.basis.z
	away = away.normalized()
	player.velocity.x = away.x * speed
	player.velocity.z = away.z * speed
	player.velocity.y = maxf(player.velocity.y, 2.4)
	if player.golf != null and player.is_golfing():
		player.golf.cancel_swing()


func knock_from(player: Player, from: Vector3) -> void:
	if player.is_riding():
		return
	var push := Player.hit_push(from, player.global_position)
	player.velocity.x += push.x
	player.velocity.z += push.z


func can_latch_climb(player: Player) -> bool:
	if player.state != Player.State.NORMAL or player.shopping or player.talking or player.is_milling():
		return false
	if player.health == null or not player.health.is_alive():
		return false
	var wall := ClimbingWall.nearest(player)
	return wall != null and wall.can_latch(player)


func try_latch_climb(player: Player) -> bool:
	if not can_latch_climb(player):
		return false
	if player.input.just_pressed("melee") or player.input.just_pressed("shield"):
		return start_climb(player)
	var wall := ClimbingWall.nearest(player)
	if wall is LeanLadder and _pushing_into(player, wall):
		return start_climb(player)
	return false


func _pushing_into(player: Player, wall: ClimbingWall) -> bool:
	var stick := walk_stick(player)
	if stick.length_squared() < 0.16:
		return false
	var wish := player.transform.basis * Vector3(stick.x, 0.0, stick.y)
	wish.y = 0.0
	if wish.length_squared() < 0.0001:
		return false
	return wish.normalized().dot(-wall.face_normal()) > 0.35


func start_climb(player: Player) -> bool:
	var wall := ClimbingWall.nearest(player)
	if wall == null or not player.climber.latch(player, wall):
		return false
	player.state = Player.State.CLIMBING
	if player._shield != null:
		player._shield.set_raised(false)
	return true


func drop_climb(player: Player) -> void:
	player.climber.drop()
	if player.state == Player.State.CLIMBING:
		player.state = Player.State.NORMAL


func enter_boost_pad(player: Player, along: Vector3) -> void:
	boost_count += 1
	boost_along = along
	if boost_count == 1 and player.state != Player.State.RIDING:
		Sfx.play("boost_pad", player)


func exit_boost() -> void:
	boost_count = maxi(0, boost_count - 1)


func enter_escalator(lift) -> void:
	escalator = lift


func exit_escalator(lift) -> void:
	if escalator == lift:
		escalator = null


