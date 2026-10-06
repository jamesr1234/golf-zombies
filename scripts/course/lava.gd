@tool
class_name Lava
extends StaticBody3D
## Red pool. The body is a ball-only skip deck; a child area dunks walkers.

const _Look := preload("res://scripts/course/lava_look.gd")


const GROUP := "lava"
const SCENE := "res://scenes/course/props/lava.tscn"
const COLOR := Color(1.0, 0.16, 0.04)
const SPAN := GridSnap.CELL
## Shallow enough that a zipline over the pool does not count as a dunk.
const DETECT_HEIGHT := 0.85
const CART_LIFT := 0.4

## World point to stand on after a dunk. INF means this tile is not armed.
var respawn := Vector3.INF
## World cell centres when this node is a whole pool. Empty means a lone tile.
var _cells: Array[Vector3] = []


static func from_cells(cells: Array[Vector3], point: Vector3) -> Lava:
	var packed := load(SCENE) as PackedScene
	var lava := packed.instantiate() as Lava
	lava._cells = cells
	lava.respawn = point
	return lava


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = Layers.LAVA
	collision_mask = 0
	var skin := PhysicsMaterial.new()
	skin.bounce = 0.88
	skin.friction = 0.12
	physics_material_override = skin
	if get_child_count() == 0:
		if _cells.is_empty():
			_assemble()
		else:
			_assemble_pool(_cells)
	var kill := get_node_or_null("Kill") as Area3D
	if kill != null:
		kill.monitoring = respawn.is_finite() and not Engine.is_editor_hint()
		if not kill.body_entered.is_connected(_on_body_entered):
			kill.body_entered.connect(_on_body_entered)


func try_dunk(body: Node3D) -> bool:
	if Engine.is_editor_hint() or not respawn.is_finite() or body == null:
		return false
	if NetSession.is_active() and not NetSession.is_host():
		return false
	var cart := body as GolfCart
	if cart != null:
		cart.recover_at(respawn + Vector3.UP * CART_LIFT, rad_to_deg(cart.rotation.y))
		Sfx.play("hazard", cart)
		return true
	if body is GolfBall:
		return false
	var player := _player_from(body)
	if player == null or player.state == Player.State.RIDING:
		return false
	if (
		player.state == Player.State.ZIPLINING
		or player.state == Player.State.GRAPPLING
		or player.state == Player.State.CLIMBING
	):
		return false
	if player.health != null and not player.health.is_alive():
		return false
	return player.fall_in_lava(respawn)


## Square footprint on the 1.35 m grid, XZ only. Height is ignored so a point
## hovering over a tile still counts as landing in it.
static func tile_covers(tile_at: Vector3, point: Vector3) -> bool:
	var half := SPAN * 0.5 + 0.02
	return maxf(absf(point.x - tile_at.x), absf(point.z - tile_at.z)) <= half


## True when a stand would still dip into this tile's kill column.
static func covers_stand(tile_at: Vector3, point: Vector3) -> bool:
	return tile_covers(tile_at, point) and point.y < tile_at.y + DETECT_HEIGHT


static func covers_any(placements: Array, point: Vector3) -> bool:
	for entry in placements:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not is_tile(String(entry.get("path", ""))):
			continue
		if tile_covers(entry["position"] as Vector3, point):
			return true
	return false


static func would_cover_respawn(placements: Array, tile_at: Vector3) -> bool:
	for entry in placements:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not entry.has("respawn") or not (entry["respawn"] is Vector3):
			continue
		var point: Vector3 = entry["respawn"]
		if point.is_finite() and covers_stand(tile_at, point):
			return true
	return false


static func is_tile(path: String) -> bool:
	return path == SCENE or path.get_file() == "lava.tscn"


## Inclusive grid cells from one corner to the other, XZ only.
static func cells_between(from: Vector3, to: Vector3) -> Array[Vector3]:
	var ax := snappedf(from.x, SPAN)
	var az := snappedf(from.z, SPAN)
	var bx := snappedf(to.x, SPAN)
	var bz := snappedf(to.z, SPAN)
	var x0 := minf(ax, bx)
	var x1 := maxf(ax, bx)
	var z0 := minf(az, bz)
	var z1 := maxf(az, bz)
	var out: Array[Vector3] = []
	var x := x0
	while x <= x1 + 0.001:
		var z := z0
		while z <= z1 + 0.001:
			out.append(Vector3(x, 0.0, z))
			z += SPAN
		x += SPAN
	return out


func _assemble() -> void:
	_build_pool([Vector3.ZERO], Vector3.ZERO)


func _assemble_pool(cells: Array[Vector3]) -> void:
	var origin := _centroid(cells)
	position = origin
	_build_pool(cells, origin)


func _build_pool(cells: Array[Vector3], origin: Vector3) -> void:
	var kill := Area3D.new()
	kill.name = "Kill"
	kill.collision_layer = 0
	kill.collision_mask = Layers.PLAYER | Layers.VEHICLE | Layers.MECH
	kill.monitorable = false
	add_child(kill)
	for cell in cells:
		kill.add_child(_detector_at(cell - origin))
		add_child(_Look.skip_shape(cell - origin))
	if cells.size() == 1:
		add_child(_Look.slab_at(cells[0] - origin))
	else:
		add_child(_Look.pool_surface(cells, origin))
	if not Engine.is_editor_hint():
		add_child(_Look.bubbles(cells, origin))
	add_child(_lamp(_lamp_range(cells, origin)))


func _detector_at(offset: Vector3) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SPAN, DETECT_HEIGHT, SPAN)
	node.shape = box
	node.position = Vector3(offset.x, DETECT_HEIGHT * 0.5, offset.z)
	return node


func _lamp(reach: float) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 2.4
	lamp.omni_range = reach
	lamp.position.y = 0.8
	return lamp


func _lamp_range(cells: Array[Vector3], origin: Vector3) -> float:
	var reach := 0.0
	for cell in cells:
		reach = maxf(reach, Vector2(cell.x - origin.x, cell.z - origin.z).length())
	return maxf(5.5, reach + 3.5)


func _centroid(cells: Array[Vector3]) -> Vector3:
	var origin := Vector3.ZERO
	for cell in cells:
		origin += cell
	return origin / float(cells.size())


func _on_body_entered(body: Node3D) -> void:
	try_dunk(body)


static func _player_from(body: Node3D) -> Player:
	var player := body as Player
	if player != null:
		return player
	var mech := body as MechSuit
	if mech != null:
		return mech.pilot
	return null
