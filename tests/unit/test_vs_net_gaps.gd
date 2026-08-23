extends GutTest
## Desync holes in online VS: who may change the world, and what a disconnect does.

const PLAYER := preload("res://scenes/players/player.tscn")
const ZOMBIE := preload("res://scenes/zombies/zombie.tscn")
const WALKER: ZombieStats = preload("res://resources/zombies/walker.tres")
const WorldFxScript := preload("res://scripts/net/world_fx.gd")


func after_each() -> void:
	NetSession.close()
	NetSession.seats.clear()
	GameSettings.reset()
	for group in ["rockets", "net_shots", "net_traps", "thrown_beers", "fireworks", "sniper_beams"]:
		for node in get_tree().get_nodes_in_group(group):
			node.remove_from_group(group)
			node.queue_free()


func test_a_pawn_sync_speaks_for_its_owner() -> void:
	var pawn := Node3D.new()
	add_child_autofree(pawn)
	var health := Node.new()
	health.name = "Health"
	pawn.add_child(health)
	pawn.set_multiplayer_authority(7)
	health.set_multiplayer_authority(1)
	var health_sync := NetSync.attach_health(health)
	var pawn_sync := NetSync.attach_pawn(pawn, 7)
	assert_eq(pawn_sync.get_multiplayer_authority(), 7, "a late Sync child must not stay on the host")
	assert_eq(health_sync.get_multiplayer_authority(), 1, "hp still belongs to the host")
	assert_true(pawn_sync.replication_config.has_property(NodePath(":aiming")))
	assert_true(pawn_sync.replication_config.has_property(NodePath(":sync_gun")))
	assert_true(pawn_sync.replication_config.has_property(NodePath(":holding_beer")))
	assert_true(pawn_sync.replication_config.has_property(NodePath(":sync_state")))
	assert_true(pawn_sync.replication_config.has_property(NodePath(":sync_dive")))
	assert_true(pawn_sync.replication_config.has_property(NodePath(":sync_firing")))
	assert_true(pawn_sync.replication_config.has_property(NodePath(":sync_reload")))
	assert_true(pawn_sync.replication_config.has_property(NodePath(":sync_scoped")))


func test_zombie_and_cart_sync_carry_the_look_flags() -> void:
	var zombie := Node3D.new()
	add_child_autofree(zombie)
	var zombie_sync := NetSync.attach_zombie(zombie)
	assert_true(zombie_sync.replication_config.has_property(NodePath(":allied")))
	assert_true(zombie_sync.replication_config.has_property(NodePath(":sync_netted")))
	assert_true(zombie_sync.replication_config.has_property(NodePath(":sync_drink")))
	assert_true(zombie_sync.replication_config.has_property(NodePath(":sync_dying")))
	var cart := Node3D.new()
	add_child_autofree(cart)
	var cart_sync := NetSync.attach_cart(cart)
	assert_true(cart_sync.replication_config.has_property(NodePath(":turbo")))
	assert_true(cart_sync.replication_config.has_property(NodePath(":ram_plate")))
	assert_true(cart_sync.replication_config.has_property(NodePath(":armored")))
	var girl := Node3D.new()
	add_child_autofree(girl)
	var girl_sync := NetSync.attach_cart_girl(girl)
	assert_true(girl_sync.replication_config.has_property(NodePath(":visit")))
	assert_true(girl_sync.replication_config.has_property(NodePath(":cooler_open")))
	assert_true(girl_sync.replication_config.has_property(NodePath(":tending")))


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


func test_a_replicated_index_selects_that_gun() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	var idx := gun.loadout.find(rifle)
	gun.apply_replicated_index(idx)
	assert_eq(gun.stats(), rifle)
	assert_eq(gun.index, idx)
	gun.apply_replicated_index(99)
	assert_eq(gun.index, gun.loadout.size() - 1)


func test_a_remote_pawn_shows_the_synced_gun() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	player.net_driven = true
	player.set_multiplayer_authority(99)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	player.sync_gun = player.weapon.loadout.find(rifle)
	player._animate(1.0 / 60.0)
	assert_eq(player.weapon.stats(), rifle)
	assert_false(player.raygun.is_net())
	player.holding_beer = true
	assert_true(player.is_holding_beer(), "remotes keep the replicated beer flag")
	player._animate(1.0 / 60.0)
	assert_true(player._beer.visible)
	assert_false(player.raygun.visible)


