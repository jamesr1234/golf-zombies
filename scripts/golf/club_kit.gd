class_name ClubKit
extends RefCounted
## One bought set of clubs. Distance, forgiveness and putting all scale with the
## kit; hole generation keeps using Shot.max_carry() so an upgrade makes the
## course easier rather than stretching it.

const STARTER_ID := "starter"
const TOUR_ID := "tour"
const PRO_ID := "pro"
const FORGED_ID := "forged"


var id := STARTER_ID
var display_name := "Starter Set"
var price := 0
## Below 1: mishits slice and hook less.
var deviation_scale := 1.0
## Above 1: a wider contact window on the meter.
var contact_scale := 1.0
## Full-swing speed multiplier. Does not change Shot.max_carry().
var speed_scale := 1.0
## Below 1: putts run out less, so lag putting is easier.
var putt_speed_scale := 1.0
## Below 1: a missed contact keeps more of its power.
var mishit_power_scale := 1.0
var color := Palette.CYAN


static func starter() -> ClubKit:
	return by_id(STARTER_ID)


static func by_id(kit_id: String) -> ClubKit:
	var kit := ClubKit.new()
	match kit_id:
		TOUR_ID:
			kit.id = TOUR_ID
			kit.display_name = "Tour Set"
			kit.price = 120
			kit.deviation_scale = 0.75
			kit.contact_scale = 1.2
			kit.speed_scale = 1.08
			kit.putt_speed_scale = 0.82
			kit.mishit_power_scale = 0.7
			kit.color = Palette.LIME
		PRO_ID:
			kit.id = PRO_ID
			kit.display_name = "Pro Set"
			kit.price = 220
			kit.deviation_scale = 0.55
			kit.contact_scale = 1.45
			kit.speed_scale = 1.16
			kit.putt_speed_scale = 0.68
			kit.mishit_power_scale = 0.5
			kit.color = Palette.AMBER
		FORGED_ID:
			kit.id = FORGED_ID
			kit.display_name = "Forged Set"
			kit.price = 380
			kit.deviation_scale = 0.35
			kit.contact_scale = 1.75
			kit.speed_scale = 1.28
			kit.putt_speed_scale = 0.5
			kit.mishit_power_scale = 0.35
			kit.color = Palette.MAGENTA
		_:
			kit.id = STARTER_ID
			kit.display_name = "Starter Set"
			kit.price = 0
			kit.color = Palette.CYAN
	return kit


static func mech() -> ClubKit:
	var kit := ClubKit.new()
	kit.id = "mech"
	kit.display_name = "Mech"
	kit.deviation_scale = 0.2
	kit.contact_scale = 2.0
	kit.speed_scale = 1.4
	kit.putt_speed_scale = 0.45
	kit.mishit_power_scale = 0.25
	kit.color = Palette.MECH
	return kit


static func shop_ids() -> PackedStringArray:
	return PackedStringArray([TOUR_ID, PRO_ID, FORGED_ID])


func tier() -> int:
	match id:
		TOUR_ID:
			return 1
		PRO_ID:
			return 2
		FORGED_ID:
			return 3
		_:
			return 0


func scaled_carry() -> float:
	return Shot.max_carry() * Shot.DISTANCE_SCALE * speed_scale


## A copy with extra swing speed, used for a drunk drive without mutating the kit.
func boosted(mult: float) -> ClubKit:
	if is_equal_approx(mult, 1.0):
		return self
	var copy := ClubKit.mech() if id == "mech" else ClubKit.by_id(id)
	copy.speed_scale *= mult
	return copy
