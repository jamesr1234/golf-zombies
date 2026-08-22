class_name BeerCartVisuals
extends Object
## Bigger beverage wagon: longer deck, a rear cooler, and a lid that flips
## open. Kept apart from the driving so the chrome can change without the AI.

const DECK_HEIGHT := 0.62
const ROOF_HEIGHT := 2.05
const WHEEL_RADIUS := 0.36
const WHEEL_X := 0.95
const WHEEL_Z := 1.35
const NOSE_Z := -2.05
const COOLER_Z := 1.72


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Visuals"
	root.add_child(_deck())
	for post in _roof():
		root.add_child(post)
	for wheel in _wheels():
		root.add_child(wheel)
	for light in _headlights():
		root.add_child(light)
	root.add_child(_cooler())
	return root


static func _deck() -> Node3D:
	var deck := Node3D.new()
	var floor_slab := MeshFactory.box(Vector3(2.2, 0.48, 4.2), Palette.BEER_CART_FRAME)
	floor_slab.position.y = DECK_HEIGHT
	deck.add_child(floor_slab)
	var lip := MeshFactory.box(Vector3(2.28, 0.08, 4.28), Palette.BEER_CART, Palette.GLOW_SOFT)
	lip.position.y = DECK_HEIGHT + 0.28
	deck.add_child(lip)
	for side: float in [-1.0, 1.0]:
		var back := MeshFactory.box(Vector3(0.78, 0.62, 0.12), Palette.BEER_CART)
		back.position = Vector3(side * 0.48, 1.18, 0.42)
		deck.add_child(back)
	var dash := MeshFactory.box(Vector3(1.6, 0.16, 0.28), Palette.BEER_CART, Palette.GLOW_FAINT)
	dash.position = Vector3(0.0, 1.18, -0.55)
	deck.add_child(dash)
	return deck


static func _roof() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	var canopy := MeshFactory.box(Vector3(2.2, 0.1, 2.4), Palette.BEER_CART, Palette.GLOW_FAINT)
	canopy.position = Vector3(0.0, ROOF_HEIGHT, -0.15)
	parts.append(canopy)
	for x: float in [-0.98, 0.98]:
		for z: float in [-1.1, 0.75]:
			var post := MeshFactory.box(Vector3(0.08, 1.12, 0.08), Palette.BEER_CART_FRAME)
			post.position = Vector3(x, ROOF_HEIGHT - 0.56, z)
			parts.append(post)
	return parts


static func _wheels() -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	for x: float in [-WHEEL_X, WHEEL_X]:
		for z: float in [-WHEEL_Z, WHEEL_Z]:
			var wheel := MeshFactory.cylinder(WHEEL_RADIUS, 0.2, Palette.BEER_CART_FRAME)
			wheel.rotation.z = deg_to_rad(90.0)
			wheel.position = Vector3(x, WHEEL_RADIUS, z)
			wheels.append(wheel)
	return wheels


static func _headlights() -> Array[Node3D]:
	var lights: Array[Node3D] = []
	for x: float in [-0.7, 0.7]:
		var lamp := MeshFactory.box(
			Vector3(0.3, 0.16, 0.08), Palette.HEADLIGHT, Palette.GLOW_STRONG
		)
		lamp.position = Vector3(x, 0.82, NOSE_Z)
		lights.append(lamp)
	var beam := SpotLight3D.new()
	beam.light_color = Palette.HEADLIGHT
	beam.light_energy = 3.2
	beam.spot_range = 28.0
	beam.spot_angle = 44.0
	beam.spot_attenuation = 0.7
	beam.position = Vector3(0.0, 0.95, NOSE_Z)
	lights.append(beam)
	return lights


static func _cooler() -> Node3D:
	var cooler := Node3D.new()
	cooler.name = "Cooler"
	var tub := MeshFactory.box(Vector3(1.55, 0.72, 1.25), Palette.COOLER, Palette.GLOW_FAINT)
	tub.position = Vector3(0.0, 1.12, COOLER_Z)
	cooler.add_child(tub)
	var trim := MeshFactory.box(Vector3(1.62, 0.08, 1.32), Palette.BEER, Palette.GLOW_MEDIUM)
	trim.position = Vector3(0.0, 1.5, COOLER_Z)
	cooler.add_child(trim)
	for can in _cans():
		cooler.add_child(can)
	var hinge := Node3D.new()
	hinge.name = "Lid"
	hinge.position = Vector3(0.0, 1.5, COOLER_Z + 0.58)
	var lid := MeshFactory.box(Vector3(1.58, 0.08, 1.28), Palette.COOLER, Palette.GLOW_SOFT)
	lid.position.z = -0.58
	hinge.add_child(lid)
	var handle := MeshFactory.box(Vector3(0.42, 0.06, 0.08), Palette.BEER, Palette.GLOW_MEDIUM)
	handle.position = Vector3(0.0, 0.08, -1.12)
	hinge.add_child(handle)
	cooler.add_child(hinge)
	return cooler


static func _cans() -> Array[Node3D]:
	var cans: Array[Node3D] = []
	for x: float in [-0.42, 0.0, 0.42]:
		for z: float in [-0.28, 0.22]:
			var can := BeerCan.create(1.55)
			can.position = Vector3(x, 1.28, COOLER_Z + z)
			cans.append(can)
	return cans
