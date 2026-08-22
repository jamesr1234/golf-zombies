class_name Ragdoll
extends RefCounted
## Limp-body physics for the primitive robots. There is no skeleton: a hit picks
## a region, that region takes the spin, and neighbouring limbs follow. Translation
## still lives on the CharacterBody; this only flops the mesh.

enum Region { HEAD, TORSO, ARM_L, ARM_R, LEG_L, LEG_R }

## Same band Zombie.is_headshot uses, so a skull ping and a skull flop agree.
const HEAD_RATIO := 0.72
const LEG_RATIO := 0.38
## Past this fraction of radius, a chest-height hit is an arm, not the ribs.
const ARM_SIDE := 0.55
const RECOVER := 0.62
const DAMP := 3.6
const HANG := 14.0
const SETTLE := 4.2
const MAX_OMEGA := 22.0
const LIMIT := deg_to_rad(125.0)
const HIP_LIMIT := deg_to_rad(28.0)
## Keep the pelvis high enough that folded legs stay on the turf, not under it.
const HIP_DROP := 0.78
const FLOOR_CLEARANCE := 0.04

var _omega: Dictionary = {}
var _left := 0.0
var _locked := false
var _planted := false
var _active := false
var _hip_rest := 0.92
var _hip_down := 0.28


func is_active() -> bool:
	return _active


func is_locked() -> bool:
	return _active and _locked


func configure_hips(rest: float, down: float) -> void:
	_hip_rest = rest
	_hip_down = down


func flop(
	parts: Dictionary, region: Region, direction: Vector3, strength: float, locked := false,
	planted := false
) -> void:
	_active = true
	_locked = _locked or locked
	_planted = planted
	_left = maxf(_left, RECOVER)
	if _locked:
		_left = 9999.0
	var spins := spins_for(region, direction, strength, planted)
	for part in spins:
		kick(part, spins[part])


func kick(part: StringName, spin: Vector3) -> void:
	var next: Vector3 = _omega.get(part, Vector3.ZERO) + spin
	_omega[part] = next.limit_length(MAX_OMEGA)


func lock() -> void:
	if _active:
		_locked = true
		_left = 9999.0


func stop() -> void:
	_active = false
	_locked = false
	_planted = false
	_left = 0.0
	_omega.clear()


func tick(delta: float, parts: Dictionary, airborne: bool) -> bool:
	if not _active:
		return false
	for key in parts:
		var node := parts[key] as Node3D
		if node == null:
			continue
		var w: Vector3 = _omega.get(key, Vector3.ZERO)
		if w.length_squared() > 0.00001:
			node.rotate(w.normalized(), w.length() * delta)
		if _locked and not airborne:
			node.rotation = node.rotation.lerp(_crumple(key), clampf(SETTLE * delta, 0.0, 1.0))
			w *= exp(-DAMP * 1.8 * delta)
		else:
			w += _hang_torque(node) * delta
			w *= exp(-DAMP * delta)
		_clamp(node, key, not airborne)
		_omega[key] = w.limit_length(MAX_OMEGA)
	_drop_hips(parts.get(&"hips") as Node3D, delta, airborne)
	if _locked:
		return true
	_left = maxf(0.0, _left - delta)
	if _left > 0.0:
		return true
	stop()
	return false


static func region(
	hit: Vector3, origin: Vector3, height: float, radius: float, right: Vector3
) -> Region:
	if not hit.is_finite():
		return Region.TORSO
	var tall := maxf(0.1, height)
	var t := clampf((hit.y - origin.y) / tall, 0.0, 1.0)
	if t >= HEAD_RATIO:
		return Region.HEAD
	var side := 0.0
	if right.length_squared() > 0.0001:
		side = (hit - origin).dot(right.normalized())
	if t <= LEG_RATIO:
		return Region.LEG_R if side >= 0.0 else Region.LEG_L
	if absf(side) > radius * ARM_SIDE:
		return Region.ARM_R if side >= 0.0 else Region.ARM_L
	return Region.TORSO


## Extra vertical on a player hit. Enemy gunshots stay planted; only melee throws
## a zombie into the air.
static func shot_pop(region: Region, amount: float, resistance: float) -> Vector3:
	var scale := 1.0 / maxf(0.1, resistance)
	var force := amount * scale
	var lift := 0.55
	match region:
		Region.HEAD:
			lift = 2.6
		Region.LEG_L, Region.LEG_R:
			lift = 0.25
		Region.ARM_L, Region.ARM_R:
			lift = 0.7
		_:
			lift = 0.55
	return Vector3.UP * lift * scale * (1.0 + force * 0.012)


static func strength_for(amount: float, resistance: float) -> float:
	return clampf((0.4 + amount * 0.042) / maxf(0.1, resistance), 0.3, 2.8)


