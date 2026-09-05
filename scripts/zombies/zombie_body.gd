class_name ZombieBody
extends Node3D
## Undead golfers. Walkers wear a Blender chassis (ripped polo, hanging jaw);
## the others stay primitive so a runner, brute and gunner still read apart.

enum Kind { WALKER, RUNNER, BRUTE, GUNNER, SNIPER }

const WALKER_MODEL := "res://assets/zombies/walker.glb"
const STRIDE_RATE := 6.2
const RUNNER_STRIDE_RATE := 10.4
const BRUTE_STRIDE_RATE := 4.1
const LEG_SWING_DEG := 26.0
const ARM_SWING_DEG := 16.0
const LIMP := 0.55
const BOUNCE := 0.045
const JAW_OPEN_DEG := 20.0
const JAW_WAG_DEG := 8.0
## Hand at the mouth. Positive pitch swings the arm forward/up; negative hid the can behind their back.
const DRINK_ARM_DEG := 128.0
const DRINK_HEAD_DEG := -32.0
const DRINK_JAW_EXTRA := 28.0
const DRINK_CAN_REST_DEG := 70.0
const DRINK_CAN_TIP_DEG := 128.0
const DRINK_RAISE := 0.22
const DRINK_LOWER := 0.78
const CHEER_TIME := 1.35

var kind := Kind.WALKER
var hunch_deg := 26.0
var club: Node3D
var bag: Node3D
var hips: Node3D
var torso: Node3D
var jaw: Node3D
var head: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var meshes: Array[MeshInstance3D] = []

var _height := 1.8
var _radius := 0.42
var _phase := 0.0
var _reach_deg := 58.0
var _drag_deg := 78.0
var _beer: Node3D
var _ally_cap: Node3D
var _melee_left := 0.0
var _club_rest_x := 0.0
var ragdoll := Ragdoll.new()
var _floor_lift := 0.0


func build(stats: ZombieStats) -> void:
	_clear()
	kind = kind_of(stats)
	_height = stats.height
	_radius = stats.radius
	_apply_kind()
	var trim := stats.body_color
	var shell := trim.darkened(0.62)
	if kind != Kind.WALKER or not _skin_walker(shell, trim):
		hips = Node3D.new()
		hips.position.y = _hip_height()
		add_child(hips)
		torso = Node3D.new()
		hips.add_child(torso)
		_build_torso(shell, trim)
		_build_head(shell, trim)
		for side: float in [-1.0, 1.0]:
			legs.append(_build_leg(side, shell, trim))
			arms.append(_build_arm(side, shell, trim))
	_build_kit(shell, trim)
	pose(0.0)


func animate(delta: float, pace: float) -> void:
	if ragdoll.is_active():
		return
	_phase = wrapf(_phase + clampf(pace, 0.0, 1.0) * _stride_rate() * delta, 0.0, TAU)
	pose(pace)


func pose(pace: float) -> void:
	var p := clampf(pace, 0.0, 1.0)
	hips.position.y = _hip_height() + absf(sin(_phase)) * BOUNCE * p * _scale()
	torso.rotation.x = deg_to_rad(hunch_deg)
	torso.rotation.y = 0.0
	if head != null:
		head.rotation.x = 0.0
	legs[0].rotation.x = deg_to_rad(leg_angle_deg(_phase, p, false))
	legs[1].rotation.x = deg_to_rad(leg_angle_deg(_phase + PI, p, true))
	if kind == Kind.SNIPER:
		arms[0].rotation.x = deg_to_rad(24.0)
		arms[0].rotation.z = 0.0
		arms[1].rotation.x = deg_to_rad(82.0)
		arms[1].rotation.z = deg_to_rad(-8.0)
	else:
		arms[0].rotation.x = deg_to_rad(
			_drag_deg + PlayerBody.limb_angle_deg(_phase + PI, p, ARM_SWING_DEG * LIMP)
		)
		arms[0].rotation.z = 0.0
		arms[1].rotation.x = deg_to_rad(
			_reach_deg + PlayerBody.limb_angle_deg(_phase, p, ARM_SWING_DEG)
		)
		arms[1].rotation.z = 0.0
	if jaw != null:
		jaw.rotation.x = deg_to_rad(JAW_OPEN_DEG + sin(_phase * 2.0) * JAW_WAG_DEG * p)


func start_melee() -> void:
	_melee_left = Melee.SWING_TIME


