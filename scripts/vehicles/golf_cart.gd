class_name GolfCart
extends CharacterBody3D
## The shared cart. Either player can hop in; whoever gets there first drives and
## the other rides shotgun, free to keep shooting. Zombies are not solid to it, so
## anything you drive into gets run over rather than blocking the wheels.

const MAX_SPEED := 17.5
const BOOST_SPEED := 21.5
const REVERSE_SPEED := 5.0
const ACCELERATION := 14.0
const BOOST_ACCEL := 19.0
## Applied when nobody is on the throttle, so a cart left alone rolls to a stop.
const COAST_DECAY := 4.5
const IMPACT_DECAY := 34.0
const TURN_DEG_PER_SEC := 105.0
const DRIFT_TURN := 2.0
## How quickly velocity tracks the nose while sliding. Lower is more sideways.
const DRIFT_FOLLOW := 1.5
## Catch-up rate as the tires bite again after you let go.
const DRIFT_GRIP := 3.0
## Seconds of leftover slide after the drift button is released.
const DRIFT_RECOVER := 1.0
## Extra top speed at a full sideways slide, on top of the boost cap.
const DRIFT_TOP := 6.5
const DRIFT_MIN_SPEED := 5.5
const DRIFT_STEER := 0.28
const BOARD_RANGE := 3.4
const EXIT_SIDE := 1.7
const FLOOR_SNAP := 0.25
const FLOOR_MAX_DEG := 50.0
## Faster than a crawl, and climbing, before the cart lets go of the ground.
const LAUNCH_MIN_SPEED := 7.0
const LAUNCH_CLIMB := 0.1
const PITCH_CATCH := 10.0
## Heavier than the world's 9.8 so a ramp launch dumps you onto the far bank
## instead of hanging over the pond.
const AIR_GRAVITY := 26.0
const _Boost := preload("res://scripts/course/cart_path_boost.gd")
const _TireMarks := preload("res://scripts/fx/tire_marks.gd")

## Below this the cart is just nudging zombies out of the way.
const CRUSH_MIN_SPEED := 4.0
const CRUSH_DAMAGE_PER_SPEED := 24.0
const CRUSH_PUSH := 9.0
const TURBO_MULT := 1.18
const RAM_MULT := 1.45
const ARMOR_SCALE := 0.5
## Zoomed-out chase cam: far enough to read the whole cart and the path ahead.
const CHASE_DISTANCE := 9.5
const CHASE_HEIGHT := 4.8
const CHASE_LOOK_HEIGHT := 1.15
const CHASE_LOOK_AHEAD := 2.5
const CHASE_FOV := 88.0

var driver: Player
var passenger: Player
var _net_throttle := 0.0
var _net_steer := 0.0
var _net_boost := false
## Signed speed along the cart's own forward axis; negative is reverse.
var drive_speed := 0.0
var turbo := false
var ram_plate := false
var armored := false
## 1 while drifting, then falls to 0 over DRIFT_RECOVER after you let go.
var _drift := 0.0
var _boost_count := 0
var _fling_left := 0.0

@onready var seats: Array[Node3D] = [$DriverSeat, $PassengerSeat]
@onready var crush_area: Area3D = $Crush

var _wheel: SteeringWheel
var _driver_view: Node3D
var _shown_driver: Player
var _marks: _TireMarks
## Zombies already hit on this pass, so one run-over is one hit no matter how many
## frames they spend under the cart.
var _hit := {}


func _ready() -> void:
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.VEHICLE_MASK
	floor_snap_length = FLOOR_SNAP
	floor_max_angle = deg_to_rad(FLOOR_MAX_DEG)
	crush_area.collision_layer = 0
	crush_area.collision_mask = Layers.ZOMBIE
	crush_area.body_exited.connect(_on_body_exited)
	add_child(CartVisuals.build())
	_marks = _TireMarks.new()
	_marks.name = "TireMarks"
	add_child(_marks)
	_wheel = SteeringWheel.new()
	_wheel.position = Vector3(-0.42, 1.22, 0.04)
	add_child(_wheel)
	_driver_view = Node3D.new()
	_driver_view.name = "DriverView"
	# Back and up from the wheel so the cabin is in frame, not just the rim.
	_driver_view.position = Vector3(-0.42, 1.72, 0.78)
	_driver_view.rotation.x = deg_to_rad(-16.0)
	add_child(_driver_view)
	# Face the rim at the seat so the driver sees a hoop, not the edge of a doughnut.
	var to_seat := _driver_view.position - _wheel.position
	_wheel.rotation.x = -atan2(to_seat.y, to_seat.z)


