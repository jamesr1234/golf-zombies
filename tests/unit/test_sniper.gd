extends GutTest
## Tower snipers: already standing during warm-up, live only after the hole
## starts, and they only go down to a headshot. The player rifle clicks 2-5-10x.

const SEED := 20260816
const SNIPER := preload("res://resources/zombies/sniper.tres")
const GUN := preload("res://resources/weapons/sniper.tres")
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")
const _Tower := preload("res://scripts/course/sniper_tower.gd")


func test_every_hole_has_towers_off_the_fairway() -> void:
	var hole0 := HoleGenerator.generate(0, SEED)
	assert_eq(_towers(hole0).size(), 2, "the first tee has to already have both perches")
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		var towers := _towers(hole)
		assert_gt(towers.size(), 0, "hole %d should have a perch" % (index + 1))
		var half := HoleGenerator.fairway_width(hole.par) * 0.5
		for prop in towers:
			assert_gt(
				HoleGenerator.distance_to_centerline(hole, prop["position"]), half,
				"a tower sat on the landing strip"
			)
			assert_gt(
				prop["position"].distance_to(hole.tee), 20.0,
				"snipers have to sit far from the tee"
			)


func test_the_built_hole_already_has_the_towers() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var towers := hole.find_children("*", "", true, false).filter(
		func(node: Node) -> bool: return node.is_in_group("sniper_towers")
	)
	assert_eq(towers.size(), 2)
	assert_eq(data.sniper_perches().size(), 2)
	for perch in data.sniper_perches():
		assert_gt(perch.y, data.tee.y + 10.0, "the deck has to sit well above the tee")


func test_snipers_never_walk_in_with_the_horde() -> void:
	assert_true(SNIPER.stationary)
	assert_true(SNIPER.headshot_only)
	assert_true(SNIPER.ranged)
	assert_eq(SNIPER.projectile_speed, 400.0)
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_hole(0, [Vector3(80.0, 0.0, 0.0)])
	assert_false(director._type_allowed(SNIPER))
	director.begin_hole(8, [Vector3(80.0, 0.0, 0.0)])
	assert_false(director._type_allowed(SNIPER))
	director.begin_transit(2, [Vector3(20.0, 0.0, 0.0)])
	assert_false(director._type_allowed(SNIPER))


func test_place_snipers_stays_off_for_now() -> void:
	assert_false(SpawnDirector.SNIPERS_ENABLED)
	var director := SpawnDirector.new()
	add_child_autofree(director)
	var box := Node3D.new()
	add_child_autofree(box)
	director.container = box
	var perches: Array[Vector3] = [Vector3(10.0, 14.5, 40.0), Vector3(-12.0, 14.5, 55.0)]
	director.place_snipers(perches)
	assert_eq(get_tree().get_nodes_in_group("zombies").size(), 0, "tower snipers are parked")


func test_a_body_shot_does_not_drop_a_sniper() -> void:
	var zombie := _sniper()
	var body := zombie.global_position + Vector3.UP * zombie.stats.height * 0.4
	zombie.take_damage(400.0, Vector3.FORWARD, body)
	assert_false(zombie.is_dying())
	assert_gt(zombie.hp, 0.0)
	assert_true(zombie.is_flashing(), "the ping still has to show")


func test_a_headshot_is_the_only_kill() -> void:
	var zombie := _sniper()
	var skull := zombie.global_position + Vector3.UP * zombie.stats.height * 0.9
	assert_true(Zombie.is_headshot(skull, zombie.global_position, zombie.stats.height))
	zombie.take_damage(1.0, Vector3.FORWARD, skull)
	assert_true(zombie.is_dying())


func test_an_unknown_hit_does_not_count_as_a_headshot() -> void:
	assert_false(Zombie.is_headshot(Vector3.INF, Vector3.ZERO, 1.8))
	var zombie := _sniper()
	zombie.take_damage(400.0, Vector3.FORWARD)
	assert_false(zombie.is_dying(), "rockets and shoves without a point of aim do not count")


func test_the_held_sniper_clicks_through_its_zooms() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	assert_eq(player.weapon.stats().display_name, "Net")
	player.weapon.index = player.weapon.loadout.find(GUN)
	assert_eq(player.weapon.stats(), GUN)
	assert_false(player.weapon.is_scoped())
	player.weapon.cycle_zoom()
	player.aiming = true
	assert_almost_eq(player.get_view_fov(), Player.BASE_FOV / 2.0, 0.001)
	player.weapon.cycle_zoom()
	assert_almost_eq(player.get_view_fov(), Player.BASE_FOV / 5.0, 0.001)
	player.weapon.cycle_zoom()
	assert_almost_eq(player.get_view_fov(), Player.BASE_FOV / 10.0, 0.001)
	player.weapon.cycle_zoom()
	player.aiming = player.weapon.is_scoped()
	assert_almost_eq(player.get_view_fov(), Player.BASE_FOV, 0.001)


func test_a_sniper_waits_before_the_first_shot() -> void:
	assert_gt(SNIPER.first_shot_delay, 1.5)
	var zombie := _sniper()
	zombie.set_physics_process(false)
	assert_almost_eq(zombie._attack_timer, SNIPER.first_shot_delay, 0.001)
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.0, -20.0)
	zombie._target = player
	zombie._try_attack()
	assert_eq(zombie.get_tree().get_nodes_in_group("zombie_shots").size(), 0)
	zombie._attack_timer = 0.0
	zombie._try_attack()
	var shots := zombie.get_tree().get_nodes_in_group("zombie_shots")
	assert_eq(shots.size(), 1)
	assert_true(shots[0].sniper)
	shots[0].queue_free()


