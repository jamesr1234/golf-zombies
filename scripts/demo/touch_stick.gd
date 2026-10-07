class_name TouchStick
extends RefCounted
## Floating thumbstick: it appears where the thumb lands and reports how far the
## thumb has been dragged from there. Pure math, so it can be tested.

const RADIUS := 90.0
const DEADZONE := 0.12
## Pushed this far toward the rim, the body sprints.
const SPRINT_AT := 0.7

## Browsers hand out any integer as a finger id, negative ones included.
var finger := 0
var held := false
var origin := Vector2.ZERO
var tip := Vector2.ZERO
## How far the thumb can travel. The on-screen base uses the same value.
var radius := RADIUS


func is_held() -> bool:
	return held


func grab(index: int, at: Vector2) -> void:
	finger = index
	held = true
	origin = at
	tip = at


func drag(at: Vector2) -> void:
	tip = origin + (at - origin).limit_length(radius)


func release() -> void:
	held = false
	tip = origin


## Screen-space direction, length 0..1. Up on screen is negative y.
func vector() -> Vector2:
	if not is_held():
		return Vector2.ZERO
	var raw := (tip - origin) / radius
	if raw.length() < DEADZONE:
		return Vector2.ZERO
	return raw.limit_length(1.0)


func sprinting() -> bool:
	return vector().length() >= SPRINT_AT
