class_name CustomHole
extends RefCounted
## One player-made hole: the shape of the fairway and everything dropped on it.
## Plain data with no nodes, so the same record round-trips through JSON on
## disk today and can be handed to a server later without changing shape.

const VERSION := 2
const UNTITLED := "UNTITLED"
## A placement is one scene sitting on the hole. The path is either a res://
## piece from the catalog or a user:// custom structure, which expands into the
## placements it was grouped from.
const PATH := "path"
const POSITION := "position"
const YAW := "yaw"
## Only weapons use this. -1 leaves the gun live for the whole hole. Anything
## from 0 to 1 is how far down the centreline the gun stops working, which the
## creator draws as a line across the fairway and the game never shows at all.
const GATE := "gate"
const NO_GATE := -1.0
## A zipline stores its far deck here, in the same space as POSITION. Missing
## means the scene's default run. INF is the in-memory stand-in for "none".
const END := "end"
const NO_END := Vector3.INF
## Where weapon placements point. Owned here rather than read off PieceCatalog
## so this record stays clear of the editor-only catalog: everything that holds
## a placement would otherwise drag a @tool script into its own parse.
const WEAPON_DIR := "res://resources/weapons"
const ZIPLINE := "res://scenes/course/props/zipline.tscn"
const WINDMILL := "res://scenes/course/props/windmill.tscn"
const LAVA := "res://scenes/course/props/lava.tscn"
const WATER := "res://scenes/course/props/water.tscn"
const SPIN := "spin"
const POOL := "pool"
const SURFACE := "surface"
## Token path, not a scene. A dug swim tunnel: the line it follows plus a bore.
const TUNNEL := "tunnel"
const NODES := "nodes"
const BORE := "bore"
const DONE := "done"
## Shared stand-back point for a batch of lava tiles. Missing or INF means the
## tiles are still being laid and are not armed yet.
const RESPAWN := "respawn"
const NO_RESPAWN := Vector3.INF
## Token path, not a scene. The creator draws the yard; play plants the pack.
const SPAWN := "spawn"
## Token path. The creator draws a circle, then a depth; play paints the bunker.
const SANDTRAP := "sandtrap"
const RADIUS := "radius"
const AGGRO := "aggro"
const COUNTS := "counts"
const DEPTH := "depth"
const DEFAULT_RADIUS := 10.8
const DEFAULT_AGGRO := 16.2
const MAX_EACH := 12

var id := ""
var title := UNTITLED
var pieces := PackedInt32Array()
var placements: Array[Dictionary] = []
var created_at := 0
var fairway_size := FairwayPiece.Width.SMALL
## Set when a new hole is handed to the creator so it asks for a width before
## the ribbon is touched. Saved holes never need that prompt.
var needs_width := false


static func create(hole_title := UNTITLED) -> CustomHole:
	var hole := CustomHole.new()
	hole.id = _new_id()
	hole.title = hole_title
	hole.pieces = FairwayPiece.starter()
	hole.created_at = int(Time.get_unix_time_from_system())
	return hole


static func placement(
	path: String, position: Vector3, yaw := 0.0, gate := NO_GATE, end := NO_END
) -> Dictionary:
	var row := {PATH: path, POSITION: position, YAW: yaw, GATE: gate}
	if end.is_finite():
		row[END] = end
	return row


static func is_weapon(path: String) -> bool:
	return path.begins_with(WEAPON_DIR)


static func is_zipline(path: String) -> bool:
	return path == ZIPLINE


static func is_windmill(path: String) -> bool:
	return path == WINDMILL


static func is_lava(path: String) -> bool:
	return path == LAVA or path.get_file() == "lava.tscn"


static func is_water(path: String) -> bool:
	return path == WATER or path.get_file() == "water.tscn"


static func is_tunnel(path: String) -> bool:
	return path == TUNNEL


static func lava_spots(listed: Array) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for entry in listed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if is_lava(String(entry.get(PATH, ""))):
			spots.append(entry[POSITION] as Vector3)
	return spots


static func has_respawn(entry: Dictionary) -> bool:
	return entry.has(RESPAWN) and (entry[RESPAWN] as Vector3).is_finite()


static func respawn_of(entry: Dictionary) -> Vector3:
	return entry[RESPAWN] as Vector3 if has_respawn(entry) else NO_RESPAWN


