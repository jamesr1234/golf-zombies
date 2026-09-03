class_name PlayerSwim
extends RefCounted
## Treading, diving, ball grab / throw, and climbing out of ponds. Kept off the
## Player script so the water rules can be read and tested on their own.

const SWIM_SPEED := 4.2
const SWIM_VERTICAL := 3.4
const SWIM_DIVE_SPEED := 4.0
## Water this deep is still walked through on foot, which is how you wade in off
## the bank. Past it the ground is too far down to stand on and you tread instead.
const WADE_DEPTH := 1.2
## Ankle-deep is enough to slow a run down.
const WADE_DRAG_DEPTH := 0.3
const WADE_SPEED_SCALE := 0.62
## How far the feet hang below the water line while treading, so the head and
## shoulders stay above it until you choose to dive.
const SWIM_FLOAT_DEPTH := 1.05
## Treading rises onto the water line at this rate rather than snapping to it.
const SWIM_SETTLE_SPEED := 3.2
## The body stands on its origin, so this is only enough to keep a dive off the
## pond floor rather than fighting the heightmap for it.
const SWIM_FLOOR_CLEARANCE := 0.1
const SWIM_GRAB_RANGE := 2.4
## How far from the bank you can haul yourself out while treading. Long enough
## to clear the slope you jam into, short enough that open water is still a swim.
const SWIM_CLIMB_REACH := 3.6
const SWIM_THROW_SPEED := 15.0
const SWIM_THROW_LIFT := 0.38
const SWIM_CARRY_FORWARD := 0.55
const SWIM_CARRY_HEIGHT := 0.15

var underwater := false


## Shallow water is walked through, so the shoreline is waded into on foot. Only
## once it is over your chest do you start treading, and only your own dive takes
## you under from there.
func should_swim(player: Player, water_depth: float) -> bool:
	if (
		not player.health.is_alive()
		or player.state == Player.State.GOLFING
		or player.state == Player.State.RIDING
		or player.state == Player.State.MECH
	):
		return false
	if player.state == Player.State.SWIMMING and underwater:
		return true
	return water_depth >= WADE_DEPTH


func water_depth(player: Player) -> float:
	if player.flow == null or player.flow.hole == null:
		return 0.0
	return player.flow.hole.water_depth_at(player.global_position)


func enter(player: Player) -> void:
	player._cancel_place()
	player.state = Player.State.SWIMMING
	player.aiming = false
	Sfx.play("splash", player)
	if player.combat.shield != null:
		player.combat.shield.set_raised(false)
	if player.golf != null and player.golf.golfer == player:
		player.golf.release()


func leave(player: Player) -> void:
	underwater = false
	if player.state == Player.State.SWIMMING:
		player.state = Player.State.NORMAL


## Treading water. You ride the surface with your head out until the dive button
## takes you under, and from there descend and ascend hold you between the floor
## and the water line.
func tick(player: Player, delta: float) -> void:
	if player.state != Player.State.SWIMMING:
		enter(player)
	var bed_y := water_floor_y(player) + SWIM_FLOOR_CLEARANCE
	var float_y := maxf(water_surface_y(player) - SWIM_FLOAT_DEPTH, bed_y)
	if not underwater and not player.is_carrying_ball() and player.input.just_pressed("shoot"):
		underwater = true
		player.velocity.y = -SWIM_DIVE_SPEED
		Sfx.play("dive", player)
	var stick := player.input.move_vector() if player.health.is_alive() else Vector2.ZERO
	var wish := (player.transform.basis * Vector3(stick.x, 0.0, stick.y))
	wish.y = 0.0
	if wish.length_squared() > 0.0001:
		wish = wish.normalized() * minf(1.0, stick.length()) * SWIM_SPEED
	else:
		wish = Vector3.ZERO
	player.velocity.x = move_toward(player.velocity.x, wish.x, PlayerMotion.ACCELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, wish.z, PlayerMotion.ACCELERATION * delta)
	if underwater:
		var vertical := 0.0
		if player.input.pressed("melee"):
			vertical -= SWIM_VERTICAL
		if player.input.pressed("ascend"):
			vertical += SWIM_VERTICAL
		player.velocity.y = move_toward(
			player.velocity.y, vertical, PlayerMotion.ACCELERATION * delta
		)
	else:
		player.velocity.y = 0.0
	player.move_and_slide()
	if underwater:
		player.global_position.y = clampf(player.global_position.y, bed_y, float_y)
		if player.input.pressed("ascend") and player.global_position.y >= float_y - 0.05:
			underwater = false
			player.velocity.y = 0.0
		return
	# Buoyancy rather than a snap, so stepping off the bank is a wade and not a
	# teleport onto the water line.
	player.global_position.y = move_toward(
		player.global_position.y, float_y, SWIM_SETTLE_SPEED * delta
	)


