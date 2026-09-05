extends GutTest
## A gun dropped by a hole creator can be pinned to part of its hole. Past that
## line it will not fire, only throw, and throwing costs you the gun. None of it
## is announced to the player: the line only exists in the creator.

const PLAYER := preload("res://scenes/players/player.tscn")
const RIFLE: WeaponStats = preload("res://resources/weapons/rifle.tres")
const SHOTGUN: WeaponStats = preload("res://resources/weapons/shotgun.tres")


## The gate only ever reads the hole off the flow, so a stub keeps the test off
## the whole match machinery.
class _Round:
	var hole: HoleData

	func _init(for_hole: HoleData) -> void:
		hole = for_hole


func after_each() -> void:
	GameSettings.reset()


func _armed(gate: float) -> Player:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.flow = _Round.new(CustomLayout.build(CustomHole.create("Gated")))
	player.weapon.add_gun(RIFLE, gate)
	return player


func _stand_at(player: Player, t: float) -> void:
	player.global_position = HoleGenerator.point_along(player.flow.hole, t)


func test_a_gun_with_no_line_never_stops_working() -> void:
	var player := _armed(CustomHole.NO_GATE)
	for t in [0.0, 0.5, 1.0]:
		_stand_at(player, t)
		assert_false(WeaponGate.blocked(player), "unpinned at %s" % t)


func test_the_gun_dies_past_its_line_and_not_before() -> void:
	var player := _armed(0.5)
	_stand_at(player, 0.2)
	assert_false(WeaponGate.blocked(player), "still live short of the line")
	_stand_at(player, 0.9)
	assert_true(WeaponGate.blocked(player), "dead past the line")


## Progress runs along the hole, so the line is a gate across the fairway rather
## than a circle around where the gun was dropped.
func test_past_reads_progress_down_the_hole() -> void:
	assert_false(WeaponGate.past(CustomHole.NO_GATE, 0.99), "no line means no gate")
	assert_false(WeaponGate.past(0.5, 0.5), "standing on the line is still allowed")
	assert_true(WeaponGate.past(0.5, 0.51))


## Throwing is the only thing left, and it empties the slot whether or not it
## hits anything.
func test_throwing_costs_you_the_gun() -> void:
	var player := _armed(0.4)
	_stand_at(player, 0.8)
	assert_true(WeaponGate.throw_gun(player))
	assert_false(player.weapon.has_gun(RIFLE), "the thrown gun is gone for good")
	assert_false(player.weapon.has_weapon())
	assert_eq(get_tree().get_nodes_in_group("thrown_guns").size(), 1)
	for node in get_tree().get_nodes_in_group("thrown_guns"):
		node.queue_free()


func test_a_live_gun_is_never_thrown() -> void:
	var player := _armed(0.9)
	_stand_at(player, 0.1)
	assert_false(WeaponGate.throw_gun(player))
	assert_true(player.weapon.has_gun(RIFLE))


## Dropping one gun leaves the rest of the bag alone and in step.
func test_dropping_a_gun_keeps_the_rest_of_the_bag_lined_up() -> void:
	var player := _armed(0.4)
	player.weapon.add_gun(SHOTGUN, CustomHole.NO_GATE)
	assert_eq(player.weapon.loadout.size(), 2)
	assert_eq(player.weapon.drop_gun(0), RIFLE)
	assert_eq(player.weapon.loadout, [SHOTGUN] as Array[WeaponStats])
	assert_eq(player.weapon.mags.size(), 1)
	assert_eq(player.weapon.reserves.size(), 1)
	assert_eq(player.weapon.gates.size(), 1)
	assert_eq(player.weapon.gate(), CustomHole.NO_GATE)
	assert_eq(player.weapon.index, 0)
	assert_null(player.weapon.drop_gun(4), "an index that is not there drops nothing")


## Solo and co-op have nobody to throw at, so a thrown gun sails past everyone.
func test_only_a_rival_can_be_floored() -> void:
	var thrower: Player = PLAYER.instantiate()
	add_child_autofree(thrower)
	var other: Player = PLAYER.instantiate()
	add_child_autofree(other)
	GameSettings.mode = GameSettings.Mode.SOLO
	assert_false(ThrownGun.is_rival(thrower, other))
	GameSettings.mode = GameSettings.Mode.COOP
	assert_false(ThrownGun.is_rival(thrower, other))
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	assert_true(ThrownGun.is_rival(thrower, other))
	assert_false(ThrownGun.is_rival(thrower, thrower), "not yourself")
	assert_false(ThrownGun.is_rival(thrower, null))
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	thrower.partner = other
	assert_false(ThrownGun.is_rival(thrower, other), "your partner is on your side")
	assert_false(ThrownGun.is_rival(other, thrower))


## Floored is short and self-righting: no walking, no shooting, then back up
## without anyone having to come over.
func test_being_floored_takes_your_feet_and_gives_them_back() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	assert_false(player.is_floored())
	assert_true(PlayerMotion.can_walk(player))
	ThrownGun.floor_player(player, player.global_position + Vector3.FORWARD)
	assert_true(player.is_floored())
	assert_almost_eq(player.floored_for, ThrownGun.FLOOR_SECONDS, 0.01)
	assert_false(PlayerMotion.can_walk(player), "you cannot steer off the floor")
	assert_true(player.health.is_alive(), "floored is not downed, so nobody revives you")
	player.floored_for = 0.0
	assert_true(PlayerMotion.can_walk(player))
