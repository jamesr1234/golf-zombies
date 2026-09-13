extends GutTest
## Parked suit seals, takes eight enemy rockets, stomps foes, and does not open.

const PLAYER := preload("res://scenes/players/player.tscn")
const MECH := preload("res://scenes/course/items/mech_suit.tscn")

var suit: MechSuit
var pilot: Player
var foe: Player


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	suit = MECH.instantiate()
	add_child_autofree(suit)
	pilot = PLAYER.instantiate()
	add_child_autofree(pilot)
	foe = PLAYER.instantiate()
	add_child_autofree(foe)
	await wait_physics_frames(2)
	suit.global_position = Vector3.ZERO
	pilot.global_position = suit.get_node("Cockpit").global_position
	foe.global_position = Vector3(8.0, 0.0, 0.0)
	suit.bind_owner(pilot)


func after_each() -> void:
	NetSession.close()
	NetSession.seats.clear()


func test_the_suit_is_built_of_neon_parts() -> void:
	var visuals := suit.get_node_or_null("Visuals") as Node3D
	assert_not_null(visuals, "MechVisuals.build is attached in _ready")
	assert_not_null(visuals.find_child("Hatch", true, false))
	assert_null(visuals.get_node_or_null("Stairs"), "boarding is from the ground")
	assert_null(suit.get_node_or_null("StairRamp"))
	assert_not_null(visuals.find_child("LeftArm", true, false))
	assert_not_null(visuals.find_child("RightArm", true, false))
	assert_not_null(visuals.find_child("Chassis", true, false), "blender plates ride the godot rig")
	assert_not_null(visuals.find_child("LeftPod", true, false))
	assert_not_null(visuals.find_child("RightPod", true, false))
	var meshes := suit.find_children("*", "MeshInstance3D", true, false)
	assert_gte(meshes.size(), 25, "plates, arms, vents")
	var hatch := visuals.find_child("Hatch", true, false) as Node3D
	assert_lt(hatch.rotation.x, deg_to_rad(-45.0), "parked hatch starts open")
	suit.try_close(pilot)
	assert_gt(hatch.rotation.x, deg_to_rad(-20.0), "sealing folds the hatch")
	var hull := visuals.find_child("Chassis", true, false) as MeshInstance3D
	assert_eq(hull.layers & MechVisuals.BODY_LAYER, MechVisuals.BODY_LAYER)
	var mat := hull.get_active_material(0) as StandardMaterial3D
	assert_not_null(mat)
	assert_lte(mat.emission_energy_multiplier, Palette.GLOW_SOFT)


func test_the_pilot_sits_behind_the_helmet() -> void:
	var eye := suit.get_node("PilotView") as Node3D
	var visor := suit.find_child("Visor", true, false) as Node3D
	var head := suit.find_child("Head", true, false) as Node3D
	assert_not_null(eye)
	assert_not_null(visor)
	assert_gt(eye.position.z, 1.0, "behind the body so the swinging arms stay on camera")
	assert_gt(eye.global_position.z, visor.global_position.z)
	if head != null:
		assert_gt(eye.global_position.y, head.global_position.y, "looks over the helmet")


func test_l1_does_not_pull_a_chase_cam() -> void:
	suit.try_close(pilot)
	pilot.look.cart_chase = true
	var view := pilot.look.view_transform(pilot)
	var cockpit := suit.pilot_view_transform(0.0)
	assert_almost_eq(view.origin.x, cockpit.origin.x, 0.05)
	assert_almost_eq(view.origin.z, cockpit.origin.z, 0.05, "L1 no longer pops the chase cam")


func test_l2_scopes_past_the_visor() -> void:
	suit.try_close(pilot)
	var cockpit := suit.pilot_view_transform(0.0)
	var scoped := suit.scope_view_transform(0.0)
	assert_lt(scoped.origin.z, cockpit.origin.z, "ADS sits in front of the helmet")
	pilot.aiming = true
	var view := pilot.look.view_transform(pilot)
	assert_almost_eq(view.origin.z, scoped.origin.z, 0.05)
	assert_eq(pilot.view_cull_mask() & MechVisuals.BODY_LAYER, 0, "the suit drops out of the visor")
	pilot.aiming = false
	assert_ne(pilot.view_cull_mask() & MechVisuals.BODY_LAYER, 0)