func test_a_replicated_pose_picks_shield_swim_and_scope() -> void:
	var player := _remote_pawn()
	player.sync_state = int(Player.State.SHIELDING)
	player._animate(1.0 / 60.0)
	assert_true(player.is_shielding())
	assert_true(player._shield.visible)
	assert_false(player.raygun.visible)
	player.sync_state = int(Player.State.SWIMMING)
	player.sync_dive = true
	player._animate(1.0 / 60.0)
	assert_true(player.is_swimming())
	assert_true(player.is_underwater())
	assert_false(player.raygun.visible)
	var sniper: WeaponStats = preload("res://resources/weapons/sniper.tres")
	player.sync_state = int(Player.State.NORMAL)
	player.sync_dive = false
	player.sync_gun = player.weapon.loadout.find(sniper)
	player.sync_scoped = true
	player._animate(1.0 / 60.0)
	assert_true(player.weapon.is_scoped())
	assert_false(player.raygun.visible)


func test_a_remote_pawn_crouches_when_downed_and_hides_the_gun_while_placing() -> void:
	var player := _remote_pawn()
	player.health.state = Health.State.DOWNED
	player._animate(1.0 / 60.0)
	assert_almost_eq(player.head.position.y, Player.DOWNED_HEAD_HEIGHT, 0.001)
	player.health.state = Health.State.ALIVE
	player.sync_state = int(Player.State.PLACING)
	player._animate(1.0 / 60.0)
	assert_true(player.is_placing())
	assert_false(player.raygun.visible)


func test_a_replicated_gun_pose_shows_reload_and_fire() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	gun.apply_replicated_pose(true, 0.4, false)
	assert_true(gun.is_firing())
	assert_almost_eq(gun.reload_fraction(), 0.4, 0.001)
	assert_false(gun.is_scoped())
	var sniper: WeaponStats = preload("res://resources/weapons/sniper.tres")
	gun.index = gun.loadout.find(sniper)
	gun.apply_replicated_pose(false, 0.0, true)
	assert_true(gun.is_scoped())
	assert_false(gun.is_firing())


func test_a_replicated_melee_starts_the_swing() -> void:
	var player := _remote_pawn()
	player._replicate_melee()
	assert_true(player.body.is_meleeing())


func test_a_replicated_barrier_sits_at_the_pose() -> void:
	var world := _world_fx()
	var hex: Node3D = world.apply_barrier(Vector3(2.0, 0.0, 4.0), 90.0)
	assert_not_null(hex)
	assert_almost_eq(hex.global_position.x, 2.0, 0.001)
	assert_almost_eq(hex.global_position.z, 4.0, 0.001)
	assert_almost_eq(hex.rotation.y, deg_to_rad(90.0), 0.001)


func test_a_visual_rocket_does_not_deal_blast_damage() -> void:
	var world := _world_fx()
	var zombie := _zombie(Vector3.ZERO)
	var rocket := world.apply_rocket(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, 110.0, 6.5, 90.0)
	assert_true(rocket.visual_only)
	rocket._explode(zombie.global_position + Vector3.UP)
	assert_false(zombie.is_dying())
	assert_gt(zombie.hp, 0.0)


func test_a_visual_net_does_not_scoop() -> void:
	var world := _world_fx()
	var zombie := _zombie(Vector3.ZERO)
	var trap := world.apply_trap(Vector3.ZERO, 20.0, 10.0)
	assert_true(trap.visual_only)
	assert_eq(trap.trapped_count(), 0)
	assert_false(zombie.is_netted())
	trap._physics_process(0.016)
	assert_false(zombie.is_netted())


func test_a_visual_net_shot_does_not_deploy_a_live_trap() -> void:
	var world := _world_fx()
	var zombie := _zombie(Vector3.ZERO)
	var before := get_tree().get_nodes_in_group("net_traps").size()
	var shot := world.apply_net_shot(Vector3.ZERO, Vector3.FORWARD, 20.0, 10.0, 80.0)
	assert_true(shot.visual_only)
	shot._land(zombie.global_position)
	assert_eq(get_tree().get_nodes_in_group("net_traps").size(), before)
	assert_false(zombie.is_netted())


func test_a_visual_ammo_drop_does_not_grant() -> void:
	var world := _world_fx()
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var reserve := player.weapon.reserve()
	var pickup := world.apply_ammo(3, Vector3.ZERO, 24)
	assert_true(pickup.visual_only)
	pickup._on_body_entered(player)
	assert_eq(player.weapon.reserve(), reserve)
	world.remove_ammo(3)
	assert_true(pickup.is_queued_for_deletion())


