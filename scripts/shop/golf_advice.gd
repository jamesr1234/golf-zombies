class_name GolfAdvice
extends Object
## Lounge chatter. Two thirds is how to play this game; one third is real golf
## advice that does not apply here and is only funny because of that.

const USEFUL: PackedStringArray = [
	"Three clicks. Second click is power, third is contact. Miss the bottom and it slices.",
	"No yardage on the meter. The tee sign has the number. The flag beam is the pin.",
	"A fast tap-tap is a chip. That is how you play short with one club.",
	"The bright green grid is a putt. The HUD says PUTTER. A full stroke still just rolls.",
	"Rough and bunkers steal distance. Get it back to the short grass first.",
	"Double bogey costs cash and you play on. Par or better pays you.",
	"Water is a swim, not a penalty. Dive, grab the ball, throw it to your partner.",
	"Hold interact if you want the CPU partner to take the shot for you.",
	"Buy better clubs in here. They forgive a fat swing and make putting easier.",
	"The cart is a weapon on the path. Run them down, then shop.",
	"Grapple a cart or mech and ride it down the hole. Jump lets go near the ball.",
	"Hex barriers are cover you drop with gear. Charges stack across holes.",
	"Par or better: leftover seconds pay five dollars each. Speed is money.",
]

const COMEDY: PackedStringArray = [
	"Keep your head down. Always works. Ignore the zombies.",
	"Golf is ninety percent mental. The other ten percent is also mental.",
	"The woods are ninety percent air. Just aim at the trees.",
	"Take one more club than you think. Then take another, for luck.",
	"Play it as it lies. Unless it lies badly. Then take a drop in your mind.",
	"Never up, never in. Also never in if a brute is standing on the cup.",
	"Drive for show, putt for dough. I have never putted. I just live here.",
	"Stay below the hole. The hole is that glowing ring. You cannot miss it.",
]

const NAMES: PackedStringArray = [
	"Chip", "Bogey Bill", "Mulligan", "The Caddie", "Sandbag", "Pin High"
]


static func comedy_slots(total: int) -> int:
	return int(round(float(total) / 3.0))


static func is_comedy_index(index: int) -> bool:
	return posmod(index, 3) == 2


static func name_at(index: int) -> String:
	return NAMES[posmod(index, NAMES.size())]


static func pick(comedy: bool, avoid := "") -> String:
	var pool := COMEDY if comedy else USEFUL
	if pool.is_empty():
		return ""
	var line := pool[randi() % pool.size()]
	if pool.size() == 1:
		return line
	var guard := 0
	while line == avoid and guard < 8:
		line = pool[randi() % pool.size()]
		guard += 1
	return line


static func is_useful_line(line: String) -> bool:
	var text := line.to_lower()
	for token in [
		"click", "yardage", "flag", "tap-tap", "chip", "putt", "rough", "bunker",
		"double bogey", "swim", "cpu", "club", "cart", "barrier", "dollar", "seconds",
		"grapple", "hook",
	]:
		if text.contains(token):
			return true
	return false