func place_at(position: Vector3, facing_yaw: float) -> void:
	eject_all()
	recover_at(position, facing_yaw)


func recover_at(at: Vector3, facing_yaw: float) -> void:
	if is_inside_tree():
		global_position = at
	else:
		position = at
	rotation = Vector3(0.0, deg_to_rad(facing_yaw), 0.0)
	velocity = Vector3.ZERO
	drive_speed = 0.0
	_drift = 0.0
	_boost_count = 0
	_fling_left = 0.0
	_hit.clear()
	if _marks != null:
		_marks.clear()


func driver_view_transform() -> Transform3D:
	if _driver_view == null:
		return global_transform
	return _driver_view.global_transform


func chase_view_transform() -> Transform3D:
	return chase_cam(global_position, rotation.y)


## Behind the cart, looking over the roof down the fairway.
static func chase_cam(origin: Vector3, yaw: float) -> Transform3D:
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye := origin - facing * CHASE_DISTANCE + Vector3.UP * CHASE_HEIGHT
	var target := origin + Vector3.UP * CHASE_LOOK_HEIGHT + facing * CHASE_LOOK_AHEAD
	var xform := Transform3D(Basis(), eye)
	return xform.looking_at(target, Vector3.UP)


func wheel_angle_deg() -> float:
	return 0.0 if _wheel == null else _wheel.angle_deg()


func wheel_grips() -> Array[Vector3]:
	if _wheel == null:
		return []
	return _wheel.grip_positions()


func is_riding(player: Player) -> bool:
	return driver == player or passenger == player


func can_board(player: Player) -> bool:
	if is_riding(player) or not player.health.is_alive():
		return false
	if driver != null and passenger != null:
		return false
	var offset := player.global_position - global_position
	offset.y = 0.0
	return offset.length() <= BOARD_RANGE


## First one in drives.
func board(player: Player) -> void:
	if NetSession.is_active() and not is_multiplayer_authority():
		_request_board.rpc_id(1, player.peer_id)
		return
	_do_board(player)
	_broadcast_seats()


func _do_board(player: Player) -> void:
	if not can_board(player):
		return
	if driver == null:
		driver = player
	else:
		passenger = player
	player.cart = self
	player.enter_ride()
	_seat_riders()
	Sfx.play("board", self)


func eject(player: Player) -> void:
	if NetSession.is_active() and not is_multiplayer_authority():
		_request_eject.rpc_id(1, player.peer_id)
		return
	_do_eject(player)
	_broadcast_seats()


func _do_eject(player: Player) -> void:
	if not is_riding(player):
		return
	var side := 1.0 if driver == player else -1.0
	if driver == player:
		driver = null
	else:
		passenger = null
	player.exit_ride()
	player.stand_at(exit_point(side), rad_to_deg(player.rotation.y))
	Sfx.play("eject", self)


func eject_all() -> void:
	if driver != null:
		_do_eject(driver)
	if passenger != null:
		_do_eject(passenger)
	_broadcast_seats()


static func can_hijack(driver_player: Player, attacker: Player, distance: float) -> bool:
	if driver_player == null or attacker == null or attacker == driver_player:
		return false
	return distance <= Melee.RANGE


func try_hijack(attacker: Player) -> bool:
	if attacker == null or driver == null:
		return false
	var offset := attacker.global_position - driver.global_position
	offset.y = 0.0
	if not can_hijack(driver, attacker, offset.length()):
		return false
	var victim := driver
	if passenger == attacker:
		passenger = null
		attacker.exit_ride()
	_do_eject(victim)
	victim.apply_knockback(attacker.global_position, 10.0)
	_do_board(attacker)
	_broadcast_seats()
	return true


