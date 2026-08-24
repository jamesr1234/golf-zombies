class_name Zombie
extends CharacterBody3D
## Chases the nearest standing player and hits them at contact range. Pathing
## uses the baked navigation mesh, with a straight-line fallback so a failed
## bake degrades into dumb-but-working behaviour instead of frozen zombies.

signal died(zombie: Zombie)

const REPATH_INTERVAL := 0.3
const STAGGER_DECAY := 6.0
const TURN_SPEED := 8.0
## Getting shot knocks a zombie back. Runners get flung, brutes barely notice: that
## is what stagger_resistance is for.
const KNOCKBACK_BASE := 2.2
const KNOCKBACK_PER_DAMAGE := 0.05
## Ceiling on stacked bullet knockback for a zombie with no resistance at all. The
## melee shove is deliberately allowed past this.
const MAX_KNOCKBACK := 5.0
const FLASH_TIME := 0.1
const MELEE_EXPLODE_DELAY := 1.0
## Extra upward pop on a shove so they burst as fireworks in the air
## instead of on the turf.
const MELEE_SKY_LIFT := 13.0
const SPIN_RATE := 8.0
## Hits at or above this fraction of height count as the skull.
const HEAD_RATIO := 0.72
## Stick to the mounds instead of bouncing off every cell. The rough can pitch
## steeper than Godot's 45-degree default, which is what made them hitch.
const FLOOR_SNAP := 0.45
const FLOOR_MAX_DEG := 60.0
const SAFE_MARGIN := 0.04
const FLARE_LIGHT_ENERGY := 5.5
const FLARE_LIGHT_RANGE := 9.0
const _ZombieShot := preload("res://scripts/zombies/zombie_shot.gd")
const _BeerCan := preload("res://scripts/player/beer_can.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")
const DRINK_TIME := 1.8

@export var stats: ZombieStats

var hp := 90.0
var move_speed := 3.4
@export var allied := false
@export var sync_netted := false
@export var sync_drink := 0.0
@export var sync_dying := false
@export var sync_yaw := 0.0
@export var sync_xform := Transform3D.IDENTITY:
	set(value):
		sync_xform = value
		if is_inside_tree() and not NetSession.should_simulate(self):
			_net_interp.arrive(value)
var last_hit_by: Player
var _net_interp := NetInterp.new()

@onready var agent: NavigationAgent3D = $Agent
@onready var shape: CollisionShape3D = $Shape
@onready var visual: ZombieBody = $Visual

var _target: Node3D
var _attack_timer := 0.0
var _repath_timer := 0.0
var _stagger := Vector3.ZERO
var _flash_left := 0.0
var _flash_material: StandardMaterial3D
var _flare_left := 0.0
var _flare_material: StandardMaterial3D
var _flare_light: OmniLight3D
var _launched := false
var _dying := false
var _exploded := false
var _explode_in := 0.0
var _spin := Vector3.ZERO
var _drink_left := 0.0
var _beer_prop: Node3D
var _melee: Melee
var _melee_pending := false
var _trap
var _shown_ally := false
var _shown_beer := false


func _ready() -> void:
	collision_layer = Layers.ZOMBIE
	collision_mask = Layers.ZOMBIE_MASK
	floor_snap_length = FLOOR_SNAP
	floor_max_angle = deg_to_rad(FLOOR_MAX_DEG)
	floor_constant_speed = true
	safe_margin = SAFE_MARGIN
	add_to_group("zombies")
	_melee = Melee.new()
	add_child(_melee)
	_apply_stats()
	_park_if_watched()


## A watched zombie is a drawing. Sliding its capsule across the heightmap
## every interpolated frame, and leaving its agent live for a bake it should
## never have started, is how Computer 2 locked up late in a hole.
func _park_if_watched() -> void:
	if NetSession.should_simulate(self):
		return
	collision_mask = 0
	if agent == null:
		return
	agent.avoidance_enabled = false
	agent.process_mode = Node.PROCESS_MODE_DISABLED


func _apply_stats() -> void:
	hp = stats.max_hp * GameSettings.zombie_hp_scale()
	move_speed = stats.speed * GameSettings.zombie_speed_scale()
	# Drawn over the top of the body colour for a hit blink, so nothing about the
	# zombie's own materials has to be saved and put back.
	_flash_material = MeshFactory.material(Color.WHITE, false, Palette.GLOW_STRONG)
	_flare_material = MeshFactory.material(Palette.LIME, false, Palette.GLOW_STRONG)
	var capsule := CapsuleShape3D.new()
	capsule.radius = stats.radius
	capsule.height = stats.height
	shape.shape = capsule
	shape.position.y = stats.height * 0.5
	agent.radius = stats.radius + 0.1
	agent.target_desired_distance = stats.attack_range * 0.7
	visual.build(stats)
	_attack_timer = stats.first_shot_delay


