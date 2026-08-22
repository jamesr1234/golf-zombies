class_name CartVisuals
extends Object
## Builds the cart out of primitives, same as everything else in the game. Kept
## apart from golf_cart.gd so the driving and the chrome stay separate.

const DECK_HEIGHT := 0.62
const ROOF_HEIGHT := 1.95
const WHEEL_RADIUS := 0.32
const WHEEL_X := 0.72
const WHEEL_Z := 1.0
const NOSE_Z := -1.5


static func build() -> Node3D:
	var root := Node3D.new()
	root.add_child(_deck())
	for post in _roof():
		root.add_child(post)
	for wheel in _wheels():
		root.add_child(wheel)
	for light in _headlights():
		root.add_child(light)
	return root


static func _deck() -> Node3D:
	var deck := Node3D.new()
	var floor_slab := MeshFactory.box(Vector3(1.7, 0.45, 3.0), Palette.CART_FRAME)
	floor_slab.position.y = DECK_HEIGHT
	deck.add_child(floor_slab)
	# A glowing lip around the deck, so the cart reads as a shape at night.
	var lip := MeshFactory.box(Vector3(1.78, 0.08, 3.08), Palette.CART, Palette.GLOW_SOFT)
	lip.position.y = DECK_HEIGHT + 0.26
	deck.add_child(lip)
	for side: float in [-1.0, 1.0]:
		var back := MeshFactory.box(Vector3(0.72, 0.62, 0.12), Palette.CART)
		back.position = Vector3(side * 0.42, 1.15, 0.62)
		deck.add_child(back)
	return deck


static func _roof() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	var canopy := MeshFactory.box(Vector3(1.8, 0.1, 2.0), Palette.CART, Palette.GLOW_FAINT)
	canopy.position.y = ROOF_HEIGHT
	parts.append(canopy)
	for x: float in [-0.8, 0.8]:
		for z: float in [-0.85, 0.85]:
			var post := MeshFactory.box(Vector3(0.08, 1.05, 0.08), Palette.CART_FRAME)
			post.position = Vector3(x, ROOF_HEIGHT - 0.55, z)
			parts.append(post)
	return parts


static func wheel_offsets() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for x: float in [-WHEEL_X, WHEEL_X]:
		for z: float in [-WHEEL_Z, WHEEL_Z]:
			points.append(Vector3(x, 0.0, z))
	return points


static func _wheels() -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	for offset in wheel_offsets():
		var wheel := MeshFactory.cylinder(WHEEL_RADIUS, 0.18, Palette.CART_FRAME)
		wheel.rotation.z = deg_to_rad(90.0)
		wheel.position = Vector3(offset.x, WHEEL_RADIUS, offset.z)
		wheels.append(wheel)
	return wheels


static func _headlights() -> Array[Node3D]:
	var lights: Array[Node3D] = []
	for x: float in [-0.55, 0.55]:
		var lamp := MeshFactory.box(
			Vector3(0.26, 0.14, 0.08), Palette.HEADLIGHT, Palette.GLOW_STRONG
		)
		lamp.position = Vector3(x, 0.78, NOSE_Z)
		lights.append(lamp)
	var beam := SpotLight3D.new()
	beam.light_color = Palette.HEADLIGHT
	beam.light_energy = 3.0
	beam.spot_range = 26.0
	beam.spot_angle = 42.0
	beam.spot_attenuation = 0.7
	beam.position = Vector3(0.0, 0.9, NOSE_Z)
	lights.append(beam)
	return lights
