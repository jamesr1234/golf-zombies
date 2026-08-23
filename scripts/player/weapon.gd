class_name Weapon
extends Node3D
## Hitscan shooting for both players. Which gun is in hand is just an index into
## the stats array, so reload, spread and ammo logic exist once.

signal ammo_changed()
signal fired()

const TRACER_COLOR := Palette.TRACER
const BLOOD_COLOR := Palette.HIT_ZOMBIE
const DUST_COLOR := Palette.HIT_WORLD
const _WorldFx := preload("res://scripts/net/world_fx.gd")

## Net and rocket lead the bag so hole one can test the trap combo.
var loadout: Array[WeaponStats] = [
	preload("res://resources/weapons/net.tres"),
	preload("res://resources/weapons/rocket.tres"),
	preload("res://resources/weapons/rifle.tres"),
	preload("res://resources/weapons/shotgun.tres"),
	preload("res://resources/weapons/sniper.tres"),
]

var index := 0
var mags: Array[int] = []
var reserves: Array[int] = []
## -1 is hip fire. 0..n-1 indexes stats.zoom_levels.
var zoom_step := -1

var _cooldown := 0.0
var _reload_left := 0.0
var _firing := false
## Multiplies pellet and rocket damage. 1 is sober.
var power_mult := 1.0
var _pair_shots := 0
var _pair_idle := 0.0
var _flash: OmniLight3D
var _flash_time := 0.0


func _ready() -> void:
	for stats in loadout:
		mags.append(stats.mag_size)
		reserves.append(stats.reserve_start)
	_flash = OmniLight3D.new()
	_flash.light_energy = 0.0
	_flash.omni_range = 6.0
	_flash.light_color = TRACER_COLOR
	add_child(_flash)


func stats() -> WeaponStats:
	return loadout[index]


func mag() -> int:
	return mags[index]


func reserve() -> int:
	return reserves[index]


func is_reloading() -> bool:
	return _reload_left > 0.0


## Trigger down with something in the mag, which is what the held raygun watches so
## it can hold itself still through a burst rather than only on the shot frames.
func is_firing() -> bool:
	return _firing


func reload_fraction() -> float:
	if not is_reloading():
		return 0.0
	return 1.0 - _reload_left / stats().reload_time


func swap(step := 1) -> void:
	if loadout.size() < 2 or step == 0:
		return
	index = posmod(index + step, loadout.size())
	_reload_left = 0.0
	_pair_shots = 0
	_pair_idle = 0.0
	zoom_step = -1
	_cooldown = maxf(_cooldown, 0.3)
	ammo_changed.emit()
	Sfx.play("weapon_swap", self)


func zoom_mult() -> float:
	return stats().zoom_at(zoom_step)


func is_scoped() -> bool:
	return zoom_mult() > 1.0


func cycle_zoom() -> float:
	zoom_step = zoom_after(zoom_step, stats())
	return zoom_mult()


## Hip, then each listed power, then hip again.
static func zoom_after(step: int, current: WeaponStats) -> int:
	if current == null or not current.has_scope():
		return -1
	var next := step + 1
	return next if next < current.zoom_levels.size() else -1


func start_reload() -> void:
	if is_reloading() or mags[index] >= stats().mag_size or reserves[index] <= 0:
		return
	_reload_left = stats().reload_time
	Sfx.play("reload", self)


func add_ammo(amount: int) -> void:
	for i in reserves.size():
		var share := amount if i == index else int(amount * 0.5)
		reserves[i] = mini(loadout[i].reserve_max, reserves[i] + share)
	ammo_changed.emit()


func has_gun(stats: WeaponStats) -> bool:
	return loadout.has(stats)


func apply_replicated_index(gun_index: int) -> void:
	if loadout.is_empty():
		return
	index = clampi(gun_index, 0, loadout.size() - 1)


