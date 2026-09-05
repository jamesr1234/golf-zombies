class_name PlayerAnim
extends RefCounted
## Body and raygun posing for every locomotion state. Remotes ease pace / pitch
## here so the run cycle does not stair-step with the pose stream.

const REMOTE_POSE_EASE := 18.0
const DOWNED_HEAD_HEIGHT := 0.45
const SIT_HEAD_HEIGHT := 0.96
const SLIDE_HEAD_HEIGHT := 0.55
const STAND_HEAD_HEIGHT := 1.55

var remote_pace := 0.0
var remote_pitch := 0.0


func apply_replicated_pose(player: Player, delta: float) -> void:
	player.state = player.sync_state as Player.State
	player.swim.underwater = player.sync_dive
	if player.weapon != null:
		player.weapon.apply_replicated_index(player.sync_gun)
		player.weapon.apply_replicated_pose(
			player.sync_firing, player.sync_reload, player.sync_scoped
		)
	if player.combat.shield != null:
		player.combat.shield.set_raised(player.state == Player.State.SHIELDING)
	var ease := clampf(REMOTE_POSE_EASE * delta, 0.0, 1.0)
	remote_pace = lerpf(remote_pace, player.sync_pace, ease)
	remote_pitch = lerpf(remote_pitch, player.sync_pitch, ease)
	player.set_look_pitch(remote_pitch)
	if player.head != null:
		player.head.rotation.x = deg_to_rad(clampf(remote_pitch, -PlayerLook.PITCH_LIMIT, PlayerLook.PITCH_LIMIT))
	if player.health != null and player.health.is_downed():
		player.head.position.y = DOWNED_HEAD_HEIGHT
	elif player.is_riding():
		player.head.position.y = SIT_HEAD_HEIGHT
	elif player.is_poker_seated():
		player.head.position.y = SIT_HEAD_HEIGHT
	elif player.sync_slide or player.is_sliding():
		player.head.position.y = SLIDE_HEAD_HEIGHT
	else:
		player.head.position.y = STAND_HEAD_HEIGHT


## The gun is stowed for the swing, since the golfer is holding a club, and dropped
## when you go down.
func tick(player: Player, delta: float) -> void:
	if player.net_driven and not player.is_multiplayer_authority():
		player.slide.apply_replicated(player, player.sync_slide)
		player.glide.apply_replicated(player, player.sync_glide, player.sync_glide_worn)
		apply_replicated_pose(player, delta)
	if player.health.is_alive() and player.body != null and player.body.is_locked_limp():
		player.body.stop_limp()
	var travel := player.pace()
	if player.body != null and player.body.is_limp():
		player.body.tick_limp(delta, not player.is_on_floor() and not player.is_riding())
	elif player.is_riding():
		var wheel := 0.0
		var grips: Array[Vector3] = []
		if player.is_driving() and player.cart != null:
			wheel = player.cart.wheel_angle_deg()
			grips = player.cart.wheel_grips()
		player.body.sit(player.is_driving(), wheel, grips)
	elif player.is_poker_seated():
		player.body.hold_cards()
	elif player.is_celebrating():
		player.body.cheer(delta, player.look.cheer_left)
	elif player.is_swimming():
		player.body.swim(delta, player.pace(), player.swim.underwater)
	elif player.is_climbing():
		if player.climber.is_mantling():
			player.body.mantle(player.climber.mantle_progress())
		else:
			player.body.climb(
				player.climber.pose_left(), player.climber.pose_right(), player.climber.left_aim,
				player.climber.left != Vector3.INF, player.climber.right != Vector3.INF
			)
	elif player.state == Player.State.ZIPLINING:
		player.body.zip(player.zipliner.grip_left(), player.zipliner.grip_right())
	elif player.is_grappling():
		player.body.tow(player.grappler.line_end(), player.pace())
	elif player.is_shielding():
		player.body.guard()
	elif player.is_sliding():
		player.body.slide()
	elif player.is_gliding():
		player.body.glide()
	else:
		player.body.animate(delta, travel)
	if not player.is_celebrating():
		player.body.tick_melee(delta)
	if player.net_driven and not player.is_multiplayer_authority() and player.body != null and player.body.head != null:
		if not player.body.is_limp() and not player.is_celebrating():
			player.body.head.rotation.x = deg_to_rad(
				clampf(remote_pitch, -PlayerLook.PITCH_LIMIT, PlayerLook.PITCH_LIMIT)
			)
	player.body.hide_cabin_from_driver(player.cabin_layer(), player.look.hides_own_cabin(player))
	var show_gun := (
		player.health.is_alive() and player.state != Player.State.GOLFING and not player.is_driving()
		and not player.is_swimming() and not player.is_shielding() and not player.is_placing()
		and not player.is_climbing()
		and not player.is_ziplining()
		and not player.is_milling()
		and not player.is_in_mech()
		and not player.is_holding_beer() and not player.is_holding_mines()
		and not player.weapon.is_scoped() and not player.is_celebrating()
		and not player.shopping
		and not player.is_poker_seated()
		and not player.is_gliding()
		and player.weapon.has_weapon()
	)
	player.raygun.visible = show_gun
	if show_gun:
		player.raygun.show_gun(player.weapon.stats().visual)
		player.raygun.animate(delta, travel, player.weapon.is_firing(), player.weapon.reload_fraction())
	player.beer.animate(player, delta)
	player._draw_grapple_line()
