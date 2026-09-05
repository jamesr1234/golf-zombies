class_name Apparel
extends Object
## Neon clothes the robot wears, and the bigger hanging versions on the shop wall.
## Chevrons, sleeves and streamers are what stop a bought shirt from reading as
## another box on the chest. The shop inspect spins these hung garments, not the
## robot wearing them.


static func trim(color: Color) -> Color:
	return Palette.NIGHT if color.get_luminance() > 0.72 else Palette.ICE


static func wear_shirt(body, color: Color) -> Array[MeshInstance3D]:
	var pieces: Array[MeshInstance3D] = []
	var accent := trim(color)
	pieces.append(_piece(body, Vector3(0.52, 0.58, 0.34), color, Palette.GLOW_MEDIUM, Vector3(0.0, 0.27, 0.0)))
	pieces.append(_piece(body, Vector3(0.22, 0.08, 0.2), accent, Palette.GLOW_STRONG, Vector3(0.0, 0.56, 0.0)))
	for side: float in [-1.0, 1.0]:
		var chevron := MeshFactory.box(Vector3(0.09, 0.42, 0.05), accent, Palette.GLOW_STRONG)
		chevron.rotation.z = deg_to_rad(-32.0 * side)
		pieces.append(_on(body, chevron, Vector3(side * 0.09, 0.34, -0.18)))
		var sleeve := MeshFactory.box(Vector3(0.18, 0.2, 0.18), color, Palette.GLOW_MEDIUM)
		sleeve.position.y = -0.06
		body.attach_wear(sleeve, body.arms[0 if side < 0.0 else 1], false)
		pieces.append(sleeve)
	return pieces


static func wear_headband(body, color: Color) -> Array[MeshInstance3D]:
	var pieces: Array[MeshInstance3D] = []
	var accent := trim(color)
	var host: Node3D = body.head
	var lift := 0.26 if host != null else 0.9
	pieces.append(_piece(body, Vector3(0.32, 0.07, 0.3), color, Palette.GLOW_MEDIUM, Vector3(0.0, lift, 0.0), host))
	pieces.append(_piece(body, Vector3(0.18, 0.05, 0.04), accent, Palette.GLOW_STRONG, Vector3(0.0, lift, -0.16), host))
	pieces.append(_on(body, MeshFactory.sphere(0.04, accent, Palette.GLOW_STRONG), Vector3(0.16, lift, 0.1), host))
	var streamer := MeshFactory.box(Vector3(0.045, 0.28, 0.09), color, Palette.GLOW_STRONG)
	streamer.rotation.x = deg_to_rad(42.0)
	streamer.rotation.z = deg_to_rad(-22.0)
	pieces.append(_on(body, streamer, Vector3(0.16, lift - 0.12, 0.16), host))
	return pieces


static func wear_bottom(body, style: String, color: Color) -> Array[MeshInstance3D]:
	var pieces: Array[MeshInstance3D] = []
	var accent := trim(color)
	var long := style == "pants"
	pieces.append(_piece(body, Vector3(0.5, 0.08, 0.32), color, Palette.GLOW_MEDIUM, Vector3(0.0, -0.02, 0.0), body.hips))
	pieces.append(_piece(body, Vector3(0.52, 0.035, 0.34), accent, Palette.GLOW_STRONG, Vector3(0.0, 0.02, 0.0), body.hips))
	for i in body.legs.size():
		var leg := body.legs[i] as Node3D
		var side := -1.0 if i == 0 else 1.0
		var thigh_h := 0.28 if long else 0.24
		pieces.append(_piece(body, Vector3(0.18, thigh_h, 0.18), color, Palette.GLOW_MEDIUM, Vector3(0.0, -0.2, 0.0), leg))
		pieces.append(_piece(body, Vector3(0.04, thigh_h - 0.02, 0.05), accent, Palette.GLOW_STRONG, Vector3(side * 0.09, -0.2, 0.0), leg))
		if long:
			pieces.append(_piece(body, Vector3(0.16, 0.4, 0.16), color, Palette.GLOW_MEDIUM, Vector3(0.0, -0.62, 0.0), leg))
			pieces.append(_piece(body, Vector3(0.035, 0.36, 0.045), accent, Palette.GLOW_STRONG, Vector3(side * 0.08, -0.62, 0.0), leg))
			pieces.append(_piece(body, Vector3(0.17, 0.06, 0.17), accent, Palette.GLOW_STRONG, Vector3(0.0, -0.8, 0.0), leg))
		else:
			pieces.append(_piece(body, Vector3(0.19, 0.05, 0.19), accent, Palette.GLOW_STRONG, Vector3(0.0, -0.32, 0.0), leg))
	return pieces


