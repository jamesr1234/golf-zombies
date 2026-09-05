class_name FairwayPiece
extends Object
## The eight fairway shapes the hole creator lays down. A piece is one segment
## of centerline: how far the ribbon turns off the last heading, then how far it
## runs. Keeping the choice small is deliberate, so a hole is made interesting
## by what gets built on it rather than by the shape of the grass.
##
## Turn sign follows the engine: a heading is fed to Vector3.FORWARD.rotated on
## the up axis, so a positive turn bends left.

## Every custom hole is laid out as hole 1, which has no setpiece attached to it.
const INDEX := 0
const MIN_PIECES := 2
const MAX_PIECES := 50
## Two centerlines that are not joined need a full fairway between them, plus a
## little slack, or the lip walls of one strip end up standing on the other.
const CLEARANCE := 1.15
## How close to the joining corners a hit has to be to count as the ribbon's
## own turn rather than a fold. Wide strips are closer than a full width at
## every bend; that is still one fairway.
const CORRIDOR := 0.75
## Small is the regular strip. Large is the double-wide landing strip. Medium
## sits halfway between. Extra large is triple, gigantic is four times across.
enum Width { SMALL, MEDIUM, LARGE, EXTRA_LARGE, GIGANTIC }
const WIDTH_SCALE: PackedFloat32Array = [1.0, 1.5, 2.0, 3.0, 4.0]
const WIDTH_LABELS: PackedStringArray = ["SMALL", "MEDIUM", "LARGE", "EXTRA LARGE", "GIGANTIC"]

const PIECES: Array[Dictionary] = [
	{"id": "straight", "label": "STRAIGHT", "turn": 0.0, "length": 34.0},
	{"id": "long_straight", "label": "LONG STRAIGHT", "turn": 0.0, "length": 56.0},
	{"id": "gentle_left", "label": "GENTLE LEFT", "turn": 20.0, "length": 36.0},
	{"id": "gentle_right", "label": "GENTLE RIGHT", "turn": -20.0, "length": 36.0},
	{"id": "sharp_left", "label": "SHARP LEFT", "turn": 45.0, "length": 32.0},
	{"id": "sharp_right", "label": "SHARP RIGHT", "turn": -45.0, "length": 32.0},
	{"id": "dogleg_left", "label": "DOGLEG LEFT", "turn": 72.0, "length": 30.0},
	{"id": "dogleg_right", "label": "DOGLEG RIGHT", "turn": -72.0, "length": 30.0},
]


static func count() -> int:
	return PIECES.size()


static func at(index: int) -> Dictionary:
	return PIECES[clampi(index, 0, PIECES.size() - 1)]


static func label_of(index: int) -> String:
	return String(at(index)["label"])


static func id_of(index: int) -> String:
	return String(at(index)["id"])


static func index_of(id: String) -> int:
	for i in PIECES.size():
		if PIECES[i]["id"] == id:
			return i
	return -1


## A fresh hole is already playable: a straight off the tee and a gentle bend.
static func starter() -> PackedInt32Array:
	return PackedInt32Array([index_of("long_straight"), index_of("gentle_right")])


static func headings(pieces: PackedInt32Array) -> Array[float]:
	var out: Array[float] = []
	var heading := 0.0
	for index in pieces:
		heading += float(at(index)["turn"])
		out.append(heading)
	return out


static func lengths(pieces: PackedInt32Array) -> Array[float]:
	var out: Array[float] = []
	for index in pieces:
		out.append(float(at(index)["length"]))
	return out


## Tee at the origin, first segment running down negative Z, matching how the
## generator lays out every other hole.
static func points(pieces: PackedInt32Array) -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3.ZERO]
	var turned := headings(pieces)
	var run := lengths(pieces)
	var at_point := Vector3.ZERO
	for i in pieces.size():
		var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(turned[i]))
		at_point += direction * run[i]
		out.append(at_point)
	return out


static func total_length(pieces: PackedInt32Array) -> float:
	var total := 0.0
	for length in lengths(pieces):
		total += length
	return total


static func par_for(pieces: PackedInt32Array) -> int:
	return HoleGenerator.par_for_length(total_length(pieces))


static func width_scale(size: Width) -> float:
	return WIDTH_SCALE[clampi(int(size), 0, WIDTH_SCALE.size() - 1)]


static func width_label(size: Width) -> String:
	return WIDTH_LABELS[clampi(int(size), 0, WIDTH_LABELS.size() - 1)]


static func width_for(pieces: PackedInt32Array, size := Width.SMALL) -> float:
	return HoleGenerator.fairway_width(par_for(pieces), INDEX) * width_scale(size)


## A piece may go down when the ribbon it makes still reads as one fairway: no
## strip doubling back over an earlier one, and no more pieces than a hole can
## carry.
static func can_append(pieces: PackedInt32Array, index: int, size := Width.SMALL) -> bool:
	if index < 0 or index >= PIECES.size():
		return false
	if pieces.size() >= MAX_PIECES:
		return false
	var next := pieces.duplicate()
	next.append(index)
	return is_clear(next, size)


static func can_pop(pieces: PackedInt32Array) -> bool:
	return pieces.size() > 0


static func is_playable(pieces: PackedInt32Array, size := Width.SMALL) -> bool:
	return pieces.size() >= MIN_PIECES and pieces.size() <= MAX_PIECES and is_clear(pieces, size)


## Only segments that do not share a corner are compared. Joined segments always
## touch, which is the whole point of a turn. A wide ribbon's next piece also
## sits closer than a full width across the piece in between; that approach is
## the chain already joining them, not a fold.
static func is_clear(pieces: PackedInt32Array, size := Width.SMALL) -> bool:
	if pieces.size() < 3:
		return true
	var line := points(pieces)
	var gap := width_for(pieces, size) * CLEARANCE
	for i in range(1, line.size()):
		for j in range(i + 2, line.size()):
			var closest := Geometry3D.get_closest_points_between_segments(
				line[i - 1], line[i], line[j - 1], line[j]
			)
			if closest[0].distance_to(closest[1]) >= gap:
				continue
			if _joins_through_chain(closest[0], closest[1], line[i], line[j - 1]):
				continue
			return false
	return true


static func _joins_through_chain(a: Vector3, b: Vector3, from: Vector3, to: Vector3) -> bool:
	return a.distance_to(from) <= CORRIDOR and b.distance_to(to) <= CORRIDOR


## Pieces that would still leave a valid ribbon, for greying out the rest of
## the palette instead of letting a player pick a dead end.
static func allowed(pieces: PackedInt32Array, size := Width.SMALL) -> Array[bool]:
	var out: Array[bool] = []
	for i in PIECES.size():
		out.append(can_append(pieces, i, size))
	return out
