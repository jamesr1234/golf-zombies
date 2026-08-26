extends GutTest
## Warp Door plants a doorway that stands you next to your ball.

const PLAYER := preload("res://scenes/players/player.tscn")
const DOOR: WeaponStats = preload("res://resources/weapons/warp_door.tres")


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)


func after_each() -> void:
	for group in ["door_shots", "warp_doors"]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()


func test_the_warp_door_is_a_projectile_not_a_net_or_blast() -> void:
	assert_true(DOOR.is_door())
	assert_false(DOOR.is_net())
	assert_false(DOOR.is_explosive())
	assert_gt(DOOR.door_duration, 10.0)
	assert_eq(DOOR.visual, "door")
	assert_false(DOOR.automatic)
	assert_eq(DOOR.mag_size, 2)


func test_the_shot_only_flies_for_a_fifth_of_a_second() -> void:
	assert_almost_eq(DoorShot.FLIGHT_TIME, 0.2, 0.001)
	assert_almost_eq(DoorShot.flight_distance(), DoorShot.SPEED * 0.2, 0.001)
	var shot := DoorShot.spawn_flight(self, Vector3.ZERO, Vector3.FORWARD, 20.0)
	assert_not_null(shot)
	shot._physics_process(0.1)
	assert_false(shot._dead, "still in the air at 0.1s")
	assert_eq(get_tree().get_nodes_in_group("warp_doors").size(), 0)
	shot._physics_process(0.1)
	assert_true(shot._dead, "the door has to appear at 0.2s")
	await wait_physics_frames(1)
	assert_eq(get_tree().get_nodes_in_group("door_shots").size(), 0)
	assert_eq(get_tree().get_nodes_in_group("warp_doors").size(), 1)


func test_a_floor_hit_plants_the_door_on_its_feet() -> void:
	var at := Vector3(3.0, 1.2, -4.0)
	var planted := WarpDoor.plant_point(at, Vector3.UP)
	assert_almost_eq(planted.y, at.y, 0.001)
	var face := WarpDoor.facing_from_hit(Vector3.UP, Vector3(0.0, -0.2, 1.0))
	assert_almost_eq(face.y, 0.0, 0.001)
	assert_lt(face.z, 0.0, "a floor door faces the shooter")


func test_a_wall_hit_centres_the_door_on_the_impact() -> void:
	var at := Vector3(0.0, 1.6, -8.0)
	var planted := WarpDoor.plant_point(at, Vector3.BACK)
	assert_almost_eq(planted.y, at.y - WarpDoor.HEIGHT * 0.5, 0.001)
	var face := WarpDoor.facing_from_hit(Vector3.BACK, Vector3.FORWARD)
	assert_almost_eq(face.z, 1.0, 0.001)


func test_stand_point_puts_you_beside_the_ball_facing_it() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.global_position = Vector3(10.0, GolfBall.RADIUS, 0.0)
	var from := Vector3.ZERO
	var at := WarpDoor.stand_point(ball, from)
	assert_almost_eq(at.y, 0.0, 0.001)
	assert_almost_eq(at.distance_to(Vector3(ball.global_position.x, 0.0, 0.0)), WarpDoor.STAND_GAP, 0.05)
	assert_lt(at.x, ball.global_position.x, "stand on the side you came from")
	var yaw := WarpDoor.face_yaw(at, ball.global_position)
	assert_almost_eq(yaw, -90.0, 0.5)


func test_walking_through_warps_you_to_your_ball() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	player.global_position = Vector3(0.0, 0.0, 8.0)
	var golf := GolfController.new()
	add_child_autofree(golf)
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.global_position = Vector3(12.0, GolfBall.RADIUS, 0.0)
	golf.ball = ball
	player.golf = golf
	var door := WarpDoor.spawn_facing(self, Vector3(0.0, 0.0, 6.0), Vector3.FORWARD, 20.0)
	door._arm = 0.0
	assert_true(WarpDoor.can_warp(player))
	assert_true(door.try_warp(player))
	assert_almost_eq(
		player.global_position.distance_to(WarpDoor.stand_point(ball, Vector3(0.0, 0.0, 8.0))),
		0.0, 0.05
	)
	assert_almost_eq(player.look_yaw(), WarpDoor.face_yaw(player.global_position, ball.global_position), 0.5)


func test_a_missing_or_holed_ball_does_not_warp() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	assert_false(WarpDoor.can_warp(player))
	var golf := GolfController.new()
	add_child_autofree(golf)
	var ball := GolfBall.new()
	add_child_autofree(ball)
	golf.ball = ball
	player.golf = golf
	ball._holed = true
	assert_false(WarpDoor.can_warp(player))


func test_a_second_shot_replaces_the_old_door() -> void:
	var first := WarpDoor.spawn_facing(self, Vector3.ZERO, Vector3.FORWARD, 20.0, 3)
	var second := WarpDoor.spawn_facing(self, Vector3(4.0, 0.0, 0.0), Vector3.FORWARD, 20.0, 3)
	await wait_physics_frames(1)
	assert_false(is_instance_valid(first), "one door per shooter")
	assert_true(is_instance_valid(second))
	assert_eq(get_tree().get_nodes_in_group("warp_doors").size(), 1)


func test_firing_the_warp_door_spends_a_round_and_spawns_a_shot() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	gun.index = gun.loadout.find(DOOR)
	assert_eq(gun.stats(), DOOR)
	var before := get_tree().get_nodes_in_group("door_shots").size()
	gun.tick(0.0, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), DOOR.mag_size - 1)
	assert_eq(get_tree().get_nodes_in_group("door_shots").size(), before + 1)
	assert_eq(Sfx.last_cue, "door_fire")
