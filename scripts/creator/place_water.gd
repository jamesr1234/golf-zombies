class_name PlaceWater
extends RefCounted
## Pond fill and depth lock for the place tool. Kept off PlaceTool so the lava
## and sand flows stay readable. DigTunnel handles what gets dug between two
## finished ponds.

var tool: PlaceTool
var from := Vector3.INF
var depthing := false


func _init(place: PlaceTool) -> void:
	tool = place


func is_filling() -> bool:
	return from.is_finite()


func is_depthing() -> bool:
	return depthing


func is_pending() -> bool:
	return CustomHole.is_water(tool.picked_path()) and not depthing and not open().is_empty()


func is_busy() -> bool:
	return is_filling() or is_depthing()


func cells() -> Array[Vector3]:
	if not is_filling():
		return []
	return WaterTile.cells_between(from, tool.aim_at())


func fill_ok() -> bool:
	if not is_filling():
		return false
	var any := false
	var lo := INF
	var hi := -INF
	for cell in cells():
		var at := tool._stand_at(cell)
		if Lava.covers_any(tool.hole.placements, at) or WaterTile.covers_any(tool.hole.placements, at):
			continue
		if not tool.hole.covers(at):
			continue
		lo = minf(lo, at.y)
		hi = maxf(hi, at.y)
		any = true
	return any and hi - lo <= 0.2


func preview_depth() -> float:
	return WaterTile.clamp_depth(_raw_depth())


func clear_fill() -> bool:
	if not is_filling():
		return false
	from = Vector3.INF
	return true


func clear_depth() -> bool:
	if not is_depthing():
		return false
	depthing = false
	return true


func open() -> Array[int]:
	var out: Array[int] = []
	for i in tool.hole.placements.size():
		if not CustomHole.is_water(String(tool.hole.placements[i][CustomHole.PATH])):
			continue
		if not WaterTile.has_depth(tool.hole.placements[i]):
			out.append(i)
	return out


func confirm() -> bool:
	if is_filling() or not is_pending():
		return false
	depthing = true
	tool._holding = false
	tool._clear_ghost()
	return true


func lock_depth() -> bool:
	if not is_depthing():
		return false
	var listed := open()
	if listed.is_empty():
		return false
	var seed: Dictionary = tool.hole.placements[listed[0]]
	var surface := tool._world_pos(seed[CustomHole.POSITION]).y
	var depth := WaterTile.clamp_depth(surface - tool.aim_at().y)
	var pool := Vector3(seed[CustomHole.POSITION].x, 0.0, seed[CustomHole.POSITION].z)
	for i in listed:
		var entry: Dictionary = tool.hole.placements[i]
		entry[CustomHole.DEPTH] = depth
		entry[CustomHole.POOL] = pool
		entry[CustomHole.SURFACE] = surface
	depthing = false
	tool.wants_rebuild = true
	return true


func begin_fill() -> bool:
	if Lava.covers_any(tool.hole.placements, tool.aim_at()):
		tool.refused.emit("NOT ON THE LAVA.")
		return false
	if WaterTile.covers_any(tool.hole.placements, tool.aim_at()):
		tool.refused.emit("THAT TILE IS ALREADY WATER.")
		return false
	from = tool.aim_at()
	tool._holding = false
	tool._clear_ghost()
	return true


func fill() -> bool:
	if not is_filling():
		return false
	var path := tool.picked_path()
	if not CustomHole.is_water(path):
		return false
	if not fill_ok():
		tool.refused.emit("KEEP THE POND ON ONE LEVEL.")
		return false
	var added := 0
	for cell in cells():
		var at := tool._stand_at(cell)
		if Lava.covers_any(tool.hole.placements, at):
			tool.refused.emit("NOT ON THE LAVA.")
			return false
		if not tool.hole.covers(at) or WaterTile.covers_any(tool.hole.placements, at):
			continue
		tool.hole.add_placement(path, GridSnap.stored_offset(at, tool.height), tool.yaw)
		added += 1
	if added <= 0:
		tool.refused.emit("THAT TILE IS ALREADY WATER.")
		return false
	from = Vector3.INF
	tool._holding = false
	return true


## A pond comes off as one piece, and so does anything dug out of it: leaving a
## run hanging off water that is gone would be a tunnel to nowhere.
func erase_pool(index: int) -> void:
	var listed := tool.hole.placements
	if CustomHole.is_tunnel(String(listed[index][CustomHole.PATH])):
		tool.hole.remove_placement(index)
		tool.tunnel.drop()
		return
	var pool := CustomHole.water_pool(listed, index)
	pool.append_array(tool.tunnel.hanging_off(CustomHole.pool_of(listed[index])))
	pool.sort()
	pool.reverse()
	for i in pool:
		tool.hole.remove_placement(i)
	if open().is_empty():
		depthing = false
	tool.tunnel.drop()
	tool.wants_rebuild = true


func drop() -> void:
	from = Vector3.INF
	depthing = false


func _raw_depth() -> float:
	var listed := open()
	if listed.is_empty():
		return WaterTile.DEFAULT_DEPTH
	var surface := tool._world_pos(tool.hole.placements[listed[0]][CustomHole.POSITION]).y
	return surface - tool.aim_at().y
