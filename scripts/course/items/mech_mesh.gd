class_name MechMesh
extends Object
## Extra neon plates, vents and joints hung on the mech rig. Kept apart from the
## walk cycle so the silhouette can get denser without the pose code growing.

const S := 4.0


static func torso(parent: Node3D) -> void:
	_box(parent, Vector3(1.95, 1.72, 1.22), Vector3(0.0, 0.78, -0.08), Palette.MECH, Palette.GLOW_SOFT)
	_box(parent, Vector3(2.08, 0.14, 1.32), Vector3(0.0, 1.58, -0.08), Palette.MECH_FRAME, Palette.GLOW_MEDIUM)
	_box(parent, Vector3(1.15, 0.18, 1.28), Vector3(0.0, 0.08, -0.04), Palette.MECH_FRAME, Palette.GLOW_FAINT)
	var core := MeshFactory.cylinder(0.22 * S, 0.18 * S, Palette.AMBER, Palette.GLOW_STRONG)
	core.rotation.x = deg_to_rad(90.0)
	core.position = Vector3(0.0, 0.72, -0.68) * S
	parent.add_child(core)
	_box(parent, Vector3(0.62, 0.72, 0.1), Vector3(-0.28, 0.85, -0.66), Palette.ICE, Palette.GLOW_MEDIUM)
	_box(parent, Vector3(0.62, 0.72, 0.1), Vector3(0.28, 0.85, -0.66), Palette.ICE, Palette.GLOW_MEDIUM)
	for side: float in [-1.0, 1.0]:
		_box(parent, Vector3(0.22, 1.15, 0.55), Vector3(side * 0.98, 0.7, -0.02), Palette.MECH_FRAME)
		var vent := MeshFactory.cylinder(0.1 * S, 0.42 * S, Palette.ICE, Palette.GLOW_SOFT)
		vent.rotation.z = deg_to_rad(90.0)
		vent.position = Vector3(side * 1.08, 0.55, 0.28) * S
		parent.add_child(vent)
	_box(parent, Vector3(1.55, 0.85, 0.72), Vector3(0.0, 0.82, 0.72), Palette.MECH_FRAME)
	for side: float in [-1.0, 1.0]:
		var stack := MeshFactory.cylinder(0.14 * S, 0.85 * S, Palette.MECH_FRAME, Palette.GLOW_FAINT)
		stack.position = Vector3(side * 0.38, 1.42, 0.78) * S
		parent.add_child(stack)
		var rim := MeshFactory.cylinder(0.18 * S, 0.08 * S, Palette.AMBER, Palette.GLOW_STRONG)
		rim.position = Vector3(side * 0.38, 1.88, 0.78) * S
		parent.add_child(rim)


static func head(parent: Node3D) -> void:
	_box(parent, Vector3(1.05, 0.78, 0.92), Vector3(0.0, 0.28, -0.06), Palette.MECH_FRAME, Palette.GLOW_FAINT)
	_box(parent, Vector3(0.22, 0.55, 0.72), Vector3(0.0, 0.72, 0.04), Palette.MECH, Palette.GLOW_SOFT)
	var visor := Node3D.new()
	visor.name = "Visor"
	parent.add_child(visor)
	var z := -0.52
	_box(visor, Vector3(0.82, 0.08, 0.1), Vector3(0.0, 0.42, z), Palette.ICE, Palette.GLOW_MEDIUM)
	_box(visor, Vector3(0.82, 0.08, 0.1), Vector3(0.0, 0.12, z), Palette.ICE, Palette.GLOW_MEDIUM)
	for side: float in [-1.0, 1.0]:
		_box(visor, Vector3(0.08, 0.28, 0.1), Vector3(side * 0.4, 0.27, z), Palette.ICE, Palette.GLOW_MEDIUM)
		_box(parent, Vector3(0.18, 0.42, 0.38), Vector3(side * 0.58, 0.3, 0.02), Palette.MECH_FRAME)
	var mast := MeshFactory.cylinder(0.04 * S, 0.55 * S, Palette.MECH_FRAME)
	mast.position = Vector3(0.22, 0.92, 0.12) * S
	parent.add_child(mast)
	var beacon := MeshFactory.sphere(0.09 * S, Palette.LED_RED, Palette.GLOW_STRONG)
	beacon.position = Vector3(0.22, 1.22, 0.12) * S
	parent.add_child(beacon)