func water_surface_y(player: Player) -> float:
	if player.flow != null and player.flow.hole != null:
		return player.flow.hole.water_surface_y(player.global_position)
	return player.global_position.y + SWIM_FLOAT_DEPTH


func water_floor_y(player: Player) -> float:
	if player.flow != null and player.flow.hole != null:
		return player.flow.hole.water_floor_y(player.global_position)
	return player.global_position.y - HeightField.WATER_DEPTH


func try_grab_ball(player: Player) -> void:
	if player.golf == null or player.golf.ball == null or player.golf.ball.is_carried():
		return
	if player.global_position.distance_to(player.golf.ball.global_position) > SWIM_GRAB_RANGE:
		return
	player.golf.ball.pick_up(player)
	# Fishing the ball out settles the shot it was still resolving. Without this
	# the ball leaves play without ever coming to rest, so the golfer who played
	# it keeps the claim and stays rooted at their stance with zombies incoming.
	player.golf.release()
	Sfx.play("grab_ball", player)


## Circle / Space while treading, empty-handed, and close enough to the bank.
## The float sits you below the shelf, so walking into it never gets you out.
func try_climb_out(player: Player) -> bool:
	if underwater or player.is_carrying_ball():
		return false
	var land := climb_out_at(player)
	if land == Vector3.INF:
		return false
	leave(player)
	player.global_position = land
	player.velocity = Vector3.ZERO
	Sfx.play("splash", player)
	return true


func can_climb_out(player: Player) -> bool:
	return not underwater and not player.is_carrying_ball() and climb_out_at(player) != Vector3.INF


func climb_out_at(player: Player) -> Vector3:
	if player.flow == null or player.flow.hole == null:
		return Vector3.INF
	var facing := Vector3(-player.transform.basis.z.x, 0.0, -player.transform.basis.z.z)
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	else:
		facing = facing.normalized()
	var probes: Array[Vector3] = []
	for dist in [1.2, 2.2, SWIM_CLIMB_REACH]:
		probes.append(player.global_position + facing * dist)
	for radius in [1.8, SWIM_CLIMB_REACH]:
		for i in 12:
			var angle := TAU * float(i) / 12.0
			probes.append(player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	var best := Vector3.INF
	var best_depth := INF
	for probe in probes:
		var depth: float = player.flow.hole.water_depth_at(probe)
		if depth >= WADE_DEPTH:
			continue
		if depth < best_depth:
			best_depth = depth
			best = Vector3(probe.x, player.flow.hole.water_floor_y(probe), probe.z)
	return best


func throw_ball(player: Player) -> void:
	if not player.is_carrying_ball():
		return
	var forward := -player.head.global_transform.basis.z
	player.golf.ball.toss(
		player.head.global_position + forward * 0.8,
		throw_velocity(forward)
	)
	Sfx.play("throw_ball", player)


static func throw_velocity(forward: Vector3) -> Vector3:
	var dir := (forward + Vector3.UP * SWIM_THROW_LIFT).normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	return dir * SWIM_THROW_SPEED


static func carry_point(held_at: Transform3D) -> Vector3:
	return held_at.origin + (-held_at.basis.z * SWIM_CARRY_FORWARD) + Vector3.DOWN * SWIM_CARRY_HEIGHT


func prompt(player: Player) -> String:
	if underwater:
		if can_grab_ball(player):
			return "%s to grab the ball   %s down   %s up" % [
				player.input.hint("grab"), player.input.hint("descend"), player.input.hint("ascend")
			]
		return "Underwater   %s down   %s up to the surface" % [
			player.input.hint("descend"), player.input.hint("ascend")
		]
	if player.is_carrying_ball():
		return "%s to throw the ball to your partner" % player.input.hint("shoot")
	if can_climb_out(player):
		return "Treading water   %s to climb out   %s to dive" % [
			player.input.hint("grab"), player.input.hint("shoot")
		]
	return "Treading water   %s to dive for the ball" % player.input.hint("shoot")


func can_grab_ball(player: Player) -> bool:
	if player.golf == null or player.golf.ball == null or player.is_carrying_ball():
		return false
	return player.global_position.distance_to(player.golf.ball.global_position) <= SWIM_GRAB_RANGE