## Hung garment for the shop inspect, centered on the spin so you can turn it.
static func preview(parent: Node3D, item: Dictionary) -> bool:
	if parent == null or String(item.get("kind", "")) != "apparel":
		return false
	var color: Color = item.get("color", Palette.CYAN)
	match String(item.get("slot", "")):
		"headband":
			hang_headband(parent, Vector3.ZERO, color)
		"shirt":
			hang_shirt(parent, Vector3.ZERO, color)
		"bottom":
			hang_bottom(parent, Vector3.ZERO, color, String(item.get("style", "")) == "pants")
		_:
			return false
	return true


static func hang_wall(root: Node3D) -> void:
	var counts := {"headband": 0, "shirt": 0, "shorts": 0, "pants": 0}
	for item in ShopStock.apparel():
		var key := String(item["slot"])
		if key == "bottom":
			key = String(item.get("style", "shorts"))
		var n: int = counts[key]
		counts[key] = n + 1
		var color: Color = item["color"]
		match key:
			"headband":
				hang_headband(root, Vector3(-2.7 + float(n) * 1.8, 2.45, 0.34), color)
			"shirt":
				hang_shirt(root, Vector3(0.9 + float(n) * 1.8, 2.12, 0.34), color)
			"shorts":
				hang_bottom(root, Vector3(-2.7 + float(n) * 1.8, 0.92, 0.36), color, false)
			"pants":
				hang_bottom(root, Vector3(0.9 + float(n) * 1.8, 0.78, 0.36), color, true)


static func hang_shirt(host: Node3D, at: Vector3, color: Color) -> void:
	var accent := trim(color)
	_hook(host, at + Vector3(0.0, 0.58, 0.0))
	_box(host, Vector3(0.62, 0.95, 0.12), color, Palette.GLOW_MEDIUM, at)
	for side: float in [-1.0, 1.0]:
		var sleeve := _box(host, Vector3(0.42, 0.22, 0.12), color, Palette.GLOW_MEDIUM, at + Vector3(side * 0.44, 0.28, 0.0))
		sleeve.rotation.z = deg_to_rad(-38.0 * side)
		var chevron := _box(host, Vector3(0.08, 0.52, 0.05), accent, Palette.GLOW_STRONG, at + Vector3(side * 0.08, 0.06, 0.08))
		chevron.rotation.z = deg_to_rad(-28.0 * side)


static func hang_headband(host: Node3D, at: Vector3, color: Color) -> void:
	var accent := trim(color)
	_hook(host, at + Vector3(0.0, 0.28, 0.0))
	var ring := MeshFactory.torus(0.12, 0.2, color, Palette.GLOW_MEDIUM)
	ring.rotation.x = deg_to_rad(90.0)
	ring.position = at
	host.add_child(ring)
	var plate := _box(host, Vector3(0.22, 0.07, 0.05), accent, Palette.GLOW_STRONG, at + Vector3(0.0, 0.0, 0.18))
	plate.rotation.x = deg_to_rad(8.0)
	var streamer := _box(host, Vector3(0.07, 0.55, 0.12), color, Palette.GLOW_STRONG, at + Vector3(0.22, -0.28, 0.04))
	streamer.rotation.z = deg_to_rad(-28.0)
	streamer.rotation.x = deg_to_rad(18.0)


static func hang_bottom(host: Node3D, at: Vector3, color: Color, long: bool) -> void:
	var accent := trim(color)
	var drop := 0.95 if long else 0.42
	_hook(host, at + Vector3(0.0, 0.22, 0.0))
	_box(host, Vector3(0.7, 0.12, 0.16), color, Palette.GLOW_MEDIUM, at + Vector3(0.0, 0.12, 0.0))
	_box(host, Vector3(0.74, 0.05, 0.18), accent, Palette.GLOW_STRONG, at + Vector3(0.0, 0.18, 0.0))
	for side: float in [-1.0, 1.0]:
		var leg_at := at + Vector3(side * 0.16, -drop * 0.5, 0.0)
		_box(host, Vector3(0.28, drop, 0.16), color, Palette.GLOW_MEDIUM, leg_at)
		_box(host, Vector3(0.06, drop * 0.86, 0.05), accent, Palette.GLOW_STRONG, leg_at + Vector3(side * 0.14, 0.0, 0.08))


static func _piece(
	body, size: Vector3, color: Color, glow: float, at: Vector3, parent: Node3D = null
) -> MeshInstance3D:
	return _on(body, MeshFactory.box(size, color, glow), at, parent)


static func _on(body, mesh: MeshInstance3D, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	mesh.position = at
	body.attach_wear(mesh, parent)
	return mesh


static func _hook(host: Node3D, at: Vector3) -> void:
	var hook := MeshFactory.cylinder(0.018, 0.16, Palette.ICE, Palette.GLOW_FAINT)
	hook.position = at
	host.add_child(hook)


static func _box(
	host: Node3D, size: Vector3, color: Color, glow: float, at: Vector3
) -> MeshInstance3D:
	var mesh := MeshFactory.box(size, color, glow)
	mesh.position = at
	host.add_child(mesh)
	return mesh
