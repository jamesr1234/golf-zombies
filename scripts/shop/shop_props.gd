class_name ShopProps
extends Object
## Wall stock for the rooms that used to hang labelled boxes. Guns, kits and a
## cart are built from the same primitives as everything else, then set leaning
## and turning so they read as the thing, not a crate of the thing.

const BOB_GROUP := "shop_bob"


class Bob extends Node3D:
	var yaw_speed := 0.55
	var bob_height := 0.07
	var bob_rate := 1.7
	var _t := 0.0
	var _rest_y := 0.0

	func _ready() -> void:
		_rest_y = position.y
		add_to_group(ShopProps.BOB_GROUP)

	func _process(delta: float) -> void:
		_t += delta
		rotate_y(yaw_speed * delta)
		position.y = _rest_y + sin(_t * bob_rate) * bob_height


static func armory(root: Node3D) -> void:
	_net(_bob(root, Vector3(-2.45, 2.25, 0.42), 0.7, 0.2))
	_sniper(_bob(root, Vector3(2.45, 2.22, 0.42), -0.55, 0.8))
	_rocket(_bob(root, Vector3(0.0, 1.85, 0.48), 0.4, 1.4))
	_rifle(_bob(root, Vector3(-2.35, 0.95, 0.42), -0.65, 2.1))
	_shotgun(_bob(root, Vector3(2.35, 0.92, 0.42), 0.6, 2.8))


static func items(root: Node3D) -> void:
	_caption(root, "AMMO", Vector3(-2.45, 2.55, 0.78))
	_ammo(_bob(root, Vector3(-2.45, 2.15, 0.42), 0.5, 0.3))
	_caption(root, "HEX", Vector3(0.0, 2.55, 0.78))
	_hex(_bob(root, Vector3(0.0, 2.12, 0.42), 0.85, 1.0))
	_caption(root, "KIT", Vector3(2.45, 2.55, 0.78))
	_medkit(_bob(root, Vector3(2.45, 2.12, 0.42), -0.45, 1.6))
	_caption(root, "REVIVE", Vector3(-2.45, 1.15, 0.78))
	_revive(_bob(root, Vector3(-2.45, 0.78, 0.42), 0.6, 2.2))
	_caption(root, "+30", Vector3(0.0, 1.15, 0.78))
	_clock(_bob(root, Vector3(0.0, 0.78, 0.42), 0.7, 2.7), Palette.AMBER, false)
	_caption(root, "FREEZE", Vector3(2.45, 1.15, 0.78))
	_clock(_bob(root, Vector3(2.45, 0.78, 0.42), -0.5, 3.3), Palette.ICE, true)


static func preview(parent: Node3D, item: Dictionary) -> void:
	if parent == null or item.is_empty():
		return
	match String(item.get("id", "")):
		"rocket":
			_rocket(parent)
		"ammo":
			_ammo(parent)
		"barrier":
			_hex(parent)
		"medkit":
			_medkit(parent)
		"revive":
			_revive(parent)
		"time_bonus":
			_clock(parent, Palette.AMBER, false)
		"time_freeze":
			_clock(parent, Palette.ICE, true)
		"cart_turbo", "cart_ram", "cart_armor":
			_cart_body(parent)
			parent.scale = Vector3.ONE * 0.42
		"tour", "pro", "forged":
			_club(parent, ClubKit.by_id(String(item["id"])).color)
		_:
			return
	parent.rotation = Vector3.ZERO


static func cart(root: Node3D) -> void:
	_caption(root, "TURBO", Vector3(-2.45, 2.55, 0.72))
	_caption(root, "RAM", Vector3(0.0, 2.55, 0.72))
	_caption(root, "ARMOR", Vector3(2.45, 2.55, 0.72))
	var show := _bob(root, Vector3(0.0, 1.05, 0.55), 0.35, 0.4)
	show.bob_height = 0.05
	show.rotation.y = deg_to_rad(38.0)
	_cart_body(show)


static func _bob(root: Node3D, at: Vector3, yaw_speed: float, phase: float) -> Bob:
	var mount := Bob.new()
	mount.position = at
	mount.yaw_speed = yaw_speed
	mount.bob_rate = 1.4 + absf(yaw_speed)
	mount._t = phase
	root.add_child(mount)
	return mount


