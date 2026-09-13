class_name CartBrute
extends Object
## A cart cannot flatten a brute. The brute swats the cart into the air instead,
## so you have to step out and fight it.

const SPEED := 22.0
const LIFT := 16.0
const LOCK := 1.0


static func ignores_crush(stats: ZombieStats) -> bool:
	return stats != null and ZombieBody.kind_of(stats) == ZombieBody.Kind.BRUTE


static func away(brute_at: Vector3, cart_at: Vector3, fallback := Vector3.FORWARD) -> Vector3:
	var flat := cart_at - brute_at
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		flat = Vector3(fallback.x, 0.0, fallback.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


static func try_swat(cart: GolfCart, zombie: Zombie) -> bool:
	if cart == null or zombie == null or not ignores_crush(zombie.stats):
		return false
	swat(cart, zombie)
	return true


static func swat(cart: GolfCart, zombie: Zombie) -> void:
	if cart == null or zombie == null:
		return
	var cart_at := cart.global_position if cart.is_inside_tree() else cart.position
	var brute_at := zombie.global_position if zombie.is_inside_tree() else zombie.position
	var fallback := cart.global_transform.basis.z if cart.is_inside_tree() else cart.transform.basis.z
	var dir := away(brute_at, cart_at, fallback)
	cart.fling(dir, SPEED, LIFT, LOCK)
	if zombie.visual != null:
		zombie.visual.start_melee()
	Sfx.play("zombie_attack", zombie)
	Sfx.play("melee_hit", cart)
