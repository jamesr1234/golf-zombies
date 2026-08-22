class_name CartGirl
extends CharacterBody3D
## Stays out of sight until the first counted stroke, then rolls in from down
## the hole, sells beers, and leaves for the rest of that hole.

enum Visit { WAITING, APPROACHING, SERVING, LEAVING, GONE }

const CRUISE_SPEED := 9.0
const ACCELERATION := 10.0
const COAST_DECAY := 6.0
const TURN_DEG_PER_SEC := 95.0
const STOP_RANGE := 5.2
const FOLLOW_RANGE := 16.0
const USE_RANGE := 4.4
const LID_OPEN_DEG := -118.0
const LID_SPEED := 4.2
const SPAWN_ALONG := 88.0
const SPAWN_SIDE := 9.0
const SPAWN_CLEAR := 8.0
const LEAVE_BACK := 32.0
const LEAVE_SIDE := -38.0
const LINGER_SECONDS := 15.0
const SALE_LINGER_SECONDS := 30.0
const ENJOY := "enjoy!"
const ENJOY_TIME := 1.6
const SEAT := Vector3(-0.42, 0.86, 0.18)
const STAND := Vector3(1.38, 0.0, 2.05)
const GIRL_COLOR := Palette.HOT_PINK

var cooler_open := false
var drive_speed := 0.0
var visit := Visit.WAITING
var tending := false

var _lid: Node3D
var _wheel: SteeringWheel
var _girl: PlayerBody
var _phase := 0.0
var _parked := false
var _linger := 0.0
var _linger_limit := LINGER_SECONDS
var _leave_at := Vector3.ZERO


static func roadside(hole: HoleData, back: float, side: float) -> Vector3:
	var forward := hole.cup - hole.tee
	forward.y = 0.0
	forward = forward.normalized()
	var lateral := forward.cross(Vector3.UP).normalized()
	var spot := hole.tee - forward * back + lateral * side
	return hole.lift(spot) + Vector3.UP * 0.4


static func spawn_along(hole_length: float, green_radius := HoleData.DEFAULT_GREEN_RADIUS) -> float:
	var room := hole_length - green_radius - SPAWN_CLEAR
	return clampf(room, 28.0, SPAWN_ALONG)


static func spawn_at_hole(hole: HoleData) -> CartGirl:
	var girl := CartGirl.new()
	girl.name = "CartGirl"
	var along := spawn_along(hole.tee_to_cup(), hole.green_radius)
	# Negative back is down the hole, so she rolls in from the fairway.
	var spot := roadside(hole, -along, SPAWN_SIDE)
	girl.position = spot
	girl._leave_at = roadside(hole, LEAVE_BACK, LEAVE_SIDE)
	girl.rotation.y = drive_yaw(hole.tee - spot)
	girl.visible = false
	return girl


static func wanted_speed(distance: float, parked := false) -> float:
	if distance <= STOP_RANGE:
		return 0.0
	if parked and distance < FOLLOW_RANGE:
		return 0.0
	return CRUISE_SPEED


static func linger_expired(elapsed: float, limit := LINGER_SECONDS) -> bool:
	return elapsed >= limit


static func drive_yaw(to_target: Vector3) -> float:
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return atan2(-flat.x, -flat.z)


## Same nose the player cart uses: yaw 0 faces -Z.
static func nose_at(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Local +Z is the cooler. Park with that axis aimed at the player.
static func cooler_yaw(to_player: Vector3) -> float:
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return atan2(flat.x, flat.z)


func _ready() -> void:
	if visit == Visit.WAITING:
		_set_present(false)
	else:
		_set_present(true)
	floor_snap_length = GolfCart.FLOOR_SNAP
	floor_max_angle = deg_to_rad(GolfCart.FLOOR_MAX_DEG)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.1, 4.6)
	shape.shape = box
	shape.position.y = 0.55
	add_child(shape)
	add_child(BeerCartVisuals.build())
	_lid = find_child("Lid", true, false) as Node3D
	_wheel = SteeringWheel.new()
	_wheel.position = Vector3(-0.42, 1.22, -0.12)
	add_child(_wheel)
	_girl = PlayerBody.new()
	_girl.position = SEAT
	add_child(_girl)
	_girl.build(GIRL_COLOR)
	_wheel.show_hands(true, GIRL_COLOR, PlayerBody.WORLD_LAYER)


func begin_approach() -> void:
	if visit != Visit.WAITING:
		return
	visit = Visit.APPROACHING
	_parked = false
	_set_present(true)


