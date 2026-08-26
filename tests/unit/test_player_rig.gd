extends GutTest
## The robot's run cycle and the raygun's bob: both keyed off pace, both required to
## stay smooth frame to frame.

const STEP := 1.0 / 60.0
const InspectScript := preload("res://scripts/shop/shop_inspect.gd")


func test_a_standing_robot_is_in_a_neutral_pose() -> void:
	assert_eq(PlayerBody.limb_angle_deg(1.2, 0.0, PlayerBody.LEG_SWING_DEG), 0.0)
	assert_eq(PlayerBody.bounce_height(1.2, 0.0), 0.0)


func test_a_sprint_swings_further_than_a_walk() -> void:
	var walk := absf(PlayerBody.limb_angle_deg(PI * 0.5, 0.5, PlayerBody.LEG_SWING_DEG))
	var sprint := absf(PlayerBody.limb_angle_deg(PI * 0.5, 1.0, PlayerBody.LEG_SWING_DEG))
	assert_gt(sprint, walk)
	assert_almost_eq(sprint, PlayerBody.LEG_SWING_DEG, 0.01)


func test_the_legs_are_always_on_opposite_sides_of_the_stride() -> void:
	for phase: float in [0.4, 1.1, 2.6, 5.0]:
		var left := PlayerBody.limb_angle_deg(phase, 1.0, PlayerBody.LEG_SWING_DEG)
		var right := PlayerBody.limb_angle_deg(phase + PI, 1.0, PlayerBody.LEG_SWING_DEG)
		assert_almost_eq(left, -right, 0.001)


func test_the_hips_rise_but_never_sink() -> void:
	for phase: float in [0.0, 0.8, 3.3, 4.9]:
		var lift := PlayerBody.bounce_height(phase, 1.0)
		assert_between(lift, 0.0, PlayerBody.BOUNCE)


func test_the_run_never_jumps_between_frames() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	var previous := 0.0
	var worst := 0.0
	for _frame in 180:
		body.animate(STEP, 1.0)
		var angle := rad_to_deg(body.legs[0].rotation.x)
		worst = maxf(worst, absf(angle - previous))
		previous = angle
	assert_gt(worst, 1.0, "at a full sprint the legs should actually be moving")
	assert_lt(worst, 8.0, "no single frame should snap the leg across the stride")


func test_the_stride_fades_out_as_the_player_slows_down() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	for _frame in 30:
		body.animate(STEP, 1.0)
	var running := absf(rad_to_deg(body.legs[0].rotation.x))
	body.animate(STEP, 0.0)
	assert_eq(absf(rad_to_deg(body.legs[0].rotation.x)), 0.0, "a stopped robot stands still")
	assert_gt(running, 0.0)


func test_a_seated_robot_folds_up_instead_of_standing() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.sit(true, 0.0)
	assert_lt(body.hips.position.y, PlayerBody.HIP_HEIGHT)
	assert_gt(rad_to_deg(body.legs[0].rotation.x), 50.0, "knees come up")
	assert_gt(rad_to_deg(body.arms[0].rotation.x), 40.0, "hands reach the wheel")
	body.pose(0.0)
	assert_almost_eq(body.hips.position.y, PlayerBody.HIP_HEIGHT, 0.001)
	assert_almost_eq(body.legs[0].rotation.x, 0.0, 0.001)


func test_a_celebration_puts_both_arms_up() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.pose(0.0)
	var tallest := PlayerBody.HIP_HEIGHT
	for _frame in 40:
		body.cheer(STEP, PlayerBody.CHEER_TIME * 0.5)
		tallest = maxf(tallest, body.hips.position.y)
	assert_gt(rad_to_deg(body.arms[0].rotation.x), 120.0, "free arm goes overhead")
	assert_gt(rad_to_deg(body.arms[1].rotation.x), 120.0, "gun arm goes overhead")
	assert_gt(tallest, PlayerBody.HIP_HEIGHT + 0.05, "the robot hops")


