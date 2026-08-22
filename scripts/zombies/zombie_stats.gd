class_name ZombieStats
extends Resource
## One zombie archetype. Walker, runner, brute and gunner share the same script
## and scene; ranged types just keep their distance and throw shots.

@export var display_name := "Walker"
@export var max_hp := 90.0
@export var speed := 3.4
@export var damage := 12.0
@export var attack_cooldown := 1.1
@export var attack_range := 2.0
@export var body_color := Palette.LIME
@export var height := 1.8
@export var radius := 0.42
## Higher values shrug off shove and bullet knockback.
@export var stagger_resistance := 1.0
@export var ammo_drop_chance := 0.35
@export var ammo_drop_amount := 24
@export var spawn_weight := 6.0
## Hole number (zero based) this type starts showing up on.
@export var unlock_hole := 0
## Paid into the shared wallet when this zombie dies.
@export var bounty := 10
## Gunners stay back and fire instead of walking into melee.
@export var ranged := false
## Distance a gunner tries to hold. Inside it they back up; outside they close.
@export var preferred_range := 14.0
@export var projectile_speed := 20.0
## Snipers stay in a perch and never join the walking swarm.
@export var stationary := false
## Body shots ping off. Only a hit on the skull pays.
@export var headshot_only := false
## Extra wait before the first shot. 0 fires as soon as they have a target.
@export var first_shot_delay := 0.0
