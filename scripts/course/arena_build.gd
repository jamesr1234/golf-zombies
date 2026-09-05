class_name ArenaBuild
extends Object
## Code-built bowl for hole 5: a 24-sided stand ring and a sitting crowd.

const CROWD_GROUP := "arena_crowd"
const ROOT_NAME := "Arena"
const APRON_NAME := "LeaveApron"
const _META_CUP := "leave_cup"
const _META_ALONG := "leave_along"
const _StepsXL := preload("res://assets/obstacles/steps_extra_large.glb")
const _StepsL := preload("res://assets/obstacles/steps_large.glb")
const _StepsM := preload("res://assets/obstacles/steps_medium.glb")
const _Wall := preload("res://assets/obstacles/wall_extra_large.glb")
const _Board := preload("res://scenes/course/structures/scoreboard.tscn")
const _Gun := preload("res://scenes/course/props/gun_pickup.tscn")
const _PALETTE: Array[Color] = [
	Palette.ICE, Palette.VIOLET, Palette.LIME, Palette.HOT_PINK, Palette.CYAN, Palette.AMBER
]


static func dress(host: Node3D, data: HoleData) -> void:
	if host == null or not ArenaHole.applies(data):
		return
	var root := Node3D.new()
	root.name = ROOT_NAME
	host.add_child(root)
	var cup := data.cup
	var along := data.cup - data.tee
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = Vector3(0.0, 0.0, -1.0)
	else:
		along = along.normalized()
	root.set_meta(_META_CUP, cup)
	root.set_meta(_META_ALONG, along)
	var radius := ArenaHole.floor_radius()
	var crowd := 0
	for side in ArenaHole.SIDES:
		var bay := _place_bay(root, cup, radius, side)
		if ArenaHole.is_gate_side(side):
			continue
		crowd = _seat_bay(root, bay, cup, crowd)
	_place_scoreboard(root, cup, radius)
	_place_weapons(root, data)
	ObstacleLeds.adopt(root)


## Knock the leave-side bays out after the round so the cart path can leave the pit.
static func open_exit(host: Node) -> void:
	if host == null:
		return
	var root := host.find_child(ROOT_NAME, true, false)
	if root == null:
		return
	for child in root.get_children():
		if not _is_exit_piece(String(child.name)):
			continue
		_clear_collision(child)
		child.queue_free()
	_lay_apron(root)


static func _is_exit_piece(node_name: String) -> bool:
	for side in ArenaHole.SIDES:
		if not ArenaHole.is_gate_side(side):
			continue
		if (
			node_name == "StepsXL_%d" % side
			or node_name == "StepsL_%d" % side
			or node_name == "StepsM_%d" % side
			or node_name == "Wall_%d" % side
		):
			return true
	return false


static func _clear_collision(node: Node) -> void:
	var body := node as CollisionObject3D
	if body != null:
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_clear_collision(child)


## A flush slab through the gate so leftover stair corners cannot ridge the cart.
static func _lay_apron(root: Node3D) -> void:
	if not root.has_meta(_META_CUP) or not root.has_meta(_META_ALONG):
		return
	if root.find_child(APRON_NAME, false, false) != null:
		return
	var cup: Vector3 = root.get_meta(_META_CUP)
	var along: Vector3 = root.get_meta(_META_ALONG)
	var width := maxf(CartPath.PATH_WIDTH + 10.0, float(ArenaHole.GATE_BAYS) * ArenaHole.BAY)
	var inner := ArenaHole.floor_radius() - 8.0
	var outer := ArenaHole.flatten_reach() + 32.0
	var length := outer - inner
	var mid: Vector3 = cup + along * ((inner + outer) * 0.5)
	var slab := MeshFactory.box_body(
		Vector3(width, 0.5, length), Palette.CART, Layers.WORLD, true, Palette.GLOW_FAINT
	)
	slab.name = APRON_NAME
	slab.position = Vector3(mid.x, cup.y - 0.22, mid.z)
	slab.rotation.y = atan2(-along.x, -along.z)
	root.add_child(slab)
	# #region agent log
	var _af := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-09d604.log", FileAccess.READ_WRITE)
	if _af == null:
		_af = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-09d604.log", FileAccess.WRITE)
	else:
		_af.seek_end()
	if _af != null:
		_af.store_line(JSON.stringify({
			"sessionId": "09d604",
			"hypothesisId": "C",
			"location": "arena_build.gd:_lay_apron",
			"message": "leave apron placed",
			"data": {
				"inner": inner,
				"outer": outer,
				"width": width,
				"slab_y": slab.position.y,
				"top": slab.position.y + 0.25,
				"cup_y": cup.y,
			},
			"timestamp": Time.get_ticks_msec(),
		}))
		_af.close()
	# #endregion


static func _theta(side: int) -> float:
	return float(side) * TAU / float(ArenaHole.SIDES)


static func _outward(theta: float) -> Vector3:
	return Vector3(sin(theta), 0.0, cos(theta))