func test_a_player_celebration_pulls_the_camera_back() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	player.celebrate()
	assert_true(player.is_celebrating())
	assert_gt(
		player.get_view_transform().origin.distance_to(player.global_position), 2.5,
		"third person, so you see the dance"
	)
	assert_almost_eq(player.get_view_fov(), Player.CHEER_FOV, 0.001)


func test_browsing_apparel_pulls_the_camera_back() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	player.stand_at(Vector3.ZERO, 0.0)
	var fps := player.get_view_transform()
	player.shopping = true
	player.shop_dept = Shop.Dept.APPAREL
	var tps := player.get_view_transform()
	assert_true(player.trying_on_apparel())
	assert_gt(fps.origin.distance_to(tps.origin), 2.0, "the lens leaves the head")
	assert_gt(tps.origin.y, player.head.global_position.y - 0.2)
	assert_almost_eq(player.get_view_fov(), InspectScript.CAM_FOV, 0.001)
	player._animate(STEP)
	assert_false(player.raygun.visible, "stow the gun so the shirt can read")
	assert_ne(player.view_cull_mask() & player.cabin_layer(), 0, "the robot has to stay in frame")
	assert_lt(
		player.get_view_transform().origin.x, player.global_position.x,
		"camera slides left so the listing can sit there"
	)


func test_a_cpu_does_not_celebrate() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	player.possess_cpu()
	player.celebrate()
	assert_false(player.is_celebrating())


func test_a_driver_reaches_along_the_arm_toward_the_grip() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	var left := body.arms[0].global_position + Vector3(-0.1, -0.2, -0.45)
	var right := body.arms[1].global_position + Vector3(0.1, -0.2, -0.45)
	body.sit(true, 0.0, [left, right])
	var along := -body.arms[0].global_transform.basis.y
	var want := (left - body.arms[0].global_position).normalized()
	assert_gt(along.dot(want), 0.95, "the hanging arm should point at the wheel")
	assert_false(body.arm_hands[0].visible, "the rim mittens are the fists")


func test_driving_hides_the_cabin_but_not_the_arms() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	assert_gt(body.cabin.size(), 0)
	body.hide_cabin_from_driver(PlayerBody.CABIN_P1, true)
	assert_eq(body.cabin[0].layers, PlayerBody.CABIN_P1)
	var arm_mesh := body.arms[0].get_child(0) as MeshInstance3D
	assert_eq(arm_mesh.layers, PlayerBody.WORLD_LAYER, "hands stay in the driver's own view")
	body.hide_cabin_from_driver(PlayerBody.CABIN_P1, false)
	assert_eq(body.cabin[0].layers, PlayerBody.WORLD_LAYER)


func test_the_raygun_bob_is_mostly_up_and_down() -> void:
	var tallest := 0.0
	var widest := 0.0
	for step in 64:
		var offset := Raygun.bob_offset(TAU * step / 64.0, 1.0)
		tallest = maxf(tallest, absf(offset.y))
		widest = maxf(widest, absf(offset.x))
	assert_almost_eq(tallest, Raygun.BOB_HEIGHT, 0.001)
	assert_gt(tallest, widest, "the gun rides up and down, it does not wave side to side")


func test_the_raygun_only_bobs_when_the_player_is_moving() -> void:
	assert_eq(Raygun.bob_amount(0.0, 0.0), 0.0)
	assert_almost_eq(Raygun.bob_amount(1.0, 0.0), 1.0, 0.001)
	assert_eq(Raygun.bob_amount(1.0, Raygun.STEADY_LINGER), 0.0, "shooting overrides the run")


func test_the_raygun_holds_perfectly_still_while_shooting() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	for _frame in 30:
		gun.animate(STEP, 1.0, false)
	assert_gt(gun.position.distance_to(Raygun.REST), 0.005, "running should move the gun")
	assert_false(gun.is_steady())
	for _frame in 30:
		gun.animate(STEP, 1.0, true)
	assert_true(gun.is_steady())
	assert_almost_eq(gun.position.distance_to(Raygun.REST), 0.0, 0.0001)
	assert_almost_eq(gun.rotation.z, 0.0, 0.0001)
	gun.animate(STEP, 1.0, true)
	assert_almost_eq(
		gun.position.distance_to(Raygun.REST), 0.0, 0.0001,
		"a sprinting player firing on the move still shoots from a fixed gun"
	)


