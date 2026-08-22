extends GutTest
## Down, bleed out, revive: the rules that decide when the run is over.

var health: Health


func before_each() -> void:
	health = Health.new()
	health.max_hp = 100.0
	health.hp = 100.0
	health.bleed_out_time = 10.0
	health.revive_time = 3.0
	health.bleed_remaining = 10.0


func after_each() -> void:
	health.free()


func test_starts_alive_and_full() -> void:
	assert_true(health.is_alive())
	assert_eq(health.fraction(), 1.0)


func test_damage_reduces_health_without_downing() -> void:
	health.take_damage(30.0)
	assert_true(health.is_alive())
	assert_almost_eq(health.fraction(), 0.7, 0.001)


func test_reaching_zero_downs_instead_of_killing() -> void:
	watch_signals(health)
	health.take_damage(120.0)
	assert_true(health.is_downed())
	assert_false(health.is_alive())
	assert_signal_emitted(health, "downed")
	assert_signal_not_emitted(health, "died")


func test_downed_players_take_no_further_damage() -> void:
	health.take_damage(120.0)
	health.take_damage(50.0)
	assert_true(health.is_downed(), "a downed player cannot be downed again")


func test_bleed_out_kills_after_the_timer() -> void:
	watch_signals(health)
	health.take_damage(120.0)
	health.tick(9.0)
	assert_true(health.is_downed())
	health.tick(1.5)
	assert_eq(health.state, Health.State.DEAD)
	assert_signal_emitted(health, "died")


func test_revive_needs_the_full_hold() -> void:
	health.take_damage(120.0)
	health.add_revive_progress(2.0)
	assert_true(health.is_downed())
	assert_almost_eq(health.revive_fraction(), 2.0 / 3.0, 0.001)
	health.add_revive_progress(1.1)
	assert_true(health.is_alive())
	assert_almost_eq(health.fraction(), 0.5, 0.001)


func test_interrupted_revive_resets() -> void:
	health.take_damage(120.0)
	health.add_revive_progress(2.5)
	health.reset_revive_progress()
	assert_eq(health.revive_fraction(), 0.0)
	assert_true(health.is_downed())


func test_dead_players_cannot_be_revived() -> void:
	health.take_damage(120.0)
	health.tick(11.0)
	health.add_revive_progress(5.0)
	assert_eq(health.state, Health.State.DEAD)


func test_a_medkit_restores_health() -> void:
	health.take_damage(40.0)
	health.heal()
	assert_almost_eq(health.hp, health.max_hp, 0.001)
	assert_true(health.is_alive())


func test_an_auto_revive_gets_you_up_instead_of_downing() -> void:
	watch_signals(health)
	health.add_auto_revive()
	health.take_damage(120.0)
	assert_true(health.is_alive())
	assert_eq(health.auto_revives, 0)
	assert_almost_eq(health.fraction(), 0.5, 0.001)
	assert_signal_emitted(health, "revived")
	assert_signal_not_emitted(health, "downed")


func test_revive_now_stands_a_downed_player_up() -> void:
	health.take_damage(120.0)
	assert_true(health.is_downed())
	health.revive_now()
	assert_true(health.is_alive())
	assert_almost_eq(health.fraction(), 0.5, 0.001)


func test_restore_stands_a_dead_player_back_up() -> void:
	health.take_damage(120.0)
	health.tick(11.0)
	assert_eq(health.state, Health.State.DEAD)
	health.restore()
	assert_true(health.is_alive())
	assert_eq(health.hp, health.max_hp)


func test_health_regenerates_after_a_break_in_contact() -> void:
	health.regen_delay = 2.0
	health.regen_rate = 10.0
	health.take_damage(50.0)
	health.tick(1.0)
	assert_almost_eq(health.hp, 50.0, 0.001, "no regen while under fire")
	health.tick(1.5)
	health.tick(1.0)
	assert_gt(health.hp, 50.0)
	assert_lte(health.hp, 100.0)