func begin_service() -> void:
	if visit != Visit.APPROACHING:
		return
	visit = Visit.SERVING
	_parked = true
	_linger = 0.0
	_linger_limit = LINGER_SECONDS
	drive_speed = 0.0


func wait_out(seconds: float) -> void:
	if visit != Visit.SERVING:
		return
	_linger += seconds
	if linger_expired(_linger, _linger_limit):
		depart()


func depart() -> void:
	if visit != Visit.SERVING and visit != Visit.APPROACHING:
		return
	hop_in()
	visit = Visit.LEAVING
	_parked = false
	cooler_open = false
	if _leave_at == Vector3.ZERO:
		_leave_at = global_position + Vector3(LEAVE_SIDE, 0.0, LEAVE_BACK)


func vanish() -> void:
	hop_in()
	visit = Visit.GONE
	_parked = false
	cooler_open = false
	drive_speed = 0.0
	velocity = Vector3.ZERO
	_set_present(false)
	collision_mask = 0


func _set_present(on: bool) -> void:
	visible = on
	collision_layer = Layers.VEHICLE if on else 0
	# Hidden still has to feel the ground. Zero mask lets gravity drop her
	# through the map during warmup, so she is already gone by the first shot.
	collision_mask = Layers.VEHICLE_MASK if on else Layers.WORLD


func can_use(who: Node3D) -> bool:
	if visit != Visit.SERVING:
		return false
	if who == null or not is_inside_tree():
		return false
	var offset := who.global_position - cooler_point()
	offset.y = 0.0
	return offset.length() <= USE_RANGE


func cooler_point() -> Vector3:
	return global_position + global_transform.basis.z * BeerCartVisuals.COOLER_Z


func attendant() -> PlayerBody:
	return _girl


func hop_out() -> void:
	if _girl == null:
		return
	tending = true
	_girl.position = STAND
	_girl.rotation.y = PI
	if _wheel != null:
		_wheel.show_hands(false)


func hop_in() -> void:
	tending = false
	if _girl == null:
		return
	_girl.position = SEAT
	_girl.rotation = Vector3.ZERO
	if _girl.hips != null:
		_girl.hips.rotation.y = 0.0


func cheer(text: String) -> void:
	if _girl == null:
		return
	var old := _girl.get_node_or_null("Cheer")
	if old != null:
		_girl.remove_child(old)
		old.free()
	var copy := Label3D.new()
	copy.name = "Cheer"
	copy.text = text
	copy.font_size = 42
	copy.pixel_size = 0.016
	copy.modulate = Palette.BEER_INK
	copy.outline_size = 10
	copy.outline_modulate = Palette.NIGHT
	copy.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	copy.position = Vector3(0.0, 2.12, 0.0)
	_girl.add_child(copy)
	var timer := Timer.new()
	timer.wait_time = ENJOY_TIME
	timer.one_shot = true
	timer.timeout.connect(copy.queue_free)
	copy.add_child(timer)
	timer.start()


func open_cooler() -> void:
	cooler_open = true
	if visit == Visit.SERVING:
		_linger = 0.0
		hop_out()
	Sfx.play("cooler_open", self)


func sell_to(player: Player, wallet: GameState = null) -> bool:
	if player == null:
		return false
	var score := wallet
	if score == null and player.has_method("wallet"):
		score = player.wallet()
	if score == null and player.flow != null:
		score = player.flow.score
	if score == null or not score.try_spend(Buzz.PRICE):
		Sfx.play("ui_deny", self)
		return false
	player.buzz.take()
	Sfx.play("buy_beer", self)
	if visit == Visit.SERVING:
		if not tending:
			hop_out()
		_linger = 0.0
		_linger_limit = SALE_LINGER_SECONDS
		cheer(ENJOY)
	return true


func _physics_process(delta: float) -> void:
	_drive(delta)
	_animate(delta)


func _drive(delta: float) -> void:
	if visit == Visit.GONE:
		velocity = Vector3.ZERO
		return
	if visit == Visit.WAITING:
		_hold_still(delta)
		return
	if visit == Visit.SERVING:
		wait_out(delta)
	if visit == Visit.SERVING:
		if cooler_open:
			_plant(delta)
		else:
			_serve(delta)
		return
	if visit == Visit.LEAVING:
		_roll_away(delta)
		return
	_chase_player(delta)


func _hold_still(delta: float) -> void:
	drive_speed = 0.0
	velocity = Vector3.ZERO
	if _wheel != null:
		_wheel.turn(0.0, delta)


func _plant(delta: float) -> void:
	drive_speed = 0.0
	velocity = Vector3.ZERO
	if _wheel != null:
		_wheel.turn(0.0, delta)


