extends GutTest
## A claw on a neon rope. Paint a cart or a mech, ride it down the hole, jump off
## when you want the ball.

const PLAYER := preload("res://scenes/players/player.tscn")
const CART := preload("res://scenes/vehicles/golf_cart.tscn")
const MECH := preload("res://scenes/course/items/mech_suit.tscn")
const STEP := 1.0 / 60.0


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	Sfx.clear_log()


func after_each() -> void:
	for node in get_tree().get_nodes_in_group("grapple_hooks"):
		node.queue_free()


func test_the_hook_only_bites_rides() -> void:
	var cart := GolfCart.new()
	var mech := MechSuit.new()
	var girl := CartGirl.new()
	assert_eq(Grappler.hitchable(cart), cart)
	assert_eq(Grappler.hitchable(mech), mech)
	assert_eq(Grappler.hitchable(girl), girl)
	var dummy := Node3D.new()
	assert_null(Grappler.hitchable(dummy))
	assert_null(Grappler.hitchable(null))
	cart.free()
	mech.free()
	girl.free()
	dummy.free()


func test_a_child_collider_still_counts_as_the_ride() -> void:
	var cart := GolfCart.new()
	var bolt := Node3D.new()
	cart.add_child(bolt)
	assert_eq(Grappler.hitchable(bolt), cart)
	cart.free()


func test_a_slack_rope_does_not_pull() -> void:
	var hook := Vector3(0.0, 2.0, -6.0)
	var from := Vector3(0.0, 1.0, 0.0)
	assert_eq(Grappler.taut_offset(from, hook, 8.0), Vector3.ZERO)


func test_a_taut_rope_snaps_back_to_length() -> void:
	var hook := Vector3.ZERO
	var from := Vector3(0.0, 0.0, 10.0)
	var pull := Grappler.taut_offset(from, hook, 6.0)
	assert_almost_eq((from + pull).distance_to(hook), 6.0, 0.001)
	assert_lt((from + pull).z, from.z)


func test_towing_inherits_the_vehicle_speed() -> void:
	var ride := Vector3(0.0, 0.0, -16.0)
	var vel := Grappler.tow_velocity(
		Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 1.0, -4.0), ride, 5.0, STEP
	)
	assert_almost_eq(vel.z, -16.0, 0.001)


func test_a_stretched_rope_adds_pull_toward_the_hook() -> void:
	var vel := Grappler.tow_velocity(
		Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -10.0), Vector3.ZERO, 4.0, STEP
	)
	assert_lt(vel.z, 0.0, "the extra metres yank you toward the claw")
	assert_lt(vel.z, -Grappler.STIFF, "a long stretch has to be a real tug")


func test_the_hook_mask_sees_carts_and_mechs() -> void:
	assert_ne(Grappler.HOOK_MASK & Layers.VEHICLE, 0)
	assert_ne(Grappler.HOOK_MASK & Layers.MECH, 0)
	assert_ne(Grappler.HOOK_MASK & Layers.WORLD, 0)
	assert_eq(Grappler.HOOK_MASK & Layers.PLAYER, 0)
	assert_eq(Grappler.HOOK_MASK & Layers.ZOMBIE, 0)


func test_firing_spawns_a_flying_claw() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	assert_true(player.grappler.fire(player, Vector3(0.0, 1.4, 0.0), Vector3.FORWARD))
	assert_true(player.grappler.is_flying())
	assert_eq(get_tree().get_nodes_in_group("grapple_hooks").size(), 1)
	assert_eq(Sfx.last_cue, "grapple_fire")


func test_a_latch_puts_you_on_the_rope() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	await wait_physics_frames(1)
	player.global_position = Vector3(0.0, 1.0, 8.0)
	cart.global_position = Vector3(0.0, 0.4, 0.0)
	assert_true(player.begin_grapple(cart, cart.global_position + Vector3(0.0, 0.6, 0.0)))
	assert_true(player.is_grappling())
	assert_eq(player.state, Player.State.GRAPPLING)
	assert_eq(Sfx.last_cue, "grapple_latch")
	assert_true(player.grappler.is_latched())


func test_the_cart_drags_you_when_it_leaves() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	await wait_physics_frames(1)
	player.global_position = Vector3(0.0, 1.0, 8.0)
	cart.global_position = Vector3(0.0, 0.4, 0.0)
	player.begin_grapple(cart, cart.global_position + Vector3(0.0, 0.6, 0.0))
	cart.global_position.z = -12.0
	var start := player.global_position.z
	for _frame in 45:
		player._physics_process(STEP)
	assert_true(player.is_grappling())
	assert_lt(player.global_position.z, start - 2.0, "the rope has to tow you after the cart")


func test_jump_lets_go_and_keeps_the_speed() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	await wait_physics_frames(1)
	player.input = CpuInput.new("p1", true)
	player.global_position = Vector3(0.0, 1.0, 8.0)
	cart.global_position = Vector3(0.0, 0.4, 0.0)
	player.begin_grapple(cart, cart.global_position + Vector3(0.0, 0.6, 0.0))
	player.velocity = Vector3(0.0, 0.0, -14.0)
	(player.input as CpuInput).tap("jump")
	player._physics_process(STEP)
	assert_false(player.is_grappling())
	assert_lt(player.velocity.z, -8.0, "letting go keeps the ride's speed")


func test_you_cannot_hook_from_the_cart_seat() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.state = Player.State.RIDING
	assert_false(player._can_fire_grapple())
	player.state = Player.State.GOLFING
	assert_false(player._can_fire_grapple())
	player.state = Player.State.MECH
	assert_false(player._can_fire_grapple())
	player.state = Player.State.CLIMBING
	assert_false(player._can_fire_grapple())
	player.state = Player.State.NORMAL
	assert_true(player._can_fire_grapple())


func test_a_mech_is_a_legal_hitch() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var mech: MechSuit = MECH.instantiate()
	add_child_autofree(mech)
	await wait_physics_frames(1)
	player.global_position = Vector3(0.0, 1.0, 14.0)
	mech.global_position = Vector3(0.0, 0.0, 0.0)
	assert_true(player.begin_grapple(mech, mech.global_position + Vector3(0.0, 2.0, 0.0)))
	assert_true(player.is_grappling())
	assert_eq(player.grappler.target, mech)


func test_the_prompt_teaches_the_let_go() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	await wait_physics_frames(1)
	player.begin_grapple(cart, cart.global_position)
	var prompt := player.get_prompt()
	assert_true(prompt.contains("let go") or prompt.contains("jump"), prompt)
	assert_true(prompt.contains("reel") or prompt.contains("sprint"), prompt)


func test_the_line_draws_while_you_are_on_the_rope() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	await wait_physics_frames(1)
	player.global_position = Vector3(0.0, 1.0, 6.0)
	player.begin_grapple(cart, cart.global_position + Vector3(0.0, 0.5, 0.0))
	player._physics_process(STEP)
	assert_not_null(player._grapple_line)
	assert_true(player._grapple_line.visible)


func test_sprint_reels_the_rope_in() -> void:
	var grappler := Grappler.new()
	grappler.slack = 12.0
	var before := grappler.slack
	var dummy := Grappler.tow_velocity(
		Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -8.0), Vector3.ZERO, grappler.slack, STEP
	)
	assert_eq(dummy.z, 0.0)
	grappler.slack = move_toward(grappler.slack, Grappler.MIN_SLACK, Grappler.REEL * 1.0)
	assert_lt(grappler.slack, before)
	assert_gt(grappler.slack, Grappler.MIN_SLACK - 0.01)