static func spin_of(entry: Dictionary) -> float:
	return CartPathWindmill.clamp_spin(float(entry.get(SPIN, CartPathWindmill.SPIN_DEFAULT)))


static func is_spawn(path: String) -> bool:
	return path == SPAWN


static func is_sandtrap(path: String) -> bool:
	return path == SANDTRAP or path.get_file() == SANDTRAP


static func has_end(entry: Dictionary) -> bool:
	return entry.has(END) and (entry[END] as Vector3).is_finite()


static func end_of(entry: Dictionary) -> Vector3:
	return entry[END] as Vector3 if has_end(entry) else NO_END


func par() -> int:
	return FairwayPiece.par_for(pieces)


func width() -> float:
	return FairwayPiece.width_for(pieces, fairway_size)


func width_label() -> String:
	return FairwayPiece.width_label(fairway_size)


func length() -> float:
	return FairwayPiece.total_length(pieces)


func centerline() -> Array[Vector3]:
	return FairwayPiece.points(pieces)


func is_playable() -> bool:
	return FairwayPiece.is_playable(pieces, fairway_size)


func has_open_lava() -> bool:
	for entry in placements:
		if is_lava(String(entry[PATH])) and not has_respawn(entry):
			return true
	return false


func has_open_water() -> bool:
	for entry in placements:
		if is_water(String(entry[PATH])) and float(entry.get(DEPTH, 0.0)) <= 0.001:
			return true
	return false


## A dig that never reached a second pond is a dead end, so the hole is not
## ready to play until every tunnel lands.
func has_open_tunnel() -> bool:
	for entry in placements:
		if is_tunnel(String(entry[PATH])) and not bool(entry.get(DONE, false)):
			return true
	return false


## The line a tunnel follows, in world points. Held here as plain vectors so a
## record never has to reach into the node that draws it.
static func nodes_of(entry: Dictionary) -> Array:
	var listed: Variant = entry.get(NODES, [])
	return listed if typeof(listed) == TYPE_ARRAY else []


static func has_pool(entry: Dictionary) -> bool:
	return entry.has(POOL) and (entry[POOL] as Vector3).is_finite()


static func pool_of(entry: Dictionary) -> Vector3:
	return entry[POOL] as Vector3 if has_pool(entry) else Vector3.INF


## Tiles locked with one depth share a pond. Unfinished tiles are one pool.
static func same_water(a: Dictionary, b: Dictionary) -> bool:
	if not is_water(String(a.get(PATH, ""))) or not is_water(String(b.get(PATH, ""))):
		return false
	var left := pool_of(a)
	var right := pool_of(b)
	if left.is_finite() != right.is_finite():
		return false
	return not left.is_finite() or left.distance_squared_to(right) < 0.0025


static func water_pool(listed: Array, index: int) -> Array[int]:
	var out: Array[int] = []
	if index < 0 or index >= listed.size() or typeof(listed[index]) != TYPE_DICTIONARY:
		return out
	var seed: Dictionary = listed[index]
	if not is_water(String(seed.get(PATH, ""))):
		return out
	for i in listed.size():
		if typeof(listed[i]) != TYPE_DICTIONARY:
			continue
		if same_water(seed, listed[i]):
			out.append(i)
	return out


static func water_groups(listed: Array) -> Array:
	var groups: Array = []
	var used := {}
	for i in listed.size():
		if used.has(i):
			continue
		var pool := water_pool(listed, i)
		if pool.is_empty():
			continue
		var rows: Array[Dictionary] = []
		for j in pool:
			used[j] = true
			rows.append(listed[j])
		groups.append(rows)
	return groups


## Tiles confirmed together share a stand-back. Unfinished tiles are one pool.
static func same_lava(a: Dictionary, b: Dictionary) -> bool:
	if not is_lava(String(a.get(PATH, ""))) or not is_lava(String(b.get(PATH, ""))):
		return false
	var left := respawn_of(a)
	var right := respawn_of(b)
	if left.is_finite() != right.is_finite():
		return false
	return not left.is_finite() or left.distance_squared_to(right) < 0.0025


