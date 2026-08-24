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
	assert_not_null(visuals.get_node_or_null("Stairs"))
	assert_not_null(visuals.find_child("LeftArm", true, false))
	assert_not_null(visuals.find_child("RightArm", true, false))
	assert_gte(visuals.get_node("Stairs").get_child_count(), 16, "a run of steps plus the balcony")
	var meshes := suit.find_children("*", "MeshInstance3D", true, false)
	assert_gte(meshes.size(), 40, "plates, arms, vents and a walkable stair")
	var hatch := visuals.find_child("Hatch", true, false) as Node3D
	assert_lt(hatch.rotation.x, deg_to_rad(-45.0), "parked hatch starts open")
	assert_true(visuals.get_node("Stairs").visible)
	suit.try_close(pilot)
	assert_gt(hatch.rotation.x, deg_to_rad(-20.0), "sealing folds the hatch")
	assert_false(visuals.get_node("Stairs").visible, "the stair drops away once you are in")
	assert_true((suit.get_node("StairRamp") as CollisionShape3D).disabled)


func test_the_pilot_looks_out_past_the_visor() -> void:
	var eye := suit.get_node("PilotView") as Node3D
	var visor := suit.find_child("Visor", true, false) as Node3D
	assert_not_null(eye)
	assert_not_null(visor)
	for child in visor.get_children():
		var mesh := child as Node3D
		assert_lt(eye.position.z, mesh.position.z, "camera sits in front of the visor rim")


func test_l1_pulls_a_chase_cam_behind_the_suit() -> void:
	var chase := suit.chase_view_transform()
	assert_gt(chase.origin.y, 8.0)
	assert_gt(chase.origin.z, 10.0, "yaw 0 faces -Z, so chase sits on +Z")


func test_a_stride_swings_the_arms_opposite_the_legs() -> void:
	var body := suit.get_node("Visuals") as MechVisuals
	body.pose(0.0)
	var arm_rest: float = body.arms[0].rotation.x
	var leg_rest: float = body.legs[0].rotation.x
	body.animate(0.2, 1.0)
	assert_ne(body.arms[0].rotation.x, arm_rest)
	assert_ne(body.legs[0].rotation.x, leg_rest)
	assert_almost_eq(body.arms[0].rotation.x, body.legs[1].rotation.x, 0.2)
	assert_ne(signf(body.arms[0].rotation.x), signf(body.legs[0].rotation.x))


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
	assert_false(suit.get_node("Visuals").get_node("Stairs").visible)


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


func test_a_wire_update_folds_the_stair_and_moves_the_suit() -> void:
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
	suit._tick_visuals(0.0)
	suit._process(0.05)
	assert_true(suit.closed)
	assert_false(suit.get_node("Visuals").get_node("Stairs").visible)
	assert_gt(suit.global_position.distance_to(Vector3.ZERO), 8.0)


func test_a_remote_pilot_report_drives_the_suit() -> void:
	suit.apply_pilot_report(Vector2(1.0, -0.5), true, 45.0, -12.0, true)
	assert_eq(suit.sync_stick, Vector2(1.0, -0.5))
	assert_true(suit.sync_sprint)
	assert_eq(suit.sync_pitch, -12.0)
	assert_eq(suit.sync_jumps, 1)
	suit.apply_pilot_report(Vector2.ZERO, false, 0.0, 0.0, true)
	assert_eq(suit.sync_jumps, 2)
