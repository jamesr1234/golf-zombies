class_name PlayerBody
extends Node3D
## The robot each player walks around in, built from primitives and animated by a
## single stride phase. Everything is driven by pace (0 standing, 1 sprinting), so a
## standing robot sits in a neutral pose and the run fades in and out smoothly
## instead of snapping between an idle and a run clip.

const Wear := preload("res://scripts/player/apparel.gd")

const HIP_HEIGHT := 0.92
const SHOULDER_HEIGHT := 0.5
const HIP_SPREAD := 0.15
const SHOULDER_SPREAD := 0.31
const ARM_LENGTH := 0.65

## Radians of stride phase per second at a full sprint.
const STRIDE_RATE := 9.0
const LEG_SWING_DEG := 38.0
const ARM_SWING_DEG := 26.0
const BOUNCE := 0.05
const LEAN_DEG := 9.0
## The arm holding the raygun stays up and tucked in towards the gun, with only a
## trace of the stride left in it.
const GUN_ARM_REST_DEG := 68.0
const GUN_ARM_TUCK_DEG := 18.0
const GUN_ARM_SWING := 0.3
const SIT_HIP_HEIGHT := 0.22
const SIT_RECLINE_DEG := 28.0
const SIT_LEG_DEG := 72.0
const SIT_ARM_DEG := 78.0
const SIT_ARM_SPREAD_DEG := 8.0
const SWIM_LEAN_DEG := 52.0
const SURFACE_LEAN_DEG := 16.0
const SWIM_KICK_DEG := 28.0
const SWIM_STROKE_DEG := 32.0
const CHEER_TIME := 1.8
const CHEER_ARM_DEG := 158.0
const CHEER_SPREAD_DEG := 38.0
const CHEER_HOP := 0.2
const CHEER_TWIST_DEG := 24.0

const FREE_ARM := 0
const GUN_ARM := 1
## Cabin (chest, head, legs) moves onto this layer while driving so that player's
## camera can skip it. Arms stay on WORLD_LAYER. P1 and P2 use different bits so
## the passenger still sees the driver's whole robot.
const WORLD_LAYER := 1
const CABIN_P1 := 1 << 2
const CABIN_P2 := 1 << 3

var hips: Node3D
var torso: Node3D
var head: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var cabin: Array[MeshInstance3D] = []
var arm_hands: Array[MeshInstance3D] = []

var _phase := 0.0
var _cabin_hidden := false
var _melee_left := 0.0
var ragdoll := Ragdoll.new()
var _floor_lift := 0.0
var worn := {"shirt": "", "bottom": "", "headband": ""}
var _shirts: Array[MeshInstance3D] = []
var _headbands: Array[MeshInstance3D] = []
var _bottoms: Array[MeshInstance3D] = []
var _preview_id := ""
var _preview_slot := ""


func build(color: Color) -> void:
	var shell := color.darkened(0.62)
	hips = Node3D.new()
	hips.position.y = HIP_HEIGHT
	add_child(hips)
	torso = Node3D.new()
	hips.add_child(torso)
	_build_torso(shell, color)
	for side: float in [-1.0, 1.0]:
		legs.append(_build_leg(side, shell, color))
		arms.append(_build_arm(side, shell, color))
	arms[GUN_ARM].rotation.z = deg_to_rad(GUN_ARM_TUCK_DEG)
	pose(0.0)


## Moves the stride on and re-poses the robot. Pace is the fraction of a sprint the
## player is actually travelling at.
func animate(delta: float, pace: float) -> void:
	if ragdoll.is_active():
		return
	_phase = wrapf(_phase + clampf(pace, 0.0, 1.0) * STRIDE_RATE * delta, 0.0, TAU)
	pose(pace)


func start_melee() -> void:
	_melee_left = Melee.SWING_TIME


func is_meleeing() -> bool:
	return _melee_left > 0.0


func is_limp() -> bool:
	return ragdoll.is_active()


func is_locked_limp() -> bool:
	return ragdoll.is_locked()


func flop(
	region: Ragdoll.Region, direction: Vector3, strength: float, locked := false,
	planted := false
) -> void:
	_melee_left = 0.0
	ragdoll.configure_hips(HIP_HEIGHT, HIP_HEIGHT * Ragdoll.HIP_DROP)
	ragdoll.flop(_limp_parts(), region, direction, strength, locked, planted)


