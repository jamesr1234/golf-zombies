class_name Sfx
extends Object
## Temporary placeholder sounds. Drop a real WAV at res://assets/sfx/<cue>.wav
## to replace the synthesized take for that cue.

const DIR := "res://assets/sfx/"
const RATE := 22050
const POOL_NAME := "SfxPool"
const LOG_CAP := 48

## wave, start hz, end hz, seconds, gain.
## 0 sine, 1 square, 2 noise, 3 pew (noise crack then sine sweep), 4 boom.
const CUES := {
	"rifle_fire": [3, 1900.0, 280.0, 0.08, 0.32],
	"shotgun_fire": [2, 180.0, 70.0, 0.14, 0.42],
	"sniper_fire": [4, 220.0, 42.0, 0.52, 0.78],
	"scope": [0, 880.0, 1320.0, 0.06, 0.16],
	"rocket_fire": [0, 140.0, 520.0, 0.22, 0.3],
	"rocket_explode": [2, 90.0, 40.0, 0.38, 0.48],
	"net_fire": [0, 480.0, 140.0, 0.18, 0.28],
	"net_catch": [1, 360.0, 160.0, 0.16, 0.26],
	"net_burst": [2, 150.0, 45.0, 0.3, 0.42],
	"melee_swing": [0, 420.0, 160.0, 0.16, 0.24],
	"melee_hit": [1, 110.0, 45.0, 0.12, 0.4],
	"zombie_hit": [0, 240.0, 90.0, 0.08, 0.28],
	"zombie_attack": [1, 150.0, 70.0, 0.14, 0.3],
	"zombie_shot": [3, 880.0, 220.0, 0.1, 0.26],
	"zombie_explode": [2, 280.0, 80.0, 0.42, 0.4],
	"empty_click": [1, 1700.0, 1700.0, 0.04, 0.18],
	"reload": [0, 380.0, 720.0, 0.14, 0.2],
	"reload_done": [1, 260.0, 220.0, 0.08, 0.26],
	"weapon_swap": [0, 540.0, 360.0, 0.07, 0.18],
	"jump": [0, 260.0, 440.0, 0.1, 0.22],
	"damage": [1, 170.0, 70.0, 0.1, 0.32],
	"downed": [0, 280.0, 70.0, 0.4, 0.28],
	"revived": [0, 240.0, 720.0, 0.32, 0.26],
	"died": [0, 200.0, 50.0, 0.55, 0.28],
	"shield_up": [0, 380.0, 920.0, 0.16, 0.2],
	"shield_down": [0, 920.0, 380.0, 0.12, 0.18],
	"shield_hit": [1, 640.0, 280.0, 0.08, 0.28],
	"pickup_ammo": [0, 880.0, 1320.0, 0.12, 0.2],
	"drink_beer": [2, 70.0, 40.0, 0.22, 0.2],
	"throw_beer": [0, 520.0, 180.0, 0.12, 0.22],
	"beer_catch": [0, 620.0, 380.0, 0.1, 0.24],
	"beer_convert": [0, 300.0, 880.0, 0.38, 0.26],
	"dive": [2, 160.0, 80.0, 0.18, 0.28],
	"splash": [2, 120.0, 60.0, 0.16, 0.26],
	"grab_ball": [0, 700.0, 520.0, 0.08, 0.2],
	"throw_ball": [0, 460.0, 200.0, 0.12, 0.22],
	"swing_click": [0, 1400.0, 1400.0, 0.04, 0.16],
	"club_hit": [1, 240.0, 80.0, 0.13, 0.4],
	"putt": [0, 340.0, 180.0, 0.1, 0.26],
	"ball_bounce": [0, 520.0, 240.0, 0.07, 0.2],
	"hole_out": [0, 523.0, 784.0, 0.38, 0.28],
	"hazard": [1, 180.0, 90.0, 0.28, 0.26],
	"golf_claim": [0, 440.0, 440.0, 0.1, 0.16],
	"board": [0, 210.0, 150.0, 0.12, 0.22],
	"eject": [0, 250.0, 170.0, 0.1, 0.2],
	"crush": [2, 80.0, 40.0, 0.18, 0.38],
	"boost_pad": [0, 160.0, 880.0, 0.2, 0.26],
	"cooler_open": [0, 320.0, 170.0, 0.16, 0.2],
	"buy_beer": [0, 660.0, 880.0, 0.14, 0.22],
	"place_barrier": [0, 220.0, 640.0, 0.2, 0.26],
	"grapple_fire": [3, 720.0, 180.0, 0.16, 0.3],
	"grapple_latch": [1, 420.0, 180.0, 0.14, 0.34],
	"grapple_release": [0, 280.0, 140.0, 0.1, 0.22],
	"barrier_hit": [1, 520.0, 320.0, 0.08, 0.28],
	"barrier_break": [2, 240.0, 90.0, 0.2, 0.34],
	"ui_move": [0, 880.0, 880.0, 0.04, 0.14],
	"ui_confirm": [0, 660.0, 880.0, 0.1, 0.2],
	"ui_back": [0, 440.0, 330.0, 0.08, 0.16],
	"ui_deny": [1, 140.0, 110.0, 0.12, 0.2],
	"purchase": [0, 523.0, 784.0, 0.18, 0.24],
	"pause": [0, 392.0, 330.0, 0.12, 0.2],
	"map_open": [0, 300.0, 520.0, 0.12, 0.16],
	"talk": [0, 500.0, 420.0, 0.08, 0.16],
	"shop_open": [0, 400.0, 620.0, 0.12, 0.18],
	"hole_start": [0, 392.0, 523.0, 0.28, 0.22],
	"start_play": [0, 262.0, 523.0, 0.32, 0.26],
	"hole_complete": [0, 523.0, 1046.0, 0.45, 0.28],
	"run_win": [0, 392.0, 784.0, 0.65, 0.3],
	"run_lose": [0, 330.0, 110.0, 0.65, 0.28],
}

