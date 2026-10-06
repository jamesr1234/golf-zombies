class_name DigTunnel
extends RefCounted
## Digging a swim tunnel between two finished ponds, kept off PlaceWater so the
## pond flow stays readable.
##
## A whole corridor is one placement holding the line it follows, so a run with
## four corners costs four points rather than a tile per metre. Nothing here
## re-cuts the ground, so a press only swaps the overlay instead of rebuilding
## the hole, and the dig closes itself the moment it breaks into other water.

## How far under the water line the lens has to be before a dig can start.
const UNDER := 0.35
## Slack around a pond mouth, so the last leg can land just short and still
## join the water.
const MOUTH := 1.6
## How close to the open end of a half-dug run you have to be to carry on with
## it. Without this, leaving the tool mid-dig would strand a dead end.
const RESUME := 8.0
## Step and step count used to find where a run crosses an underwater wall.
## Long enough to cross a wide pond from the middle of it.
const STRIDE := WaterTile.SPAN * 0.5
const WALK := 48

## The place tool this digs for. Left untyped so PlaceTool and DigTunnel are
## not a class cycle, the same way Player holds its match flow.
var tool
var bore := WaterTunnel.BORE_DEFAULT
## Index of the run being dug, or -1 when no dig is open.
var digging := -1


func _init(place) -> void:
	tool = place


func is_dragging() -> bool:
	return digging >= 0 and digging < tool.hole.placements.size()


## True once the lens is under the water line of a finished pond, which is the
## only place a new dig can start.
func is_submerged() -> bool:
	if tool.water_pending():
		return false
	var eye := _eye()
	var pond := WaterTile.pond_at(tool.hole.placements, eye)
	return not pond.is_empty() and eye.y < WaterTile.surface_of(pond) - UNDER


func can_dig() -> bool:
	if is_dragging():
		return true
	if not CustomHole.is_water(String(tool.picked_path())):
		return false
	return is_submerged() or _resume_index() >= 0


## Where the next corner would land: straight out of the lens, held to one
## press worth of reach and never above ground.
func dig_target() -> Vector3:
	if not can_dig():
		return Vector3.INF
	var head := _head()
	if not head.is_finite():
		return Vector3.INF
	var at: Vector3 = tool.aim_at()
	var reach := at - head
	if reach.length() > WaterTunnel.STEP_MAX:
		at = head + reach.normalized() * WaterTunnel.STEP_MAX
	return Vector3(at.x, minf(at.y, _roof_at(at)), at.z)


## The line a dig would follow if R2 went in now, ready to be drawn.
func dig_preview() -> Array:
	var target := dig_target()
	if not target.is_finite():
		return []
	if not is_dragging():
		return [_head(), target]
	var line: Array = tool.hole.placements[digging][CustomHole.NODES].duplicate()
	line.append(target)
	return line


## The pond a dig would break into, or nothing while it is still in rock.
func dig_lands_in() -> Dictionary:
	return _lands_in(dig_target()) if is_dragging() else {}


## Yaw means nothing to a corridor, so the buttons that turn a piece size this.
func grow(steps: float) -> bool:
	if not can_dig():
		return false
	bore = WaterTunnel.clamp_bore(bore + steps * WaterTunnel.BORE_STEP)
	if is_dragging():
		tool.hole.placements[digging][CustomHole.BORE] = bore
	return true


## R2 underwater. The first press opens a run from the pond you are in, each
## one after drops a corner, and reaching other water finishes the tunnel.
func dig() -> bool:
	if not can_dig():
		return false
	if not is_dragging():
		digging = _resume_index()
	var target := dig_target()
	if not target.is_finite():
		return false
	if not tool.hole.covers(target):
		tool.refused.emit("OFF THE FAIRWAY. NOTHING OUT THERE IS REACHABLE.")
		return false
	if Lava.covers_any(tool.hole.placements, target):
		tool.refused.emit("NOT THROUGH THE LAVA.")
		return false
	if not is_dragging():
		return _open(target)
	var entry: Dictionary = tool.hole.placements[digging]
	var line: Array = entry[CustomHole.NODES]
	if target.distance_to(line[line.size() - 1]) < WaterTunnel.STEP_MIN:
		tool.refused.emit("DIG FURTHER OUT.")
		return false
	if line.size() >= WaterTunnel.MAX_NODES:
		tool.refused.emit("THAT TUNNEL HAS ENOUGH TURNS.")
		return false
	line.append(target)
	_close_if_landed(target)
	return true


## L2 backs a dig up one corner, and off the last corner the run is dropped.
func undo() -> bool:
	if not is_dragging():
		return false
	var line: Array = tool.hole.placements[digging][CustomHole.NODES]
	if line.size() > 2:
		line.remove_at(line.size() - 1)
		return true
	tool.hole.remove_placement(digging)
	digging = -1
	return true


## Runs dug out of a pond that is being erased, so nothing is left hanging off
## water that is gone.
func hanging_off(pool: Vector3) -> Array[int]:
	var out: Array[int] = []
	for i in tool.hole.placements.size():
		var entry: Dictionary = tool.hole.placements[i]
		if not CustomHole.is_tunnel(String(entry[CustomHole.PATH])):
			continue
		if _joins(entry, pool):
			out.append(i)
	return out