static func spins_for(
	region: Region, direction: Vector3, strength: float, planted := false
) -> Dictionary:
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var axis := dir.cross(Vector3.UP)
	if axis.length_squared() < 0.0001:
		axis = Vector3.RIGHT
	else:
		axis = axis.normalized()
	var s := maxf(0.15, strength)
	var spins := {
		&"hips": axis * s * 0.35,
		&"torso": axis * s * 0.7,
		&"head": axis * s * 0.4,
		&"arm_l": Vector3.RIGHT * s * 0.5 + Vector3.FORWARD * s * 0.2,
		&"arm_r": Vector3.RIGHT * s * 0.45 - Vector3.FORWARD * s * 0.2,
		&"leg_l": Vector3.RIGHT * s * 0.3,
		&"leg_r": Vector3.RIGHT * s * 0.28,
	}
	match region:
		Region.HEAD:
			spins[&"head"] = axis * s * 2.6 + Vector3.RIGHT * s * 1.1
			spins[&"torso"] = axis * s * 1.2
			spins[&"hips"] = axis * s * 0.55
		Region.ARM_L:
			spins[&"arm_l"] = Vector3.RIGHT * s * -2.8 + axis * s * 1.4
			spins[&"torso"] = Vector3.UP * s * -0.9 + axis * s * 0.5
		Region.ARM_R:
			spins[&"arm_r"] = Vector3.RIGHT * s * -2.8 + axis * s * 1.4
			spins[&"torso"] = Vector3.UP * s * 0.9 + axis * s * 0.5
		Region.LEG_L:
			spins[&"leg_l"] = Vector3.RIGHT * s * 2.4 + axis * s
			spins[&"hips"] = Vector3.FORWARD * s * 0.8 + axis * s * 0.6
			spins[&"leg_r"] = Vector3.RIGHT * s * 0.4
		Region.LEG_R:
			spins[&"leg_r"] = Vector3.RIGHT * s * 2.4 + axis * s
			spins[&"hips"] = Vector3.FORWARD * s * -0.8 + axis * s * 0.6
			spins[&"leg_l"] = Vector3.RIGHT * s * 0.4
		Region.TORSO:
			spins[&"torso"] = axis * s * 1.6 + Vector3.RIGHT * s * 0.5
			spins[&"head"] = axis * s * 0.9
			spins[&"hips"] = axis * s * 0.7
	if planted:
		spins[&"hips"] = spins[&"hips"] * 0.12
		spins[&"leg_l"] = spins[&"leg_l"] * 0.18
		spins[&"leg_r"] = spins[&"leg_r"] * 0.18
	return spins


func _hang_torque(node: Node3D) -> Vector3:
	return Vector3(-node.rotation.x, -node.rotation.y * 0.4, -node.rotation.z) * HANG


func _crumple(part: StringName) -> Vector3:
	if _planted and (part == &"hips" or part == &"leg_l" or part == &"leg_r"):
		return Vector3.ZERO
	match part:
		&"hips":
			return Vector3(deg_to_rad(16.0), 0.0, deg_to_rad(8.0))
		&"torso":
			return Vector3(deg_to_rad(22.0), deg_to_rad(8.0), 0.0)
		&"head":
			return Vector3(deg_to_rad(28.0), deg_to_rad(14.0), 0.0)
		&"leg_l":
			return Vector3(deg_to_rad(38.0), 0.0, deg_to_rad(-14.0))
		&"leg_r":
			return Vector3(deg_to_rad(48.0), 0.0, deg_to_rad(16.0))
		&"arm_l":
			return Vector3(deg_to_rad(58.0), 0.0, deg_to_rad(-28.0))
		&"arm_r":
			return Vector3(deg_to_rad(70.0), 0.0, deg_to_rad(24.0))
		_:
			return Vector3.ZERO


func _clamp(node: Node3D, part: StringName, grounded: bool) -> void:
	var pitch_limit := LIMIT
	if grounded and part == &"hips":
		pitch_limit = HIP_LIMIT
	elif grounded and _planted and (part == &"leg_l" or part == &"leg_r"):
		pitch_limit = deg_to_rad(18.0)
	node.rotation.x = clampf(node.rotation.x, -pitch_limit, pitch_limit)
	node.rotation.y = clampf(node.rotation.y, -LIMIT, LIMIT)
	node.rotation.z = clampf(node.rotation.z, -pitch_limit, pitch_limit)


## How far to lift a visual so none of its meshes sit under floor_y.
static func floor_lift(meshes: Array, floor_y: float) -> float:
	var lowest := INF
	for mesh in meshes:
		var instance := mesh as MeshInstance3D
		if instance == null or not is_instance_valid(instance) or instance.mesh == null:
			continue
		var aabb := instance.get_aabb()
		var xf := instance.global_transform
		for i in 8:
			lowest = minf(lowest, (xf * aabb.get_endpoint(i)).y)
	if lowest == INF or lowest >= floor_y:
		return 0.0
	return floor_y - lowest


func _drop_hips(hips: Node3D, delta: float, airborne: bool) -> void:
	if hips == null:
		return
	var slump := _locked and not airborne and not _planted
	var target := _hip_down if slump else _hip_rest
	hips.position.y = lerpf(hips.position.y, target, clampf(6.5 * delta, 0.0, 1.0))
