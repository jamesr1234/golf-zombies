extends GutTest
## Gunners unlock after hole one, stay at range, and their bolts die on a shield.


const GUNNER := preload("res://resources/zombies/gunner.tres")
const WALKER := preload("res://resources/zombies/walker.tres")
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const _Shield := preload("res://scripts/player/shield.gd")
const _ZombieShot := preload("res://scripts/zombies/zombie_shot.gd")
const STEP := 1.0 / 60.0


func test_the_shield_is_twice_the_player_wide() -> void:
	assert_almost_eq(_Shield.covers_width(), _Shield.player_width() * 2.0, 0.001)
	assert_gt(_Shield.covers_width(), 1.5)


func test_the_shield_is_a_lit_outline() -> void:
	var shield: Node = _Shield.new()
	add_child_autofree(shield)
	await wait_physics_frames(1)
	var bars := 0
	for child in shield.find_children("*", "MeshInstance3D", true, false):
		var box := (child as MeshInstance3D).mesh as BoxMesh
		assert_not_null(box, "outline is built from bars")
		var size := box.size
		assert_true(size.x <= _Shield.FRAME * 1.5 or size.y <= _Shield.FRAME * 1.5)
		var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
		assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
		assert_gt(mat.emission_energy_multiplier, Palette.GLOW_MEDIUM)
		bars += 1
	assert_eq(bars, 4)
	assert_gt(shield.find_children("*", "OmniLight3D", true, false).size(), 0)


func test_friendly_fire_passes_through_the_panel() -> void:
	assert_eq(Layers.BULLET_MASK & Layers.SHIELD, 0)
	assert_gt(Layers.ENEMY_SHOT_MASK & Layers.SHIELD, 0)
	assert_gt(Layers.ENEMY_SHOT_MASK & Layers.PLAYER, 0)


func test_friendly_fire_passes_through_a_hex_fort() -> void:
	assert_eq(Layers.BULLET_MASK & Layers.FORT, 0)
	assert_eq(Layers.PLAYER_MASK & Layers.FORT, 0)
	assert_gt(Layers.ENEMY_SHOT_MASK & Layers.FORT, 0)
	assert_gt(Layers.ZOMBIE_MASK & Layers.FORT, 0)
	assert_gt(Layers.VEHICLE_MASK & Layers.FORT, 0)


func test_gunners_wait_until_after_the_first_hole() -> void:
	assert_eq(GUNNER.unlock_hole, 1)
	assert_true(GUNNER.ranged)
	assert_false(WALKER.ranged)
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_hole(0, [Vector3(80.0, 0.0, 0.0)])
	assert_false(director._type_allowed(GUNNER), "hole 1 is melee")
	director.begin_hole(1, [Vector3(80.0, 0.0, 0.0)])
	assert_true(director._type_allowed(GUNNER))


func test_the_cart_path_keeps_gunners_off_the_tarmac() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_transit(4, [Vector3(20.0, 0.0, 0.0)])
	assert_false(director._type_allowed(GUNNER))
	assert_true(director._type_allowed(WALKER))


func test_a_gunner_holds_range_instead_of_walking_into_melee() -> void:
	var toward := Vector3(0.0, 0.0, -20.0)
	assert_eq(Zombie.range_steer(GUNNER, toward, 40.0), toward.normalized())
	assert_eq(Zombie.range_steer(GUNNER, toward, 10.0), -toward.normalized())
	assert_eq(Zombie.range_steer(GUNNER, toward, 16.0), Vector3.ZERO)


func test_cover_camera_stands_behind_the_planted_robot() -> void:
	var origin := Vector3(5.0, 0.0, 10.0)
	var view := _Shield.view_transform(origin, 0.0, 0.0)
	assert_gt(view.origin.z, origin.z, "facing -Z, the camera sits on +Z")
	assert_gt(view.origin.y, origin.y + 1.4, "pulled up over the robot")
	assert_gt((-view.basis.z).dot(Vector3.FORWARD), 0.85, "looking the way the panel faces")


func test_cover_camera_orbits_when_the_player_turns() -> void:
	var view := _Shield.view_transform(Vector3.ZERO, 90.0, 0.0)
	assert_gt(view.origin.x, 1.0, "yaw 90 faces -X, so the camera is on +X")


func test_raising_the_shield_pops_to_third_person() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.stand_at(Vector3.ZERO, 0.0)
	var fps := player.get_view_transform()
	player.state = Player.State.SHIELDING
	var tps := player.get_view_transform()
	assert_gt(fps.origin.distance_to(tps.origin), 2.0, "the lens leaves the head")
	assert_gt(tps.origin.y, player.head.global_position.y)
	assert_eq(player.get_view_fov(), _Shield.CAM_FOV)
	player._animate(STEP)
	assert_false(player.raygun.visible)
	assert_ne(player.view_cull_mask() & player.cabin_layer(), 0, "the robot has to stay in frame")


func test_shielding_roots_the_feet_but_still_turns() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.input = CpuInput.new(player.input_prefix, false)
	player.state = Player.State.SHIELDING
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.move = Vector2(0.0, -1.0)
	player._move(STEP)
	assert_almost_eq(player.velocity.x, 0.0, 0.05)
	assert_almost_eq(player.velocity.z, 0.0, 0.05)
	pad.begin_frame()
	pad.look = Vector2(1.0, 0.0)
	var yaw_before := player._yaw
	player._apply_look(0.4)
	assert_ne(player._yaw, yaw_before, "the shield turns on the spot")


func test_an_enemy_bolt_hurts_an_open_player() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.set_physics_process(false)
	await wait_physics_frames(2)
	var hp := player.health.hp
	_ZombieShot.spawn(
		self, Vector3(0.0, 1.1, -4.0), Vector3(0.0, 0.0, 1.0), 16.0, 40.0, 20.0
	)
	await wait_physics_frames(20)
	assert_lt(player.health.hp, hp)


func test_a_raised_shield_stops_the_bolt() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.rotation.y = 0.0
	player.state = Player.State.SHIELDING
	player._shield.set_raised(true)
	player.set_physics_process(false)
	await wait_physics_frames(2)
	var hp := player.health.hp
	_ZombieShot.spawn(
		self, Vector3(0.0, 1.1, -6.0), Vector3(0.0, 0.0, 1.0), 16.0, 40.0, 20.0
	)
	await wait_physics_frames(24)
	assert_almost_eq(player.health.hp, hp, 0.01, "the panel has to eat the shot")