static func _bay_xform(cup: Vector3, radius: float, side: int) -> Transform3D:
	var outward := _outward(_theta(side))
	var inward := -outward
	var yaw := atan2(inward.x, inward.z)
	var mid := cup + outward * radius
	mid.y = cup.y
	var basis := Basis(Vector3.UP, yaw)
	var origin := mid - basis.x * (ArenaHole.BAY * 0.5)
	origin.y = cup.y
	return Transform3D(basis, origin)


static func _place_bay(root: Node3D, cup: Vector3, radius: float, side: int) -> Transform3D:
	var xform := _bay_xform(cup, radius, side)
	# Gate bays stay on the pit deck. Stairs here are a 9 m ledge the cart
	# cannot climb once the wall drops.
	if not ArenaHole.is_gate_side(side):
		root.add_child(_piece(_StepsXL, xform, Vector3.ZERO, "StepsXL_%d" % side))
		root.add_child(_piece(
			_StepsL, xform, Vector3((ArenaHole.XL - ArenaHole.LARGE) * 0.5, 0.0, -ArenaHole.XL),
			"StepsL_%d" % side
		))
		root.add_child(_piece(
			_StepsM, xform,
			Vector3((ArenaHole.XL - ArenaHole.MED) * 0.5, 0.0, -(ArenaHole.XL + ArenaHole.LARGE)),
			"StepsM_%d" % side
		))
	root.add_child(_piece(
		_Wall, xform, Vector3(0.0, 0.0, -ArenaHole.STAND_DEPTH), "Wall_%d" % side
	))
	return xform


static func _piece(packed: PackedScene, bay: Transform3D, local: Vector3, node_name: String) -> Node3D:
	var node := packed.instantiate() as Node3D
	node.name = node_name
	node.transform = Transform3D(bay.basis, bay * local)
	return node


static func _place_scoreboard(root: Node3D, cup: Vector3, radius: float) -> void:
	var opposite := posmod(ArenaHole.gate_center() + ArenaHole.SIDES / 2, ArenaHole.SIDES)
	var xform := _bay_xform(cup, radius, opposite)
	var board: Node3D = _Board.instantiate()
	board.name = "Scoreboard"
	board.transform = Transform3D(
		xform.basis,
		xform * Vector3((ArenaHole.BAY - ArenaHole.XL) * 0.5, ArenaHole.LARGE, -ArenaHole.XL)
	)
	root.add_child(board)


static func _place_weapons(root: Node3D, data: HoleData) -> void:
	var n := ArenaHole.WEAPONS.size()
	if n <= 0:
		return
	var along := data.cup - data.tee
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = Vector3(0.0, 0.0, 1.0)
	else:
		along = along.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var start := -0.5 * float(n - 1) * ArenaHole.WEAPON_GAP
	for i in n:
		var pickup: GunPickup = _Gun.instantiate()
		pickup.name = "Gun_%d" % i
		pickup.stats = load(ArenaHole.WEAPONS[i]) as WeaponStats
		pickup.laid_out = true
		var at: Vector3 = data.cup + along * ArenaHole.WEAPON_ROW + side * (start + float(i) * ArenaHole.WEAPON_GAP)
		at.y = data.cup.y + ArenaHole.WEAPON_REST
		pickup.position = at
		root.add_child(pickup)


static func _seat_bay(root: Node3D, bay: Transform3D, cup: Vector3, start: int) -> int:
	var seats: Array[Vector3] = [
		Vector3(ArenaHole.XL * 0.5, ArenaHole.CELL * 3.0, -ArenaHole.CELL * 3.5),
		Vector3(ArenaHole.LARGE * 0.5 + (ArenaHole.XL - ArenaHole.LARGE) * 0.5,
			ArenaHole.CELL * 2.0, -(ArenaHole.XL + ArenaHole.CELL * 2.5)),
		Vector3(ArenaHole.MED * 0.5 + (ArenaHole.XL - ArenaHole.MED) * 0.5,
			ArenaHole.CELL, -(ArenaHole.XL + ArenaHole.LARGE + ArenaHole.CELL * 1.5)),
	]
	var index := start
	for local in seats:
		var at: Vector3 = bay * local
		root.add_child(_spectator(index, at, _face_yaw(at, cup)))
		index += 1
	return index


static func _face_yaw(at: Vector3, cup: Vector3) -> float:
	var to := cup - at
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return 0.0
	return atan2(-to.x, -to.z)


static func _spectator(index: int, at: Vector3, yaw: float) -> Node3D:
	var npc := Node3D.new()
	npc.name = "Spectator%d" % index
	npc.add_to_group(CROWD_GROUP)
	npc.position = at
	npc.rotation.y = yaw
	var body := PlayerBody.new()
	npc.add_child(body)
	body.build(_PALETTE[posmod(index, _PALETTE.size())])
	body.sit(false)
	npc.process_mode = Node.PROCESS_MODE_DISABLED
	return npc