func is_meleeing() -> bool:
	return _melee_left > 0.0


func melee_progress() -> float:
	if _melee_left <= 0.0:
		return 1.0
	return 1.0 - _melee_left / Melee.SWING_TIME


func is_limp() -> bool:
	return ragdoll.is_active()


func flop(
	region: Ragdoll.Region, direction: Vector3, strength: float, locked := false,
	planted := false
) -> void:
	_melee_left = 0.0
	ragdoll.configure_hips(_hip_height(), _hip_height() * Ragdoll.HIP_DROP)
	ragdoll.flop(_limp_parts(), region, direction, strength, locked, planted)


func tick_limp(delta: float, airborne: bool) -> void:
	position.y -= _floor_lift
	_floor_lift = 0.0
	var still := ragdoll.tick(delta, _limp_parts(), airborne)
	if airborne:
		_pin_to_floor()
	else:
		position.y = 0.0
	if still:
		return
	position = Vector3.ZERO
	pose(0.0)


func stop_limp() -> void:
	ragdoll.stop()
	_floor_lift = 0.0
	position = Vector3.ZERO
	if hips != null:
		pose(0.0)


## Club-hand chop. Walkers and brutes drag the iron on the left, so that is the
## arm that has to come through; runners and gunners swipe with the reach arm.
func tick_melee(delta: float) -> void:
	if ragdoll.is_active() or _melee_left <= 0.0:
		return
	_melee_left = maxf(0.0, _melee_left - delta)
	var progress := melee_progress()
	var weight := Melee.swing_weight(progress)
	var swing := _swing_arm_index()
	var other := 1 - swing
	var club_pose := club_arm_deg(progress)
	var off_pose := off_arm_deg(progress)
	arms[swing].rotation.x = lerp_angle(arms[swing].rotation.x, deg_to_rad(club_pose.x), weight)
	arms[swing].rotation.z = lerp_angle(arms[swing].rotation.z, deg_to_rad(club_pose.y), weight)
	arms[other].rotation.x = lerp_angle(arms[other].rotation.x, deg_to_rad(off_pose.x), weight)
	arms[other].rotation.z = lerp_angle(arms[other].rotation.z, deg_to_rad(off_pose.y), weight)
	torso.rotation.y = lerp_angle(torso.rotation.y, deg_to_rad(club_twist_deg(progress)), weight)
	if club != null:
		club.rotation.x = lerp_angle(_club_rest_x, deg_to_rad(club_grip_deg(progress)), weight)


func hold_beer(can: Node3D) -> void:
	drop_beer()
	if can == null or arms.is_empty():
		return
	_beer = can
	arms[1].add_child(can)
	_place_can(0.0)
	if club != null and club.get_parent() == arms[1]:
		club.visible = false


func drop_beer() -> void:
	if _beer != null and is_instance_valid(_beer):
		_beer.queue_free()
	_beer = null
	if club != null:
		club.visible = true


func drink(progress: float) -> void:
	pose(0.0)
	var lift := drink_lift(progress)
	arms[1].rotation.x = deg_to_rad(lerpf(_reach_deg, DRINK_ARM_DEG, lift))
	torso.rotation.x = deg_to_rad(hunch_deg - 12.0 * lift)
	if head != null:
		head.rotation.x = deg_to_rad(DRINK_HEAD_DEG * lift)
	if jaw != null:
		jaw.rotation.x = deg_to_rad(JAW_OPEN_DEG + DRINK_JAW_EXTRA * lift)
	_place_can(lift)


static func drink_lift(progress: float) -> float:
	var t := clampf(progress, 0.0, 1.0)
	if t < DRINK_RAISE:
		return t / DRINK_RAISE
	if t > DRINK_LOWER:
		return 1.0 - (t - DRINK_LOWER) / (1.0 - DRINK_LOWER)
	return 1.0


func cheer(text: String) -> void:
	var old := get_node_or_null("Cheer")
	if old != null:
		old.queue_free()
	var copy := Label3D.new()
	copy.name = "Cheer"
	copy.text = text
	copy.font_size = 42
	copy.pixel_size = 0.014
	copy.modulate = Palette.BEER_INK
	copy.outline_size = 10
	copy.outline_modulate = Palette.NIGHT
	copy.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	copy.position = Vector3(0.0, _height + 0.28, 0.0)
	add_child(copy)
	var timer := Timer.new()
	timer.wait_time = CHEER_TIME
	timer.one_shot = true
	timer.timeout.connect(copy.queue_free)
	copy.add_child(timer)
	timer.start()