static func hatch(parent: Node3D) -> Node3D:
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	hatch.position = Vector3(0.0, 0.82, 0.62) * S
	hatch.rotation.x = deg_to_rad(-78.0)
	parent.add_child(hatch)
	_box(hatch, Vector3(1.15, 0.1, 1.25), Vector3(0.0, 0.0, -0.5), Palette.MECH_FRAME, Palette.GLOW_MEDIUM)
	_box(hatch, Vector3(0.55, 0.06, 0.4), Vector3(0.0, 0.08, -0.5), Palette.ICE, Palette.GLOW_SOFT)
	return hatch


static func leg(pivot: Node3D, side: float) -> Node3D:
	_box(pivot, Vector3(0.62, 0.28, 0.62), Vector3(0.0, 0.0, 0.0), Palette.MECH_FRAME, Palette.GLOW_SOFT)
	_box(pivot, Vector3(0.58, 1.22, 0.68), Vector3(0.0, -0.7, -0.04), Palette.MECH_FRAME, Palette.GLOW_FAINT)
	var knee := Node3D.new()
	knee.position = Vector3(0.0, -1.28, 0.0) * S
	pivot.add_child(knee)
	_box(knee, Vector3(0.55, 0.28, 0.58), Vector3.ZERO, Palette.ICE, Palette.GLOW_SOFT)
	_box(knee, Vector3(0.5, 1.05, 0.52), Vector3(0.0, -0.58, 0.04), Palette.MECH_FRAME)
	var ram := MeshFactory.cylinder(0.08 * S, 0.85 * S, Palette.AMBER, Palette.GLOW_MEDIUM)
	ram.position = Vector3(side * 0.28, -0.52, 0.22) * S
	knee.add_child(ram)
	_box(knee, Vector3(0.72, 0.32, 1.05), Vector3(0.0, -1.18, 0.12), Palette.MECH, Palette.GLOW_SOFT)
	_box(knee, Vector3(0.38, 0.16, 0.32), Vector3(0.0, -1.22, -0.48), Palette.MECH_FRAME)
	_box(knee, Vector3(0.55, 0.08, 0.72), Vector3(0.0, -1.36, 0.18), Palette.ICE, Palette.GLOW_FAINT)
	return knee


static func arm(pivot: Node3D, side: float, pod_name: String) -> Node3D:
	_box(pivot, Vector3(0.85, 0.42, 0.72), Vector3(side * 0.12, 0.08, 0.0), Palette.MECH_FRAME, Palette.GLOW_MEDIUM)
	var pod := MeshFactory.cylinder(0.28 * S, 0.72 * S, Palette.MECH_FRAME, Palette.GLOW_MEDIUM)
	pod.name = pod_name
	pod.rotation.z = deg_to_rad(90.0)
	pod.position = Vector3(side * 0.22, 0.22, -0.08) * S
	pivot.add_child(pod)
	var tube := MeshFactory.cylinder(0.11 * S, 0.58 * S, Palette.MECH, Palette.GLOW_STRONG)
	tube.rotation.x = deg_to_rad(90.0)
	tube.position = Vector3(side * 0.22, 0.22, -0.46) * S
	pivot.add_child(tube)
	_box(pivot, Vector3(0.42, 0.95, 0.42), Vector3(0.0, -0.52, 0.0), Palette.MECH_FRAME, Palette.GLOW_FAINT)
	var elbow := Node3D.new()
	elbow.position = Vector3(0.0, -1.02, 0.0) * S
	pivot.add_child(elbow)
	_box(elbow, Vector3(0.38, 0.28, 0.38), Vector3.ZERO, Palette.ICE, Palette.GLOW_SOFT)
	_box(elbow, Vector3(0.4, 0.85, 0.4), Vector3(0.0, -0.48, 0.0), Palette.MECH_FRAME)
	_box(elbow, Vector3(0.52, 0.28, 0.42), Vector3(0.0, -0.98, -0.04), Palette.MECH, Palette.GLOW_SOFT)
	for i in 3:
		var claw := MeshFactory.box(
			Vector3(0.08, 0.28, 0.1) * S, Palette.ICE, Palette.GLOW_FAINT
		)
		claw.position = Vector3((float(i) - 1.0) * 0.14, -1.22, -0.12) * S
		elbow.add_child(claw)
	return elbow


static func _box(
	parent: Node3D, size: Vector3, at: Vector3, color: Color, glow := 0.0
) -> MeshInstance3D:
	var mesh := MeshFactory.box(size * S, color, glow)
	mesh.position = at * S
	parent.add_child(mesh)
	return mesh