func _physics_process(delta: float) -> void:
	if not NetSession.should_simulate(self):
		_apply_replicated_look(delta)
		return
	if _dying:
		_fly(delta)
		_explode_in = maxf(0.0, _explode_in - delta)
		_publish_look()
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_stagger = _stagger.move_toward(Vector3.ZERO, STAGGER_DECAY * delta)
	_tick_flash(delta)
	_tick_flare(delta)
	if _drink_left > 0.0:
		_sip(delta)
		return
	if is_netted():
		_hold_in_net(delta)
		return
	if _melee != null:
		_melee.tick(delta)
	if _launched:
		move_and_slide()
		var airborne := not is_on_floor()
		_spin_visual(delta, airborne)
		_tick_limp(delta, airborne)
		if is_on_floor() and velocity.y <= 0.5:
			_launched = false
			_stagger = Vector3(velocity.x, 0.0, velocity.z)
			_stand_visual()
		return
	_repath_timer -= delta
	if not stats.stationary and _repath_timer <= 0.0:
		_repath_timer = REPATH_INTERVAL
		_target = _pick_target()
		if _target != null:
			agent.target_position = _target.global_position
	elif stats.stationary and _repath_timer <= 0.0:
		_repath_timer = REPATH_INTERVAL
		_target = _pick_target()

	var horizontal := Vector3.ZERO
	var pace := 0.0
	var swinging := visual.is_meleeing()
	if _target != null:
		if swinging:
			horizontal = Vector3.ZERO
		else:
			horizontal = _steer() * move_speed * walk_scale(_stagger.length())
			pace = clampf(horizontal.length() / maxf(0.1, move_speed), 0.0, 1.0)
		var face_dir := horizontal
		if allied or stats.ranged or swinging:
			face_dir = _target.global_position - global_position
			face_dir.y = 0.0
		_face(face_dir, delta)
	horizontal += _stagger
	if is_on_floor():
		velocity = ground_velocity(horizontal, get_floor_normal())
	else:
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	move_and_slide()
	if not swinging and not _bash_fort() and _target != null:
		_try_attack()
	if visual.is_limp():
		_tick_limp(delta, not is_on_floor())
	else:
		visual.animate(delta, pace)
		visual.tick_melee(delta)
	_resolve_melee_contact()
	_publish_look()


func take_damage(amount: float, direction := Vector3.ZERO, hit_at := Vector3.INF) -> void:
	if _dying:
		return
	var region := _hit_region(hit_at)
	if stats.headshot_only and not is_headshot(hit_at, global_position, stats.height):
		_hit_look(
			region, direction, Ragdoll.strength_for(amount * 0.35, stats.stagger_resistance)
		)
		_sfx("zombie_hit")
		return
	if stats.headshot_only:
		hp = 0.0
	else:
		hp -= amount
	# A killing shot pops into fireworks immediately. Surviving hits still flop.
	if hp <= 0.0:
		_begin_death(0.0)
		return
	var shove := knockback(direction, amount, stats.stagger_resistance)
	_stagger = stack_knockback(_stagger, shove, stats.stagger_resistance)
	_hit_look(region, direction, Ragdoll.strength_for(amount, stats.stagger_resistance))
	if velocity.y > 0.0:
		velocity.y = 0.0
	_sfx("zombie_hit")


## A melee hit is the pop-into-fireworks move: launch them from the contact
## point, then burst overhead. Damage does not have to finish them first.
func melee_hit(origin: Vector3, strength := 1.0) -> void:
	if _dying or allied:
		return
	var hit := Melee.hit_point(origin, global_position, stats.height, stats.radius)
	var launch := Melee.impulse(
		origin, hit, global_position, stats.height, stats.stagger_resistance, strength
	)
	hp = 0.0
	_launch(launch, hit)
	velocity.y = maxf(velocity.y, MELEE_SKY_LIFT)
	_hit_look(_hit_region(hit), launch, 1.8 * maxf(0.4, strength), true, false)
	_sfx("melee_hit")
	_begin_death(MELEE_EXPLODE_DELAY)


