class_name CustomOverlay
extends Object
## Props for a player-made hole. Where a bundled hole loads its authored scene,
## a custom hole instances its placement list instead, then hands the result to
## the same adopt hooks so LEDs, ladders and escalators still come alive.

const NAME := "Overlay"
## A grouped structure is stored as its own placement list, which may itself
## name another group. The depth cap stops a structure that somehow references
## itself from hanging the load.
const MAX_DEPTH := 4
const SPEED_PAD := "res://scenes/course/props/speed_rectangle.tscn"
## Temporary: the player-made RACE hole keeps its pads on disk, but they stay
## off the course until we put them back.
const SKIP_PADS_ON := "RACE"

const _Escalator := preload("res://scripts/course/escalator.gd")
const GUN_PICKUP := "res://scenes/course/props/gun_pickup.tscn"


static func build(custom: CustomHole, data: HoleData = null) -> Node3D:
	var overlay := Node3D.new()
	overlay.name = NAME
	var lava_entries: Array[Dictionary] = []
	var water_entries: Array[Dictionary] = []
	for entry in custom.placements:
		_add(overlay, entry, data, 0, custom, lava_entries, water_entries)
	for group in CustomHole.lava_groups(lava_entries):
		overlay.add_child(_lava_node(group, data))
	for group in CustomHole.water_groups(water_entries):
		overlay.add_child(_water_node(group, data))
	return overlay


static func attach(host: Node3D, data: HoleData) -> void:
	if data == null or data.custom == null:
		return
	var overlay := build(data.custom, data)
	host.add_child(overlay)
	ClimbLadder.adopt(overlay)
	_Escalator.adopt(overlay)
	ObstacleLeds.adopt(overlay)


## Groups expand in place, so a structure a player saved behaves exactly like
## the loose pieces it was made from.
static func expand(entry: Dictionary, depth := 0) -> Array[Dictionary]:
	var path := String(entry[CustomHole.PATH])
	var out: Array[Dictionary] = []
	if not path.begins_with("user://") or depth >= MAX_DEPTH:
		out.append(entry)
		return out
	var origin: Vector3 = entry[CustomHole.POSITION]
	var yaw := deg_to_rad(float(entry[CustomHole.YAW]))
	for child in HoleStore.structure_parts(path):
		var offset: Vector3 = child[CustomHole.POSITION]
		var moved := CustomHole.placement(
			String(child[CustomHole.PATH]),
			origin + offset.rotated(Vector3.UP, yaw),
			float(child[CustomHole.YAW]) + float(entry[CustomHole.YAW]),
			CustomHole.NO_GATE,
			origin + (child[CustomHole.END] as Vector3).rotated(Vector3.UP, yaw)
			if CustomHole.has_end(child) else CustomHole.NO_END
		)
		if child.has(CustomHole.SPIN):
			moved[CustomHole.SPIN] = CustomHole.spin_of(child)
		if CustomHole.has_respawn(child):
			moved[CustomHole.RESPAWN] = origin + (child[CustomHole.RESPAWN] as Vector3).rotated(
				Vector3.UP, yaw
			)
		if CustomHole.is_water(String(child[CustomHole.PATH])):
			if WaterTile.has_depth(child):
				moved[CustomHole.DEPTH] = WaterTile.depth_of(child)
			if CustomHole.has_pool(child):
				moved[CustomHole.POOL] = origin + CustomHole.pool_of(child).rotated(Vector3.UP, yaw)
			if child.has(CustomHole.SURFACE):
				moved[CustomHole.SURFACE] = WaterTile.surface_of(child)
		out.append_array(expand(moved, depth + 1))
	return out


static func skips_speed_pads(custom: CustomHole) -> bool:
	return custom != null and custom.title.strip_edges().to_upper() == SKIP_PADS_ON


static func _add(
	overlay: Node3D, entry: Dictionary, data: HoleData, depth: int, custom: CustomHole,
	lava_entries: Array[Dictionary], water_entries: Array[Dictionary]
) -> void:
	var skip_pads := skips_speed_pads(custom)
	for flat in expand(entry, depth):
		if skip_pads and String(flat[CustomHole.PATH]) == SPEED_PAD:
			continue
		if CustomHole.is_spawn(String(flat[CustomHole.PATH])):
			continue
		if CustomHole.is_sandtrap(String(flat[CustomHole.PATH])):
			continue
		if CustomHole.is_lava(String(flat[CustomHole.PATH])):
			lava_entries.append(flat)
			continue
		if CustomHole.is_water(String(flat[CustomHole.PATH])):
			water_entries.append(flat)
			continue
		if CustomHole.is_tunnel(String(flat[CustomHole.PATH])):
			var dug := WaterTunnel.create(flat)
			if data != null:
				WaterTunnel.place_mouths(dug, data.height, custom.placements)
			overlay.add_child(dug)
			# #region agent log
			_dbg_bank(flat, data, custom)
			# #endregion
			continue
		var node := instantiate(
			String(flat[CustomHole.PATH]),
			float(flat.get(CustomHole.GATE, CustomHole.NO_GATE))
		)
		if node == null:
			continue
		var at: Vector3 = flat[CustomHole.POSITION]
		var yaw := float(flat[CustomHole.YAW])
		var lifted := _lifted(at, data)
		var zip := node as Zipline
		if zip != null and CustomHole.has_end(flat):
			var finish := _lifted(flat[CustomHole.END] as Vector3, data)
			node.rotation.y = deg_to_rad(yaw)
			node.position = lifted
			zip.set_end_local(Basis(Vector3.UP, -deg_to_rad(yaw)) * (finish - lifted))
			overlay.add_child(node)
			continue
		node.rotation.y = deg_to_rad(yaw)
		if node is GunPickup:
			node.position = GunPickup.sit_at(node, lifted, yaw)
		else:
			node.position = GridSnap.anchored_at(node, lifted, yaw)
		var mill := node as CartPathWindmill
		if mill != null:
			mill.spin_deg = CustomHole.spin_of(flat)
		overlay.add_child(node)