static var last_cue := ""
static var play_log: PackedStringArray = []
static var _streams: Dictionary = {}


static func cues() -> PackedStringArray:
	return PackedStringArray(CUES.keys())


static func has_cue(cue: String) -> bool:
	return CUES.has(cue) or ResourceLoader.exists("%s%s.wav" % [DIR, cue])


static func fire_cue(visual: String) -> String:
	match visual:
		"shotgun":
			return "shotgun_fire"
		"rocket":
			return "rocket_fire"
		"net":
			return "net_fire"
		"sniper":
			return "sniper_fire"
		_:
			return "rifle_fire"


static func clear_log() -> void:
	last_cue = ""
	play_log = PackedStringArray()


static func play_gain(cue: String) -> float:
	return -1.0 if cue == "sniper_fire" else -6.0


static func play(cue: String, _host: Node = null) -> void:
	last_cue = cue
	play_log.append(cue)
	if play_log.size() > LOG_CAP:
		play_log = play_log.slice(play_log.size() - LOG_CAP)
	var stream := stream_for(cue)
	if stream == null:
		return
	var pool := _pool()
	if pool == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = play_gain(cue)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.finished.connect(player.queue_free)
	pool.add_child(player)
	player.play()


static func stream_for(cue: String) -> AudioStream:
	if cue.is_empty():
		return null
	if _streams.has(cue):
		return _streams[cue]
	var path := "%s%s.wav" % [DIR, cue]
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is AudioStream:
			_streams[cue] = loaded
			return loaded
	if not CUES.has(cue):
		return null
	var built := _synthesize(cue)
	_streams[cue] = built
	return built


static func _pool() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var pool := tree.root.get_node_or_null(POOL_NAME)
	if pool != null:
		return pool
	pool = Node.new()
	pool.name = POOL_NAME
	pool.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(pool)
	return pool


static func _synthesize(cue: String) -> AudioStreamWAV:
	var recipe: Array = CUES[cue]
	var wave: int = recipe[0]
	var hz0: float = recipe[1]
	var hz1: float = recipe[2]
	var seconds: float = recipe[3]
	var gain: float = recipe[4]
	var n := maxi(8, int(RATE * seconds))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = cue.hash()
	var boom := wave == 4
	for i in n:
		var u := float(i) / float(n)
		var env := (1.0 - u) * (1.0 - u)
		if boom:
			env = pow(1.0 - u, 1.12)
		if u < 0.02:
			env *= u / 0.02
		var hz := lerpf(hz0, hz1, u)
		var t := float(i) / RATE
		var osc := _osc(wave, hz, t, u, rng)
		var sample := int(clampf(osc * env * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


static func _osc(wave: int, hz: float, t: float, u: float, rng: RandomNumberGenerator) -> float:
	var sine := sin(TAU * hz * t)
	match wave:
		1:
			return 1.0 if sine >= 0.0 else -1.0
		2:
			return rng.randf_range(-1.0, 1.0) * 0.85 + sine * 0.2
		3:
			var crack := rng.randf_range(-1.0, 1.0) if u < 0.18 else 0.0
			return sine * 0.75 + crack * 0.55
		4:
			var sub := sin(TAU * 62.0 * t) + 0.55 * sin(TAU * 31.0 * t)
			var crack := rng.randf_range(-1.0, 1.0) if u < 0.2 else 0.0
			var punch := (1.0 - u / 0.05) if u < 0.05 else 0.0
			return sub * 0.82 + sine * 0.28 + crack * 0.38 + punch * 0.35
		_:
			return sine + 0.35 * sin(TAU * hz * 2.0 * t)