## Where a rider is dropped off: clear of the wheels on their own side.
func exit_point(side: float) -> Vector3:
	var right := global_transform.basis.x
	right.y = 0.0
	return global_position + right.normalized() * side * EXIT_SIDE


func _physics_process(delta: float) -> void:
	if not NetSession.should_simulate(self):
		return
	_drive(delta)
	_bleed_speed_on_impact(delta)
	_seat_riders()
	_run_over()


func fling(direction: Vector3, speed: float, lift := 14.0, lock := 1.0) -> void:
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		dir = -transform.basis.z
	dir = dir.normalized()
	velocity = dir * speed + Vector3.UP * lift
	drive_speed = 0.0
	_drift = 0.0
	_fling_left = lock


func is_flung() -> bool:
	return _fling_left > 0.0


func _drive(delta: float) -> void:
	if _fling_left > 0.0:
		_fling_left = maxf(0.0, _fling_left - delta)
		velocity.y -= AIR_GRAVITY * delta
		move_and_slide()
		return
	var throttle := 0.0
	var steer := 0.0
	var boosting := false
	if driver != null and driver.health.is_alive():
		if driver.net_driven and driver.peer_id != multiplayer.get_unique_id():
			throttle = _net_throttle
			steer = _net_steer
			boosting = _net_boost
		else:
			var stick := driver.input.move_vector()
			throttle = -stick.y
			steer = stick.x
			boosting = driver.input.pressed("shoot")
	var drifting := is_drifting(boosting, steer, drive_speed)
	_drift = next_drift(_drift, drifting, delta)
	var pull := ACCELERATION
	if boosting and throttle > 0.0:
		pull = BOOST_ACCEL
	elif is_zero_approx(throttle):
		pull = COAST_DECAY
	var nose := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	if _boost_count > 0:
		drive_speed = _Boost.cart_speed(drive_speed, delta)
	else:
		var wanted := target_speed(throttle, boosting, max_drive_speed(), boost_drive_speed())
		if wanted > 0.0:
			wanted += drift_bonus(slip_amount(nose, velocity), _drift)
		drive_speed = move_toward(drive_speed, wanted, pull * delta)
	var turn := turn_rate_deg(drive_speed, steer, max_drive_speed()) * drift_turn_scale(_drift)
	rotation.y += deg_to_rad(turn * delta)
	if _wheel != null:
		_wheel.turn(steer, delta)
		if _shown_driver != driver:
			_shown_driver = driver
			if driver != null:
				_wheel.show_hands(true, driver.body_color, PlayerBody.WORLD_LAYER)
			else:
				_wheel.show_hands(false)
	nose = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var slip := velocity_slip(_drift, delta)
	if is_on_floor():
		var floor_n := get_floor_normal()
		floor_snap_length = snap_length(floor_n, nose, drive_speed)
		var along := slope_velocity(nose, floor_n, drive_speed)
		velocity.x = lerpf(velocity.x, along.x, slip)
		velocity.z = lerpf(velocity.z, along.z, slip)
		velocity.y = along.y
	else:
		floor_snap_length = 0.0
		var wanted := nose * drive_speed
		velocity.x = lerpf(velocity.x, wanted.x, slip)
		velocity.z = lerpf(velocity.z, wanted.z, slip)
		velocity.y -= AIR_GRAVITY * delta
	_align_pitch(delta)
	move_and_slide()
	if _marks != null:
		_marks.trace(
			_wheel_contacts(), is_leaving_rubber(_drift, is_on_floor(), drive_speed), delta
		)


## Hitting a tree or a barrier has to cost the cart its speed, otherwise it grinds
## along the wall at full throttle.
func _bleed_speed_on_impact(delta: float) -> void:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().dot(up_direction) < 0.7:
			drive_speed = move_toward(drive_speed, 0.0, IMPACT_DECAY * delta)
			return


func _seat_riders() -> void:
	if driver != null:
		driver.sit_as_driver(seats[0].global_position, rad_to_deg(rotation.y))
	if passenger != null:
		passenger.sit_as_passenger(seats[1].global_position)