static func lava_pool(listed: Array, index: int) -> Array[int]:
	var out: Array[int] = []
	if index < 0 or index >= listed.size() or typeof(listed[index]) != TYPE_DICTIONARY:
		return out
	var seed: Dictionary = listed[index]
	if not is_lava(String(seed.get(PATH, ""))):
		return out
	for i in listed.size():
		if typeof(listed[i]) != TYPE_DICTIONARY:
			continue
		if same_lava(seed, listed[i]):
			out.append(i)
	return out


static func lava_groups(listed: Array) -> Array:
	var groups: Array = []
	var used := {}
	for i in listed.size():
		if used.has(i):
			continue
		var pool := lava_pool(listed, i)
		if pool.is_empty():
			continue
		var rows: Array[Dictionary] = []
		for j in pool:
			used[j] = true
			rows.append(listed[j])
		groups.append(rows)
	return groups


func can_append(index: int) -> bool:
	return FairwayPiece.can_append(pieces, index, fairway_size)


func allowed_pieces() -> Array[bool]:
	return FairwayPiece.allowed(pieces, fairway_size)


func append_piece(index: int) -> bool:
	if not can_append(index):
		return false
	pieces.append(index)
	return true


## Dropping the last piece can strand anything that was built out on it, so the
## placements beyond the shortened ribbon come off with it.
func pop_piece() -> bool:
	if not FairwayPiece.can_pop(pieces):
		return false
	pieces.remove_at(pieces.size() - 1)
	prune_placements()
	return true


func add_placement(
	path: String, position: Vector3, yaw := 0.0, gate := NO_GATE, end := NO_END
) -> void:
	placements.append(placement(path, position, yaw, gate, end))


func remove_placement(index: int) -> void:
	if index >= 0 and index < placements.size():
		placements.remove_at(index)


## How far off the middle of the fairway a piece may still be dropped. Beyond
## the lip walls nothing is reachable, so there is nothing to build out there.
func reach() -> float:
	return width() * 0.5


func covers(position: Vector3) -> bool:
	var line := centerline()
	var closest := INF
	for i in range(1, line.size()):
		var on := Geometry3D.get_closest_point_to_segment(position, line[i - 1], line[i])
		closest = minf(closest, Vector2(position.x - on.x, position.z - on.z).length())
	return closest <= reach()


func prune_placements() -> void:
	var kept: Array[Dictionary] = []
	for entry in placements:
		if covers(entry[POSITION]):
			kept.append(entry)
	placements = kept


## Wipe the ribbon and everything on it. The name and width stay, so a hole
## can be started over without going back to the browser.
func erase() -> void:
	pieces = FairwayPiece.starter()
	placements.clear()


func copy() -> CustomHole:
	return from_dict(to_dict())


## Restore this record in place so the tools that already hold it keep working.
func take_from(other: CustomHole) -> void:
	if other == null:
		return
	id = other.id
	title = other.title
	created_at = other.created_at
	fairway_size = other.fairway_size
	needs_width = other.needs_width
	pieces = other.pieces.duplicate()
	placements = []
	for entry in other.placements:
		placements.append(entry.duplicate(true))


func to_dict() -> Dictionary:
	var listed: Array = []
	for entry in placements:
		var row := {
			PATH: String(entry[PATH]),
			POSITION: to_array(entry[POSITION]),
			YAW: float(entry[YAW]),
			GATE: float(entry.get(GATE, NO_GATE)),
		}
		if has_end(entry):
			row[END] = to_array(entry[END])
		if is_spawn(String(entry[PATH])):
			row[RADIUS] = float(entry.get(RADIUS, DEFAULT_RADIUS))
			row[AGGRO] = float(entry.get(AGGRO, DEFAULT_AGGRO))
			row[COUNTS] = spawn_counts(entry.get(COUNTS, {}))
		if is_sandtrap(String(entry[PATH])):
			row[RADIUS] = float(entry.get(RADIUS, 5.4))
			row[DEPTH] = float(entry.get(DEPTH, 0.9))
		if is_water(String(entry[PATH])):
			if entry.has(DEPTH):
				row[DEPTH] = snappedf(float(entry[DEPTH]), 0.001)
			if has_pool(entry):
				row[POOL] = to_array(pool_of(entry))
			if entry.has(SURFACE):
				row[SURFACE] = snappedf(float(entry[SURFACE]), 0.001)
		if is_tunnel(String(entry[PATH])):
			var dug: Array = []
			for point in nodes_of(entry):
				dug.append(to_array(point))
			row[NODES] = dug
			row[BORE] = snappedf(float(entry.get(BORE, 0.0)), 0.001)
			row[DONE] = bool(entry.get(DONE, false))
			if has_pool(entry):
				row[POOL] = to_array(pool_of(entry))
		if is_windmill(String(entry[PATH])) or entry.has(SPIN):
			row[SPIN] = CartPathWindmill.clamp_spin(
				float(entry.get(SPIN, CartPathWindmill.SPIN_DEFAULT))
			)
		if has_respawn(entry):
			row[RESPAWN] = to_array(entry[RESPAWN])
		listed.append(row)
	return {
		"version": VERSION,
		"id": id,
		"title": title,
		"created_at": created_at,
		"fairway_size": int(fairway_size),
		"pieces": Array(pieces),
		"placements": listed,
	}


