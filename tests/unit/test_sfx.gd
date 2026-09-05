extends GutTest
## Placeholder SFX: every named cue builds a short wave, and game actions fire them.


func before_each() -> void:
	Sfx.clear_log()


func test_every_named_cue_builds_a_short_wave() -> void:
	var names := Sfx.cues()
	assert_gt(names.size(), 40, "the bank should cover the actions in the game")
	for cue in names:
		assert_true(Sfx.has_cue(cue), cue)
		var stream := Sfx.stream_for(cue) as AudioStreamWAV
		assert_not_null(stream, cue)
		assert_gt(stream.data.size(), 200, cue)
		assert_gt(stream.get_length(), 0.03, cue)
		assert_lt(stream.get_length(), 1.0, cue)


func test_an_unknown_cue_does_not_build_a_stream() -> void:
	assert_null(Sfx.stream_for("not_a_real_sound"))
	assert_false(Sfx.has_cue("not_a_real_sound"))


func test_play_records_the_cue_even_before_audio_starts() -> void:
	Sfx.play("ui_move")
	assert_eq(Sfx.last_cue, "ui_move")
	assert_true(Sfx.play_log.has("ui_move"))


func test_play_starts_a_player_under_the_shared_pool() -> void:
	Sfx.play("jump")
	var pool: Node = Engine.get_main_loop().root.get_node_or_null(Sfx.POOL_NAME)
	assert_not_null(pool)
	assert_gt(pool.get_child_count(), 0)
	var player := pool.get_child(pool.get_child_count() - 1) as AudioStreamPlayer
	assert_not_null(player)
	assert_not_null(player.stream)


func test_gun_visuals_pick_matching_shot_cues() -> void:
	assert_eq(Sfx.fire_cue("rifle"), "rifle_fire")
	assert_eq(Sfx.fire_cue("shotgun"), "shotgun_fire")
	assert_eq(Sfx.fire_cue("rocket"), "rocket_fire")
	assert_eq(Sfx.fire_cue("net"), "net_fire")
	assert_eq(Sfx.fire_cue("sniper"), "sniper_fire")
	assert_eq(Sfx.fire_cue("flare"), "flare_fire")
	assert_eq(Sfx.fire_cue("nailer"), "nailer_fire")
	assert_eq(Sfx.fire_cue("door"), "door_fire")
	assert_eq(Sfx.fire_cue("remote"), "remote_fire")


func test_the_sniper_shot_is_a_heavier_boom() -> void:
	var sniper: Array = Sfx.CUES["sniper_fire"]
	var rifle: Array = Sfx.CUES["rifle_fire"]
	assert_eq(sniper[0], 4, "the sniper uses the low boom wave")
	assert_gt(sniper[3], rifle[3], "the boom has to hang longer than a rifle crack")
	assert_gt(sniper[4], rifle[4], "the boom is louder")
	assert_lt(sniper[2], 70.0, "the tail has to sit in the low end")
	assert_gt(Sfx.play_gain("sniper_fire"), Sfx.play_gain("rifle_fire"))
	var wave := Sfx.stream_for("sniper_fire") as AudioStreamWAV
	assert_gt(wave.get_length(), 0.4)


func test_firing_the_rifle_plays_the_rifle_shot() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	assert_true(gun.add_gun(rifle))
	gun.tick(0.0, Transform3D.IDENTITY, true, true, false)
	assert_eq(Sfx.last_cue, "rifle_fire")


func test_firing_the_shotgun_plays_the_shotgun_shot() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	var shotgun: WeaponStats = preload("res://resources/weapons/shotgun.tres")
	assert_true(gun.add_gun(shotgun))
	gun.tick(0.5, Transform3D.IDENTITY, false, false, false)
	Sfx.clear_log()
	gun.tick(0.0, Transform3D.IDENTITY, false, true, false)
	assert_eq(Sfx.last_cue, "shotgun_fire")


func test_an_empty_gun_with_no_reserve_clicks() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	assert_true(gun.add_gun(rifle))
	gun.mags[0] = 0
	gun.reserves[0] = 0
	gun.tick(0.0, Transform3D.IDENTITY, true, true, false)
	assert_eq(Sfx.last_cue, "empty_click")


func test_a_reload_plays_the_start_and_the_close() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	assert_true(gun.add_gun(rifle))
	gun.mags[0] = 1
	gun.start_reload()
	assert_eq(Sfx.last_cue, "reload")
	gun.tick(gun.stats().reload_time, Transform3D.IDENTITY, false, false, false)
	assert_eq(Sfx.last_cue, "reload_done")


func test_taking_a_hit_plays_damage_and_a_down_plays_downed() -> void:
	var health := Health.new()
	add_child_autofree(health)
	health.take_damage(10.0)
	assert_eq(Sfx.last_cue, "damage")
	health.take_damage(200.0)
	assert_eq(Sfx.last_cue, "downed")
	health.revive_now()
	assert_eq(Sfx.last_cue, "revived")
	health.take_damage(200.0)
	health.tick(health.bleed_out_time)
	assert_eq(Sfx.last_cue, "died")


func test_a_purchase_rings_the_register() -> void:
	var shop := Shop.new()
	var score := GameState.new(PackedInt32Array([4, 3, 5]))
	var gun := Weapon.new()
	add_child_autofree(gun)
	score.credit(Shop.AMMO_PRICE)
	var weapons: Array[Weapon] = [gun]
	assert_true(shop.buy("ammo", score, weapons))
	assert_eq(Sfx.last_cue, "purchase")
	assert_false(shop.buy("ammo", score, weapons))
	assert_eq(Sfx.last_cue, "ui_deny")
