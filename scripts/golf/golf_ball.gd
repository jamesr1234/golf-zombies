class_name GolfBall
extends RigidBody3D
## The one shared ball. Reads its lie from the surface patches it overlaps and
## reports the three events the match cares about: at rest, hazard, holed.
## Water is a swim, not a penalty: the ball sinks and waits to be picked up.

signal came_to_rest(position: Vector3)
signal entered_hazard(kind: String)
signal holed()

const RADIUS := 0.15
const REST_SPEED := 0.6
const REST_TIME := 0.45
const SLOW_GRAB := 6.0
const SLOW_SPEED := 3.0
## Above this speed the ball just rattles across the cup instead of dropping.
const HOLE_SPEED_LIMIT := 6.5
const AIR_DAMP := 0.02
const SINK_DAMP := 4.5
const FLIGHT_BOUNCE := 0.35
## Well under the deepest pond floor and the skirt below the course, so this only
## catches a ball that has fallen out of the world rather than one that has sunk.
const UNDER_THE_WORLD := -22.0
const BOUNCE_MIN := 2.4
const BOUNCE_COOL := 0.14

var bounds := Rect2(-500.0, -500.0, 1000.0, 1000.0)
var last_safe_position := Vector3.ZERO
## 0 means anyone can play it (local co-op). Online VS sets the owning peer.
var owner_peer := 0

## Multiset of overlapping Surface.Type patches; the highest priority is the lie.
var _surfaces: Array = []
var _rest_timer := 0.0
var _in_play := false
var _grounded := false
var _carrier: Node3D = null
var _holed := false
var _stowed := false
var _closed := false
var _putting := false
var _sinking := false
var _sink_at := Vector3.ZERO
var _sink_floor := 0.0
var _sink_time := 0.0
var _lie_shape := SphereShape3D.new()
var _bounce_cool := 0.0


func _ready() -> void:
	collision_layer = Layers.BALL
	collision_mask = Layers.BALL_MASK
	mass = 0.2
	continuous_cd = true
	_lie_shape.radius = RADIUS + 0.35
	var material := PhysicsMaterial.new()
	material.friction = 0.7
	material.bounce = FLIGHT_BOUNCE
	physics_material_override = material
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_hit)


func apply_color(color: Color) -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.25
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = Palette.GLOW_MEDIUM
		mesh.set_surface_override_material(0, mat)
	var glow := get_node_or_null("Glow") as OmniLight3D
	if glow != null:
		glow.light_color = color


func is_owned_by(player: Node) -> bool:
	if owner_peer == 0:
		return true
	return player != null and int(player.get("peer_id")) == owner_peer


func place_at(position: Vector3) -> void:
	release_carried()
	_surfaces.clear()
	_in_play = false
	_holed = false
	_stowed = false
	_closed = false
	_putting = false
	_clear_sink()
	_rest_timer = 0.0
	_set_bounce(FLIGHT_BOUNCE)
	visible = true
	collision_layer = Layers.BALL
	freeze = true
	global_position = position + Vector3.UP * (RADIUS + 0.06)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	last_safe_position = position
	freeze = false
	sleeping = false


func strike(
	yaw_deg: float, deviation_deg: float, power: float, kit: ClubKit = null, green_span := 0.0
) -> void:
	var surface := current_surface()
	_putting = Shot.can_putt(surface)
	_set_bounce(0.0 if _putting else FLIGHT_BOUNCE)
	last_safe_position = global_position - Vector3.UP * RADIUS
	sleeping = false
	var launch := Shot.velocity(
		yaw_deg, deviation_deg, power, surface, _putting, kit, green_span
	)
	if _putting:
		launch.y = 0.0
	linear_velocity = launch
	angular_velocity = launch.cross(Vector3.UP) * 0.6
	_in_play = true
	_closed = false
	_rest_timer = 0.0


func current_surface() -> Surface.Type:
	var types := _query_lies()
	for type in _surfaces:
		types.append(type)
	return Surface.dominant(types)


func is_putting() -> bool:
	return _putting or Shot.can_putt(current_surface())


func is_on_green() -> bool:
	return Surface.looks_like_green(current_surface())


func is_in_play() -> bool:
	return _in_play


func is_submerged() -> bool:
	return current_surface() == Surface.Type.WATER and _carrier == null


func is_carried() -> bool:
	return _carrier != null


func is_holed() -> bool:
	return _holed


func is_sinking() -> bool:
	return _sinking


func is_stowed() -> bool:
	return _stowed


## The hole is over without a drop. Stay put until someone picks the ball up.
func close_for_pickup() -> void:
	_in_play = false
	_closed = true
	_putting = false
	_rest_timer = 0.0
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func is_closed() -> bool:
	return _closed


func carrier() -> Node3D:
	return _carrier


func enter_surface(type: Surface.Type) -> void:
	_surfaces.append(type)


func exit_surface(type: Surface.Type) -> void:
	var at := _surfaces.find(type)
	if at != -1:
		_surfaces.remove_at(at)


func try_hole_out(cup: Node3D = null) -> void:
	if not _in_play or is_carried() or is_holed() or _sinking:
		return
	if linear_velocity.length() > HOLE_SPEED_LIMIT:
		return
	_begin_sink(cup)


