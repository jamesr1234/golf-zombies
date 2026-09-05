class_name ClubhouseBuild
extends Object
## Layout of the walk-in clubhouse. Shell, decor, counters and regulars are
## assembled here so the Clubhouse node only has to own the result.

const _Upper := preload("res://scripts/shop/clubhouse_upper.gd")
const _Elevator := preload("res://scripts/shop/clubhouse_elevator.gd")

const WIDTH := 36.0
const DEPTH := 32.0
const WALL := 5.4
const STORY_H := 5.4
const SLAB := 0.28
const THICK := 0.34
const DOOR := 3.4
const OPEN := 3.2
const HALL := 6.0
const FLOOR_Y := 0.28
const RAISE := 0.92
const SPLIT_FRONT := 4.0
const SPLIT_BACK := -6.0
const PLAZA_THICK := 0.5
const PLAZA_SIDE := 4.0
const PLAZA_BACK := 12.0
const PLAZA_FRONT := 20.0
const PLAZA_TOP := 0.26
const EXIT_GAP := 5.0
const WALL_INSET := 5.5
## Staging tee to hall centre. Same offset the cart path uses.
const TEE_SIDE := 26.0
const PAD_BLEND := 8.0
const PAD_HALF_X := WIDTH * 0.5 + PLAZA_SIDE
const PAD_Z_MIN := -DEPTH * 0.5 - PLAZA_BACK
const PAD_Z_MAX := DEPTH * 0.5 + PLAZA_FRONT


static func assemble(host: Clubhouse) -> void:
	_plaza(host)
	ClubhouseShell.build(host)
	_doors(host)
	ClubhouseDecor.build(host)
	_lights(host)
	_stations(host)
	_lounge(host)
	_Upper.build(host)
	host.elevator = _Elevator.create()
	host.add_child(host.elevator)


static func floor_y(raised: bool) -> float:
	return PLAZA_TOP + (RAISE if raised else 0.0)


## Walkable Y of story `n`. Story 0 is the raised hall; later stories sit on the
## wall tops so a third floor is `story_floor_y(2)`.
static func story_floor_y(story: int) -> float:
	if story <= 0:
		return floor_y(true)
	return STORY_H * float(story)


## Counters and regulars only answer on their own floor.
static func same_story(a: Vector3, b: Vector3) -> bool:
	return absf(a.y - b.y) < STORY_H * 0.5


static func heading_xz(forward: Vector3) -> Vector3:
	var along := Vector3(forward.x, 0.0, forward.z)
	if along.length_squared() < 0.0001:
		return Vector3.FORWARD
	return along.normalized()


## Hall origin when the back doors open onto the practice tee.
static func at_exit(practice_tee: Vector3, forward: Vector3) -> Vector3:
	var along := heading_xz(forward)
	var spot := practice_tee - along * (DEPTH * 0.5 + EXIT_GAP)
	spot.y = practice_tee.y - PLAZA_TOP
	return spot


static func yaw_at_exit(forward: Vector3) -> float:
	var along := heading_xz(forward)
	return rad_to_deg(atan2(-along.x, -along.z))


## Hall origin beside a staging tee, doors facing the pad.
static func at_tee(tee: Vector3, heading: Vector3) -> Vector3:
	return tee + heading_xz(heading).cross(Vector3.UP).normalized() * TEE_SIDE


static func yaw_at_tee(tee: Vector3, origin: Vector3) -> float:
	var to_tee := tee - origin
	to_tee.y = 0.0
	return rad_to_deg(atan2(to_tee.x, to_tee.z))


## Metres to the plaza edge. Positive is on the slab, negative is off it.
static func pad_edge(origin: Vector3, yaw_deg: float, point: Vector3) -> float:
	var local := (point - origin).rotated(Vector3.UP, -deg_to_rad(yaw_deg))
	return minf(PAD_HALF_X - absf(local.x), minf(local.z - PAD_Z_MIN, PAD_Z_MAX - local.z))


static func covers_ground(origin: Vector3, yaw_deg: float, point: Vector3, extra := 0.0) -> bool:
	return pad_edge(origin, yaw_deg, point) >= -extra


static func covers_exit_ground(
	practice_tee: Vector3, forward: Vector3, point: Vector3, extra := 0.0
) -> bool:
	return covers_ground(at_exit(practice_tee, forward), yaw_at_exit(forward), point, extra)


static func _plaza(host: Clubhouse) -> void:
	var size := Vector3(
		WIDTH + PLAZA_SIDE * 2.0,
		PLAZA_THICK,
		DEPTH + PLAZA_BACK + PLAZA_FRONT
	)
	var body := MeshFactory.box_body(size, Palette.CART, Layers.WORLD, true, Palette.GLOW_FAINT)
	MeshFactory.apply_grid(body, Surface.LOOK[Surface.Type.TEE])
	body.position = Vector3(0.0, PLAZA_TOP - PLAZA_THICK * 0.5, (PLAZA_FRONT - PLAZA_BACK) * 0.5)
	host.plaza = body
	host.add_child(body)


static func _doors(host: Clubhouse) -> void:
	host.door_left = _door(host, -1.0, 1.0)
	host.door_right = _door(host, 1.0, 1.0)
	host.exit_left = _door(host, -1.0, -1.0)
	host.exit_right = _door(host, 1.0, -1.0)