func test_the_gun_settles_and_picks_up_smoothly_rather_than_snapping() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	var previous := gun.position
	var worst := 0.0
	for frame in 120:
		# Sprinting the whole time, with the trigger held for the middle third.
		gun.animate(STEP, 1.0, frame > 40 and frame < 80)
		worst = maxf(worst, previous.distance_to(gun.position))
		previous = gun.position
	assert_lt(worst, 0.02, "neither the lock nor the release should teleport the gun")


func test_the_shotgun_is_a_longer_double_barrel() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	assert_false(gun.is_shotgun())
	var rifle_reach := gun.forward_extent()
	gun.use_shotgun(true)
	assert_true(gun.is_shotgun())
	assert_lt(gun.forward_extent(), rifle_reach, "the shotgun barrels should stick out further")


func test_the_rocket_launcher_is_its_own_mesh() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	assert_false(gun.is_rocket())
	gun.show_gun("rocket")
	assert_true(gun.is_rocket())
	assert_false(gun.is_shotgun())
	assert_lt(gun.forward_extent(), -0.2, "the tube should stick out past the rifle")


func test_the_sniper_is_a_long_scoped_rifle() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	assert_false(gun.is_sniper())
	var rifle_reach := gun.forward_extent()
	gun.show_gun("sniper")
	assert_true(gun.is_sniper())
	assert_false(gun.is_shotgun())
	assert_false(gun.is_rocket())
	assert_false(gun.is_net())
	assert_lt(gun.forward_extent(), rifle_reach, "the sniper barrel should stick out further")


func test_the_net_launcher_is_its_own_mesh() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	assert_false(gun.is_net())
	gun.show_gun("net")
	assert_true(gun.is_net())
	assert_false(gun.is_rocket())
	assert_false(gun.is_shotgun())
	assert_lt(gun.forward_extent(), -0.2, "the hoop should stick out past the rifle")


func test_the_flare_driver_is_its_own_mesh() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	assert_false(gun.is_flare())
	gun.show_gun("flare")
	assert_true(gun.is_flare())
	assert_false(gun.is_nailer())
	assert_false(gun.is_shotgun())
	assert_lt(gun.forward_extent(), -0.2, "the glowing tip should stick out")


func test_the_cart_nailer_is_its_own_mesh() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	assert_false(gun.is_nailer())
	gun.show_gun("nailer")
	assert_true(gun.is_nailer())
	assert_false(gun.is_flare())
	assert_false(gun.is_rocket())
	assert_lt(gun.forward_extent(), -0.2, "the spike barrel should stick out")


func test_the_warp_door_gun_is_its_own_mesh() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	assert_false(gun.is_door())
	gun.show_gun("door")
	assert_true(gun.is_door())
	assert_false(gun.is_nailer())
	assert_false(gun.is_rocket())
	assert_lt(gun.forward_extent(), -0.2, "the door frame should stick out")


func test_a_shotgun_kick_throws_the_gun_back_then_recovers() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.kick(1.0)
	gun.animate(STEP, 0.0, true)
	assert_gt(gun.position.z, Raygun.REST.z, "kick throws the stock toward the camera")
	assert_lt(gun.rotation.x, 0.0, "the muzzle climbs")
	for _frame in 90:
		gun.animate(STEP, 0.0, false)
	assert_almost_eq(gun.position.z, Raygun.REST.z, 0.002)
	assert_almost_eq(gun.rotation.x, 0.0, 0.002)


func test_the_rifle_does_not_kick() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.kick(0.0)
	gun.animate(STEP, 0.0, true)
	assert_almost_eq(gun.position.distance_to(Raygun.REST), 0.0, 0.0001)


