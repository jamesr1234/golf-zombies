class_name PlayerSlide
extends RefCounted
## Sprint + R3 (Shift + Z) drops the hull for a low burst, then you stay crouched
## until a stand shapecast is clear. Zoom keeps R3 when you are not sprinting.

const STAND_HEIGHT := 1.8
const SLIDE_HEIGHT := 0.9
const STAND_SHAPE_Y := 0.9
const SLIDE_SHAPE_Y := 0.45
const SLIDE_SPEED := 11.0
const SLIDE_TIME := 0.65
const CRAWL_SPEED := 4.2
const SLIDE_HEAD_HEIGHT := 0.55

var active := false
var burst_left := 0.0
var along := Vector3.ZERO


func is_active() -> bool:
	return active


func bursting() -> bool:
	return active and burst_left > 0.0


func can_start(player: Player) -> bool:
	if active or not player.is_on_floor():
		return false
	if player.health == null or not player.health.is_alive():
		return false
	if player.state != Player.State.NORMAL:
		return false
	if player.shopping or player.is_celebrating():
		return false
	return (
		not player.is_golfing()
		and not player.is_riding()
		and not player.is_swimming()
		and not player.is_climbing()
		and not player.is_shielding()
		and not player.is_in_mech()
		and not player.is_grappling()
		and not player.is_milling()
		and not player.is_poker_seated()
	)


func try_start(player: Player, wish: Vector3) -> bool:
	if not can_start(player):
		return false
	if not player.motion.sprinting(player) or not player.input.just_pressed("slide"):
		return false
	start(player, wish)
	return true


func start(player: Player, wish: Vector3) -> void:
	along = _along(player, wish)
	burst_left = SLIDE_TIME
	active = true
	apply_hull(player, true)
	player.velocity.x = along.x * SLIDE_SPEED
	player.velocity.z = along.z * SLIDE_SPEED
	SlideSparks.attach(player)
	Sfx.play("slide", player)


func tick(player: Player, delta: float, wish: Vector3, mobile: bool) -> void:
	if player.motion.walks_from_wire(player):
		apply_replicated(player, player.sync_slide)
		return
	if active and not _can_keep(player):
		cancel(player)
		return
	if mobile:
		try_start(player, wish)
	if not active:
		return
	if bursting():
		burst_left = maxf(0.0, burst_left - delta)
		if along.length_squared() < 0.0001:
			along = _along(player, wish)
	elif try_stand(player):
		pass


func try_stand(player: Player) -> bool:
	if not active:
		return true
	if not can_stand(player):
		return false
	cancel(player)
	return true


func cancel(player: Player) -> void:
	if not active and _hull_height(player) >= STAND_HEIGHT - 0.01:
		return
	active = false
	burst_left = 0.0
	along = Vector3.ZERO
	apply_hull(player, false)
	SlideSparks.detach(player)


func apply_replicated(player: Player, low: bool) -> void:
	active = low
	if not low:
		burst_left = 0.0
	apply_hull(player, low)
	if low:
		SlideSparks.attach(player)
	else:
		SlideSparks.detach(player)


func apply_hull(player: Player, low: bool) -> void:
	var node := _shape(player)
	if node == null:
		return
	var capsule := node.shape as CapsuleShape3D
	if capsule == null:
		return
	if not capsule.resource_local_to_scene:
		capsule = capsule.duplicate()
		capsule.resource_local_to_scene = true
		node.shape = capsule
	capsule.height = SLIDE_HEIGHT if low else STAND_HEIGHT
	node.position.y = SLIDE_SHAPE_Y if low else STAND_SHAPE_Y


func can_stand(player: Player) -> bool:
	if not player.is_inside_tree():
		return true
	var node := _shape(player)
	if node == null:
		return true
	var current := node.shape as CapsuleShape3D
	if current == null:
		return true
	var extra := STAND_HEIGHT - SLIDE_HEIGHT
	var probe := CapsuleShape3D.new()
	probe.radius = current.radius
	probe.height = extra
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = player.global_transform.translated(
		Vector3.UP * (SLIDE_HEIGHT + extra * 0.5)
	)
	params.collision_mask = player.collision_mask
	params.exclude = [player.get_rid()]
	params.collide_with_areas = false
	return player.get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _can_keep(player: Player) -> bool:
	if player.health == null or not player.health.is_alive():
		return false
	return (
		player.state == Player.State.NORMAL
		and not player.shopping
		and not player.is_celebrating()
		and not player.is_swimming()
		and not player.is_climbing()
		and not player.is_shielding()
		and not player.is_grappling()
		and not player.is_milling()
		and not player.is_poker_seated()
	)


func _along(player: Player, wish: Vector3) -> Vector3:
	var dir := Vector3(wish.x, 0.0, wish.z)
	if dir.length_squared() < 0.04:
		dir = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if dir.length_squared() < 0.04:
		dir = -player.transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()


func _shape(player: Player) -> CollisionShape3D:
	return player.get_node_or_null("Shape") as CollisionShape3D


func _hull_height(player: Player) -> float:
	var node := _shape(player)
	if node == null:
		return STAND_HEIGHT
	var capsule := node.shape as CapsuleShape3D
	return capsule.height if capsule != null else STAND_HEIGHT
