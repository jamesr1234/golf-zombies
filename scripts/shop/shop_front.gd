class_name ShopFront
extends Object
## Cashier at the till, and a wall of sample stock facing into the room so you
## can see what that shop sells before you walk up.

const Wear := preload("res://scripts/player/apparel.gd")
const Props := preload("res://scripts/shop/shop_props.gd")

const CLERKS: PackedStringArray = ["Riley", "Pat", "Sage", "Jules", "Quinn"]
const BOARD := Vector3(7.6, 3.2, 0.1)


static func dress(station: ShopStation, dept: int, index: int) -> ClubhouseNpc:
	_register(station)
	return _cashier(station, index)


static func wall_display(host: Node3D, dept: int, at: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "Stock"
	root.add_to_group("shop_stock")
	root.position = at
	root.rotation.y = deg_to_rad(yaw)
	var board := MeshFactory.box_body(BOARD, Palette.NIGHT, Layers.PROP, true, 0.2)
	board.position = Vector3(0.0, BOARD.y * 0.5 + 0.35, 0.12)
	root.add_child(board)
	var rail := MeshFactory.cylinder(0.04, BOARD.x * 0.92, Palette.BABY_BLUE, Palette.GLOW_FAINT)
	rail.rotation.z = deg_to_rad(90.0)
	rail.position = Vector3(0.0, 3.15, 0.16)
	root.add_child(rail)
	match dept:
		Shop.Dept.APPAREL:
			_apparel_wall(root)
		Shop.Dept.CLUBS:
			_clubs_wall(root)
		Shop.Dept.WEAPONS:
			_armory_wall(root)
		Shop.Dept.CART:
			_cart_wall(root)
		_:
			_items_wall(root)
	host.add_child(root)


static func _cashier(station: ShopStation, index: int) -> ClubhouseNpc:
	var clerk := ClubhouseNpc.create(index, Vector3(0.0, 0.0, -1.05), 180.0)
	clerk.npc_name = CLERKS[posmod(index, CLERKS.size())]
	clerk.name = clerk.npc_name
	station.add_child(clerk)
	return clerk


static func _register(station: ShopStation) -> void:
	var till := MeshFactory.box(Vector3(0.42, 0.22, 0.28), Palette.BABY_BLUE, Palette.GLOW_FAINT)
	till.position = Vector3(0.55, ShopStation.COUNTER.y + 0.14, 0.08)
	station.add_child(till)
	var screen := MeshFactory.box(Vector3(0.22, 0.16, 0.04), Palette.AMBER, Palette.GLOW_SOFT)
	screen.position = Vector3(0.55, ShopStation.COUNTER.y + 0.32, -0.05)
	station.add_child(screen)


static func _label(root: Node3D, text: String, at: Vector3) -> void:
	var copy := Label3D.new()
	copy.text = text
	copy.font_size = 48
	copy.modulate = Palette.AMBER
	copy.outline_size = 8
	copy.outline_modulate = Palette.NIGHT
	copy.position = at
	root.add_child(copy)


static func _apparel_wall(root: Node3D) -> void:
	_label(root, "APPAREL", Vector3(0.0, 3.35, 0.2))
	Wear.hang_wall(root)


static func _clubs_wall(root: Node3D) -> void:
	_label(root, "CLUB SETS", Vector3(0.0, 3.35, 0.2))
	for i in 6:
		var x := -3.0 + float(i) * 1.2
		var bag := MeshFactory.cylinder(0.16, 1.15, Palette.BABY_BLUE, Palette.GLOW_FAINT)
		bag.position = Vector3(x, 0.95, 0.32)
		root.add_child(bag)
		var shaft := MeshFactory.cylinder(0.035, 1.6, Palette.ICE, Palette.GLOW_MEDIUM)
		shaft.position = Vector3(x, 2.15, 0.32)
		shaft.rotation.z = deg_to_rad(-10.0 + float(i) * 4.0)
		root.add_child(shaft)
		var head := MeshFactory.box(Vector3(0.22, 0.08, 0.12), Palette.AMBER, Palette.GLOW_SOFT)
		head.position = Vector3(x + 0.12, 2.85, 0.32)
		root.add_child(head)


static func _armory_wall(root: Node3D) -> void:
	_label(root, "ARMORY", Vector3(0.0, 3.35, 0.2))
	Props.armory(root)


static func _items_wall(root: Node3D) -> void:
	_label(root, "ITEMS", Vector3(0.0, 3.35, 0.2))
	Props.items(root)


static func _cart_wall(root: Node3D) -> void:
	_label(root, "CART", Vector3(0.0, 3.35, 0.2))
	Props.cart(root)