func _run_over() -> void:
	if absf(drive_speed) < CRUSH_MIN_SPEED:
		# Slowed down: the next time the cart gets going is a fresh pass.
		_hit.clear()
		return
	var direction := -global_transform.basis.z * signf(drive_speed)
	direction.y = 0.0
	direction = direction.normalized()
	for body in crush_area.get_overlapping_bodies():
		var zombie := body as Zombie
		if zombie == null or zombie.is_allied() or _hit.has(zombie.get_instance_id()):
			continue
		_hit[zombie.get_instance_id()] = true
		var hit := zombie.global_position + Vector3.UP * zombie.stats.height * 0.22
		zombie.take_damage(crush_damage(drive_speed, ram_mult()), direction, hit)
		zombie.stagger(direction * CRUSH_PUSH)
		Sfx.play("crush", self)


func _on_body_exited(body: Node3D) -> void:
	_hit.erase(body.get_instance_id())


func enter_boost(_along: Vector3) -> void:
	_boost_count += 1
	if _boost_count == 1:
		Sfx.play("boost_pad", self)


func exit_boost() -> void:
	_boost_count = maxi(0, _boost_count - 1)


func on_boost_pad() -> bool:
	return _boost_count > 0


func install_turbo() -> void:
	turbo = true


func install_ram() -> void:
	ram_plate = true


func install_armor() -> void:
	armored = true


func max_drive_speed() -> float:
	return MAX_SPEED * (TURBO_MULT if turbo else 1.0) * beer_mult()


func boost_drive_speed() -> float:
	return BOOST_SPEED * (TURBO_MULT if turbo else 1.0) * beer_mult()


func beer_mult() -> float:
	if driver == null:
		return 1.0
	return driver.buzz.cart_mult()


func ram_mult() -> float:
	return RAM_MULT if ram_plate else 1.0


## What the throttle is asking for. Reverse is slow, like a real cart. R2 / click
## adds a little extra on the way forwards.
static func target_speed(
	throttle: float, boost := false, max_speed := MAX_SPEED, boost_speed := BOOST_SPEED
) -> float:
	var wanted := clampf(throttle, -1.0, 1.0)
	if wanted < 0.0:
		return wanted * REVERSE_SPEED
	return wanted * (boost_speed if boost else max_speed)


## Boost plus a turn at speed is a drift: the cart yaws but the slide keeps going.
static func is_drifting(boost: bool, steer: float, speed: float) -> bool:
	return boost and absf(steer) > DRIFT_STEER and absf(speed) > DRIFT_MIN_SPEED


## Pins at full slide while the trigger is held, then eases off over a second.
static func next_drift(current: float, drifting: bool, delta: float) -> float:
	if drifting:
		return 1.0
	return move_toward(current, 0.0, delta / DRIFT_RECOVER)


static func drift_turn_scale(drift: float) -> float:
	return lerpf(1.0, DRIFT_TURN, clampf(drift, 0.0, 1.0))


## How far the cart is sliding off its nose. 0 is rolling straight, 1 is fully sideways.
static func slip_amount(nose: Vector3, travel: Vector3) -> float:
	var facing := Vector3(nose.x, 0.0, nose.z)
	var along := Vector3(travel.x, 0.0, travel.z)
	if facing.length_squared() < 0.0001 or along.length_squared() < 0.25:
		return 0.0
	var aligned := clampf(facing.normalized().dot(along.normalized()), -1.0, 1.0)
	return clampf(acos(aligned) / (PI * 0.5), 0.0, 1.0)


## Extra speed from the slide. A shallow drift is a nudge; a big angle is the fast line.
static func drift_bonus(angle: float, drift: float) -> float:
	return DRIFT_TOP * clampf(angle, 0.0, 1.0) * clampf(drift, 0.0, 1.0)


static func is_leaving_rubber(drift: float, on_floor: bool, speed: float) -> bool:
	return on_floor and drift > 0.0 and absf(speed) > DRIFT_MIN_SPEED * 0.5


func _wheel_contacts() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for offset in CartVisuals.wheel_offsets():
		points.append(to_global(Vector3(offset.x, _TireMarks.LIFT, offset.z)))
	return points