static func _lava_node(group: Array, data: HoleData) -> Lava:
	var cells: Array[Vector3] = []
	var point := Vector3.INF
	for entry in group:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		cells.append(_lifted(entry[CustomHole.POSITION], data))
		if CustomHole.has_respawn(entry):
			point = _lifted(CustomHole.respawn_of(entry), data)
	return Lava.from_cells(cells, point)


static func _water_node(group: Array, data: HoleData) -> WaterTile:
	var tiles: Array[Dictionary] = []
	for entry in group:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var at := _lifted(entry[CustomHole.POSITION], data)
		var water_y := float(entry[CustomHole.SURFACE]) if entry.has(CustomHole.SURFACE) else at.y
		tiles.append({
			"position": Vector3(at.x, water_y, at.z),
			WaterTile.SURFACE: water_y,
			WaterTile.DEPTH: float(entry.get(WaterTile.DEPTH, 0.0)),
		})
	return WaterTile.from_group(tiles)


static func _dbg_bank(entry: Dictionary, data: HoleData, custom: CustomHole) -> void:
	var line := WaterTunnel.nodes_of(entry)
	if line.size() < 2:
		return
	var half := WaterTunnel.half_of(entry)
	var samples: Array = []
	for end_i in [0, line.size() - 1]:
		var node: Vector3 = line[end_i]
		var other: Vector3 = line[1] if end_i == 0 else line[end_i - 1]
		var out: Vector3 = node - other
		out.y = 0.0
		if out.length_squared() < 0.0001:
			out = Vector3.FORWARD
		else:
			out = out.normalized()
		var toward: Array = []
		var land: Array = []
		for dist in [0.0, 0.9, 1.8, 2.7, 3.6, 5.0]:
			toward.append(_dbg_step(node, out, dist, half, data, custom))
			if dist > 0.0:
				land.append(_dbg_step(node, -out, dist, half, data, custom))
		var snapped := node
		if data != null and data.height != null:
			var cut: Dictionary = WaterTunnel._wall_cut(
				data.height, custom.placements, node, other, half
			)
			snapped = cut.get("position", node)
		samples.append({
			"end": end_i,
			"node": [snappedf(node.x, 0.01), snappedf(node.y, 0.01), snappedf(node.z, 0.01)],
			"bank": [snappedf(snapped.x, 0.01), snappedf(snapped.y, 0.01), snappedf(snapped.z, 0.01)],
			"pondward": toward,
			"landward": land,
		})
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.WRITE)
	else:
		f.seek_end()
	if f == null:
		return
	f.store_line(JSON.stringify({
		"sessionId": "5e45bb",
		"hypothesisId": "A",
		"location": "custom_overlay.gd:_dbg_bank",
		"message": "mouth vs lake wall",
		"data": {"half": snappedf(half, 0.01), "cell": HeightField.CELL, "ends": samples},
		"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
	}))
	f.close()


static func _dbg_step(
	node: Vector3, dir: Vector3, dist: float, half: float, data: HoleData, custom: CustomHole
) -> Dictionary:
	var at: Vector3 = node + dir * dist
	var ground: float = 0.0
	if data != null and data.height != null:
		ground = data.height.height_at(at.x, at.z)
	var pond := WaterTile.pond_at(custom.placements, at)
	return {
		"d": dist,
		"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
		"ground": snappedf(ground, 0.01),
		"roof": snappedf(node.y + half, 0.01),
		"floor": snappedf(node.y - half, 0.01),
		"covers_hole": ground > node.y - half + 0.05,
		"in_pond": not pond.is_empty(),
	}


static func _lifted(at: Vector3, data: HoleData) -> Vector3:
	if data == null:
		return at
	return Vector3(at.x, data.height.height_at(at.x, at.z) + at.y, at.z)


## Only pieces the catalog knows about are ever loaded, so a hand-edited or
## downloaded record cannot point the game at an arbitrary path.
static func instantiate(path: String, gate := CustomHole.NO_GATE) -> Node3D:
	if not PieceCatalog.has_piece(path) or not ResourceLoader.exists(path):
		return null
	if CustomHole.is_weapon(path):
		return _gun(path, gate)
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## A weapon is picked from the catalog as its stats resource, but what stands on
## the hole is the same pickup the bundled holes use.
static func _gun(path: String, gate: float) -> Node3D:
	var stats := load(path) as WeaponStats
	if stats == null:
		return null
	var pickup := (load(GUN_PICKUP) as PackedScene).instantiate() as GunPickup
	if pickup == null:
		return null
	pickup.stats = stats
	pickup.gate = gate
	return pickup
