class_name ArenaHole
extends Object
## Hole 5: a sealed pit. Pick two guns, then last team standing scores.

const INDEX := 4
const PAR := 4
const CELL := 1.35
const SIDES := 24
const XL := CELL * 7.0
const LARGE := CELL * 5.0
const MED := CELL * 3.0
const BAY := XL
const STAND_DEPTH := XL + LARGE + MED
const GREEN_RADIUS := 10.0
const WIN_UNDER := 3
const PICKS := 2
const WEAPON_GAP := 2.4
const WEAPON_ROW := 5.0
const WEAPON_REST := 0.18
const SPAWN_RING := 0.86
const SPAWN_CAP := 28
const SPAWN_INTERVAL := 0.55
const SPAWN_KEEP_AWAY := 8.0
const SPAWN_BURST := 12
const FIRST_SPAWN := 0.6
const HUNT_RANGE := 48.0
## Six 15° bays so the cart path fits without clipping the remaining stairs.
const GATE_BAYS := 6
const WARMUP := "Pick two guns.\nThe round starts when everyone has chosen."
const WARMUP_SHORT := "Pick two guns. Last team standing wins."
const PLAY_BANNER := "Last team standing. There is no hole. Survive."
const WEAPONS: PackedStringArray = [
	"res://resources/weapons/rifle.tres",
	"res://resources/weapons/shotgun.tres",
	"res://resources/weapons/sniper.tres",
	"res://resources/weapons/rocket.tres",
	"res://resources/weapons/net.tres",
	"res://resources/weapons/flare_driver.tres",
	"res://resources/weapons/cart_nailer.tres",
	"res://resources/weapons/warp_door.tres",
	"res://resources/weapons/shape_remote.tres",
]


static func applies(data) -> bool:
	return data is HoleData and data.custom == null and data.index == INDEX


static func applies_index(index: int) -> bool:
	return index == INDEX


static func floor_radius() -> float:
	return BAY * 0.5 / tan(PI / float(SIDES))


static func flatten_reach() -> float:
	return floor_radius() + STAND_DEPTH + CELL * 2.0


## Bays facing down the hole, the same way the cart path leaves the green.
static func gate_center() -> int:
	return SIDES / 2


static func is_gate_side(side: int) -> bool:
	var delta := posmod(side - gate_center(), SIDES)
	if delta > SIDES / 2:
		delta -= SIDES
	var half := GATE_BAYS / 2
	return delta >= -half and delta < GATE_BAYS - half


static func strokes_for_place(par: int, place: int) -> int:
	return par - clampi(WIN_UNDER - place, 0, WIN_UNDER)


static func gun_count(player: Player) -> int:
	if player == null or player.weapon == null:
		return 0
	return player.weapon.loadout.size()


static func choosing(player: Player) -> bool:
	return player != null and player.flow != null and applies(player.flow.hole) and int(player.flow.phase) == 0


static func needs_gun(player: Player) -> bool:
	return choosing(player) and gun_count(player) < PICKS


static func can_pick(player: Player) -> bool:
	if player == null or player.weapon == null:
		return false
	if choosing(player):
		return gun_count(player) < PICKS
	return true


static func all_armed(players: Array) -> bool:
	var waiting := 0
	for node in players:
		var player := node as Player
		if player == null or player.health == null or not player.health.is_alive():
			continue
		waiting += 1
		if gun_count(player) < PICKS:
			return false
	return waiting > 0


static func layout(data: HoleData, _headings: Array[float], _width: float) -> void:
	var kept: Array[Dictionary] = []
	for patch in data.patches:
		if patch["type"] != Surface.Type.FAIRWAY:
			kept.append(patch)
	data.patches = kept
	var span := floor_radius() * 2.0
	data.patches.insert(0, {
		"type": Surface.Type.FAIRWAY,
		"position": data.cup,
		"size": Vector2(span, span),
		"yaw": 0.0,
		"round": true,
	})
	data.green_radius = GREEN_RADIUS
	data.spawn_points.clear()
	var radius := floor_radius() * SPAWN_RING
	for side in SIDES:
		var theta := float(side) * TAU / float(SIDES)
		data.spawn_points.append(data.cup + Vector3(sin(theta), 0.0, cos(theta)) * radius)


static func flatten(field: HeightField, data: HoleData) -> void:
	if not applies(data):
		return
	# The old disk left a circular ridge where the bowl met the hills. The
	# cart cannot climb that lip, so the whole hole sits on one deck.
	for i in field.samples.size():
		field.samples[i] = HeightField.DECK


static func nearest_gun(from: Node3D) -> Node3D:
	if from == null or not from.is_inside_tree():
		return null
	var player := from as Player
	var best: Node3D
	var best_d := INF
	for node in from.get_tree().get_nodes_in_group("gun_pickups"):
		var gun := node as GunPickup
		if gun == null or not is_instance_valid(gun):
			continue
		if player != null and player.weapon != null and player.weapon.has_gun(gun.stats):
			continue
		var dist := from.global_position.distance_to(gun.global_position)
		if dist < best_d:
			best = gun
			best_d = dist
	return best