func test_the_suit_is_a_quarter_of_the_old_giant() -> void:
	assert_almost_eq(MechVisuals.SCALE, 1.0, 0.001)
	var hull := suit.get_node("Hull") as CollisionShape3D
	var box := hull.shape as BoxShape3D
	assert_almost_eq(box.size.y, 3.8, 0.05)
	assert_lt(MechVisuals.HEIGHT, 6.0)


func test_a_stride_swings_the_arms_opposite_the_legs() -> void:
	var body := suit.get_node("Visuals") as MechVisuals
	body.stride(0.0, 0.0, true, true)
	var arm_back: float = body.arms[0].rotation.x
	var leg_back: float = body.legs[0].rotation.x
	body.stride(0.0, 1.0, true, true)
	assert_gt(absf(body.arms[0].rotation.x - arm_back), deg_to_rad(90.0))
	assert_gt(absf(body.legs[0].rotation.x - leg_back), deg_to_rad(80.0))
	assert_almost_eq(body.arms[0].rotation.x, body.legs[1].rotation.x, 0.2)
	assert_ne(signf(body.arms[0].rotation.x), signf(body.legs[0].rotation.x))


func test_a_stopped_suit_stands_upright() -> void:
	var body := suit.get_node("Visuals") as MechVisuals
	body.stride(0.0, 1.0, true, true)
	assert_ne(body.legs[0].rotation.x, 0.0)
	body.stride(1.0, 1.0, true, false)
	assert_almost_eq(body.legs[0].rotation.x, 0.0, 0.05)
	assert_almost_eq(body.arms[0].rotation.x, 0.0, 0.05)
	assert_almost_eq(body.torso.rotation.x, 0.0, 0.05)
	assert_almost_eq(body.torso.rotation.y, 0.0, 0.05)


func test_a_tap_walks_one_step_distance() -> void:
	suit.try_close(pilot)
	suit.step_distance = 2.5
	var start := suit.global_position
	assert_true(suit.try_step(Vector2(0.0, -1.0)))
	assert_true(suit.is_stepping())
	for _i in 40:
		suit._physics_process(1.0 / 60.0)
	var moved := Vector2(
		suit.global_position.x - start.x, suit.global_position.z - start.z
	).length()
	assert_almost_eq(moved, 2.5, 0.4, "one tap is one locked stride")
	assert_false(suit.is_stepping(), "the suit plants instead of gliding on")


func test_step_distance_is_tunable() -> void:
	assert_gt(suit.step_distance, 0.0)
	suit.try_close(pilot)
	suit.step_distance = 4.0
	assert_true(suit.try_step(Vector2(0.0, -1.0)))
	assert_almost_eq(suit.global_position.distance_to(suit._step_to), 4.0, 0.05)


func test_a_player_on_the_ground_can_seal_the_suit() -> void:
	pilot.global_position = suit.global_position + Vector3(2.0, 0.9, 0.0)
	assert_true(suit.can_close(pilot), "walk up and board, no stair")
	suit.try_close(pilot)
	assert_true(suit.closed)
	assert_true(pilot.is_in_mech())


func test_circle_in_the_cockpit_seals_the_suit() -> void:
	assert_false(suit.closed)
	assert_true(suit.can_close(pilot))
	suit.try_close(pilot)
	assert_true(suit.closed)
	assert_eq(suit.pilot, pilot)
	assert_true(pilot.is_in_mech())
	assert_false(suit.can_close(pilot), "already sealed")


func test_eight_enemy_rockets_wreck_it_and_eject_alive() -> void:
	suit.try_close(pilot)
	for _i in MechSuit.MAX_HP - 1:
		suit.take_rocket(foe)
		assert_true(is_instance_valid(suit))
	assert_eq(suit.hp, 1)
	assert_true(pilot.health.is_alive())
	suit.take_rocket(foe)
	await wait_physics_frames(1)
	assert_false(is_instance_valid(suit))
	assert_true(pilot.health.is_alive())
	assert_false(pilot.is_in_mech())


func test_friendly_rockets_do_nothing() -> void:
	suit.try_close(pilot)
	suit.take_rocket(pilot)
	assert_eq(suit.hp, MechSuit.MAX_HP)
	var partner := PLAYER.instantiate()
	add_child_autofree(partner)
	pilot.partner = partner
	partner.partner = pilot
	suit.take_rocket(partner)
	assert_eq(suit.hp, MechSuit.MAX_HP)