func _serve(delta: float) -> void:
	var guest := _nearest_player()
	var to := Vector3.ZERO
	if guest != null:
		to = guest.global_position - global_position
		to.y = 0.0
	_roll(delta, to, 0.0, true)


func _chase_player(delta: float) -> void:
	var guest := _nearest_player()
	var to := Vector3.ZERO
	var distance := 999.0
	if guest != null:
		to = guest.global_position - global_position
		to.y = 0.0
		distance = to.length()
	var wanted := wanted_speed(distance) if guest != null else 0.0
	if guest != null and wanted <= 0.0:
		begin_service()
		_serve(delta)
		return
	_roll(delta, to, wanted, false)


func _roll_away(delta: float) -> void:
	var to := _leave_at - global_position
	to.y = 0.0
	if to.length() <= STOP_RANGE:
		vanish()
		return
	_roll(delta, to, CRUISE_SPEED, false)


func _roll(delta: float, to: Vector3, wanted: float, use_cooler: bool) -> void:
	var pull := ACCELERATION if wanted > 0.0 else COAST_DECAY
	drive_speed = move_toward(drive_speed, wanted, pull * delta)
	var desired := rotation.y
	if to.length_squared() > 0.0001:
		desired = cooler_yaw(to) if use_cooler else drive_yaw(to)
	var yaw_err := wrapf(desired - rotation.y, -PI, PI)
	# Player-cart steering is inverted for a stick. Do not reuse that here.
	rotation.y = lerp_angle(rotation.y, desired, clampf(delta * 3.2, 0.0, 1.0))
	var steer := 0.0 if use_cooler or wanted <= 0.0 else -clampf(
		yaw_err / deg_to_rad(35.0), -1.0, 1.0
	)
	if _wheel != null:
		_wheel.turn(steer, delta)
	var nose := nose_at(rotation.y)
	if is_on_floor():
		velocity = GolfCart.slope_velocity(nose, get_floor_normal(), drive_speed)
	else:
		velocity.x = nose.x * drive_speed
		velocity.z = nose.z * drive_speed
		velocity.y -= GolfCart.AIR_GRAVITY * delta
	move_and_slide()


func _animate(delta: float) -> void:
	_phase += delta
	if _lid != null:
		var wanted := deg_to_rad(LID_OPEN_DEG) if cooler_open else 0.0
		_lid.rotation.x = lerp_angle(_lid.rotation.x, wanted, clampf(LID_SPEED * delta, 0.0, 1.0))
	if _girl == null:
		return
	if tending:
		_wheel.show_hands(false)
		_tend_pose()
	elif _parked:
		_wheel.show_hands(false)
		_girl.sit(false)
		var wave := sin(_phase * 3.2) * 24.0
		_girl.arms[PlayerBody.FREE_ARM].rotation.x = deg_to_rad(42.0 + wave)
		_girl.arms[PlayerBody.FREE_ARM].rotation.z = deg_to_rad(-14.0)
		_girl.torso.rotation.y = deg_to_rad(sin(_phase * 1.6) * 12.0)
	else:
		_wheel.show_hands(true, GIRL_COLOR, PlayerBody.WORLD_LAYER)
		_girl.sit(true, _wheel.angle_deg(), _wheel.grip_positions())


func _tend_pose() -> void:
	_girl.pose(0.0)
	var sway := sin(_phase * 2.2) * 8.0
	var present := sin(_phase * 3.4) * 16.0
	var other := sin(_phase * 1.8 + 0.7) * 10.0
	_girl.hips.position.y = PlayerBody.HIP_HEIGHT + 0.02 + sin(_phase * 2.8) * 0.03
	_girl.hips.rotation.y = deg_to_rad(sin(_phase * 1.4) * 7.0)
	_girl.torso.rotation.y = deg_to_rad(sway)
	_girl.torso.rotation.x = deg_to_rad(-4.0 + sin(_phase * 2.1) * 3.5)
	_girl.arms[PlayerBody.FREE_ARM].rotation.x = deg_to_rad(54.0 + present)
	_girl.arms[PlayerBody.FREE_ARM].rotation.z = deg_to_rad(-22.0)
	_girl.arms[PlayerBody.GUN_ARM].rotation.x = deg_to_rad(18.0 + other)
	_girl.arms[PlayerBody.GUN_ARM].rotation.z = deg_to_rad(12.0)


func _nearest_player() -> Player:
	if not is_inside_tree():
		return null
	var best: Player
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player == null or not player.health.is_alive():
			continue
		var offset := player.global_position - global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist < best_dist:
			best = player
			best_dist = dist
	return best
