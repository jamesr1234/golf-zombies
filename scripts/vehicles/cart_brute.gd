class_name CartBrute
extends Object
## A cart cannot flatten a brute. The brute clubs the ride apart: riders fly
## out unharmed, and every body style — cart, truck, van, the lot — is gone.

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


static func overlapping(cart: GolfCart) -> bool:
	if cart == null or cart.crush_area == null:
		return false
	for body in cart.crush_area.get_overlapping_bodies():
		var zombie := body as Zombie
		if zombie != null and not zombie.is_allied() and ignores_crush(zombie.stats):
			return true
	return false


static func try_swat(cart: GolfCart, zombie: Zombie) -> bool:
	if cart == null or zombie == null or not ignores_crush(zombie.stats):
		return false
	if cart.is_wrecked():
		return false
	swat(cart, zombie)
	return true


static func try_swat_rider(player: Player, zombie: Zombie) -> bool:
	if player == null or not player.is_riding() or player.cart == null:
		return false
	return try_swat(player.cart, zombie)


static func swat(cart: GolfCart, zombie: Zombie) -> void:
	if cart == null or zombie == null:
		return
	var cart_at := cart.global_position if cart.is_inside_tree() else cart.position
	var brute_at := zombie.global_position if zombie.is_inside_tree() else zombie.position
	var fallback := cart.global_transform.basis.z if cart.is_inside_tree() else cart.transform.basis.z
	var dir := away(brute_at, cart_at, fallback)
	_launch_riders(cart, dir)
	if zombie.visual != null:
		zombie.visual.start_melee()
	if zombie.ai != null:
		zombie.ai.melee_pending = false
		if zombie.stats != null:
			zombie.ai.attack_timer = zombie.stats.attack_cooldown
	cart.wreck()
	Sfx.play("zombie_attack", zombie)
	Sfx.play("melee_hit", cart)


static func _launch_riders(cart: GolfCart, dir: Vector3) -> void:
	var launch := cart_at_up(cart)
	for player in _riders(cart):
		cart.unseat_at(player, launch)
		if player.hit_fx != null:
			player.hit_fx.register_hit()
		player.fling(dir, SPEED, LIFT, LOCK)


static func cart_at_up(cart: GolfCart) -> Vector3:
	var at := cart.global_position if cart.is_inside_tree() else cart.position
	return at + Vector3.UP * 1.2


static func _riders(cart: GolfCart) -> Array[Player]:
	var out: Array[Player] = []
	if cart.driver != null:
		out.append(cart.driver)
	if cart.passenger != null:
		out.append(cart.passenger)
	return out
