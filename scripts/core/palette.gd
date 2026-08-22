class_name Palette
extends Object
## The neon palette. Every colour in the game comes from here so the theme can be
## re-tuned in one place. Surface lies keep their own looks in Surface.LOOK,
## since those are grid materials rather than flat colours.

const CYAN := Color(0.15, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.14, 0.72)
const LIME := Color(0.5, 1.0, 0.2)
const AMBER := Color(1.0, 0.7, 0.1)
const BABY_BLUE := Color(0.58, 0.84, 1.0)
const VIOLET := Color(0.62, 0.28, 1.0)
const HOT_PINK := Color(1.0, 0.24, 0.5)
const ICE := Color(0.8, 0.97, 1.0)
const NET: Color = Color(0.42, 1.0, 0.62)
const NIGHT := Color(0.03, 0.03, 0.06)

const PLAYER_ONE := CYAN
const PLAYER_TWO := AMBER
## Seat colours for online VS. Local co-op still uses the first two.
const SEATS: Array[Color] = [
	CYAN, AMBER, MAGENTA, LIME, VIOLET, HOT_PINK, BABY_BLUE, ICE,
]


static func seat_color(seat: int) -> Color:
	if SEATS.is_empty():
		return CYAN
	return SEATS[posmod(seat, SEATS.size())]

const BALL := ICE
const FLAG := HOT_PINK
const FLAGPOLE := ICE
const AIM_ARROW := MAGENTA
const CUP_RING := MAGENTA
const CUP_MOUTH := Color(0.02, 0.01, 0.03)

const CART := Color(0.2, 1.0, 0.85)
const CART_FRAME := Color(0.09, 0.26, 0.28)
const HEADLIGHT := Color(1.0, 0.85, 0.4)
const TIRE_MARK: Color = Color(0.04, 0.02, 0.05)
const BEER := Color(1.0, 0.78, 0.18)
const BEER_CAN := Color(0.58, 0.6, 0.64)
const BEER_INK := Color(0.18, 0.5, 1.0)
const BEER_CART := Color(0.22, 1.0, 0.42)
const BEER_CART_FRAME := Color(0.05, 0.18, 0.08)
const COOLER := Color(0.72, 0.8, 0.86)
const ALLY_CAP := Color(0.2, 0.78, 1.0)
const BEER_LID := Color(0.82, 0.86, 0.9)

const TRACER := AMBER
const HIT_ZOMBIE := MAGENTA
const HIT_WORLD := CYAN
const PICKUP := LIME

const TOWER := Color(0.14, 0.18, 0.26)
const TOWER_TRIM := ICE
const SNIPER := Color(0.72, 0.92, 1.0)
const LED_RED := Color(1.0, 0.08, 0.05)
const LED_WHITE := Color(0.96, 0.98, 1.0)

const TREE_TRUNK := Color(0.14, 0.08, 0.05)
const TREE_CANOPY := Color(0.28, 0.82, 0.32)
const TREE_CANOPIES: Array[Color] = [
	Color(0.22, 0.78, 0.28),
	Color(0.10, 0.52, 0.22),
	Color(0.48, 0.95, 0.18),
	Color(0.16, 0.70, 0.58),
	Color(0.62, 0.88, 0.20),
	VIOLET,
	HOT_PINK,
	AMBER,
]
const ROCK := Color(0.1, 0.13, 0.18)
const ROCK_TRIM := CYAN
const WALL := Color(0.12, 0.06, 0.14)
const WALL_TRIM := MAGENTA

## Emission strengths. Anything above the environment glow threshold blooms.
const GLOW_FAINT := 0.45
const GLOW_SOFT := 0.9
const GLOW_MEDIUM := 1.8
const GLOW_STRONG := 3.0