func tick_limp(delta: float, airborne: bool) -> void:
	position.y -= _floor_lift
	_floor_lift = 0.0
	var still := ragdoll.tick(delta, _limp_parts(), airborne)
	_pin_to_floor()
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


## Overlays the club-swing on top of whatever pose was just applied, so a punch
## can interrupt a run or a passenger seat without replacing those poses.
func tick_melee(delta: float) -> void:
	if ragdoll.is_active() or _melee_left <= 0.0:
		return
	_melee_left = maxf(0.0, _melee_left - delta)
	var progress := 1.0 - _melee_left / Melee.SWING_TIME
	var weight := Melee.swing_weight(progress)
	var free := melee_free_arm_deg(progress)
	var gun := melee_gun_arm_deg(progress)
	arms[FREE_ARM].rotation.x = lerp_angle(arms[FREE_ARM].rotation.x, deg_to_rad(free.x), weight)
	arms[FREE_ARM].rotation.z = lerp_angle(arms[FREE_ARM].rotation.z, deg_to_rad(free.y), weight)
	arms[GUN_ARM].rotation.x = lerp_angle(arms[GUN_ARM].rotation.x, deg_to_rad(gun.x), weight)
	arms[GUN_ARM].rotation.z = lerp_angle(arms[GUN_ARM].rotation.z, deg_to_rad(gun.y), weight)
	torso.rotation.y = lerp_angle(torso.rotation.y, deg_to_rad(melee_twist_deg(progress)), weight)


func pose(pace: float) -> void:
	hips.position.y = HIP_HEIGHT + bounce_height(_phase, pace)
	torso.rotation.x = deg_to_rad(-LEAN_DEG * clampf(pace, 0.0, 1.0))
	torso.rotation.y = 0.0
	if head != null:
		head.rotation = Vector3.ZERO
	legs[0].rotation.x = deg_to_rad(limb_angle_deg(_phase, pace, LEG_SWING_DEG))
	legs[1].rotation.x = deg_to_rad(limb_angle_deg(_phase + PI, pace, LEG_SWING_DEG))
	arms[FREE_ARM].rotation.x = deg_to_rad(limb_angle_deg(_phase + PI, pace, ARM_SWING_DEG))
	arms[FREE_ARM].rotation.z = 0.0
	arms[GUN_ARM].rotation.x = deg_to_rad(
		GUN_ARM_REST_DEG + limb_angle_deg(_phase, pace, ARM_SWING_DEG * GUN_ARM_SWING)
	)
	arms[GUN_ARM].rotation.z = deg_to_rad(GUN_ARM_TUCK_DEG)
	_show_arm_hands(true)


## Arms up, hopping, a little twist. Solo hole-out so you can actually see it.
func cheer(delta: float, left: float) -> void:
	var pump := 1.0 - clampf(left / CHEER_TIME, 0.0, 1.0)
	_phase = wrapf(_phase + STRIDE_RATE * 1.35 * delta, 0.0, TAU)
	var hop := absf(sin(_phase * 2.0)) * CHEER_HOP
	hips.position.y = HIP_HEIGHT + hop
	torso.rotation.x = deg_to_rad(-8.0)
	torso.rotation.y = deg_to_rad(sin(_phase) * CHEER_TWIST_DEG)
	if head != null:
		head.rotation.x = deg_to_rad(-12.0)
		head.rotation.y = 0.0
	legs[0].rotation.x = deg_to_rad(-8.0 + hop * 40.0)
	legs[1].rotation.x = deg_to_rad(-8.0 + hop * 40.0)
	var raise := CHEER_ARM_DEG + sin(_phase * 2.0) * 16.0 * (0.35 + pump)
	arms[FREE_ARM].rotation.x = deg_to_rad(raise)
	arms[FREE_ARM].rotation.z = deg_to_rad(-CHEER_SPREAD_DEG)
	arms[GUN_ARM].rotation.x = deg_to_rad(raise)
	arms[GUN_ARM].rotation.z = deg_to_rad(CHEER_SPREAD_DEG)
	_show_arm_hands(true)


## Planted behind the shield: feet still, both arms up on the panel.
func guard() -> void:
	pose(0.0)
	arms[FREE_ARM].rotation.x = deg_to_rad(78.0)
	arms[FREE_ARM].rotation.z = deg_to_rad(-12.0)
	arms[GUN_ARM].rotation.x = deg_to_rad(78.0)
	arms[GUN_ARM].rotation.z = deg_to_rad(12.0)
	torso.rotation.x = deg_to_rad(6.0)