func stagger(impulse: Vector3) -> void:
	if _dying or _launched:
		return
	_stagger += impulse / maxf(0.1, stats.stagger_resistance)


func is_flashing() -> bool:
	return _flash_left > 0.0


func is_flared() -> bool:
	return _flare_left > 0.0


func is_dying() -> bool:
	return _dying


func is_launched() -> bool:
	return _launched


func explode_in() -> float:
	return _explode_in


func is_allied() -> bool:
	return allied


func is_drinking() -> bool:
	return _drink_left > 0.0


func can_catch() -> bool:
	return (
		not _dying and not allied and _drink_left <= 0.0
		and not stats.stationary and not is_netted()
	)


func is_netted() -> bool:
	return _trap != null and is_instance_valid(_trap)


func net_trap():
	return _trap if is_netted() else null


func catch_net(trap) -> bool:
	if _dying or allied or trap == null:
		return false
	_trap = trap
	_target = null
	velocity.x = 0.0
	velocity.z = 0.0
	return true


func release_net() -> void:
	_trap = null


func _sfx(cue: String) -> void:
	Sfx.play(cue, self)
	_WorldFx.announce_sfx(self, cue)


func _publish_look() -> void:
	sync_netted = is_netted()
	sync_drink = _drink_left
	sync_dying = _dying
	sync_xform = global_transform
	if visual != null:
		sync_yaw = visual.rotation.y


func _process(delta: float) -> void:
	if not NetSession.should_simulate(self):
		_net_interp.follow(self, sync_xform, delta, NetSync.ZOMBIE_HZ)


func net_interp() -> NetInterp:
	return _net_interp


func _apply_replicated_look(delta: float) -> void:
	if visual == null:
		return
	_tick_flash(delta)
	_tick_flare(delta)
	if visual.is_limp():
		_tick_limp(delta, false)
	visual.rotation.y = lerp_angle(
		visual.rotation.y, sync_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0)
	)
	if allied and not _shown_ally:
		_shown_ally = true
		add_to_group("allies")
		visual.drop_beer()
		visual.wear_ally_cap()
		visual.cheer("delicious!")
		_shown_beer = false
	if sync_drink > 0.0:
		if not _shown_beer:
			_shown_beer = true
			visual.hold_beer(_BeerCan.create(1.5))
		visual.drink(1.0 - sync_drink / DRINK_TIME)
		return
	if _shown_beer:
		visual.drop_beer()
		_shown_beer = false
	if sync_dying:
		return
	visual.animate(delta, 0.0 if sync_netted else 0.35)


func catch_beer() -> bool:
	if not can_catch():
		return false
	_drink_left = DRINK_TIME
	_target = null
	velocity.x = 0.0
	velocity.z = 0.0
	_beer_prop = _BeerCan.create(1.5)
	visual.hold_beer(_beer_prop)
	visual.drink(0.0)
	_sfx("beer_catch")
	return true


## Allies hunt hostile zombies. Hostiles hunt players and anyone already converted.
static func hunts(self_allied: bool, target_is_player: bool, target_allied: bool) -> bool:
	if self_allied:
		return not target_is_player and not target_allied
	return target_is_player or target_allied


## The shove a single hit lands. Kept horizontal so shooting down at a zombie below
## you still knocks it backwards instead of into the ground.
static func knockback(direction: Vector3, amount: float, resistance: float) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized() * (
		(KNOCKBACK_BASE + amount * KNOCKBACK_PER_DAMAGE) / maxf(0.1, resistance)
	)


## Hits stack, but a shotgun lands every pellet on the same frame and must not
## launch a zombie down the fairway. Tough archetypes cap out lower, which is what
## stops sustained fire from pinning a brute the way it can pin a walker.
static func stack_knockback(current: Vector3, added: Vector3, resistance: float) -> Vector3:
	return (current + added).limit_length(MAX_KNOCKBACK / maxf(0.1, resistance))


static func is_headshot(hit_at: Vector3, origin: Vector3, height: float) -> bool:
	if not hit_at.is_finite():
		return false
	return hit_at.y >= origin.y + height * Ragdoll.HEAD_RATIO


## A zombie that has just been hit stops driving forward for a moment. Without this
## its own walking speed simply eats the knockback and hits land weightless.
static func walk_scale(stagger_speed: float) -> float:
	return clampf(1.0 - stagger_speed / MAX_KNOCKBACK, 0.0, 1.0)