func test_shoulders_alternate_and_the_mag_holds_eight() -> void:
	var combat := MechCombat.new()
	assert_eq(combat.mag, 8)
	var view := Transform3D.IDENTITY
	assert_true(combat.try_fire(suit, view, foe))
	assert_eq(combat.mag, 7)
	assert_true(combat.next_right)
	combat.cooldown = 0.0
	assert_true(combat.try_fire(suit, view, foe))
	assert_false(combat.next_right)
	combat.mag = 0
	assert_true(combat.try_reload())
	combat.tick(MechCombat.RELOAD)
	assert_eq(combat.mag, 8)


func test_the_eighth_shot_reloads_and_shells_never_run_out() -> void:
	var combat := MechCombat.new()
	var view := Transform3D.IDENTITY
	for _i in MechCombat.MAG_SIZE:
		combat.cooldown = 0.0
		assert_true(combat.try_fire(suit, view, foe))
	assert_eq(combat.mag, 0)
	assert_true(combat.is_reloading())
	assert_false(combat.try_fire(suit, view, foe), "empty until the mag is back")
	combat.tick(MechCombat.RELOAD)
	assert_eq(combat.mag, MechCombat.MAG_SIZE)
	assert_true(combat.try_fire(suit, view, foe))
	assert_eq(combat.mag, MechCombat.MAG_SIZE - 1)


func test_l1_strafes_left_and_glows_on_the_right() -> void:
	suit.try_close(pilot)
	var pad := CpuInput.new(pilot.input_prefix, false)
	pilot.input = pad
	pad.hold("melee")
	var stick := suit._stick()
	assert_lt(stick.x, -0.9, "L1 is a left strafe")
	assert_almost_eq(stick.y, 0.0, 0.01)
	suit._tick_visuals(0.0)
	assert_true(_strafe_glow("RightStrafeGlow").visible)
	assert_false(_strafe_glow("LeftStrafeGlow").visible)


func test_r1_strafes_right_and_glows_on_the_left() -> void:
	suit.try_close(pilot)
	var pad := CpuInput.new(pilot.input_prefix, false)
	pilot.input = pad
	pad.hold("shield")
	var stick := suit._stick()
	assert_gt(stick.x, 0.9, "R1 is a right strafe")
	suit._tick_visuals(0.0)
	assert_true(_strafe_glow("LeftStrafeGlow").visible)
	assert_false(_strafe_glow("RightStrafeGlow").visible)


func test_stick_sidestep_does_not_light_the_strafe_glow() -> void:
	suit.try_close(pilot)
	var pad := CpuInput.new(pilot.input_prefix, false)
	pilot.input = pad
	pad.move = Vector2(-1.0, 0.0)
	var stick := suit._stick()
	assert_lt(stick.x, -0.9)
	assert_almost_eq(suit.sync_strafe, 0.0, 0.01)
	suit._tick_visuals(0.0)
	assert_false(_strafe_glow("LeftStrafeGlow").visible)
	assert_false(_strafe_glow("RightStrafeGlow").visible)


func _strafe_glow(node_name: String) -> Node3D:
	return suit.get_node("Visuals").get_node(node_name) as Node3D


func test_shoulder_rockets_meet_the_crosshair() -> void:
	var view := Transform3D(Basis.IDENTITY, Vector3(0.0, 4.0, 0.0))
	var origin := Vector3(-4.5, 3.7, 0.2)
	var aim := MechCombat.look_point(view, 40.0)
	var fly := MechCombat.fly_to_crosshair(origin, view, aim)
	assert_gt(fly.x, 0.05, "left pod has to fly inward")
	var end := origin + fly * origin.distance_to(aim)
	assert_almost_eq(end.x, aim.x, 0.02)
	assert_almost_eq(end.y, aim.y, 0.02)
	assert_almost_eq(end.z, aim.z, 0.02)


func test_stomp_hits_a_foe_not_the_pilot() -> void:
	suit.try_close(pilot)
	suit.velocity = Vector3(0.0, 0.0, -6.0)
	var area := Area3D.new()
	add_child_autofree(area)
	# Direct call with overlapping skipped: unit the ally filter.
	assert_true(suit.allies().has(pilot))
	assert_false(suit.is_foe(pilot))
	assert_true(suit.is_foe(foe))


func test_closed_sync_folds_the_hatch_for_watchers() -> void:
	var hatch := suit.find_child("Hatch", true, false) as Node3D
	assert_lt(hatch.rotation.x, deg_to_rad(-45.0))
	suit.closed = true
	suit._tick_visuals(0.0)
	assert_gt(hatch.rotation.x, deg_to_rad(-20.0), "the replicated closed flag folds the hatch")