## Flutter-kick while treading, and a longer reach once the head goes under.
func swim(delta: float, pace: float, underwater: bool) -> void:
	var kick := clampf(maxf(pace, 0.35), 0.0, 1.0)
	_phase = wrapf(_phase + kick * STRIDE_RATE * 0.72 * delta, 0.0, TAU)
	hips.position.y = HIP_HEIGHT
	torso.rotation.x = deg_to_rad(-(SWIM_LEAN_DEG if underwater else SURFACE_LEAN_DEG))
	torso.rotation.y = 0.0
	legs[0].rotation.x = deg_to_rad(limb_angle_deg(_phase, kick, SWIM_KICK_DEG))
	legs[1].rotation.x = deg_to_rad(limb_angle_deg(_phase + PI, kick, SWIM_KICK_DEG))
	var stroke := SWIM_STROKE_DEG if underwater else ARM_SWING_DEG
	arms[FREE_ARM].rotation.x = deg_to_rad(limb_angle_deg(_phase + PI, kick, stroke) + 18.0)
	arms[FREE_ARM].rotation.z = 0.0
	arms[GUN_ARM].rotation.x = deg_to_rad(limb_angle_deg(_phase, kick, stroke) + 18.0)
	arms[GUN_ARM].rotation.z = 0.0
	_show_arm_hands(true)


## Reach for holds. A free hand points at the aimed spot until L1 or R1 plants it.
func climb(left_to: Vector3, right_to: Vector3, _aim: Vector3, _left_on: bool, _right_on: bool) -> void:
	hips.position.y = HIP_HEIGHT
	torso.rotation.x = deg_to_rad(-8.0)
	torso.rotation.y = 0.0
	legs[0].rotation.x = deg_to_rad(18.0)
	legs[1].rotation.x = deg_to_rad(-8.0)
	_climb_arm(arms[FREE_ARM], left_to)
	_climb_arm(arms[GUN_ARM], right_to)
	_show_arm_hands(true)


## Folded into a cart seat. The driver reaches for the wheel; shotgun keeps the
## gun arm up. Goofy on purpose: the legs stick out and the chest leans back.
func sit(driving: bool, wheel_deg := 0.0, grips: Array[Vector3] = []) -> void:
	hips.position.y = SIT_HIP_HEIGHT
	torso.rotation.x = deg_to_rad(SIT_RECLINE_DEG)
	torso.rotation.y = 0.0
	legs[0].rotation.x = deg_to_rad(SIT_LEG_DEG)
	legs[1].rotation.x = deg_to_rad(SIT_LEG_DEG)
	if driving:
		if grips.size() >= 2:
			_reach(arms[FREE_ARM], grips[0])
			_reach(arms[GUN_ARM], grips[1])
		else:
			var follow := wheel_deg * 0.18
			arms[FREE_ARM].rotation.x = deg_to_rad(SIT_ARM_DEG - follow)
			arms[GUN_ARM].rotation.x = deg_to_rad(SIT_ARM_DEG + follow)
			arms[FREE_ARM].rotation.z = deg_to_rad(-SIT_ARM_SPREAD_DEG)
			arms[GUN_ARM].rotation.z = deg_to_rad(SIT_ARM_SPREAD_DEG)
	else:
		arms[FREE_ARM].rotation.x = deg_to_rad(12.0)
		arms[FREE_ARM].rotation.z = 0.0
		arms[GUN_ARM].rotation.x = deg_to_rad(GUN_ARM_REST_DEG)
		arms[GUN_ARM].rotation.z = deg_to_rad(GUN_ARM_TUCK_DEG)
	# Mittens on the rim are the fists, so the robot's own hands would double up.
	_show_arm_hands(not driving)


func _climb_arm(arm: Node3D, to: Vector3) -> void:
	if to == Vector3.INF or to.is_equal_approx(Vector3.ZERO):
		arm.rotation.x = deg_to_rad(110.0)
		arm.rotation.z = 0.0
		return
	_reach(arm, to)


## Point an arm's -Y (the way the meshes hang) at a grip on the wheel.
func _reach(arm: Node3D, to: Vector3) -> void:
	if arm.global_position.distance_squared_to(to) < 0.002:
		return
	arm.look_at(to, Vector3.UP)
	arm.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))


func _show_arm_hands(on: bool) -> void:
	for hand in arm_hands:
		hand.visible = on