## Walk along the turf instead of into it. Horizontal-only motion on a slope is
## what jammed capsules into triangle edges and made them jitter.
static func ground_velocity(wish: Vector3, floor_normal: Vector3) -> Vector3:
	var along := wish.slide(floor_normal)
	if along.length_squared() < 0.0001:
		return Vector3.ZERO
	return along.normalized() * wish.length()


func apply_hit_look(
	region: Ragdoll.Region, direction: Vector3, strength: float, locked := false,
	planted := true
) -> void:
	_flash_left = FLASH_TIME
	_set_flash(true)
	_flop(region, direction, strength, locked, planted)


## The look without the HP change. Computer 2 draws this from its own trace so
## the host does not have to echo the flop back down the same shot.
func show_hit(direction: Vector3, hit_at: Vector3, amount: float) -> void:
	if stats == null:
		return
	apply_hit_look(
		_hit_region(hit_at), direction, Ragdoll.strength_for(amount, stats.stagger_resistance)
	)


func _hit_look(
	region: Ragdoll.Region, direction: Vector3, strength: float, locked := false,
	planted := true
) -> void:
	apply_hit_look(region, direction, strength, locked, planted)
	var skip := last_hit_by.peer_id if last_hit_by != null else 0
	_WorldFx.announce_zombie_hit(self, int(region), direction, strength, locked, planted, skip)


## Neon mark from the Flare Driver so packs and tower snipers stay lit at night.
func mark_flare(duration: float, announce := true, skip_peer := 0) -> void:
	if duration <= 0.0 or _dying:
		return
	_flare_left = maxf(_flare_left, duration)
	_ensure_flare_light()
	_set_flare(true)
	if announce and NetSession.should_simulate(self):
		_WorldFx.announce_flare(self, _flare_left, skip_peer)


func _tick_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left = maxf(0.0, _flash_left - delta)
	if is_zero_approx(_flash_left):
		_set_flash(false)


func _tick_flare(delta: float) -> void:
	if _flare_left <= 0.0:
		return
	_flare_left = maxf(0.0, _flare_left - delta)
	if _flare_light != null:
		_flare_light.light_energy = FLARE_LIGHT_ENERGY * clampf(_flare_left / 2.0, 0.35, 1.0)
	if is_zero_approx(_flare_left):
		_set_flare(false)


func _set_flash(on: bool) -> void:
	if on:
		visual.set_flash(_flash_material)
	elif is_flared():
		visual.set_flash(_flare_material)
	else:
		visual.set_flash(null)


func _set_flare(on: bool) -> void:
	if on:
		if not is_flashing():
			visual.set_flash(_flare_material)
		if _flare_light != null:
			_flare_light.visible = true
			_flare_light.light_energy = FLARE_LIGHT_ENERGY
	else:
		if _flare_light != null:
			_flare_light.visible = false
			_flare_light.light_energy = 0.0
		if is_flashing():
			visual.set_flash(_flash_material)
		else:
			visual.set_flash(null)


func _ensure_flare_light() -> void:
	if _flare_light != null:
		return
	_flare_light = OmniLight3D.new()
	_flare_light.light_color = Palette.LIME
	_flare_light.light_energy = FLARE_LIGHT_ENERGY
	_flare_light.omni_range = FLARE_LIGHT_RANGE
	_flare_light.position = Vector3(0.0, stats.height * 0.7, 0.0)
	add_child(_flare_light)


func _launch(impulse: Vector3, hit: Vector3) -> void:
	_launched = true
	_stagger = Vector3.ZERO
	velocity = impulse
	var centre := global_position + Vector3.UP * stats.height * 0.5
	var offset := hit - centre
	if offset.length_squared() > 0.0001:
		_spin = offset.cross(impulse)
		if _spin.length_squared() > 0.0001:
			_spin = _spin.normalized()
		else:
			_spin = Vector3.RIGHT
	else:
		_spin = Vector3.RIGHT


func _fly(delta: float) -> void:
	if _launched or not is_on_floor():
		velocity += get_gravity() * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0
	move_and_slide()
	var airborne := _launched and not is_on_floor()
	_spin_visual(delta, airborne)
	_tick_limp(delta, airborne)