func test_a_sniper_hit_asks_the_cpu_to_cover() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	assert_false(player.wants_cover)
	player.call_for_cover()
	assert_true(player.wants_cover)
	assert_true(player.needs_cover())


func test_drawing_the_sniper_asks_the_cpu_to_cover() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	assert_false(player.is_holding_sniper())
	assert_false(player.needs_cover())
	player.weapon.index = player.weapon.loadout.find(GUN)
	assert_true(player.is_holding_sniper())
	assert_true(player.needs_cover())
	player.weapon.swap(1)
	assert_false(player.is_holding_sniper())
	assert_false(player.needs_cover())


func test_a_sniper_holds_still_on_the_perch() -> void:
	var zombie := _sniper()
	assert_true(zombie.stats.stationary)
	assert_eq(zombie._steer(), Vector3.ZERO)


func test_a_sniper_body_holds_a_long_rifle() -> void:
	var body := ZombieBody.new()
	add_child_autofree(body)
	body.build(SNIPER)
	assert_eq(body.kind, ZombieBody.Kind.SNIPER)
	assert_not_null(body.club)
	assert_lt(body.hunch_deg, 8.0, "they stand up to aim")
	body.pose(0.0)
	assert_gt(rad_to_deg(body.arms[1].rotation.x), 60.0, "the rifle arm stays up")


func test_a_sniper_beam_stays_solid_for_75_yards() -> void:
	assert_almost_eq(HitFx.sniper_fade_after(), 75.0 * HitFx.YARD, 0.001)
	assert_eq(HitFx.sniper_alpha(0.0), 1.0)
	assert_eq(HitFx.sniper_alpha(HitFx.sniper_fade_after()), 1.0)
	assert_lt(HitFx.sniper_alpha(HitFx.sniper_fade_after() + 20.0), 0.85)
	assert_lt(
		HitFx.sniper_alpha(HitFx.sniper_fade_after() + 50.0),
		HitFx.sniper_alpha(HitFx.sniper_fade_after() + 20.0)
	)


func test_player_sniper_lines_are_white_and_enemy_lines_are_red() -> void:
	assert_eq(HitFx.sniper_tint(true), Palette.LED_WHITE)
	assert_eq(HitFx.sniper_tint(false), Palette.LED_RED)


func test_a_sniper_beam_covers_the_shot_and_dims_past_75_yards() -> void:
	var far := Vector3(0.0, 1.0, -(HitFx.sniper_fade_after() + 40.0))
	var beam := HitFx.sniper_beam(self, Vector3(0.0, 1.0, 0.0), far, Palette.LED_RED)
	assert_not_null(beam)
	assert_true(beam.is_in_group("sniper_beams"))
	var leds := beam.find_children("*", "MeshInstance3D", true, false)
	assert_gt(leds.size(), 8, "the line has to run the whole shot")
	var first := leds[0] as MeshInstance3D
	var last := leds[leds.size() - 1] as MeshInstance3D
	var near := first.material_override as StandardMaterial3D
	var tail := last.material_override as StandardMaterial3D
	assert_almost_eq(near.albedo_color.a, 1.0, 0.001)
	assert_eq(near.emission, Palette.LED_RED)
	assert_lt(tail.albedo_color.a, 0.7, "past 75 yards the LEDs have to fall off")


func test_an_enemy_sniper_line_grows_with_the_bolt() -> void:
	var far := Vector3(0.0, 1.0, -90.0)
	var beam := HitFx.sniper_beam(self, Vector3(0.0, 1.0, 0.0), far, Palette.LED_RED, true)
	assert_eq(HitFx.sniper_drawn_count(beam), 0, "the line must not paint the whole path on fire")
	HitFx.sniper_draw_to(beam, 12.0)
	var drawn := HitFx.sniper_drawn_count(beam)
	assert_gt(drawn, 0)
	assert_lt(drawn, beam.find_children("*", "MeshInstance3D", true, false).size())
	HitFx.sniper_draw_to(beam, 90.0)
	assert_eq(
		HitFx.sniper_drawn_count(beam),
		beam.find_children("*", "MeshInstance3D", true, false).size()
	)


func test_an_enemy_sniper_bolt_paints_the_red_line() -> void:
	var shot := ZombieShot.spawn(
		self, Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), 10.0, 400.0, 90.0,
		false, Palette.LED_RED, 0.04, 0.0, true
	)
	assert_true(shot.sniper)
	var beams := get_tree().get_nodes_in_group("sniper_beams")
	assert_gt(beams.size(), 0)
	assert_eq(HitFx.sniper_drawn_count(beams[0]), 0, "the bolt has not moved yet")
	var led := beams[0].find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mat := led.material_override as StandardMaterial3D
	assert_eq(mat.emission, Palette.LED_RED)


func _towers(hole: HoleData) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for prop in hole.props:
		if _Tower.is_tower(prop):
			found.append(prop)
	return found


func _sniper() -> Zombie:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	zombie.stats = SNIPER
	add_child_autofree(zombie)
	return zombie
