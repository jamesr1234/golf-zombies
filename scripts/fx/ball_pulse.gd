class_name BallPulse
extends Node
## Breathes the glow on the ball the local viewer owns, so a pile of seat-colored
## balls still reads as yours. Opponent balls stay a steady light.

const RATE := 1.0
const REST_LIGHT := 0.7
const REST_RANGE := 4.5
const PULSE_RANGE := REST_RANGE * 3.0


func _ready() -> void:
	_own_material()


func _process(_delta: float) -> void:
	var ball := _ball()
	if ball == null:
		return
	var glow := should_pulse_for_viewers(ball, _local_viewers())
	var t := Time.get_ticks_msec() * 0.001
	_set_energy(
		energy_at(t) if glow else Palette.GLOW_MEDIUM,
		range_at(t) if glow else REST_RANGE
	)


static func should_pulse(ball: GolfBall, viewer: Node) -> bool:
	if ball == null or viewer == null or not ball.visible:
		return false
	if ball.is_holed() or ball.is_stowed() or ball.is_closed() or ball.is_carried():
		return false
	return ball.is_owned_by(viewer)


static func should_pulse_for_viewers(ball: GolfBall, viewers: Array) -> bool:
	for viewer in viewers:
		if should_pulse(ball, viewer):
			return true
	return false


static func energy_at(t: float, rate := RATE) -> float:
	return lerpf(Palette.GLOW_MEDIUM, Palette.GLOW_STRONG, 0.5 + 0.5 * sin(t * TAU * rate))


static func range_at(t: float, rate := RATE) -> float:
	return lerpf(REST_RANGE, PULSE_RANGE, 0.5 + 0.5 * sin(t * TAU * rate))


func _local_viewers() -> Array:
	var tree := get_tree()
	if tree == null:
		return []
	var net := NetSession.is_active()
	var local_id := multiplayer.get_unique_id() if net else 0
	var viewers: Array = []
	for node in tree.get_nodes_in_group("players"):
		if net and int(node.get("peer_id")) != local_id:
			continue
		viewers.append(node)
	return viewers


func _own_material() -> void:
	var mesh := _mesh()
	if mesh == null or mesh.get_surface_override_material(0) != null:
		return
	var source: Material = null
	if mesh.mesh != null:
		source = mesh.mesh.surface_get_material(0)
	if source != null:
		mesh.set_surface_override_material(0, source.duplicate())


func _set_energy(amount: float, reach := REST_RANGE) -> void:
	var mesh := _mesh()
	if mesh != null:
		if mesh.get_surface_override_material(0) == null:
			_own_material()
		var mat := mesh.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = amount
			mat.disable_fog = reach > REST_RANGE + 0.01
	var lamp := _glow()
	if lamp != null:
		lamp.light_energy = REST_LIGHT * (amount / Palette.GLOW_MEDIUM)
		lamp.omni_range = reach


func _ball() -> GolfBall:
	var node := get_parent()
	while node != null:
		if node is GolfBall:
			return node
		node = node.get_parent()
	return null


func _mesh() -> MeshInstance3D:
	var parent := get_parent() as MeshInstance3D
	if parent != null:
		return parent
	var ball := _ball()
	return ball.get_node_or_null("Mesh") as MeshInstance3D if ball != null else null


func _glow() -> OmniLight3D:
	var ball := _ball()
	return ball.get_node_or_null("Glow") as OmniLight3D if ball != null else null