func apply_replicated_pose(firing: bool, reload: float, scoped: bool) -> void:
	_firing = firing
	if scoped and stats().has_scope():
		if zoom_step < 0:
			zoom_step = 0
	else:
		zoom_step = -1
	if reload <= 0.0:
		_reload_left = 0.0
	else:
		_reload_left = (1.0 - clampf(reload, 0.0, 1.0)) * maxf(0.001, stats().reload_time)


func apply_replicated_loadout(gun_index: int, paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	loadout.clear()
	mags.clear()
	reserves.clear()
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var next: WeaponStats = load(path)
		loadout.append(next)
		mags.append(next.mag_size)
		reserves.append(next.reserve_start)
	if loadout.is_empty():
		return
	index = clampi(gun_index, 0, loadout.size() - 1)
	_reload_left = 0.0
	_pair_shots = 0
	_pair_idle = 0.0
	zoom_step = -1
	ammo_changed.emit()


func add_gun(stats: WeaponStats) -> bool:
	if stats == null or has_gun(stats):
		return false
	loadout.append(stats)
	mags.append(stats.mag_size)
	reserves.append(stats.reserve_start)
	index = loadout.size() - 1
	_reload_left = 0.0
	_pair_shots = 0
	_pair_idle = 0.0
	zoom_step = -1
	ammo_changed.emit()
	return true


func tick(delta: float, view: Transform3D, trigger_held: bool, trigger_pulled: bool, ads: bool) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_pair_idle += delta
	if pair_expired(stats(), _pair_shots, _pair_idle):
		_pair_shots = 0
	_flash_time = maxf(0.0, _flash_time - delta)
	_flash.light_energy = 6.0 if _flash_time > 0.0 else 0.0
	if is_reloading():
		_firing = false
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		return
	_firing = trigger_held and mags[index] > 0
	var wants_shot := trigger_held if stats().automatic else trigger_pulled
	if not wants_shot or _cooldown > 0.0:
		return
	if mags[index] <= 0:
		if trigger_pulled and reserves[index] <= 0:
			Sfx.play("empty_click", self)
		start_reload()
		return
	_fire(view, ads)


func host_fire(view: Transform3D, ads: bool, gun_index: int) -> bool:
	if gun_index < 0 or gun_index >= loadout.size():
		return false
	if mags[gun_index] <= 0 or _cooldown > 0.0 or is_reloading():
		return false
	index = gun_index
	_commit_fire(view, ads)
	return true


func _finish_reload() -> void:
	_reload_left = 0.0
	_pair_shots = 0
	_pair_idle = 0.0
	var needed: int = stats().mag_size - mags[index]
	var loaded: int = mini(needed, reserves[index])
	mags[index] += loaded
	reserves[index] -= loaded
	ammo_changed.emit()
	Sfx.play("reload_done", self)


func _fire(view: Transform3D, ads: bool) -> void:
	if NetSession.defers_world():
		_spend_round(view)
		var owner := get_parent() as Player
		if owner != null:
			owner.request_host_fire(view, ads, index)
		if stats().is_net() or stats().is_explosive():
			return
		var spread := deg_to_rad(stats().ads_spread_deg if ads else stats().spread_deg)
		for _pellet in stats().pellets:
			_trace(view, spread, stats())
		return
	_commit_fire(view, ads)


func _spend_round(view: Transform3D) -> WeaponStats:
	var current := stats()
	mags[index] -= 1
	_cooldown = cooldown_after_shot(current, _pair_shots)
	_pair_shots = pair_shots_after(current, _pair_shots)
	_pair_idle = 0.0
	_flash_time = 0.04
	if _flash != null:
		_flash.global_position = view.origin - view.basis.z * 0.6
	ammo_changed.emit()
	fired.emit()
	var cue := Sfx.fire_cue(current.visual)
	Sfx.play(cue, self)
	_WorldFx.announce_sfx(self, cue, _shooter_peer())
	return current


func _commit_fire(view: Transform3D, ads: bool) -> void:
	var current := _spend_round(view)
	if current.is_net():
		_launch_net(view, current)
		return
	if current.is_explosive():
		_launch_rocket(view, scaled_stats(current, power_mult))
		return
	var spread := deg_to_rad(current.ads_spread_deg if ads else current.spread_deg)
	for _pellet in current.pellets:
		_trace(view, spread, current)


func _launch_rocket(view: Transform3D, current: WeaponStats) -> void:
	var direction := -view.basis.z
	var origin := view.origin + direction * 0.9
	var rocket := Rocket.spawn(_fx_root(), origin, direction, current)
	if rocket != null:
		_WorldFx.announce_rocket(
			self, origin, direction, rocket.damage, rocket.blast_radius, rocket.max_range
		)


func _launch_net(view: Transform3D, current: WeaponStats) -> void:
	var direction := -view.basis.z
	var origin := view.origin + direction * 0.9
	var shot := NetShot.spawn(_fx_root(), origin, direction, current)
	if shot != null:
		_WorldFx.announce_net(
			self, origin, direction, shot.radius, shot.duration, shot.max_range
		)


func _fx_root() -> Node:
	var root := get_tree().get_first_node_in_group("fx_root")
	return root if root != null else get_tree().current_scene


static func scaled_stats(current: WeaponStats, mult: float) -> WeaponStats:
	if current == null or is_equal_approx(mult, 1.0):
		return current
	var copy := current.duplicate() as WeaponStats
	copy.damage *= mult
	return copy


## First shot of a pair can follow quickly; the last shot pays the full interval.
static func cooldown_after_shot(current: WeaponStats, pair_shots: int) -> float:
	if pair_shots + 1 < current.burst:
		return current.burst_gap
	return current.shot_interval()


static func pair_shots_after(current: WeaponStats, pair_shots: int) -> int:
	var next := pair_shots + 1
	return 0 if next >= current.burst else next


## Wait the long interval after a lone first shot and the pair is fresh again,
## so you can always dump two quick ones.
static func pair_expired(current: WeaponStats, pair_shots: int, idle: float) -> bool:
	return pair_shots > 0 and idle >= current.shot_interval()


func _trace(view: Transform3D, spread: float, current: WeaponStats) -> void:
	var direction := -view.basis.z
	if spread > 0.0:
		direction = direction.rotated(view.basis.y, randf_range(-spread, spread))
		direction = direction.rotated(view.basis.x, randf_range(-spread, spread))
	var muzzle := view.origin + direction * 0.7
	var target := view.origin + direction * current.range_m
	var query := PhysicsRayQueryParameters3D.create(view.origin, target, Layers.BULLET_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var root := get_tree().get_first_node_in_group("fx_root")
	var end: Vector3 = target if hit.is_empty() else hit["position"]
	var collider: Object = null if hit.is_empty() else hit["collider"]
	var is_zombie := hurts_target(collider)
	var kind := "tracer"
	var color := TRACER_COLOR
	if current.has_scope():
		kind = "sniper_hit" if collider != null else "sniper"
		color = BLOOD_COLOR if is_zombie else DUST_COLOR
		HitFx.sniper_beam(root, muzzle, end, HitFx.sniper_tint(true))
		if collider != null:
			HitFx.spark(root, end, color)
		else:
			color = HitFx.sniper_tint(true)
	elif hit.is_empty():
		HitFx.spawn(root, muzzle, target, TRACER_COLOR)
	else:
		color = BLOOD_COLOR if is_zombie else DUST_COLOR
		HitFx.spawn(root, muzzle, end, color)
	_WorldFx.announce_hitscan(self, muzzle, end, kind, color, _shooter_peer())
	if NetSession.is_active() and not multiplayer.is_server():
		return
	if is_zombie:
		if collider.has_method("is_allied") and collider.is_allied():
			return
		var zombie := collider as Zombie
		var owner := get_parent() as Player
		if zombie != null and owner != null:
			zombie.last_hit_by = owner
		collider.take_damage(current.damage * power_mult, direction, end)


static func hurts_target(collider: Object) -> bool:
	return collider is Zombie


func _shooter_peer() -> int:
	var owner := get_parent() as Player
	return 0 if owner == null else owner.peer_id