func _begin_sink(cup: Node3D) -> void:
	_sinking = true
	_putting = false
	_sink_time = 0.0
	_set_bounce(0.0)
	collision_mask = Layers.CUP
	if cup != null:
		_sink_at = cup.global_position
		_sink_floor = cup.global_position.y + Cup.floor_top()
	else:
		_sink_at = global_position
		_sink_floor = global_position.y - Cup.DEPTH + Cup.FLOOR_THICK
	var vel := linear_velocity
	vel.x *= 0.3
	vel.z *= 0.3
	vel.y = minf(vel.y, -1.4)
	linear_velocity = vel
	freeze = false
	sleeping = false
	Sfx.play("hole_out", self)


func _tick_sink(delta: float) -> void:
	_sink_time += delta
	var to_center := Vector3(_sink_at.x - global_position.x, 0.0, _sink_at.z - global_position.z)
	linear_velocity.x += to_center.x * 22.0 * delta
	linear_velocity.z += to_center.z * 22.0 * delta
	linear_damp = 1.4
	angular_damp = 2.4
	var in_the_hole := global_position.y <= _sink_floor + RADIUS + 0.14
	if (in_the_hole and linear_velocity.length() < 1.6) or _sink_time > 2.2:
		_finish_sink()


func _finish_sink() -> void:
	_sinking = false
	_in_play = false
	_holed = true
	freeze = true
	collision_mask = 0
	global_position = Vector3(_sink_at.x, _sink_floor + RADIUS, _sink_at.z)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	holed.emit()


func _clear_sink() -> void:
	_sinking = false
	_sink_time = 0.0
	collision_mask = Layers.BALL_MASK


func pick_up(who: Node3D) -> void:
	if who == null or is_carried() or is_stowed():
		return
	_carrier = who
	_in_play = false
	_putting = false
	_clear_sink()
	_rest_timer = 0.0
	freeze = true
	collision_layer = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Pocketed after a hole-out so it rides to the next tee instead of bouncing around
## the cart. `place_at` puts it back in play.
func stow() -> void:
	release_carried()
	_stowed = true
	_holed = true
	_in_play = false
	_putting = false
	_clear_sink()
	_rest_timer = 0.0
	visible = false
	freeze = true
	collision_layer = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func release_carried() -> void:
	if _carrier == null:
		return
	_carrier = null
	freeze = false
	collision_layer = Layers.BALL
	sleeping = false


func toss(origin: Vector3, velocity: Vector3) -> void:
	release_carried()
	_putting = false
	_set_bounce(FLIGHT_BOUNCE)
	global_position = origin
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	last_safe_position = origin
	_in_play = true
	_closed = false
	_rest_timer = 0.0
	sleeping = false


func _physics_process(delta: float) -> void:
	if not NetSession.should_simulate(self):
		return
	_bounce_cool = maxf(0.0, _bounce_cool - delta)
	if _carrier != null:
		_follow_carrier()
		return
	if _sinking:
		_tick_sink(delta)
		return
	_grounded = _check_grounded()
	_keep_putt_down()
	_apply_lie_damping()
	if not _in_play:
		return
	var off_the_map := not bounds.has_point(Vector2(global_position.x, global_position.z))
	if off_the_map or global_position.y < UNDER_THE_WORLD:
		_in_play = false
		_putting = false
		entered_hazard.emit("out of bounds")
		Sfx.play("hazard", self)
		return
	if linear_velocity.length() <= REST_SPEED and _grounded:
		_rest_timer += delta
		if _rest_timer >= REST_TIME:
			_in_play = false
			_putting = false
			came_to_rest.emit(global_position)
	else:
		_rest_timer = 0.0


func _follow_carrier() -> void:
	if _carrier is Player:
		global_position = Player.carry_point((_carrier as Player).head.global_transform)
		return
	global_position = _carrier.global_position + Vector3.UP * 1.1


func _apply_lie_damping() -> void:
	var surface := current_surface()
	if surface == Surface.Type.WATER:
		linear_damp = SINK_DAMP
		angular_damp = SINK_DAMP
		return
	if not _grounded:
		linear_damp = AIR_DAMP
		angular_damp = AIR_DAMP
		return
	linear_damp = Surface.LINEAR_DAMP[surface]
	angular_damp = Surface.ANGULAR_DAMP[surface]
	# Grass grabs a trickling ball, otherwise a gentle downhill never comes to rest.
	if linear_velocity.length() < SLOW_SPEED:
		linear_damp += SLOW_GRAB
		angular_damp += SLOW_GRAB


func _keep_putt_down() -> void:
	if not _putting:
		return
	var velocity := linear_velocity
	if velocity.y <= 0.0:
		return
	velocity.y = 0.0
	linear_velocity = velocity


func _set_bounce(amount: float) -> void:
	if physics_material_override == null:
		return
	physics_material_override.bounce = amount


func _query_lies() -> Array:
	if not is_inside_tree():
		return []
	var world := get_world_3d()
	if world == null:
		return []
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _lie_shape
	params.transform = global_transform
	params.collision_mask = Layers.SURFACE
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = [get_rid()]
	var types: Array = []
	for hit in world.direct_space_state.intersect_shape(params, 12):
		var patch := hit.get("collider") as SurfacePatch
		if patch != null:
			types.append(patch.type)
	return types


func _check_grounded() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * (RADIUS + 0.2),
		Layers.WORLD | Layers.PROP, [get_rid()]
	)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_body_hit(_body: Node) -> void:
	if not _in_play or _bounce_cool > 0.0:
		return
	if linear_velocity.length() < BOUNCE_MIN:
		return
	_bounce_cool = BOUNCE_COOL
	Sfx.play("ball_bounce", self)