## The player's own camera skips these meshes. Everyone else still sees them.
func hide_cabin_from_driver(layer: int, hidden: bool) -> void:
	if _cabin_hidden == hidden:
		return
	_cabin_hidden = hidden
	var bits := layer if hidden else WORLD_LAYER
	for mesh in cabin:
		mesh.layers = bits


## Free (left) arm: pulled back, then a hook through the target. x is pitch, y is
## the shoulder roll.
static func melee_free_arm_deg(progress: float) -> Vector2:
	var pose := Melee.swing_arc(
		progress, Vector3(-48.0, -22.0, 0.0), Vector3(108.0, 18.0, 0.0), Vector3(42.0, -8.0, 0.0)
	)
	return Vector2(pose.x, pose.y)


## Gun arm chops like a club, from a backswing into a forward strike.
static func melee_gun_arm_deg(progress: float) -> Vector2:
	var pose := Melee.swing_arc(
		progress, Vector3(-28.0, 38.0, 0.0), Vector3(118.0, 6.0, 0.0), Vector3(52.0, -12.0, 0.0)
	)
	return Vector2(pose.x, pose.y)


static func melee_twist_deg(progress: float) -> float:
	return Melee.swing_arc(
		progress, Vector3(18.0, 0.0, 0.0), Vector3(-22.0, 0.0, 0.0), Vector3(-8.0, 0.0, 0.0)
	).x


## One limb's swing off its rest pose. Amplitude follows pace, which is what makes
## the run fade in as you speed up rather than popping on.
static func limb_angle_deg(phase: float, pace: float, swing_deg: float) -> float:
	return sin(phase) * swing_deg * clampf(pace, 0.0, 1.0)


## The hips rise twice per stride. Without it the robot glides along the ground.
static func bounce_height(phase: float, pace: float) -> float:
	return absf(sin(phase)) * BOUNCE * clampf(pace, 0.0, 1.0)


func _build_torso(shell: Color, trim: Color) -> void:
	var chest := MeshFactory.box(Vector3(0.44, 0.6, 0.26), shell)
	chest.position.y = 0.3
	_add_cabin(chest)
	var vent := MeshFactory.box(Vector3(0.3, 0.06, 0.28), trim, Palette.GLOW_MEDIUM)
	vent.position.y = 0.42
	_add_cabin(vent)
	var collar := MeshFactory.box(Vector3(0.16, 0.08, 0.16), shell)
	collar.position.y = 0.64
	_add_cabin(collar)
	head = Node3D.new()
	head.position.y = 0.64
	torso.add_child(head)
	var skull := MeshFactory.box(Vector3(0.28, 0.26, 0.26), shell)
	skull.position.y = 0.16
	_add_cabin(skull, head)
	var visor := MeshFactory.box(Vector3(0.2, 0.08, 0.03), trim, Palette.GLOW_STRONG)
	visor.position = Vector3(0.0, 0.16, -0.14)
	_add_cabin(visor, head)
	var mast := MeshFactory.cylinder(0.012, 0.18, shell)
	mast.position = Vector3(0.0, 0.38, 0.0)
	_add_cabin(mast, head)
	var beacon := MeshFactory.sphere(0.04, trim, Palette.GLOW_STRONG)
	beacon.position = Vector3(0.0, 0.49, 0.0)
	_add_cabin(beacon, head)


func _build_leg(side: float, shell: Color, trim: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * HIP_SPREAD, 0.0, 0.0)
	hips.add_child(pivot)
	var joint := MeshFactory.box(Vector3(0.16, 0.1, 0.16), trim, Palette.GLOW_SOFT)
	_add_cabin(joint, pivot)
	var thigh := MeshFactory.box(Vector3(0.15, 0.4, 0.15), shell)
	thigh.position.y = -0.24
	_add_cabin(thigh, pivot)
	var shin := MeshFactory.box(Vector3(0.13, 0.38, 0.13), shell)
	shin.position.y = -0.62
	_add_cabin(shin, pivot)
	var foot := MeshFactory.box(Vector3(0.17, 0.1, 0.3), trim, Palette.GLOW_SOFT)
	foot.position = Vector3(0.0, -0.84, -0.07)
	_add_cabin(foot, pivot)
	return pivot