static func from_dict(body: Dictionary) -> CustomHole:
	var hole := CustomHole.new()
	hole.id = String(body.get("id", _new_id()))
	hole.title = String(body.get("title", UNTITLED))
	hole.created_at = int(body.get("created_at", 0))
	hole.fairway_size = clampi(
		int(body.get("fairway_size", FairwayPiece.Width.SMALL)),
		FairwayPiece.Width.SMALL, FairwayPiece.Width.GIGANTIC
	) as FairwayPiece.Width
	for index in body.get("pieces", []):
		hole.pieces.append(int(index))
	for entry in body.get("placements", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row := placement(
			String(entry.get(PATH, "")),
			to_vector(entry.get(POSITION, [])),
			float(entry.get(YAW, 0.0)),
			float(entry.get(GATE, NO_GATE)),
			to_vector(entry[END]) if entry.has(END) else NO_END
		)
		if is_sandtrap(String(row[PATH])):
			row[RADIUS] = float(entry.get(RADIUS, 5.4))
			row[DEPTH] = float(entry.get(DEPTH, 0.9))
		elif is_water(String(row[PATH])):
			if entry.has(DEPTH):
				row[DEPTH] = float(entry[DEPTH])
			if entry.has(POOL):
				row[POOL] = to_vector(entry[POOL])
			if entry.has(SURFACE):
				row[SURFACE] = float(entry[SURFACE])
		elif is_tunnel(String(row[PATH])):
			var dug: Array[Vector3] = []
			for point in entry.get(NODES, []):
				dug.append(to_vector(point))
			row[NODES] = dug
			row[BORE] = float(entry.get(BORE, 0.0))
			row[DONE] = bool(entry.get(DONE, false))
			if entry.has(POOL):
				row[POOL] = to_vector(entry[POOL])
		elif is_spawn(String(row[PATH])) or entry.has(RADIUS) or entry.has(COUNTS) or entry.has(AGGRO):
			row[RADIUS] = float(entry.get(RADIUS, DEFAULT_RADIUS))
			row[AGGRO] = float(entry.get(AGGRO, DEFAULT_AGGRO))
			row[COUNTS] = spawn_counts(entry.get(COUNTS, {}))
		if is_windmill(String(row[PATH])) or entry.has(SPIN):
			row[SPIN] = CartPathWindmill.clamp_spin(
				float(entry.get(SPIN, CartPathWindmill.SPIN_DEFAULT))
			)
		if entry.has(RESPAWN):
			row[RESPAWN] = to_vector(entry[RESPAWN])
		hole.placements.append(row)
	if int(body.get("version", 1)) < VERSION:
		PieceLadder.remap_centers(hole.placements)
	return hole


## Shared with saved structures, which store the same placement shape.
static func to_array(at: Vector3) -> Array:
	return [snappedf(at.x, 0.001), snappedf(at.y, 0.001), snappedf(at.z, 0.001)]


static func to_vector(listed) -> Vector3:
	if typeof(listed) != TYPE_ARRAY or (listed as Array).size() < 3:
		return Vector3.ZERO
	return Vector3(float(listed[0]), float(listed[1]), float(listed[2]))


static func spawn_counts(raw) -> Dictionary:
	var out := {"walker": 0, "runner": 0, "brute": 0, "gunner": 0}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key in out.keys():
		out[key] = clampi(int(raw.get(key, 0)), 0, MAX_EACH)
	return out


static func _new_id() -> String:
	return "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
