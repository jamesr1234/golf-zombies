class_name ZombieShot
extends Node3D
## Slow glowing bolt a gunner throws. Dies on world, a player, or a raised shield.
## Player bullets never query the shield layer, so a partner can still shoot
## through the panel that is covering them.

const COLOR := Palette.AMBER
const RADIUS := 0.11


var damage := 16.0
var speed := 22.0
var max_range := 36.0
var direction := Vector3.FORWARD
var color := COLOR
var radius := RADIUS
var streak := 0.0
var sniper := false
var muzzle := Vector3.ZERO

var _travelled := 0.0
var _dead := false
var _friendly := false
var _beamed := false
var _beam: Node3D


static func spawn(
	root: Node, origin: Vector3, fly: Vector3, amount: float, pace: float, reach: float,
	friendly := false, tint := COLOR, size := RADIUS, tracer := 0.0, is_sniper := false
) -> ZombieShot:
	if root == null:
		return null
	var shot := ZombieShot.new()
	shot.damage = amount
	shot.speed = pace
	shot.max_range = reach
	shot.direction = fly.normalized()
	shot._friendly = friendly
	shot.color = tint
	shot.radius = size
	shot.streak = tracer
	shot.sniper = is_sniper
	shot.muzzle = origin
	shot.add_to_group("zombie_shots")
	root.add_child(shot)
	shot.global_position = origin
	shot._build()
	if is_sniper:
		shot.reveal()
	return shot


static func hits_player(collider: Object) -> bool:
	return collider is Player


static func is_blocked(collider: Object) -> bool:
	var body := collider as CollisionObject3D
	if body == null:
		return false
	return (body.collision_layer & (Layers.SHIELD | Layers.FORT)) != 0


func _build() -> void:
	if sniper:
		if direction.length_squared() > 0.0001:
			look_at(global_position + direction)
		return
	if streak > 0.0:
		var bolt := MeshFactory.box(
			Vector3(radius * 1.4, radius * 1.4, streak), color, Palette.GLOW_STRONG
		)
		bolt.position.z = -streak * 0.5
		add_child(bolt)
	else:
		add_child(MeshFactory.sphere(radius, color, Palette.GLOW_STRONG))
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = 3.2 if streak <= 0.0 else 5.0
	lamp.omni_range = 5.0 if streak <= 0.0 else 10.0
	add_child(lamp)
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var step := speed * delta
	var from := global_position
	var to := from + direction * step
	var mask := Layers.BULLET_MASK if _friendly else Layers.ENEMY_SHOT_MASK
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = to
	_travelled += step
	_sync_beam()
	if _travelled >= max_range:
		_die()


func _impact(hit: Dictionary) -> void:
	var at: Vector3 = hit["position"]
	var collider: Object = hit["collider"]
	global_position = at
	if hits_player(collider):
		if _friendly:
			_mark(at, Palette.HIT_WORLD)
			_die()
			return
		var player := collider as Player
		player.apply_hit(damage, global_position, at)
		if sniper:
			player.call_for_cover()
		_mark(at, Palette.HIT_ZOMBIE)
	elif collider is Zombie:
		var zombie := collider as Zombie
		if _friendly and not zombie.is_allied() and not zombie.is_dying():
			zombie.take_damage(damage, direction, at)
			_mark(at, Palette.HIT_ZOMBIE)
		else:
			_mark(at, Palette.HIT_WORLD)
	elif collider.has_method("take_hit"):
		collider.take_hit(at)
		_mark(at, Palette.CYAN)
	elif is_blocked(collider):
		_mark(at, Palette.CYAN)
		Sfx.play("shield_hit")
	else:
		_mark(at, Palette.HIT_WORLD)
	_die()


func reveal() -> void:
	if _beamed:
		return
	_beamed = true
	_beam = HitFx.sniper_beam(_fx_root(), muzzle, _aim_end(), HitFx.sniper_tint(_friendly), true)


func _aim_end() -> Vector3:
	var to := muzzle + direction * max_range
	var space := get_world_3d()
	if space == null:
		return to
	var mask := Layers.BULLET_MASK if _friendly else Layers.ENEMY_SHOT_MASK
	var query := PhysicsRayQueryParameters3D.create(muzzle, to, mask)
	var hit := space.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"]


func _mark(at: Vector3, tint: Color) -> void:
	if sniper:
		reveal()
		HitFx.spark(_fx_root(), at, tint)
		return
	HitFx.spawn(_fx_root(), from_muzzle(), at, tint)


func _sync_beam() -> void:
	if not sniper:
		return
	HitFx.sniper_draw_to(_beam, muzzle.distance_to(global_position))


func from_muzzle() -> Vector3:
	return global_position - direction * 0.4


func _fx_root() -> Node:
	var root := get_tree().get_first_node_in_group("fx_root")
	if root != null:
		return root
	if get_parent() != null:
		return get_parent()
	return get_tree().current_scene


func _die() -> void:
	if _dead:
		return
	_dead = true
	if sniper:
		_sync_beam()
		HitFx.sniper_finish(_beam)
	queue_free()