func wear_ally_cap() -> void:
	if head == null or _ally_cap != null:
		return
	var s := _scale()
	_ally_cap = Node3D.new()
	head.add_child(_ally_cap)
	var crown := MeshFactory.box(
		Vector3(_radius * 1.32, 0.09 * s, _radius * 1.28), Palette.ALLY_CAP, Palette.GLOW_STRONG
	)
	crown.position.y = 0.34 * s
	_add(crown, _ally_cap)
	var brim := MeshFactory.box(
		Vector3(_radius * 0.95, 0.035 * s, 0.2 * s), Palette.ALLY_CAP, Palette.GLOW_STRONG
	)
	brim.position = Vector3(0.0, 0.31 * s, _radius * 0.78)
	_add(brim, _ally_cap)


func set_flash(material: Material) -> void:
	for mesh in meshes:
		mesh.material_overlay = material


func chest_width() -> float:
	return _chest_size().x


func _place_can(lift: float) -> void:
	if _beer == null or not is_instance_valid(_beer):
		return
	var s := _scale()
	_beer.position = Vector3(0.05 * s, -0.62 * s, -0.1 * s)
	_beer.rotation.x = deg_to_rad(lerpf(DRINK_CAN_REST_DEG, DRINK_CAN_TIP_DEG, lift))


static func kind_of(stats: ZombieStats) -> Kind:
	match stats.display_name:
		"Runner":
			return Kind.RUNNER
		"Brute":
			return Kind.BRUTE
		"Gunner":
			return Kind.GUNNER
		"Sniper":
			return Kind.SNIPER
		_:
			return Kind.WALKER


## Pitch and roll of the club arm. Back and out, then a snap through the target.
static func club_arm_deg(progress: float) -> Vector2:
	var pose := Melee.swing_arc(
		progress, Vector3(-48.0, -42.0, 0.0), Vector3(118.0, 22.0, 0.0), Vector3(52.0, -8.0, 0.0)
	)
	return Vector2(pose.x, pose.y)


static func off_arm_deg(progress: float) -> Vector2:
	var pose := Melee.swing_arc(
		progress, Vector3(28.0, 16.0, 0.0), Vector3(72.0, -14.0, 0.0), Vector3(44.0, 0.0, 0.0)
	)
	return Vector2(pose.x, pose.y)


static func club_twist_deg(progress: float) -> float:
	return Melee.swing_arc(
		progress, Vector3(22.0, 0.0, 0.0), Vector3(-28.0, 0.0, 0.0), Vector3(-10.0, 0.0, 0.0)
	).x


## Extra cock on the iron so the head actually sweeps instead of hanging limp.
static func club_grip_deg(progress: float) -> float:
	return Melee.swing_arc(
		progress, Vector3(58.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), Vector3(18.0, 0.0, 0.0)
	).x


## The dragging leg never takes a full step. That limp is what makes the shamble
## read as undead instead of a robot run played backwards.
static func leg_angle_deg(phase: float, pace: float, healthy: bool) -> float:
	var swing := LEG_SWING_DEG if healthy else LEG_SWING_DEG * LIMP
	return PlayerBody.limb_angle_deg(phase, pace, swing)


func _apply_kind() -> void:
	match kind:
		Kind.RUNNER:
			hunch_deg = 40.0
			_reach_deg = 88.0
			_drag_deg = 74.0
		Kind.BRUTE:
			hunch_deg = 12.0
			_reach_deg = 32.0
			_drag_deg = 50.0
		Kind.GUNNER:
			hunch_deg = 8.0
			_reach_deg = 44.0
			_drag_deg = 36.0
		Kind.SNIPER:
			hunch_deg = 4.0
			_reach_deg = 18.0
			_drag_deg = 22.0
		Kind.WALKER:
			hunch_deg = 26.0
			_reach_deg = 58.0
			_drag_deg = 78.0


