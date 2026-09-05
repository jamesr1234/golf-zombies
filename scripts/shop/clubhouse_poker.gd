class_name ClubhousePoker
extends Object
## Two heads-up tables on the upper floor.

const SEAT := 2.05
const OVAL := Vector3(2.35, 1.0, 1.25)


static func build(host: Clubhouse) -> void:
	var y := ClubhouseBuild.story_floor_y(1)
	_table(host, Vector3(-5.4, y, -1.0))
	_table(host, Vector3(5.4, y, -1.0))


static func _table(host: Clubhouse, at: Vector3) -> void:
	var root := PokerTable.new()
	root.name = "PokerTable"
	root.add_to_group("clubhouse_poker")
	root.position = at
	host.add_child(root)
	var hull := MeshFactory.box_body(
		Vector3(4.5, 0.72, 2.5), Palette.WALL, Layers.PROP, false
	)
	hull.position.y = 0.36
	root.add_child(hull)
	var post := MeshFactory.cylinder(0.34, 0.64, Palette.WALL, Palette.GLOW_FAINT)
	post.position.y = 0.32
	root.add_child(post)
	var apron := MeshFactory.cylinder(0.95, 0.18, Palette.WALL, Palette.GLOW_FAINT)
	apron.scale = OVAL
	apron.position.y = 0.7
	root.add_child(apron)
	var felt := MeshFactory.cylinder(0.86, 0.07, Palette.TREE_CANOPIES[1], Palette.GLOW_FAINT)
	felt.scale = OVAL
	felt.position.y = 0.81
	root.add_child(felt)
	var plate := MeshFactory.box_body(
		Vector3(3.9, 0.05, 2.05), Palette.TREE_CANOPIES[1], Layers.PROP, false
	)
	plate.name = "FeltPlate"
	plate.position.y = 0.84
	root.add_child(plate)
	var rail := MeshFactory.torus(0.78, 0.96, ClubhouseDecor.BRASS, Palette.GLOW_FAINT)
	rail.rotation.x = deg_to_rad(90.0)
	rail.scale = OVAL
	rail.position.y = 0.84
	root.add_child(rail)
	var well := MeshFactory.cylinder(0.28, 0.04, Palette.AMBER, Palette.GLOW_SOFT)
	well.position.y = 0.86
	root.add_child(well)
	var line := MeshFactory.box(Vector3(1.6, 0.01, 0.04), ClubhouseDecor.BRASS, Palette.GLOW_FAINT)
	line.position.y = 0.86
	root.add_child(line)
	_chair(root, Vector3(0.0, 0.0, -SEAT), 180.0)
	_chair(root, Vector3(0.0, 0.0, SEAT), 0.0)
	root.bind_chairs()


static func _chair(root: Node3D, at: Vector3, yaw: float) -> void:
	var seat := MeshFactory.box_body(
		Vector3(0.72, 0.42, 0.72), Palette.WALL, Layers.PROP, true, Palette.GLOW_FAINT
	)
	seat.position = at + Vector3(0.0, 0.21, 0.0)
	seat.rotation.y = deg_to_rad(yaw)
	seat.add_to_group("clubhouse_poker_chairs")
	root.add_child(seat)
	var back := MeshFactory.box(Vector3(0.72, 0.7, 0.12), Palette.BABY_BLUE, Palette.GLOW_FAINT)
	back.position = Vector3(0.0, 0.55, 0.28)
	seat.add_child(back)
	var cushion := MeshFactory.box(Vector3(0.62, 0.06, 0.62), Palette.TREE_CANOPIES[1], Palette.GLOW_FAINT)
	cushion.position.y = 0.24
	seat.add_child(cushion)
