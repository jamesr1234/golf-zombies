class_name PlayerMotion
extends RefCounted
## On-foot walking, flings, climb latching, and knockback. Swimming and cart
## carriage stay on their own helpers; this only moves the capsule when those
## are not owning the body.

const WALK_SPEED := 5.4
const SPRINT_SPEED := 8.2
const ACCELERATION := 14.0
const JUMP_VELOCITY := 4.8
const HIT_KNOCK := 6.5
const FLOOR_SNAP := 0.45
const FLOOR_MAX_DEG := 60.0
const SAFE_MARGIN := 0.04

const _Boost := preload("res://scripts/course/cart_path_boost.gd")

var fling_left := 0.0
var boost_count := 0
var boost_along := Vector3.ZERO
var seen_jumps := 0


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
		return
	if player.is_climbing():
		if not player.climber.tick(player, delta):
			player._drop_climb()
		return
	if player.is_milling():
		player.mill_desk.tick(player, delta)
		player.velocity = Vector3.ZERO
		return
	if try_latch_climb(player):
		return
	if fling_left > 0.0:
		fling_left = maxf(0.0, fling_left - delta)
		if not player.is_on_floor():
			player.velocity += player.get_gravity() * delta
		player.move_and_slide()
		return
	var wading := player.swim.water_depth(player)
	if player.swim.should_swim(player, wading):
		player.swim.tick(player, delta)
		return
	if player.state == Player.State.SWIMMING:
		player.swim.leave(player)
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta
	var mobile := (
		player.health.is_alive()
		and (player.state == Player.State.NORMAL or player.state == Player.State.PLACING)
		and not player.is_celebrating()
	)
	var wish := Vector3.ZERO
	if mobile:
		var stick := walk_stick(player)
		wish = (player.transform.basis * Vector3(stick.x, 0.0, stick.y))
		wish.y = 0.0
		wish = wish.normalized() * minf(1.0, stick.length())
		if jumped(player) and player.is_on_floor():
			player.velocity.y = JUMP_VELOCITY
			Sfx.play("jump", player)
	var speed := SPRINT_SPEED if mobile and sprinting(player) else WALK_SPEED
	if wading > PlayerSwim.WADE_DRAG_DEPTH:
		speed *= PlayerSwim.WADE_SPEED_SCALE
	var target := wish * speed
	player.velocity.x = move_toward(player.velocity.x, target.x, ACCELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, target.z, ACCELERATION * delta)
	if boost_count > 0:
		player.velocity = _Boost.player_velocity(player.velocity, boost_along, delta)
	player.move_and_slide()


func walks_from_wire(player: Player) -> bool:
	return player.net_driven and not player.is_multiplayer_authority()


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


func fling(player: Player, direction: Vector3, speed: float, lift := 14.0, lock := 1.0) -> void:
	if player.is_riding():
		return
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
	if not player.input.just_pressed("melee") and not player.input.just_pressed("shield"):
		return false
	return start_climb(player)


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