func _build_torso(shell: Color, trim: Color) -> void:
	var size := _chest_size()
	var chest := MeshFactory.box(size, shell)
	chest.position.y = size.y * 0.5
	_add(chest, torso)
	var ribs := MeshFactory.box(
		Vector3(size.x * 0.55, size.y * 0.08, size.z * 1.08), trim, Palette.GLOW_MEDIUM
	)
	ribs.position.y = size.y * 0.55
	_add(ribs, torso)
	var collar := MeshFactory.box(
		Vector3(size.x * 0.42, 0.07 * _scale(), size.z * 0.7), shell.lightened(0.08)
	)
	collar.position.y = size.y + 0.02 * _scale()
	_add(collar, torso)
	match kind:
		Kind.RUNNER:
			for side: float in [-1.0, 1.0]:
				var stripe := MeshFactory.box(
					Vector3(0.05 * _scale(), size.y * 0.72, size.z * 1.04), trim, Palette.GLOW_SOFT
				)
				stripe.position = Vector3(side * size.x * 0.38, size.y * 0.5, 0.0)
				_add(stripe, torso)
		Kind.BRUTE:
			var plate := MeshFactory.box(
				Vector3(size.x * 0.48, size.y * 0.32, 0.06 * _scale()), trim, Palette.GLOW_STRONG
			)
			plate.position = Vector3(0.0, size.y * 0.52, -size.z * 0.52)
			_add(plate, torso)
		Kind.GUNNER:
			var band := MeshFactory.box(
				Vector3(size.x * 1.06, size.y * 0.18, size.z * 1.08), trim, Palette.GLOW_MEDIUM
			)
			band.position.y = size.y * 0.62
			_add(band, torso)
		Kind.SNIPER:
			var sash := MeshFactory.box(
				Vector3(size.x * 1.08, size.y * 0.12, size.z * 1.1), trim, Palette.GLOW_STRONG
			)
			sash.position.y = size.y * 0.7
			_add(sash, torso)
		Kind.WALKER:
			var placket := MeshFactory.box(
				Vector3(0.055 * _scale(), size.y * 0.48, 0.04 * _scale()), trim, Palette.GLOW_SOFT
			)
			placket.position = Vector3(0.0, size.y * 0.45, -size.z * 0.52)
			_add(placket, torso)


func _build_head(shell: Color, trim: Color) -> void:
	var s := _scale()
	var head_node := Node3D.new()
	head_node.position.y = _chest_size().y + 0.08 * s
	torso.add_child(head_node)
	head = head_node
	var skull := MeshFactory.box(Vector3(_radius * 1.15, 0.28 * s, _radius * 1.1), shell)
	skull.position.y = 0.16 * s
	_add(skull, head)
	for side: float in [-1.0, 1.0]:
		var eye := MeshFactory.box(Vector3(0.07, 0.045, 0.04) * s, trim, Palette.GLOW_STRONG)
		eye.position = Vector3(side * _radius * 0.28, 0.18 * s, -_radius * 0.52)
		_add(eye, head)
	jaw = Node3D.new()
	jaw.position.y = 0.02 * s
	head.add_child(jaw)
	var chin := MeshFactory.box(Vector3(_radius * 0.7, 0.08 * s, _radius * 0.7), shell)
	chin.position = Vector3(0.0, 0.0, -_radius * 0.12)
	_add(chin, jaw)
	if kind == Kind.BRUTE:
		var beanie := MeshFactory.sphere(_radius * 0.55, trim.darkened(0.3), Palette.GLOW_FAINT)
		beanie.position.y = 0.34 * s
		_add(beanie, head)
		return
	if kind == Kind.SNIPER:
		var hood := MeshFactory.box(
			Vector3(_radius * 1.28, 0.16 * s, _radius * 1.22), trim.darkened(0.35), Palette.GLOW_SOFT
		)
		hood.position.y = 0.3 * s
		_add(hood, head)
		var visor := MeshFactory.box(
			Vector3(_radius * 0.85, 0.05 * s, 0.06 * s), trim, Palette.GLOW_STRONG
		)
		visor.position = Vector3(0.0, 0.2 * s, -_radius * 0.55)
		_add(visor, head)
		return
	var cap := MeshFactory.box(Vector3(_radius * 1.25, 0.07 * s, _radius * 1.2), trim.darkened(0.4))
	cap.position.y = 0.32 * s
	_add(cap, head)
	var brim := MeshFactory.box(Vector3(_radius * 0.9, 0.03 * s, 0.18 * s), trim, Palette.GLOW_MEDIUM)
	var brim_z := _radius * 0.72 if kind == Kind.RUNNER else -_radius * 0.72
	brim.position = Vector3(0.0, 0.30 * s, brim_z)
	_add(brim, head)