func test_a_visual_beer_does_not_convert_a_zombie() -> void:
	var world := _world_fx()
	var zombie := _zombie(Vector3.ZERO)
	var can := world.apply_beer(Vector3.UP, Vector3.FORWARD)
	assert_true(can.visual_only)
	can._arrive(zombie.global_position, zombie)
	assert_false(zombie.is_drinking())
	assert_false(zombie.is_allied())
	assert_true(zombie.can_catch())


func test_a_replicated_hitscan_draws_a_tracer() -> void:
	var world := _world_fx()
	var before := world._fx_root().get_child_count()
	world.apply_hitscan(Vector3.ZERO, Vector3(0.0, 0.0, -12.0), "tracer", Color.WHITE)
	assert_gt(world._fx_root().get_child_count(), before)


func test_a_replicated_sniper_beam_is_visible() -> void:
	var world := _world_fx()
	world.apply_hitscan(Vector3.ZERO, Vector3(0.0, 0.0, -40.0), "sniper", Color.WHITE)
	assert_gt(get_tree().get_nodes_in_group("sniper_beams").size(), 0)


func test_a_replicated_firework_bursts() -> void:
	var world := _world_fx()
	var burst := world.apply_fireworks(Vector3.UP, Palette.MAGENTA)
	assert_not_null(burst)
	assert_gt(get_tree().get_nodes_in_group("fireworks").size(), 0)


func test_a_replicated_sfx_plays_unless_this_peer_already_did() -> void:
	Sfx.clear_log()
	var world := _world_fx()
	world.apply_sfx("zombie_explode", 0)
	assert_eq(Sfx.last_cue, "zombie_explode")
	Sfx.clear_log()
	world.apply_sfx("zombie_explode", multiplayer.get_unique_id())
	assert_eq(Sfx.last_cue, "")


func test_a_replicated_ally_wears_the_cap() -> void:
	var zombie := _zombie(Vector3.ZERO)
	zombie.allied = true
	zombie._apply_replicated_look(0.016)
	assert_true(zombie.is_in_group("allies"))
	assert_not_null(zombie.visual._ally_cap)
	assert_not_null(zombie.visual.get_node_or_null("Cheer"))


func test_a_replicated_netted_zombie_idles() -> void:
	var zombie := _zombie(Vector3.ZERO)
	zombie.sync_netted = true
	zombie._apply_replicated_look(0.016)
	assert_null(zombie.visual._beer)


func test_a_replicated_drink_puts_a_can_in_hand() -> void:
	var zombie := _zombie(Vector3.ZERO)
	zombie.sync_drink = Zombie.DRINK_TIME * 0.5
	zombie._apply_replicated_look(0.016)
	assert_not_null(zombie.visual._beer)


func test_cart_girl_shows_up_when_visit_replicates() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	assert_false(girl.visible)
	girl.visit = CartGirl.Visit.APPROACHING
	girl._apply_replicated()
	assert_true(girl.visible)
	girl.tending = true
	girl._apply_replicated()
	assert_true(girl.attendant().position.is_equal_approx(CartGirl.STAND))


func test_a_replicated_cheer_pops_enjoy() -> void:
	var world := _world_fx()
	var girl := CartGirl.new()
	add_child_autofree(girl)
	world.apply_cart_girl("cheer")
	assert_not_null(girl.attendant().get_node_or_null("Cheer"))
	assert_eq(girl.attendant().get_node("Cheer").text, CartGirl.ENJOY)


func test_held_beers_can_be_granted() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.apply_held_beers(2)
	assert_eq(player.buzz.held, 2)
	player.apply_held_beers(-3)
	assert_eq(player.buzz.held, 0)


func test_a_replicated_outfit_goes_on() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var item := ShopStock.wear_by_id("shirt_cyan")
	player.wear_apparel(item)
	assert_true(player.is_wearing("shirt_cyan"))
	var other: Player = PLAYER.instantiate()
	add_child_autofree(other)
	other.wear_apparel(ShopStock.wear_by_id(String(player.body.worn["shirt"])))
	assert_true(other.is_wearing("shirt_cyan"))


func test_ammo_drop_ids_count_up_on_the_host_copy() -> void:
	var world := _world_fx()
	assert_eq(WorldFxScript.take_ammo_id(world), 1)
	assert_eq(WorldFxScript.take_ammo_id(world), 2)


func _world_fx() -> WorldFx:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var world: WorldFx = WorldFxScript.new()
	add_child_autofree(world)
	return world


func _zombie(at: Vector3) -> Zombie:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = at
	return zombie


func _remote_pawn() -> Player:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.net_driven = true
	player.set_multiplayer_authority(99)
	return player
