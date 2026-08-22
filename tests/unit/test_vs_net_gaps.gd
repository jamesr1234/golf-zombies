extends GutTest
## Desync holes in online VS: who may change the world, and what a disconnect does.


func after_each() -> void:
	NetSession.close()
	NetSession.seats.clear()
	GameSettings.reset()


func test_clients_defer_world_shots_to_the_host() -> void:
	assert_false(NetSession.should_defer_world(false, true), "offline play is local")
	assert_false(NetSession.should_defer_world(true, true), "the host still simulates")
	assert_true(NetSession.should_defer_world(true, false), "clients only request")


func test_a_live_session_defers_only_when_not_the_server() -> void:
	assert_false(NetSession.defers_world(), "GUT is offline, so fire stays local")
	NetSession._active = true
	assert_false(NetSession.defers_world(), "an OfflineMultiplayerPeer is still the server")


func test_the_clock_is_host_owned() -> void:
	var flow := VsMatchFlow.new()
	assert_true(flow.owns_clock(), "offline and host both tick")
	flow.free()


func test_settle_disconnected_marks_the_card_done() -> void:
	var flow := VsMatchFlow.new()
	var card := PlayerScore.new()
	flow._scores[4] = card
	flow.mark_peer_gone(4)
	assert_true(card.done_this_hole)
	assert_true(PlayerScore.everyone_done([card]))
	flow.mark_peer_gone(4)
	assert_true(card.done_this_hole, "a second settle is harmless")
	flow.free()


func test_a_gone_peer_lets_the_rest_finish() -> void:
	var stayed := PlayerScore.new()
	var left := PlayerScore.new()
	stayed.finish_hole()
	assert_false(PlayerScore.everyone_done([stayed, left]))
	var flow := VsMatchFlow.new()
	flow._scores[7] = left
	flow.mark_peer_gone(7)
	assert_true(PlayerScore.everyone_done([stayed, left]))
	flow.free()


func test_host_fire_rejects_an_empty_mag() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	gun.index = gun.loadout.find(rifle)
	gun.mags[gun.index] = 0
	assert_false(gun.host_fire(Transform3D.IDENTITY, false, gun.index))
	gun.mags[gun.index] = 1
	assert_true(gun.host_fire(Transform3D.IDENTITY, false, gun.index))
	assert_eq(gun.mag(), 0)


func test_a_replicated_loadout_replaces_the_bag() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	gun.apply_replicated_loadout(0, PackedStringArray([rifle.resource_path]))
	assert_eq(gun.loadout.size(), 1)
	assert_eq(gun.stats(), rifle)
	assert_eq(gun.index, 0)