func _build_leg(side: float, shell: Color, trim: Color) -> Node3D:
	var s := _scale()
	var thick := _limb_thick()
	var pivot := Node3D.new()
	pivot.position = Vector3(side * _radius * 0.55, 0.0, 0.0)
	hips.add_child(pivot)
	var thigh := MeshFactory.box(Vector3(0.14, 0.38, 0.14) * s * thick, shell)
	thigh.position.y = -0.22 * s
	_add(thigh, pivot)
	var shin := MeshFactory.box(Vector3(0.12, 0.34, 0.12) * s * thick, shell)
	shin.position.y = -0.54 * s
	_add(shin, pivot)
	var foot := MeshFactory.box(Vector3(0.16, 0.09, 0.28) * s * thick, trim, Palette.GLOW_SOFT)
	foot.position = Vector3(0.0, -0.74 * s, -0.06 * s)
	_add(foot, pivot)
	return pivot


func _build_arm(side: float, shell: Color, trim: Color) -> Node3D:
	var s := _scale()
	var thick := _limb_thick()
	var pivot := Node3D.new()
	pivot.position = Vector3(side * _shoulder_spread(), _chest_size().y * 0.82, 0.04 * s)
	torso.add_child(pivot)
	var joint := MeshFactory.box(Vector3(0.13, 0.13, 0.13) * s * thick, trim, Palette.GLOW_SOFT)
	_add(joint, pivot)
	var upper := MeshFactory.box(Vector3(0.11, 0.3, 0.11) * s * thick, shell)
	upper.position.y = -0.18 * s
	_add(upper, pivot)
	var lower := MeshFactory.box(Vector3(0.1, 0.28, 0.1) * s * thick, shell)
	lower.position.y = -0.46 * s
	_add(lower, pivot)
	var hand := MeshFactory.box(Vector3(0.11, 0.1, 0.12) * s * thick, trim, Palette.GLOW_SOFT)
	hand.position.y = -0.64 * s
	_add(hand, pivot)
	return pivot


func _build_kit(shell: Color, trim: Color) -> void:
	if kind == Kind.GUNNER:
		club = _build_cannon(arms[1], trim)
		return
	if kind == Kind.SNIPER:
		club = _build_long_rifle(arms[1], trim)
		return
	if kind != Kind.RUNNER and club == null:
		club = _build_club(arms[0], trim)
	if kind == Kind.BRUTE:
		bag = _build_bag(shell, trim)


func _build_cannon(arm: Node3D, trim: Color) -> Node3D:
	var s := _scale()
	var grip := Node3D.new()
	grip.position.y = -0.64 * s
	grip.rotation.x = deg_to_rad(-8.0)
	_club_rest_x = grip.rotation.x
	arm.add_child(grip)
	var stock := MeshFactory.box(Vector3(0.1, 0.1, 0.22) * s, trim.darkened(0.35), Palette.GLOW_FAINT)
	stock.position.z = 0.08 * s
	_add(stock, grip)
	var barrel := MeshFactory.cylinder(0.045 * s, 0.55 * s, trim, Palette.GLOW_STRONG)
	barrel.rotation.x = deg_to_rad(90.0)
	barrel.position.z = -0.28 * s
	_add(barrel, grip)
	var muzzle := MeshFactory.sphere(0.055 * s, Palette.AMBER, Palette.GLOW_STRONG)
	muzzle.position.z = -0.56 * s
	_add(muzzle, grip)
	return grip


func _build_long_rifle(arm: Node3D, trim: Color) -> Node3D:
	var s := _scale()
	var grip := Node3D.new()
	grip.position.y = -0.64 * s
	grip.rotation.x = deg_to_rad(-70.0)
	_club_rest_x = grip.rotation.x
	arm.add_child(grip)
	var stock := MeshFactory.box(Vector3(0.08, 0.08, 0.2) * s, trim.darkened(0.4), Palette.GLOW_FAINT)
	stock.position.z = 0.1 * s
	_add(stock, grip)
	var barrel := MeshFactory.cylinder(0.028 * s, 0.9 * s, trim, Palette.GLOW_STRONG)
	barrel.rotation.x = deg_to_rad(90.0)
	barrel.position.z = -0.42 * s
	_add(barrel, grip)
	var scope := MeshFactory.cylinder(0.035 * s, 0.16 * s, Palette.ICE, Palette.GLOW_MEDIUM)
	scope.rotation.x = deg_to_rad(90.0)
	scope.position = Vector3(0.0, 0.05 * s, -0.12 * s)
	_add(scope, grip)
	var muzzle := MeshFactory.sphere(0.04 * s, Palette.ICE, Palette.GLOW_STRONG)
	muzzle.position.z = -0.88 * s
	_add(muzzle, grip)
	return grip


