class_name SniperTower
extends StaticBody3D
## Neon perch off the fairway. Built with the hole so it is already standing
## during warm-up; the sniper is dropped onto the deck when play starts.

const HEIGHT := 14.5
const DECK := 3.4
const DECK_THICK := 0.28
const LEG := 0.2
const RAIL := 0.9
const MIN_TEE := 64.0
const SIDE_GAP := 22.0


static func create(prop: Dictionary) -> SniperTower:
	var tower := SniperTower.new()
	tower.name = "SniperTower"
	tower.collision_layer = Layers.PROP
	tower.collision_mask = 0
	tower.add_to_group("sniper_towers")
	var size: Vector3 = prop["size"]
	tower._build(size.y, size.x)
	tower.position = prop["position"]
	tower.rotation.y = deg_to_rad(prop["yaw"])
	return tower


static func perch_of(prop: Dictionary) -> Vector3:
	var origin: Vector3 = prop["position"]
	return origin + Vector3.UP * float(prop["size"].y)


static func is_tower(prop: Dictionary) -> bool:
	return String(prop.get("kind", "")) == "tower"


func _build(height: float, deck: float) -> void:
	var half := deck * 0.42
	for corner in [
		Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half),
		Vector3(-half, 0.0, half), Vector3(half, 0.0, half),
	]:
		var leg := MeshFactory.cylinder(LEG, height, Palette.TOWER, Palette.GLOW_FAINT)
		leg.position = corner + Vector3.UP * height * 0.5
		add_child(leg)
	var column := MeshFactory.box(
		Vector3(0.55, height, 0.55), Palette.TOWER.darkened(0.15), Palette.GLOW_FAINT
	)
	column.position.y = height * 0.5
	add_child(column)
	_box_shape(Vector3(0.7, height, 0.7), Vector3(0.0, height * 0.5, 0.0))
	var platform := MeshFactory.box(
		Vector3(deck, DECK_THICK, deck), Palette.TOWER, Palette.GLOW_SOFT
	)
	platform.position.y = height - DECK_THICK * 0.5
	add_child(platform)
	_box_shape(Vector3(deck, DECK_THICK, deck), Vector3(0.0, height - DECK_THICK * 0.5, 0.0))
	var trim := MeshFactory.box(
		Vector3(deck * 1.04, 0.08, deck * 1.04), Palette.TOWER_TRIM, Palette.GLOW_STRONG
	)
	trim.position.y = height + 0.02
	add_child(trim)
	_rails(height, deck)
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.TOWER_TRIM
	lamp.light_energy = 2.4
	lamp.omni_range = 16.0
	lamp.position.y = height + 1.2
	add_child(lamp)


func _rails(height: float, deck: float) -> void:
	var y := height + RAIL * 0.5
	var span := deck * 0.96
	for side: float in [-1.0, 1.0]:
		var along := MeshFactory.box(
			Vector3(span, 0.08, 0.08), Palette.TOWER_TRIM, Palette.GLOW_MEDIUM
		)
		along.position = Vector3(0.0, y, side * deck * 0.48)
		add_child(along)
		var across := MeshFactory.box(
			Vector3(0.08, 0.08, span), Palette.TOWER_TRIM, Palette.GLOW_MEDIUM
		)
		across.position = Vector3(side * deck * 0.48, y, 0.0)
		add_child(across)


func _box_shape(size: Vector3, at: Vector3) -> void:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	node.shape = box
	node.position = at
	add_child(node)