func _spin_visual(delta: float, airborne: bool) -> void:
	if visual == null:
		return
	if not airborne:
		_spin = _spin.move_toward(Vector3.ZERO, 16.0 * delta)
		visual.rotation.x = move_toward(visual.rotation.x, 0.0, 10.0 * delta)
		visual.rotation.z = move_toward(visual.rotation.z, 0.0, 10.0 * delta)
		visual.position.x = move_toward(visual.position.x, 0.0, 8.0 * delta)
		visual.position.z = move_toward(visual.position.z, 0.0, 8.0 * delta)
		return
	if _spin.length_squared() < 0.0001:
		return
	var pivot := Vector3.UP * stats.height * 0.48
	var axis := _spin.normalized()
	var angle := SPIN_RATE * delta
	var offset := visual.position - pivot
	visual.position = pivot + offset.rotated(axis, angle)
	visual.rotate(axis, angle)


func _stand_visual() -> void:
	if visual == null:
		return
	visual.rotation.x = 0.0
	visual.rotation.z = 0.0
	visual.position = Vector3.ZERO


func _hit_region(hit_at: Vector3) -> Ragdoll.Region:
	return Ragdoll.region(
		hit_at, global_position, stats.height, stats.radius, visual.global_transform.basis.x
	)


func _flop(
	region: Ragdoll.Region, direction: Vector3, strength: float, locked := false, planted := false
) -> void:
	if visual == null:
		return
	visual.flop(region, direction, strength, locked, planted)


func _tick_limp(delta: float, airborne: bool) -> void:
	if visual == null or not visual.is_limp():
		return
	visual.tick_limp(delta, airborne)


func _begin_death(delay: float) -> void:
	if _dying:
		return
	_dying = true
	_explode_in = delay
	if is_netted():
		_trap.drop(self)
		_trap = null
	remove_from_group("zombies")
	collision_layer = 0
	collision_mask = Layers.WORLD | Layers.BARRIER | Layers.PROP | Layers.FORT
	died.emit(self)
	_publish_look()
	if delay <= 0.0:
		_explode()
	else:
		get_tree().create_timer(delay).timeout.connect(_explode)


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	if not is_inside_tree():
		return
	var root := get_tree().get_first_node_in_group("fx_root")
	if root == null:
		root = get_parent()
	var at := global_position + Vector3.UP * stats.height * 0.45
	Fireworks.spawn(root, at, stats.body_color)
	_sfx("zombie_explode")
	_WorldFx.announce_fireworks(self, at, stats.body_color)
	if randf() < stats.ammo_drop_chance:
		var drop_at := global_position + Vector3.UP * 0.4
		var drop_id := _WorldFx.take_ammo_id(self)
		AmmoPickup.spawn(get_parent(), drop_at, stats.ammo_drop_amount, drop_id)
		_WorldFx.announce_ammo(self, drop_id, drop_at, stats.ammo_drop_amount)
	queue_free()


func _steer() -> Vector3:
	if stats.stationary:
		return Vector3.ZERO
	var direct := _target.global_position - global_position
	direct.y = 0.0
	var span := direct.length()
	if allied:
		if span <= Melee.RANGE * 0.75:
			return Vector3.ZERO
		return _path_dir(direct)
	if stats.ranged:
		return _range_steer(direct, span)
	if span <= stats.attack_range:
		return Vector3.ZERO
	return _path_dir(direct)


func _range_steer(direct: Vector3, span: float) -> Vector3:
	if span > stats.attack_range:
		return _path_dir(direct)
	return range_steer(stats, direct, span)


## Close in outside shot range, back up if the target is in their face, hold
## the rest of the time so they actually fire.
static func range_steer(stats: ZombieStats, direct: Vector3, span: float) -> Vector3:
	if span > stats.attack_range:
		return direct.normalized()
	if span < stats.preferred_range * 0.75 and span > 0.2:
		return -direct.normalized()
	return Vector3.ZERO


func _path_dir(direct: Vector3) -> Vector3:
	var next := agent.get_next_path_position()
	var to_next := next - global_position
	to_next.y = 0.0
	# A missing or unbaked navigation mesh returns our own position; walk
	# straight at the target instead of standing still.
	if to_next.length() < 0.2:
		return direct.normalized()
	return to_next.normalized()


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.01:
		return
	var wanted := atan2(-direction.x, -direction.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, wanted, TURN_SPEED * delta)


func _bash_fort() -> bool:
	if allied or _attack_timer > 0.0 or stats.ranged:
		return false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body == null or not body.has_method("take_hit"):
			continue
		_begin_melee()
		return true
	return false