func test_a_parked_suit_still_publishes_its_pose() -> void:
	suit.global_position = Vector3(12.0, 0.4, -8.0)
	suit.rotation.y = deg_to_rad(40.0)
	await wait_physics_frames(1)
	assert_false(suit.closed)
	assert_almost_eq(suit.sync_xform.origin.x, 12.0, 0.05)
	assert_almost_eq(suit.sync_xform.origin.z, -8.0, 0.05)


func test_a_watched_suit_does_not_scrape_the_ground() -> void:
	NetSession._active = true
	suit.set_multiplayer_authority(99)
	suit._park_if_watched()
	assert_eq(suit.collision_mask, 0, "a drawing must not fight the heightmap")


func test_a_watched_suit_glides_to_the_replicated_pose() -> void:
	NetSession._active = true
	suit.set_multiplayer_authority(99)
	suit._park_if_watched()
	suit.global_position = Vector3.ZERO
	suit.sync_xform = Transform3D(Basis(), Vector3(20.0, 0.0, -6.0))
	suit._process(0.05)
	assert_gt(
		suit.global_position.distance_to(Vector3.ZERO), 8.0,
		"the replicated pose is drawn on the render frame, not left at spawn"
	)


func test_a_wire_update_seals_and_moves_the_suit() -> void:
	NetSession._active = true
	suit.set_multiplayer_authority(99)
	suit._park_if_watched()
	suit.take_wire(
		Transform3D(Basis(), Vector3(16.0, 0.4, -10.0)),
		Vector2(0.0, -1.0),
		false,
		true,
		0
	)
	suit._process(0.05)
	assert_true(suit.closed)
	assert_gt(suit.global_position.distance_to(Vector3.ZERO), 8.0)


func test_find_net_prefers_the_owner() -> void:
	var other: MechSuit = MECH.instantiate()
	add_child_autofree(other)
	other.owner_peer = 7
	suit.owner_peer = 1
	assert_eq(MechSuit.find_net(get_tree(), 1), suit)
	assert_eq(MechSuit.find_net(get_tree(), 7), other)


func test_a_hole_pad_plants_an_open_suit() -> void:
	var hole := HoleData.new()
	hole.mech_pad = Vector3(8.0, 0.4, -3.0)
	hole.mech_yaw = 40.0
	var planted := MechSuit.plant_on_hole(suit.get_parent(), hole)
	assert_eq(planted, suit, "an existing suit is the hole's suit")
	var empty := Node3D.new()
	add_child_autofree(empty)
	suit.remove_from_group("mechs")
	var fresh := MechSuit.plant_on_hole(empty, hole)
	assert_not_null(fresh)
	assert_ne(fresh, suit)
	assert_almost_eq(fresh.global_position.x, hole.mech_stand().x, 0.1)
	assert_almost_eq(fresh.global_position.z, hole.mech_stand().z, 0.1)
	assert_almost_eq(
		fresh.global_position.y, hole.mech_stand().y + MechSuit.STAND_LIFT, 0.05,
		"soles sit above the turf"
	)
	assert_false(fresh.closed)


func test_a_remote_pilot_report_drives_the_suit() -> void:
	suit.apply_pilot_report(Vector2(1.0, -0.5), true, 45.0, -12.0, true)
	assert_eq(suit.sync_stick, Vector2(1.0, -0.5))
	assert_true(suit.sync_sprint)
	assert_eq(suit.sync_pitch, -12.0)
	assert_eq(suit.sync_jumps, 1)
	suit.apply_pilot_report(Vector2.ZERO, false, 0.0, 0.0, true)
	assert_eq(suit.sync_jumps, 2)


func test_a_suit_it_already_simulates_is_never_predicted() -> void:
	suit.try_close(pilot)
	assert_false(suit.predicts_locally(), "the host already walks it")


func test_a_watched_empty_suit_is_not_predicted() -> void:
	NetSession._active = true
	suit.set_multiplayer_authority(99)
	assert_false(suit.predicts_locally(), "with no one at the stick there is nothing to predict")


func test_the_local_pilot_predicts_the_suit() -> void:
	suit.try_close(pilot)
	NetSession._active = true
	suit.set_multiplayer_authority(99)
	pilot.net_driven = true
	pilot.peer_id = 1
	assert_true(suit.predicts_locally(), "Computer 2 drives from the stick, not a late pose")
	suit._park_if_watched()
	suit._physics_process(0.05)
	assert_eq(suit.collision_mask, Layers.VEHICLE_MASK, "a predicted suit has to meet the ground")