func _build_club(arm: Node3D, trim: Color) -> Node3D:
	var s := _scale()
	var grip := Node3D.new()
	grip.position.y = -0.64 * s
	grip.rotation.x = deg_to_rad(22.0)
	_club_rest_x = grip.rotation.x
	arm.add_child(grip)
	var shaft := MeshFactory.cylinder(0.022 * s, 0.82 * s, Palette.ICE, Palette.GLOW_FAINT)
	shaft.position.y = -0.4 * s
	_add(shaft, grip)
	var iron := MeshFactory.box(Vector3(0.07, 0.05, 0.2) * s, trim, Palette.GLOW_MEDIUM)
	iron.position = Vector3(0.0, -0.82 * s, -0.05 * s)
	_add(iron, grip)
	return grip


func _build_bag(shell: Color, trim: Color) -> Node3D:
	var s := _scale()
	var root := Node3D.new()
	root.position = Vector3(0.1 * s, _chest_size().y * 0.2, _radius * 0.85)
	root.rotation.x = deg_to_rad(16.0)
	torso.add_child(root)
	var sack := MeshFactory.cylinder(_radius * 0.36, _height * 0.42, shell.darkened(0.12), Palette.GLOW_FAINT)
	_add(sack, root)
	for i in 3:
		var stick := MeshFactory.cylinder(0.016 * s, 0.32 * s, Palette.ICE, Palette.GLOW_SOFT)
		stick.position = Vector3((i - 1) * 0.05 * s, _height * 0.24, 0.0)
		_add(stick, root)
	var strap := MeshFactory.box(Vector3(0.05, 0.42, 0.04) * s, trim, Palette.GLOW_SOFT)
	strap.position = Vector3(-_radius * 0.55, _chest_size().y * 0.45, 0.0)
	_add(strap, torso)
	return root


func _skin_walker(shell: Color, trim: Color) -> bool:
	var packed := load(WALKER_MODEL) as PackedScene
	if packed == null:
		return false
	var model: Node = packed.instantiate()
	add_child(model)
	var root := model.find_child("WalkerRoot", true, false) as Node3D
	if root == null and model.name == "WalkerRoot":
		root = model as Node3D
	if root == null:
		model.free()
		return false
	_build_pivots()
	root.position = Vector3.ZERO
	root.rotation.y = PI
	_steal(_part(root, "Hips"), hips, ["Torso", "LLeg", "RLeg"])
	_steal(_part(root, "Torso"), torso, ["Head", "LArm", "RArm"])
	_steal(_part(root, "Head"), head, ["Jaw"])
	_steal(_part(root, "Jaw"), jaw)
	_steal(_part(root, "RLeg"), legs[0])
	_steal(_part(root, "LLeg"), legs[1])
	_steal(_part(root, "RArm"), arms[0], ["Club"])
	_steal(_part(root, "LArm"), arms[1])
	club = Node3D.new()
	club.position.y = -0.64 * _scale()
	club.rotation.x = deg_to_rad(22.0)
	_club_rest_x = club.rotation.x
	arms[0].add_child(club)
	_steal(_part(root, "Club"), club)
	model.free()
	_paint_walker(shell, trim)
	for node in find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	return true


func _build_pivots() -> void:
	var s := _scale()
	hips = Node3D.new()
	hips.position.y = _hip_height()
	add_child(hips)
	torso = Node3D.new()
	hips.add_child(torso)
	head = Node3D.new()
	head.position.y = _chest_size().y + 0.08 * s
	torso.add_child(head)
	jaw = Node3D.new()
	jaw.position.y = 0.02 * s
	head.add_child(jaw)
	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * _radius * 0.55, 0.0, 0.0)
		hips.add_child(leg)
		legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(side * _shoulder_spread(), _chest_size().y * 0.82, 0.04 * s)
		torso.add_child(arm)
		arms.append(arm)


func _part(from: Node, node_name: String) -> Node3D:
	return from.find_child(node_name, true, false) as Node3D