static func _rifle(parent: Node3D) -> void:
	parent.rotation.y = deg_to_rad(-22.0)
	parent.rotation.z = deg_to_rad(8.0)
	var shell := Palette.CYAN.darkened(0.45)
	_box(parent, Vector3(0.1, 0.14, 0.52), shell, 0.0, Vector3.ZERO)
	var barrel := _cyl(parent, 0.035, 0.72, shell, 0.0, Vector3(0.0, 0.02, -0.52))
	barrel.rotation.x = deg_to_rad(90.0)
	for z: float in [-0.28, -0.42, -0.56]:
		var coil := _cyl(parent, 0.07, 0.04, Palette.CYAN, Palette.GLOW_STRONG, Vector3(0.0, 0.02, z))
		coil.rotation.x = deg_to_rad(90.0)
	_sphere(parent, 0.055, Palette.CYAN, Palette.GLOW_STRONG, Vector3(0.0, 0.02, -0.9))
	var grip := _box(parent, Vector3(0.08, 0.22, 0.1), shell, 0.0, Vector3(0.0, -0.16, 0.14))
	grip.rotation.x = deg_to_rad(-18.0)


static func _shotgun(parent: Node3D) -> void:
	parent.rotation.y = deg_to_rad(24.0)
	parent.rotation.z = deg_to_rad(-7.0)
	var metal := Palette.AMBER.darkened(0.38)
	var wood := Palette.AMBER.darkened(0.68)
	_box(parent, Vector3(0.14, 0.12, 0.42), metal, 0.0, Vector3.ZERO)
	for x: float in [-0.04, 0.04]:
		var barrel := _cyl(parent, 0.032, 0.85, metal, 0.0, Vector3(x, 0.02, -0.52))
		barrel.rotation.x = deg_to_rad(90.0)
		var muzzle := _cyl(parent, 0.042, 0.05, Palette.AMBER, Palette.GLOW_STRONG, Vector3(x, 0.02, -0.96))
		muzzle.rotation.x = deg_to_rad(90.0)
	_box(parent, Vector3(0.12, 0.08, 0.28), wood, 0.0, Vector3(0.0, -0.08, -0.22))
	var grip := _box(parent, Vector3(0.08, 0.24, 0.1), wood, 0.0, Vector3(0.0, -0.18, 0.16))
	grip.rotation.x = deg_to_rad(-22.0)


static func _rocket(parent: Node3D) -> void:
	parent.rotation.y = deg_to_rad(16.0)
	parent.rotation.z = deg_to_rad(6.0)
	var tube := _cyl(parent, 0.08, 0.95, Palette.MAGENTA.darkened(0.28), Palette.GLOW_SOFT, Vector3(0.0, 0.0, -0.12))
	tube.rotation.x = deg_to_rad(90.0)
	var drum := _cyl(parent, 0.16, 0.18, Palette.MAGENTA, Palette.GLOW_STRONG, Vector3(0.12, 0.0, 0.18))
	drum.rotation.z = deg_to_rad(90.0)
	_sphere(parent, 0.1, Palette.HOT_PINK, Palette.GLOW_STRONG, Vector3(0.0, 0.0, -0.62))
	var grip := _box(parent, Vector3(0.09, 0.22, 0.1), Palette.MAGENTA.darkened(0.5), 0.0, Vector3(0.0, -0.18, 0.22))
	grip.rotation.x = deg_to_rad(-16.0)


static func _sniper(parent: Node3D) -> void:
	parent.rotation.y = deg_to_rad(18.0)
	parent.rotation.z = deg_to_rad(-5.0)
	var metal := Palette.ICE.darkened(0.42)
	_box(parent, Vector3(0.09, 0.12, 0.55), metal, 0.0, Vector3.ZERO)
	var barrel := _cyl(parent, 0.028, 1.05, metal, 0.0, Vector3(0.0, 0.02, -0.7))
	barrel.rotation.x = deg_to_rad(90.0)
	var scope := _cyl(parent, 0.05, 0.32, Palette.ICE, Palette.GLOW_STRONG, Vector3(0.0, 0.12, -0.08))
	scope.rotation.x = deg_to_rad(90.0)
	_sphere(parent, 0.055, Palette.CYAN, Palette.GLOW_STRONG, Vector3(0.0, 0.12, -0.26))
	var grip := _box(parent, Vector3(0.08, 0.2, 0.09), metal.darkened(0.2), 0.0, Vector3(0.0, -0.16, 0.16))
	grip.rotation.x = deg_to_rad(-14.0)