## How much this frame's velocity catches the nose. 1 is full grip.
static func velocity_slip(drift: float, delta: float) -> float:
	if drift <= 0.0:
		return 1.0
	var rate := lerpf(DRIFT_GRIP, DRIFT_FOLLOW, clampf(drift, 0.0, 1.0))
	return clampf(rate * delta, 0.0, 1.0)


## Drive along the floor so a ramp's slope becomes launch speed instead of being
## flattened into a horizontal shove.
static func slope_velocity(nose: Vector3, floor_normal: Vector3, speed: float) -> Vector3:
	var flat := Vector3(nose.x, 0.0, nose.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	flat = flat.normalized()
	var along := flat.slide(floor_normal)
	if along.length_squared() < 0.0001:
		return flat * speed
	return along.normalized() * speed


## Climbing at speed: snap would glue the cart to the lip and kill the jump.
static func snap_length(floor_normal: Vector3, nose: Vector3, speed: float) -> float:
	if absf(speed) < LAUNCH_MIN_SPEED:
		return FLOOR_SNAP
	var climb := slope_velocity(nose, floor_normal, signf(speed)).y
	return 0.0 if climb > LAUNCH_CLIMB else FLOOR_SNAP


func _align_pitch(delta: float) -> void:
	var wanted := 0.0
	if is_on_floor():
		wanted = pitch_on_floor(get_floor_normal(), rotation.y)
	else:
		var horiz := Vector2(velocity.x, velocity.z).length()
		if horiz > 0.5:
			wanted = clampf(atan2(-velocity.y, horiz), deg_to_rad(-50.0), deg_to_rad(50.0))
	rotation.x = lerp_angle(rotation.x, wanted, clampf(PITCH_CATCH * delta, 0.0, 1.0))


static func pitch_on_floor(floor_normal: Vector3, yaw: float) -> float:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return atan2(-floor_normal.dot(forward), floor_normal.y)


## Steering scales with how fast the cart is actually rolling, so it cannot spin on
## the spot, and the sign flips in reverse the way a real one does.
static func turn_rate_deg(speed: float, steer: float, max_speed := MAX_SPEED) -> float:
	return -clampf(steer, -1.0, 1.0) * TURN_DEG_PER_SEC * clampf(speed / maxf(1.0, max_speed), -1.0, 1.0)


## Damage from being hit by the cart. Cruising speed flattens a walker or a runner
## outright; at full tilt a brute goes down in one pass too.
static func crush_damage(speed: float, ram := 1.0) -> float:
	if absf(speed) < CRUSH_MIN_SPEED:
		return 0.0
	return absf(speed) * CRUSH_DAMAGE_PER_SPEED * ram


func _player_by_peer(peer_id: int) -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player != null and player.peer_id == peer_id:
			return player
	return null


func _peer_of(player: Player) -> int:
	return 0 if player == null else player.peer_id


func _broadcast_seats() -> void:
	if NetSession.is_active() and is_multiplayer_authority():
		_replicate_seats.rpc(_peer_of(driver), _peer_of(passenger))


@rpc("any_peer", "reliable")
func _request_board(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var player := _player_by_peer(peer_id)
	if player != null:
		_do_board(player)
		_broadcast_seats()


@rpc("any_peer", "reliable")
func _request_eject(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var player := _player_by_peer(peer_id)
	if player != null:
		_do_eject(player)
		_broadcast_seats()


@rpc("authority", "call_remote", "reliable")
func _replicate_seats(driver_id: int, passenger_id: int) -> void:
	driver = _player_by_peer(driver_id)
	passenger = _player_by_peer(passenger_id)
	if driver != null:
		driver.cart = self
		if not driver.is_riding():
			driver.enter_ride()
	if passenger != null:
		passenger.cart = self
		if not passenger.is_riding():
			passenger.enter_ride()


@rpc("any_peer", "unreliable")
func report_drive(stick: Vector2, boosting: bool) -> void:
	if not is_multiplayer_authority() or driver == null:
		return
	if multiplayer.get_remote_sender_id() != driver.peer_id:
		return
	_net_steer = stick.x
	_net_throttle = -stick.y
	_net_boost = boosting