func _try_attack() -> void:
	if allied:
		_ally_shove()
		return
	if _attack_timer > 0.0 or _target == null:
		return
	var offset := _target.global_position - global_position
	offset.y = 0.0
	if offset.length() > stats.attack_range:
		return
	_attack_timer = stats.attack_cooldown
	if stats.ranged:
		_fire_at(_target)
		return
	_begin_melee()


func _begin_melee() -> void:
	_attack_timer = stats.attack_cooldown
	_melee_pending = true
	visual.start_melee()
	_sfx("zombie_attack")


func _resolve_melee_contact() -> void:
	if not _melee_pending:
		return
	if visual.melee_progress() < Melee.CONTACT_T:
		return
	_melee_pending = false
	_land_melee()


func _land_melee() -> void:
	if _try_bash_fort():
		return
	if _target == null:
		return
	var offset := _target.global_position - global_position
	offset.y = 0.0
	if offset.length() > stats.attack_range * 1.35:
		return
	var player := _target as Player
	if player != null:
		var at := Melee.hit_point(
			global_position + Vector3.UP * stats.height * 0.7,
			player.global_position, 1.8, Player.BODY_RADIUS
		)
		player.apply_hit(stats.damage, global_position, at)
		return
	var foe := _target as Zombie
	if foe != null:
		foe.take_damage(stats.damage, offset.normalized())


func _try_bash_fort() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body == null or not body.has_method("take_hit"):
			continue
		body.take_hit(col.get_position())
		return true
	return false


func _ally_shove() -> void:
	if _melee == null or _target == null:
		return
	var offset := _target.global_position - global_position
	offset.y = 0.0
	if offset.length() > Melee.RANGE:
		return
	var origin := global_position + Vector3.UP * stats.height * 0.72
	var forward := offset
	if forward.length_squared() < 0.0001:
		forward = -visual.global_transform.basis.z
	if not _melee.shove(origin, forward):
		return
	visual.start_melee()
	_sfx("melee_swing")


func _fire_at(target: Node3D) -> void:
	var aim := target.global_position + Vector3.UP * 1.1
	var muzzle := global_position + Vector3.UP * stats.height * 0.72
	var fly := aim - muzzle
	if fly.length_squared() < 0.01:
		return
	var root := get_tree().get_first_node_in_group("fx_root")
	if root == null:
		root = get_parent()
	_ZombieShot.spawn(
		root, muzzle, fly, stats.damage, stats.projectile_speed, stats.attack_range + 8.0, allied,
		_shot_color(), _shot_radius(), _shot_streak(), stats.stationary
	)
	_sfx("zombie_shot" if not stats.stationary else "sniper_fire")


func _shot_color() -> Color:
	return Palette.SNIPER if stats.stationary else _ZombieShot.COLOR


func _shot_radius() -> float:
	return 0.045 if stats.stationary else _ZombieShot.RADIUS


func _shot_streak() -> float:
	return 3.4 if stats.stationary else 0.0


func _nearest_player() -> Player:
	var best: Player = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player == null or not player.health.is_alive():
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _pick_target() -> Node3D:
	var best: Node3D
	var best_d := INF
	if hunts(allied, true, false):
		for node in get_tree().get_nodes_in_group("players"):
			var player := node as Player
			if player == null or not player.health.is_alive():
				continue
			var dist := global_position.distance_to(player.global_position)
			if dist < best_d:
				best = player
				best_d = dist
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or zombie == self or zombie.is_dying():
			continue
		if not hunts(allied, false, zombie.is_allied()):
			continue
		var dist := global_position.distance_to(zombie.global_position)
		if dist < best_d:
			best = zombie
			best_d = dist
	return best


func _hold_in_net(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_stagger = Vector3.ZERO
	_tick_flash(delta)
	_tick_flare(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if visual.is_limp():
		_tick_limp(delta, not is_on_floor())
	else:
		visual.animate(delta, 0.0)


func _sip(delta: float) -> void:
	_drink_left = maxf(0.0, _drink_left - delta)
	var progress := 1.0 - _drink_left / DRINK_TIME
	if visual.is_limp():
		_tick_limp(delta, not is_on_floor())
	else:
		visual.drink(progress)
	if is_on_floor():
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	if _drink_left > 0.0:
		return
	allied = true
	add_to_group("allies")
	visual.drop_beer()
	visual.wear_ally_cap()
	visual.cheer("delicious!")
	_beer_prop = null
	_attack_timer = 0.0
	agent.target_desired_distance = Melee.RANGE * 0.55
	_sfx("beer_convert")