static func _net(parent: Node3D) -> void:
	parent.rotation.y = deg_to_rad(-28.0)
	parent.rotation.z = deg_to_rad(10.0)
	var tube := _cyl(parent, 0.055, 0.55, Palette.NET.darkened(0.4), 0.0, Vector3(0.0, 0.0, 0.05))
	tube.rotation.x = deg_to_rad(90.0)
	var hoop := MeshFactory.torus(0.1, 0.2, Palette.NET, Palette.GLOW_STRONG)
	hoop.rotation.x = deg_to_rad(90.0)
	hoop.position.z = -0.32
	parent.add_child(hoop)
	var grip := _box(parent, Vector3(0.08, 0.2, 0.09), Palette.NET.darkened(0.5), 0.0, Vector3(0.0, -0.16, 0.2))
	grip.rotation.x = deg_to_rad(-16.0)


static func _ammo(parent: Node3D) -> void:
	_box(parent, Vector3(0.62, 0.34, 0.42), Palette.NIGHT, 0.2, Vector3.ZERO)
	var lid := _box(parent, Vector3(0.64, 0.05, 0.44), Palette.LIME, Palette.GLOW_MEDIUM, Vector3(0.0, 0.22, -0.06))
	lid.rotation.x = deg_to_rad(-28.0)
	for x: float in [-0.16, 0.0, 0.16]:
		_box(parent, Vector3(0.14, 0.12, 0.22), Palette.LIME, Palette.GLOW_STRONG, Vector3(x, 0.08, 0.0))


static func _hex(parent: Node3D) -> void:
	var radius := 0.34
	for i in 6:
		var angle := float(i) * TAU / 6.0
		var bar := _box(
			parent, Vector3(0.38, 0.06, 0.06), Palette.VIOLET, Palette.GLOW_STRONG,
			Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)
		)
		bar.rotation.y = angle + PI * 0.5


static func _medkit(parent: Node3D) -> void:
	_box(parent, Vector3(0.55, 0.38, 0.22), Palette.ICE, Palette.GLOW_SOFT, Vector3.ZERO)
	_box(parent, Vector3(0.38, 0.1, 0.08), Palette.HOT_PINK, Palette.GLOW_STRONG, Vector3(0.0, 0.0, 0.14))
	_box(parent, Vector3(0.1, 0.38, 0.08), Palette.HOT_PINK, Palette.GLOW_STRONG, Vector3(0.0, 0.0, 0.14))
	var strap := _box(parent, Vector3(0.08, 0.42, 0.08), Palette.NIGHT, 0.0, Vector3(0.22, 0.0, 0.0))
	strap.rotation.z = deg_to_rad(18.0)


static func _revive(parent: Node3D) -> void:
	_cyl(parent, 0.04, 0.55, Palette.ICE, Palette.GLOW_FAINT, Vector3(0.0, 0.05, 0.0))
	_sphere(parent, 0.12, Palette.LIME, Palette.GLOW_STRONG, Vector3(0.0, 0.38, 0.0))
	_box(parent, Vector3(0.28, 0.07, 0.07), Palette.LIME, Palette.GLOW_STRONG, Vector3(0.0, 0.38, 0.0))
	_box(parent, Vector3(0.07, 0.28, 0.07), Palette.LIME, Palette.GLOW_STRONG, Vector3(0.0, 0.38, 0.0))
	var wing := _box(parent, Vector3(0.34, 0.05, 0.12), Palette.ICE, Palette.GLOW_MEDIUM, Vector3(0.16, 0.18, 0.0))
	wing.rotation.z = deg_to_rad(-32.0)


static func _clock(parent: Node3D, color: Color, frozen: bool) -> void:
	_cyl(parent, 0.28, 0.08, color.darkened(0.45), Palette.GLOW_SOFT, Vector3.ZERO)
	var face := MeshFactory.disk(0.24, color, Palette.GLOW_MEDIUM)
	face.rotation.x = deg_to_rad(90.0)
	face.position.z = 0.05
	parent.add_child(face)
	var hour := _box(parent, Vector3(0.05, 0.14, 0.03), Palette.NIGHT, 0.0, Vector3(0.0, 0.05, 0.08))
	hour.rotation.z = deg_to_rad(28.0)
	var minute := _box(parent, Vector3(0.035, 0.2, 0.03), Palette.NIGHT, 0.0, Vector3(0.06, 0.02, 0.08))
	minute.rotation.z = deg_to_rad(-52.0)
	if frozen:
		for side: float in [-1.0, 1.0]:
			var shard := _box(
				parent, Vector3(0.06, 0.28, 0.05), Palette.ICE, Palette.GLOW_STRONG,
				Vector3(side * 0.22, 0.08, 0.04)
			)
			shard.rotation.z = deg_to_rad(side * 38.0)