func _steal(from: Node, to: Node3D, skip: Array[String] = []) -> void:
	if from == null or to == null:
		return
	var kids: Array[Node] = []
	kids.assign(from.get_children())
	for child in kids:
		if skip.has(child.name):
			continue
		var node := child as Node3D
		if node == null:
			continue
		var xf := node.global_transform
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.owner = null
		to.add_child(node)
		node.global_transform = xf


func _paint_walker(shell: Color, trim: Color) -> void:
	var looks := {
		"WalkerShell": MeshFactory.material(shell),
		"WalkerTrim": MeshFactory.material(trim, false, Palette.GLOW_MEDIUM),
		"WalkerGlow": MeshFactory.material(trim, false, Palette.GLOW_STRONG),
		"WalkerFrame": MeshFactory.material(Palette.NIGHT.lightened(0.14)),
		"WalkerBone": MeshFactory.material(Color(0.58, 0.64, 0.48)),
		"WalkerRust": MeshFactory.material(Color(0.28, 0.14, 0.06)),
		"WalkerEye": MeshFactory.material(trim, false, Palette.GLOW_STRONG),
		"WalkerDead": MeshFactory.material(Palette.LED_RED, false, Palette.GLOW_SOFT),
	}
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var src := mesh.get_active_material(0)
		if src == null:
			continue
		var key := src.resource_name
		if key.is_empty():
			key = src.get_name()
		var painted: Material = looks.get(key)
		if painted != null:
			mesh.material_override = painted


func _add(mesh: MeshInstance3D, parent: Node3D) -> void:
	parent.add_child(mesh)
	meshes.append(mesh)


func _limp_parts() -> Dictionary:
	var parts := {
		&"hips": hips,
		&"torso": torso,
		&"head": head,
	}
	if legs.size() >= 2:
		parts[&"leg_l"] = legs[0]
		parts[&"leg_r"] = legs[1]
	if arms.size() >= 2:
		parts[&"arm_l"] = arms[0]
		parts[&"arm_r"] = arms[1]
	return parts


func _pin_to_floor() -> void:
	var host := get_parent() as Node3D
	var floor_y := Ragdoll.FLOOR_CLEARANCE
	if host != null:
		floor_y = host.global_position.y + Ragdoll.FLOOR_CLEARANCE
	_floor_lift = Ragdoll.floor_lift(meshes, floor_y)
	position.y += _floor_lift


func _clear() -> void:
	ragdoll.stop()
	_floor_lift = 0.0
	position = Vector3.ZERO
	for child in get_children():
		remove_child(child)
		child.free()
	club = null
	bag = null
	hips = null
	torso = null
	jaw = null
	head = null
	_beer = null
	_ally_cap = null
	_melee_left = 0.0
	_club_rest_x = 0.0
	legs.clear()
	arms.clear()
	meshes.clear()
	_phase = 0.0


func _stride_rate() -> float:
	match kind:
		Kind.RUNNER:
			return RUNNER_STRIDE_RATE
		Kind.BRUTE:
			return BRUTE_STRIDE_RATE
		_:
			return STRIDE_RATE


func _swing_arm_index() -> int:
	if arms.size() < 2:
		return 0
	if club != null and is_instance_valid(club) and club.get_parent() == arms[0]:
		return 0
	return 1


func _scale() -> float:
	return _height / 1.8


func _hip_height() -> float:
	return _height * 0.5


func _limb_thick() -> float:
	match kind:
		Kind.RUNNER:
			return 0.82
		Kind.BRUTE:
			return 1.4
		Kind.GUNNER:
			return 0.95
		_:
			return 1.0


func _shoulder_spread() -> float:
	var spread := _radius * 1.15
	if kind == Kind.BRUTE:
		return spread * 1.2
	if kind == Kind.RUNNER:
		return spread * 0.9
	return spread


func _chest_size() -> Vector3:
	var size := Vector3(_radius * 1.75, _height * 0.32, _radius * 1.15)
	match kind:
		Kind.RUNNER:
			return Vector3(size.x * 0.78, size.y * 0.9, size.z * 0.85)
		Kind.BRUTE:
			return Vector3(size.x * 1.32, size.y * 1.12, size.z * 1.18)
		Kind.GUNNER:
			return Vector3(size.x * 0.92, size.y * 1.04, size.z * 0.95)
		Kind.SNIPER:
			return Vector3(size.x * 0.88, size.y * 1.06, size.z * 0.9)
		_:
			return size
