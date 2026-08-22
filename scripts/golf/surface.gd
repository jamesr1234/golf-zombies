class_name Surface
extends Object
## Lie types the ball can sit on, with the physics and shot penalties for each.

enum Type { ROUGH, FAIRWAY, TEE, FRINGE, BUNKER, GREEN, WATER }

## Higher priority wins when the ball overlaps more than one patch.
const PRIORITY := {
	Type.ROUGH: 0,
	Type.FAIRWAY: 1,
	Type.TEE: 2,
	Type.FRINGE: 3,
	Type.BUNKER: 4,
	Type.GREEN: 5,
	Type.WATER: 6,
}

## Rolling resistance applied to the ball while it sits on the surface. Roll-out
## distance is roughly landing speed divided by this, so these numbers are what
## keep a big drive from trickling on forever.
const LINEAR_DAMP := {
	Type.ROUGH: 2.2,
	Type.FAIRWAY: 1.0,
	Type.TEE: 1.0,
	Type.FRINGE: 0.75,
	Type.BUNKER: 5.0,
	Type.GREEN: 0.55,
	Type.WATER: 6.0,
}

const ANGULAR_DAMP := {
	Type.ROUGH: 3.0,
	Type.FAIRWAY: 1.2,
	Type.TEE: 1.2,
	Type.FRINGE: 1.0,
	Type.BUNKER: 6.0,
	Type.GREEN: 0.8,
	Type.WATER: 8.0,
}

## How much of a full swing actually makes it into the ball from this lie.
const POWER_MULT := {
	Type.ROUGH: 0.78,
	Type.FAIRWAY: 1.0,
	Type.TEE: 1.0,
	Type.FRINGE: 1.0,
	Type.BUNKER: 0.6,
	Type.GREEN: 1.0,
	Type.WATER: 0.5,
}

## Neon grid look per lie: dark base, glowing line colour, grid cell size in
## metres, line emission strength, and vertical scroll for the water.
## Cell sizes shrink as the lie gets better, so the grid alone tells you what you
## are standing on.
const LOOK := {
	Type.ROUGH: {
		"base": Color(0.03, 0.07, 0.04), "line": Color(0.12, 0.5, 0.28),
		"cell": 8.0, "energy": 0.7, "scroll": 0.0, "fill": 0.18,
	},
	Type.FAIRWAY: {
		"base": Color(0.04, 0.14, 0.05), "line": Color(0.22, 0.7, 0.24),
		"cell": 5.0, "energy": 1.35, "scroll": 0.0, "fill": 0.38,
	},
	Type.TEE: {
		"base": Color(0.04, 0.18, 0.1), "line": Palette.CYAN,
		"cell": 2.0, "energy": 2.0, "scroll": 0.0, "fill": 0.45,
	},
	Type.FRINGE: {
		"base": Color(0.05, 0.20, 0.07), "line": Color(0.38, 0.95, 0.32),
		"cell": 1.5, "energy": 2.15, "scroll": 0.0, "fill": 0.48,
	},
	Type.BUNKER: {
		"base": Color(0.13, 0.08, 0.02), "line": Palette.AMBER,
		"cell": 1.6, "energy": 1.8, "scroll": 0.0,
	},
	## Hot lime disk. Fill stays visible after the grid fades, so the dance floor
	## still reads from the tee instead of vanishing into the fairway.
	Type.GREEN: {
		"base": Color(0.16, 0.72, 0.08), "line": Color(0.62, 1.0, 0.12),
		"cell": 0.65, "energy": 4.0, "scroll": 0.0, "fill": 2.4,
		"fade_start": 48.0, "fade_end": 360.0,
	},
	Type.WATER: {
		"base": Color(0.02, 0.03, 0.14), "line": Color(0.2, 0.5, 1.0),
		"cell": 2.4, "energy": 2.4, "scroll": 0.35, "opacity": 0.52,
	},
}

## Warm-up green sits under your feet at the start. Same putting-grid family as
## the hole green, turned down so it does not blow out the tee.
const PRACTICE_LOOK := {
	"base": Color(0.06, 0.26, 0.09), "line": Color(0.42, 0.95, 0.38),
	"cell": 1.2, "energy": 2.2, "scroll": 0.0, "fill": 0.65,
}

## Small vertical offsets keep coplanar patches from z-fighting.
const DRAW_HEIGHT := {
	Type.ROUGH: 0.01,
	Type.FAIRWAY: 0.1,
	Type.TEE: 0.12,
	Type.FRINGE: 0.13,
	Type.BUNKER: 0.08,
	Type.GREEN: 0.14,
	Type.WATER: 0.04,
}


static func name_of(type: Type) -> String:
	return ["rough", "fairway", "tee", "fringe", "bunker", "green", "water"][type]


static func look_of(type: Type, practice := false) -> Dictionary:
	if practice and type == Type.GREEN:
		return PRACTICE_LOOK
	return LOOK[type]


static func look_for(patch: Dictionary) -> Dictionary:
	return look_of(patch["type"], bool(patch.get("practice", false)))


## The bright, tight lime grid. Fairway is green grass too, but coarser and
## dimmer; this is the putting-surface look. The collar around the cup stays in
## the same lime family so you still know you can putt from it.
static func looks_like_green(type: Type) -> bool:
	var look: Dictionary = LOOK[type]
	var line: Color = look["line"]
	var cell: float = look["cell"]
	var energy: float = look.get("energy", 0.0)
	var lime := line.g >= 0.9 and line.g > line.r + 0.15 and line.g >= line.b
	return lime and cell <= 2.05 and energy >= 2.0


## Picks the surface the ball is actually lying on out of everything it overlaps.
static func dominant(types: Array) -> Type:
	var best: Type = Type.ROUGH
	for type in types:
		if PRIORITY[type] > PRIORITY[best]:
			best = type
	return best