static func _door(host: Clubhouse, side: float, z_sign: float) -> Node3D:
	var hinge := Node3D.new()
	hinge.position = Vector3(side * DOOR * 0.5, WALL * 0.5, z_sign * (DEPTH * 0.5 - 0.04))
	var slab := MeshFactory.box_body(
		Vector3(DOOR * 0.5, WALL - 0.25, 0.12), Palette.BABY_BLUE, Layers.PROP, true, Palette.GLOW_FAINT
	)
	slab.position.x = -side * DOOR * 0.25
	hinge.add_child(slab)
	host.add_child(hinge)
	return hinge


static func _lights(host: Clubhouse) -> void:
	for at in [
		Vector3(0.0, 3.6, 9.0), Vector3(-12.0, 3.2, 9.0), Vector3(12.0, 3.2, 9.0),
		Vector3(0.0, 4.2, -1.0), Vector3(-12.0, 4.0, -1.0), Vector3(12.0, 4.0, -1.0),
		Vector3(0.0, 3.8, -11.0), Vector3(-12.0, 4.0, -11.0), Vector3(12.0, 4.0, -11.0)
	]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.62, 0.28)
		lamp.light_energy = 0.9 if absf(at.x) > 8.0 else 0.48
		lamp.omni_range = 7.5
		lamp.position = at
		host.add_child(lamp)


static func _stations(host: Clubhouse) -> void:
	var ground := floor_y(false)
	var upper := floor_y(true)
	var wall := WIDTH * 0.5 - WALL_INSET
	var specs: Array = [
		[Shop.Dept.APPAREL, "Apparel", Vector3(-wall, ground, 10.0), 90.0],
		[Shop.Dept.WEAPONS, "Armory", Vector3(wall, ground, 10.0), -90.0],
		[Shop.Dept.CLUBS, "Clubs", Vector3(-wall, upper, -1.0), 90.0],
		[Shop.Dept.ITEMS, "Items", Vector3(wall, upper, -1.0), -90.0],
		[Shop.Dept.CART, "Cart", Vector3(-wall, upper, -11.0), 90.0],
	]
	for i in specs.size():
		var spec: Array = specs[i]
		var station := ShopStation.create(int(spec[0]), String(spec[1]), spec[2], float(spec[3]))
		station.cashier = ShopFront.dress(station, int(spec[0]), 6 + i)
		host.stations.append(station)
		host.cashiers.append(station.cashier)
		host.add_child(station)
	var face := WIDTH * 0.5 - THICK
	ShopFront.wall_display(host, Shop.Dept.APPAREL, Vector3(-face, 0.0, 10.0), 90.0)
	ShopFront.wall_display(host, Shop.Dept.WEAPONS, Vector3(face, 0.0, 10.0), -90.0)
	ShopFront.wall_display(host, Shop.Dept.CLUBS, Vector3(-face, RAISE, -1.0), 90.0)
	ShopFront.wall_display(host, Shop.Dept.ITEMS, Vector3(face, RAISE, -1.0), -90.0)
	ShopFront.wall_display(host, Shop.Dept.CART, Vector3(-face, RAISE, -11.0), 90.0)


static func _lounge(host: Clubhouse) -> void:
	var ground := floor_y(false)
	var upper := floor_y(true)
	var foyer_a := ClubhouseNpc.create(0, Vector3(-1.35, ground, 8.6), 90.0)
	var foyer_b := ClubhouseNpc.create(1, Vector3(1.35, ground, 8.6), -90.0)
	var lounge_a := ClubhouseNpc.create(2, Vector3(-1.7, upper, -2.2), 90.0, true)
	var lounge_b := ClubhouseNpc.create(3, Vector3(1.7, upper, -2.2), -90.0, true)
	var hall_a := ClubhouseNpc.create(4, Vector3(-4.5, upper, -0.2), 90.0)
	var hall_b := ClubhouseNpc.create(5, Vector3(4.5, upper, -0.2), -90.0)
	ClubhouseNpc.pair(foyer_a, foyer_b)
	ClubhouseNpc.pair(lounge_a, lounge_b)
	ClubhouseNpc.pair(hall_a, hall_b)
	_chair(host, Vector3(-1.7, upper, -2.2), 90.0)
	_chair(host, Vector3(1.7, upper, -2.2), -90.0)
	for npc in [foyer_a, foyer_b, lounge_a, lounge_b, hall_a, hall_b]:
		host.npcs.append(npc)
		host.add_child(npc)


static func _chair(host: Clubhouse, at: Vector3, yaw: float) -> void:
	var seat := MeshFactory.box_body(
		Vector3(0.72, 0.42, 0.72), Palette.WALL, Layers.PROP, true, Palette.GLOW_FAINT
	)
	seat.position = at + Vector3(0.0, 0.21, 0.0)
	seat.rotation.y = deg_to_rad(yaw)
	host.add_child(seat)
	var back := MeshFactory.box(Vector3(0.72, 0.7, 0.12), Palette.BABY_BLUE, Palette.GLOW_FAINT)
	back.position = Vector3(0.0, 0.55, 0.28)
	seat.add_child(back)
