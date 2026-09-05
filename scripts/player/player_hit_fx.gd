class_name PlayerHitFx
extends RefCounted
## Hit flash, ragdoll flop, and the downed / revived body reactions.

const HIT_FLASH_TIME := 0.16
const BODY_RADIUS := 0.4
const STAND_HEAD_HEIGHT := 1.55

var flash_left := 0.0
var flash_material: StandardMaterial3D


func setup(player: Player) -> void:
	flash_material = MeshFactory.material(Color(1.0, 0.12, 0.08), false, Palette.GLOW_STRONG)
	_add_glow(player)


func _add_glow(player: Player) -> void:
	var lamp := OmniLight3D.new()
	lamp.light_cull_mask = ~Raygun.VIEW_LAYER
	lamp.light_color = player.body_color
	lamp.light_energy = 0.85
	lamp.omni_range = 12.0
	lamp.omni_attenuation = 0.8
	lamp.position.y = 1.4
	player.add_child(lamp)


func on_damaged(player: Player, _amount: float) -> void:
	if player.state == Player.State.GOLFING and player.golf != null:
		player.golf.cancel_swing()
	start_flash(player)


func start_flash(player: Player) -> void:
	flash_left = HIT_FLASH_TIME
	if player.body != null:
		player.body.set_flash(flash_material)


func tick_flash(player: Player, delta: float) -> void:
	if flash_left <= 0.0:
		return
	flash_left = maxf(0.0, flash_left - delta)
	if is_zero_approx(flash_left) and player.body != null:
		player.body.set_flash(null)


func is_flashing() -> bool:
	return flash_left > 0.0


func on_downed(player: Player) -> void:
	if player.is_carrying_ball():
		player.golf.ball.release_carried()
	if player.state == Player.State.GOLFING and player.golf != null:
		player.golf.release()
	if player.state == Player.State.SWIMMING:
		player.swim.leave(player)
	player._drop_climb()
	player._drop_grapple()
	player._drop_zipline()
	if player.is_milling():
		player.mill_desk.release(player)
	# Dumped out of the cart, so your partner has to come and pick you up.
	if player.state == Player.State.RIDING:
		player.cart.eject(player)
	if player.is_placing():
		player._cancel_place()
		player.state = Player.State.NORMAL
	player.look.cheer_left = 0.0
	if player._shield != null:
		player._shield.set_raised(false)
	if player.body != null:
		player.body.flop(Ragdoll.Region.TORSO, -player.transform.basis.z, 1.7, true)


func on_revived(player: Player) -> void:
	if player.body != null:
		player.body.stop_limp()


func flop_from(player: Player, from: Vector3, hit_at: Vector3, amount: float, locked: bool) -> void:
	if player.body == null or player.is_riding():
		return
	var at := hit_at
	if not at.is_finite():
		at = player.global_position + Vector3.UP * STAND_HEAD_HEIGHT * 0.6
	var region := Ragdoll.region(
		at, player.global_position, 1.8, BODY_RADIUS, player.global_transform.basis.x
	)
	var direction := at - from
	if direction.length_squared() < 0.0001:
		direction = -player.transform.basis.z
	player.body.flop(region, direction, Ragdoll.strength_for(amount, 1.0), locked)
	if not locked:
		player.velocity.y += Ragdoll.shot_pop(region, amount, 1.0).y
