class_name CustomHole
extends RefCounted
## One player-made hole: the shape of the fairway and everything dropped on it.
## Plain data with no nodes, so the same record round-trips through JSON on
## disk today and can be handed to a server later without changing shape.

const VERSION := 1
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


func copy() -> CustomHole:
	return from_dict(to_dict())


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
		hole.placements.append(placement(
			String(entry.get(PATH, "")),
			to_vector(entry.get(POSITION, [])),
			float(entry.get(YAW, 0.0)),
			float(entry.get(GATE, NO_GATE)),
			to_vector(entry[END]) if entry.has(END) else NO_END
		))
	return hole


## Shared with saved structures, which store the same placement shape.
static func to_array(at: Vector3) -> Array:
	return [snappedf(at.x, 0.001), snappedf(at.y, 0.001), snappedf(at.z, 0.001)]


static func to_vector(listed) -> Vector3:
	if typeof(listed) != TYPE_ARRAY or (listed as Array).size() < 3:
		return Vector3.ZERO
	return Vector3(float(listed[0]), float(listed[1]), float(listed[2]))


static func _new_id() -> String:
	return "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