func drop() -> void:
	digging = -1


func _open(target: Vector3) -> bool:
	var pond := WaterTile.pond_at(tool.hole.placements, _eye())
	if pond.is_empty():
		return false
	var head := _mouth_out(target)
	tool.hole.add_placement(CustomHole.TUNNEL, GridSnap.stored_offset(head, tool.height))
	digging = tool.hole.placements.size() - 1
	var entry: Dictionary = tool.hole.placements[digging]
	var line: Array[Vector3] = [head, target]
	entry[CustomHole.NODES] = line
	entry[CustomHole.BORE] = bore
	entry[CustomHole.DONE] = false
	entry[CustomHole.POOL] = CustomHole.pool_of(pond)
	tool._holding = false
	tool._clear_ghost()
	_close_if_landed(target)
	return true


## A leg that reached other water ends the run there and then, even when it was
## the opening press, and the mouth is pushed into the pond so the two swims
## overlap instead of leaving a bite of rock between them.
func _close_if_landed(target: Vector3) -> void:
	if not is_dragging() or _lands_in(target).is_empty():
		return
	var line: Array = tool.hole.placements[digging][CustomHole.NODES]
	line[line.size() - 1] = _mouth_in(line[line.size() - 2], target)
	tool.hole.placements[digging][CustomHole.DONE] = true
	digging = -1


## Water the far end has reached, as long as it is not the pond it came from.
func _lands_in(target: Vector3) -> Dictionary:
	if not is_dragging() or not target.is_finite():
		return {}
	var pond := WaterTile.pond_at(tool.hole.placements, target, MOUTH)
	if pond.is_empty() or target.y > WaterTile.surface_of(pond):
		return {}
	var mine: Vector3 = CustomHole.pool_of(tool.hole.placements[digging])
	var theirs := CustomHole.pool_of(pond)
	if mine.is_finite() and theirs.is_finite() and mine.distance_squared_to(theirs) < 0.0025:
		return {}
	return pond


func _joins(entry: Dictionary, pool: Vector3) -> bool:
	if CustomHole.pool_of(entry) == pool:
		return true
	for point in CustomHole.nodes_of(entry):
		var pond := WaterTile.pond_at(tool.hole.placements, point, MOUTH)
		if not pond.is_empty() and CustomHole.pool_of(pond) == pool:
			return true
	return false


## The half-dug run within reach of the lens, so a dig survives a tool switch.
func _resume_index() -> int:
	var eye := _eye()
	for i in tool.hole.placements.size():
		var entry: Dictionary = tool.hole.placements[i]
		if not CustomHole.is_tunnel(String(entry[CustomHole.PATH])):
			continue
		if WaterTunnel.is_done(entry):
			continue
		var line: Array = CustomHole.nodes_of(entry)
		if not line.is_empty() and eye.distance_to(line[line.size() - 1]) <= RESUME:
			return i
	return -1


## Start a run at the underwater wall you are facing, not wherever you happened
## to be floating. The mouth is set a step into that wall so the opening reads
## as a hole in the bank; the bore still reaches back into the pond, so the two
## swims meet.
func _mouth_out(toward: Vector3) -> Vector3:
	var eye := _eye()
	var dir := _flat_dir(eye, toward)
	if dir == Vector3.ZERO:
		return eye
	var at := eye
	for _i in WALK:
		var next: Vector3 = at + dir * STRIDE
		if WaterTile.pond_at(tool.hole.placements, next).is_empty():
			return next
		at = next
	return at


## Finish a run on the far bank, the same way a dig starts: last dry cell
## before the pond. The lip still reaches into the water. Landing in the pond
## itself left the lake wall in front of the hole.
func _mouth_in(from: Vector3, target: Vector3) -> Vector3:
	var dir := _flat_dir(from, target)
	if dir == Vector3.ZERO:
		return target
	var at := from
	for _i in WALK:
		var next: Vector3 = at + dir * STRIDE
		if not WaterTile.pond_at(tool.hole.placements, next).is_empty():
			return at
		at = next
	return target


func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var dir := to - from
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


## Mouth of an open dig, or the lens when a new one is about to start.
func _head() -> Vector3:
	if not is_dragging():
		return _eye()
	var line: Array = tool.hole.placements[digging][CustomHole.NODES]
	return line[line.size() - 1]


## Keep a run under the turf, so it never breaks the surface between ponds.
func _roof_at(at: Vector3) -> float:
	var ground: float = tool.height.height_at(at.x, at.z) if tool.height != null else 0.0
	var pond := WaterTile.pond_at(tool.hole.placements, at, MOUTH)
	if not pond.is_empty():
		ground = minf(ground, WaterTile.surface_of(pond))
	return ground - UNDER - bore * 0.5


func _eye() -> Vector3:
	var eye: Vector3 = tool.look_from
	return eye if eye.is_finite() else tool.aim_at()