func test_a_reload_raises_then_settles_the_gun() -> void:
	assert_eq(Raygun.reload_envelope(0.0), 0.0)
	assert_eq(Raygun.reload_envelope(1.0), 0.0)
	assert_almost_eq(Raygun.reload_envelope(0.5), 1.0, 0.001)
	var mid := Raygun.reload_offset(0.5)
	assert_gt(mid.y, 0.04, "the gun comes up off the hip")
	assert_gt(mid.z, 0.0, "and a little closer to the camera")
	assert_eq(Raygun.reload_offset(0.0), Vector3.ZERO)
	assert_eq(Raygun.reload_offset(1.0), Vector3.ZERO)


func test_a_reload_wiggles_the_gun_while_it_is_up() -> void:
	var early := Raygun.reload_offset(0.35)
	var later := Raygun.reload_offset(0.55)
	assert_gt(early.distance_to(later), 0.008, "the mag work should move the gun around")
	assert_gt(early.y, 0.04)
	assert_gt(later.y, 0.04)
	var spin := Raygun.reload_rotation(0.4)
	assert_lt(spin.x, 0.0, "the muzzle climbs the way a kick does")
	assert_gt(absf(spin.y) + absf(spin.z), 0.02, "yaw and roll keep it from sitting still")


func test_reloading_lifts_the_held_gun_whether_rifle_or_shotgun() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.build(Palette.PLAYER_ONE)
	gun.animate(STEP, 0.0, false, 0.45)
	assert_gt(gun.position.y, Raygun.REST.y)
	assert_lt(gun.rotation.x, 0.0)
	var rifle_pose := gun.position
	gun.use_shotgun(true)
	gun.animate(STEP, 0.0, false, 0.45)
	assert_almost_eq(gun.position.distance_to(rifle_pose), 0.0, 0.0001, "same motion on both guns")
	gun.animate(STEP, 0.0, false, 0.0)
	assert_almost_eq(gun.position.distance_to(Raygun.REST), 0.0, 0.0001)
	assert_almost_eq(gun.rotation.x, 0.0, 0.0001)
	assert_almost_eq(gun.rotation.y, 0.0, 0.0001)


func test_a_melee_swing_starts_wound_up_and_finishes_at_rest() -> void:
	var start := Raygun.melee_offset(0.0)
	assert_gt(start.x, 0.1, "the club is pulled back to the right")
	assert_gt(start.y, 0.05, "and up over the shoulder")
	assert_eq(Raygun.melee_offset(1.0), Vector3.ZERO)
	assert_eq(Raygun.melee_euler_deg(1.0), Vector3.ZERO)
	assert_almost_eq(Melee.swing_weight(0.0), 1.0, 0.001)
	assert_almost_eq(Melee.swing_weight(Melee.FOLLOW_T), 1.0, 0.001)
	assert_almost_eq(Melee.swing_weight(1.0), 0.0, 0.001)


func test_the_melee_strike_drops_through_the_middle() -> void:
	var windup := Raygun.melee_offset(0.0)
	var hit := Raygun.melee_offset(Melee.CONTACT_T)
	var follow := Raygun.melee_offset(Melee.FOLLOW_T)
	assert_lt(hit.y, windup.y, "the strike is a downward blow")
	assert_lt(hit.z, windup.z, "and it reaches forward into the target")
	assert_lt(follow.x, hit.x, "follow-through carries across to the left")


func test_the_gun_swings_then_returns_when_melee_starts() -> void:
	var gun := Raygun.new()
	add_child_autofree(gun)
	gun.start_melee()
	assert_true(gun.is_meleeing())
	gun.animate(STEP, 0.0, false)
	assert_gt(gun.position.distance_to(Raygun.REST), 0.05, "the first frame has to leave rest")
	var previous := gun.position
	var worst := 0.0
	for _frame in 40:
		gun.animate(STEP, 0.0, false)
		worst = maxf(worst, previous.distance_to(gun.position))
		previous = gun.position
	assert_lt(worst, 0.12, "the club should sweep, not teleport")
	assert_false(gun.is_meleeing())
	assert_almost_eq(gun.position.distance_to(Raygun.REST), 0.0, 0.002)
	assert_almost_eq(gun.rotation.x, 0.0, 0.002)
	assert_almost_eq(gun.rotation.y, 0.0, 0.002)