func _build_arm(side: float, shell: Color, trim: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * SHOULDER_SPREAD, SHOULDER_HEIGHT, 0.0)
	torso.add_child(pivot)
	var joint := MeshFactory.box(Vector3(0.14, 0.14, 0.14), trim, Palette.GLOW_SOFT)
	pivot.add_child(joint)
	var upper := MeshFactory.box(Vector3(0.12, 0.32, 0.12), shell)
	upper.position.y = -0.2
	pivot.add_child(upper)
	var lower := MeshFactory.box(Vector3(0.1, 0.3, 0.1), shell)
	lower.position.y = -0.5
	pivot.add_child(lower)
	var hand := MeshFactory.box(Vector3(0.11, 0.11, 0.13), trim, Palette.GLOW_SOFT)
	hand.position.y = -ARM_LENGTH
	pivot.add_child(hand)
	arm_hands.append(hand)
	return pivot


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
	_floor_lift = Ragdoll.floor_lift(
		find_children("*", "MeshInstance3D", true, false), floor_y
	)
	position.y += _floor_lift


func _add_cabin(mesh: MeshInstance3D, parent: Node3D = null) -> void:
	(torso if parent == null else parent).add_child(mesh)
	cabin.append(mesh)


## Shirt sleeves stay on the arms so the driver still sees them. Everything else
## rides the cabin layer and disappears from that player's own camera.
func attach_wear(mesh: MeshInstance3D, parent: Node3D = null, hide_in_cabin := true) -> void:
	if hide_in_cabin:
		_add_cabin(mesh, parent)
	else:
		(torso if parent == null else parent).add_child(mesh)


func set_flash(material: Material) -> void:
	_paint_flash(self, material)


func _paint_flash(node: Node, material: Material) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		mesh.material_overlay = material
	for child in node.get_children():
		_paint_flash(child, material)


func is_wearing(item_id: String) -> bool:
	return worn.values().has(item_id)


func is_trying_on(item_id: String) -> bool:
	return _preview_id == item_id


func try_on(item: Dictionary) -> void:
	if item.is_empty() or String(item.get("kind", "")) != "apparel":
		clear_try_on()
		return
	var item_id := String(item["id"])
	if item_id == _preview_id:
		return
	var slot := String(item.get("slot", ""))
	if _preview_slot != "" and _preview_slot != slot:
		_restore_slot(_preview_slot)
		_preview_slot = ""
		_preview_id = ""
	if item_id == String(worn.get(slot, "")):
		if _preview_slot == slot:
			_restore_slot(slot)
			_preview_slot = ""
			_preview_id = ""
		return
	_preview_slot = slot
	_preview_id = item_id
	_put_on(item, false)


func clear_try_on() -> void:
	if _preview_slot == "":
		return
	var slot := _preview_slot
	_preview_slot = ""
	_preview_id = ""
	_restore_slot(slot)


func wear_shirt(item_id: String, color: Color) -> void:
	_put_on({"id": item_id, "slot": "shirt", "color": color, "kind": "apparel"}, true)


func wear_headband(item_id: String, color: Color) -> void:
	_put_on({"id": item_id, "slot": "headband", "color": color, "kind": "apparel"}, true)


func wear_bottom(item_id: String, style: String, color: Color) -> void:
	_put_on({
		"id": item_id, "slot": "bottom", "style": style, "color": color, "kind": "apparel"
	}, true)


func _put_on(item: Dictionary, commit: bool) -> void:
	var slot := String(item.get("slot", ""))
	var item_id := String(item.get("id", ""))
	match slot:
		"shirt":
			_clear_slot(_shirts)
			_shirts = Wear.wear_shirt(self, item["color"])
		"headband":
			_clear_slot(_headbands)
			_headbands = Wear.wear_headband(self, item["color"])
		"bottom":
			_clear_slot(_bottoms)
			_bottoms = Wear.wear_bottom(
				self, String(item.get("style", "shorts")), item["color"]
			)
		_:
			return
	if commit:
		worn[slot] = item_id
		if _preview_slot == slot:
			_preview_slot = ""
			_preview_id = ""


func _restore_slot(slot: String) -> void:
	var item := ShopStock.wear_by_id(String(worn.get(slot, "")))
	if item.is_empty():
		match slot:
			"shirt":
				_clear_slot(_shirts)
			"headband":
				_clear_slot(_headbands)
			"bottom":
				_clear_slot(_bottoms)
		return
	_put_on(item, false)


func _clear_slot(pieces: Array[MeshInstance3D]) -> void:
	for mesh in pieces:
		_drop(mesh)
	pieces.clear()


func _drop(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	cabin.erase(mesh)
	mesh.queue_free()