static func _club(parent: Node3D, color: Color) -> void:
	_cyl(parent, 0.16, 1.15, color.darkened(0.35), Palette.GLOW_FAINT, Vector3(0.0, 0.0, 0.0))
	var shaft := _cyl(parent, 0.035, 1.45, Palette.ICE, Palette.GLOW_MEDIUM, Vector3(0.04, 0.85, 0.0))
	shaft.rotation.z = deg_to_rad(-12.0)
	_box(parent, Vector3(0.22, 0.08, 0.12), color, Palette.GLOW_SOFT, Vector3(0.16, 1.48, 0.0))


static func _cart_body(parent: Node3D) -> void:
	_box(parent, Vector3(1.15, 0.28, 2.05), Palette.CART_FRAME, 0.0, Vector3(0.0, 0.22, 0.0))
	_box(parent, Vector3(1.22, 0.06, 2.12), Palette.CART, Palette.GLOW_STRONG, Vector3(0.0, 0.38, 0.0))
	_box(parent, Vector3(1.18, 0.08, 1.35), Palette.CART, Palette.GLOW_MEDIUM, Vector3(0.0, 1.05, 0.05))
	for x: float in [-0.52, 0.52]:
		for z: float in [-0.62, 0.62]:
			_box(parent, Vector3(0.06, 0.62, 0.06), Palette.CART_FRAME, 0.0, Vector3(x, 0.72, z))
	for x: float in [-0.58, 0.58]:
		for z: float in [-0.72, 0.72]:
			var wheel := _cyl(parent, 0.2, 0.1, Palette.CART_FRAME, 0.0, Vector3(x, 0.2, z))
			wheel.rotation.z = deg_to_rad(90.0)
	for x: float in [-0.32, 0.32]:
		_box(parent, Vector3(0.18, 0.1, 0.06), Palette.HEADLIGHT, Palette.GLOW_STRONG, Vector3(x, 0.42, -1.05))
	var ram := _box(parent, Vector3(1.05, 0.16, 0.42), Palette.MAGENTA, Palette.GLOW_STRONG, Vector3(0.0, 0.28, -1.12))
	ram.rotation.x = deg_to_rad(32.0)
	for x: float in [-0.38, 0.38]:
		var plate := _box(parent, Vector3(0.08, 0.42, 1.15), Palette.ICE, Palette.GLOW_MEDIUM, Vector3(x, 0.52, 0.05))
		plate.rotation.z = deg_to_rad(x * -18.0)
	for x: float in [-0.22, 0.22]:
		var jet := _cyl(parent, 0.07, 0.22, Palette.CART_FRAME, 0.0, Vector3(x, 0.32, 1.12))
		jet.rotation.x = deg_to_rad(90.0)
		_sphere(parent, 0.08, Palette.AMBER, Palette.GLOW_STRONG, Vector3(x, 0.32, 1.28))


static func _caption(root: Node3D, text: String, at: Vector3) -> void:
	var copy := Label3D.new()
	copy.text = text
	copy.font_size = 40
	copy.modulate = Palette.AMBER
	copy.outline_size = 8
	copy.outline_modulate = Palette.NIGHT
	copy.position = at
	root.add_child(copy)


static func _box(
	parent: Node3D, size: Vector3, color: Color, glow: float, at: Vector3
) -> MeshInstance3D:
	var mesh := MeshFactory.box(size, color, glow)
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _cyl(
	parent: Node3D, radius: float, height: float, color: Color, glow: float, at: Vector3
) -> MeshInstance3D:
	var mesh := MeshFactory.cylinder(radius, height, color, glow)
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _sphere(
	parent: Node3D, radius: float, color: Color, glow: float, at: Vector3
) -> MeshInstance3D:
	var mesh := MeshFactory.sphere(radius, color, glow)
	mesh.position = at
	parent.add_child(mesh)
	return mesh
