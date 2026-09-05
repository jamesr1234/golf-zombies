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
	for entry in custom.placements:
		_add(overlay, entry, data, 0, custom)
	return overlay


static func attach(host: Node3D, data: HoleData) -> void:
	if data == null or data.custom == null:
		return
	var overlay := build(data.custom, data)
	host.add_child(overlay)
	if host.is_inside_tree():
		ClimbLadder.adopt(host.get_tree())
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
		out.append_array(expand(moved, depth + 1))
	return out


static func skips_speed_pads(custom: CustomHole) -> bool:
	return custom != null and custom.title.strip_edges().to_upper() == SKIP_PADS_ON


static func _add(
	overlay: Node3D, entry: Dictionary, data: HoleData, depth: int, custom: CustomHole
) -> void:
	var skip_pads := skips_speed_pads(custom)
	for flat in expand(entry, depth):
		if skip_pads and String(flat[CustomHole.PATH]) == SPEED_PAD:
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
		node.position = GridSnap.anchored_at(node, lifted, yaw)
		overlay.add_child(node)


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