func test_a_robot_throws_its_arms_through_a_melee_swing() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.pose(0.0)
	var rest_free := body.arms[PlayerBody.FREE_ARM].rotation.x
	var rest_gun := body.arms[PlayerBody.GUN_ARM].rotation.x
	body.start_melee()
	assert_true(body.is_meleeing())
	body.pose(0.0)
	body.tick_melee(Melee.SWING_TIME * Melee.CONTACT_T)
	assert_gt(
		absf(body.arms[PlayerBody.FREE_ARM].rotation.x - rest_free), 0.4,
		"the free arm has to leave the idle"
	)
	assert_gt(
		absf(body.arms[PlayerBody.GUN_ARM].rotation.x - rest_gun), 0.4,
		"and the gun arm chops with it"
	)
	assert_ne(body.torso.rotation.y, 0.0, "the chest twists into the hit")
	for _frame in 30:
		body.pose(0.0)
		body.tick_melee(STEP)
	assert_false(body.is_meleeing())
	assert_almost_eq(body.arms[PlayerBody.FREE_ARM].rotation.x, rest_free, 0.002)
	assert_almost_eq(body.torso.rotation.y, 0.0, 0.002)


func test_a_swimming_robot_leans_and_kicks() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.pose(0.0)
	body.swim(STEP, 1.0, false)
	assert_lt(body.torso.rotation.x, 0.0, "treading still leans into the stroke")
	var surface_lean := body.torso.rotation.x
	body.swim(STEP, 1.0, true)
	assert_lt(body.torso.rotation.x, surface_lean, "diving stretches out further")
	assert_ne(body.legs[0].rotation.x, 0.0, "the legs have to kick")


func test_a_player_snaps_to_the_floor_instead_of_sinking() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	assert_almost_eq(player.floor_snap_length, Player.FLOOR_SNAP, 0.001)
	assert_almost_eq(player.floor_max_angle, deg_to_rad(Player.FLOOR_MAX_DEG), 0.001)
	assert_almost_eq(player.safe_margin, Player.SAFE_MARGIN, 0.001)
	assert_gt(player.floor_max_angle, deg_to_rad(50.0), "mounds must count as floor, not walls")


func test_riding_turns_the_capsule_off() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	assert_eq(player.collision_layer, Layers.PLAYER)
	player.enter_ride()
	assert_eq(player.collision_layer, 0, "a seated body cannot wedge into the cart")
	assert_eq(player.collision_mask, 0)
	player.exit_ride()
	assert_eq(player.collision_layer, Layers.PLAYER)
	assert_eq(player.collision_mask, Layers.PLAYER_MASK)


func test_golfing_does_not_slide_the_stance() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	player.stand_at(Vector3(2.0, 1.0, -3.0), 0.0)
	player.enter_golf_mode()
	player.velocity = Vector3(4.0, -2.0, 1.0)
	player._move(1.0 / 60.0)
	assert_eq(player.global_position, Vector3(2.0, 1.0, -3.0), "address is planted")
	assert_eq(player.velocity, Vector3(4.0, -2.0, 1.0), "physics does not eat the stance")


func test_a_hit_flash_paints_every_piece_of_the_robot() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	var flash := MeshFactory.material(Color(1.0, 0.12, 0.08), false, Palette.GLOW_STRONG)
	body.set_flash(flash)
	var painted := 0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			assert_eq(mesh.material_overlay, flash)
			painted += 1
	assert_gt(painted, 8, "the whole robot has to light up, not one piece")
	body.set_flash(null)
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			assert_eq(mesh.material_overlay, null)

