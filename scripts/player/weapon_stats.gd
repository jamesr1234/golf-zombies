class_name WeaponStats
extends Resource
## Tuning for one weapon. The weapon script is shared, so adding a gun is a
## matter of adding a resource, not code.

@export var display_name := "Rifle"
## Which first-person mesh the raygun should show. "rifle", "shotgun", "rocket",
## "net", "sniper", "flare", "nailer".
@export var visual := "rifle"
@export var damage := 24.0
@export var pellets := 1
@export var rounds_per_minute := 620.0
@export var automatic := true
@export var mag_size := 30
@export var reserve_start := 120
@export var reserve_max := 270
@export var spread_deg := 1.4
@export var ads_spread_deg := 0.4
@export var range_m := 140.0
@export var reload_time := 2.0
@export var pickup_amount := 30
## 1 is a regular gun. 2 is a double barrel: two quick shots, then a pause.
@export var burst := 1
## Gap between the two shots of a pair. The pause after the pair is shot_interval.
@export var burst_gap := 0.14
## 0 keeps the gun still. 1 is a full shotgun kick.
@export var kick := 0.0
## 0 is hitscan. Above 0 fires a projectile that explodes for this radius.
@export var blast_radius := 0.0
## 0 is a regular gun. Above 0 throws a net that roots everyone in this radius.
@export var trap_radius := 0.0
## How long a thrown net holds the pack. Ignored when trap_radius is 0.
@export var trap_duration := 8.0
## Empty keeps hip-fire ADS. Sniper zoom clicks through these multipliers.
@export var zoom_levels: PackedFloat32Array = PackedFloat32Array()
## Seconds a hit zombie stays flare-lit. 0 is a normal gun.
@export var flare_mark := 0.0
## Extra damage when the shot or shooter is near a golf cart. 1 is no bonus.
@export var cart_damage_mult := 1.0
## Metres from a golf cart that unlocks cart_damage_mult. 0 disables the bonus.
@export var cart_bonus_range := 0.0


func shot_interval() -> float:
	return 60.0 / maxf(1.0, rounds_per_minute)


func is_explosive() -> bool:
	return blast_radius > 0.0


func is_net() -> bool:
	return trap_radius > 0.0


func has_scope() -> bool:
	return zoom_levels.size() > 0


func is_flare() -> bool:
	return flare_mark > 0.0


func has_cart_bonus() -> bool:
	return cart_bonus_range > 0.0 and cart_damage_mult > 1.0


func zoom_at(step: int) -> float:
	if step < 0 or step >= zoom_levels.size():
		return 1.0
	return zoom_levels[step]
