class_name GrappleHook
extends Node3D
## Glowing claw. Homes on a painted cart or mech; otherwise flies out and dies.

const SPEED := 88.0
const SPIN_DEG := 540.0
const COLOR := Palette.HOT_PINK

var shooter: Player
var visual_only := false
var direction := Vector3.FORWARD
var _target: Node3D
var _local := Vector3.ZERO
var _end := Vector3.INF
var _dead := false
var _spin := 0.0


static func spawn(
	root: Node, origin: Vector3, fly: Vector3, who: Player, p_visual_only := false
) -> GrappleHook:
	if root == null or fly.length_squared() < 0.0001:
		return null
	var hook := GrappleHook.new()
	hook.shooter = who
	hook.visual_only = p_visual_only
	hook.direction = fly.normalized()
	hook.add_to_group("grapple_hooks")
	root.add_child(hook)
	hook.global_position = origin
	hook._end = origin + hook.direction * Grappler.RANGE
	hook._build()
	hook.look_at(origin + hook.direction)
	return hook


func lock_on(ride: Node3D, local_offset: Vector3) -> void:
	_target = ride
	_local = local_offset
	_end = Vector3.INF


func fly_to(at: Vector3) -> void:
	_target = null
	_end = at


func _build() -> void:
	add_child(build_claw(COLOR))
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 5.5
	lamp.omni_range = 7.0
	add_child(lamp)


static func build_claw(color: Color) -> Node3D:
	var claw := Node3D.new()
	claw.name = "Claw"
	var core := MeshFactory.sphere(0.07, color, Palette.GLOW_STRONG)
	claw.add_child(core)
	var ring := MeshFactory.torus(0.05, 0.09, Palette.ICE, Palette.GLOW_MEDIUM)
	ring.rotation.x = deg_to_rad(90.0)
	claw.add_child(ring)
	for i in 3:
		var pivot := Node3D.new()
		pivot.rotation.z = deg_to_rad(float(i) * 120.0)
		claw.add_child(pivot)
		var prong := MeshFactory.box(
			Vector3(0.035, 0.045, 0.16), color.darkened(0.35), Palette.GLOW_MEDIUM
		)
		prong.position = Vector3(0.0, 0.06, -0.1)
		prong.rotation.x = deg_to_rad(28.0)
		pivot.add_child(prong)
		var tip := MeshFactory.sphere(0.02, Palette.ICE, Palette.GLOW_STRONG)
		tip.position = Vector3(0.0, 0.09, -0.18)
		pivot.add_child(tip)
	return claw


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var claw := get_node_or_null("Claw") as Node3D
	if claw != null:
		_spin = wrapf(_spin + SPIN_DEG * delta, 0.0, 360.0)
		claw.rotation.z = deg_to_rad(_spin)
	var goal := _goal()
	if goal == Vector3.INF:
		_die(global_position, false)
		return
	var to_goal := goal - global_position
	var step := SPEED * delta
	if to_goal.length() <= step:
		_arrive(goal)
		return
	if to_goal.length_squared() > 0.0001:
		global_position += to_goal.normalized() * step
		look_at(goal)


func _goal() -> Vector3:
	if _target != null:
		if not is_instance_valid(_target):
			return Vector3.INF
		return _target.to_global(_local)
	return _end


func _arrive(at: Vector3) -> void:
	if _dead:
		return
	if _target != null and is_instance_valid(_target) and not visual_only:
		if shooter != null and is_instance_valid(shooter):
			shooter.begin_grapple(_target, at)
			_dead = true
			queue_free()
			return
	_die(at, _target == null)


func _die(at: Vector3, spark: bool) -> void:
	if _dead:
		return
	_dead = true
	if spark:
		var root := get_tree().get_first_node_in_group("fx_root") if is_inside_tree() else null
		HitFx.spark(root, at, COLOR)
		Sfx.play("empty_click")
	queue_free()
