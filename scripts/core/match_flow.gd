class_name MatchFlow
extends Node
## Runs the round: generates and loads each hole, tracks the shared scorecard,
## and decides when the run is over.

signal message_changed(title: String, body: String, shown: bool)
signal scorecard_changed()
signal run_ended(won: bool)

const _Music := preload("res://scripts/fx/music.gd")
const _ClubhouseFlow := preload("res://scripts/core/match_clubhouse.gd")

enum Phase { PREP, PLAYING, RETRIEVE, TRANSIT, SHOP }

const HOLE_BANNER_TIME := 3.5
const PLAYER_TEE_SPREAD := 2.6
const CART_TEE_BACK := 2.0
const CART_TEE_SIDE := 10.5
const CLUBHOUSE_SIDE := ClubhouseBuild.TEE_SIDE
const RETRIEVE_RANGE := 3.2
const CART_RECALL_RANGE := 24.0
## How close to the tee you have to be to call the hole on.
const TEE_READY_RANGE := 4.0

@export var course_seed := 20260816
## 1-based. Raise this to skip ahead when playtesting later holes.
@export var starting_hole := 1
## Spawn in the hall on that hole so shops and wall art can be checked in-game.
@export var start_in_clubhouse := false
## Spawn on the clubhouse circuit so the drive can be checked without holing out.
@export var start_on_cart_path := false

var score: GameState
var hole: HoleData
var finished := false
var started := false
var hole_time_left := 120.0
var freeze_left := 0.0
var shop: Shop
var clubhouse: Clubhouse
var phase: Phase = Phase.PLAYING
var cart_path: CartPath
var cart_girl: CartGirl

@onready var ball: GolfBall = $"../GolfBall"
@onready var cart: GolfCart = $"../GolfCart"
@onready var golf: GolfController = $"../GolfController"
@onready var hole_root: Node3D = $"../HoleRoot"
@onready var zombies: Node3D = $"../Zombies"
@onready var spawner: SpawnDirector = $"../SpawnDirector"

var _players: Array[Player] = []
var _hole_node: Node3D
var _banner := 0
var clubhouse_flow = _ClubhouseFlow.new()


func _ready() -> void:
	score = GameState.new(HoleGenerator.pars())
	var world := get_parent()
	for node in get_tree().get_nodes_in_group("players"):
		if world.is_ancestor_of(node):
			_players.append(node as Player)
	for player in _players:
		player.golf = golf
		player.cart = cart
		player.flow = self
		player.health.downed.connect(_check_team_wipe)
		player.health.died.connect(_check_team_wipe)
	if _players.size() == 2:
		_players[0].partner = _players[1]
		_players[1].partner = _players[0]
	spawner.container = zombies
	spawner.golf = golf
	spawner.zombie_killed.connect(_on_zombie_killed)
	ball.came_to_rest.connect(_on_ball_rest)
	ball.entered_hazard.connect(_on_hazard)
	ball.holed.connect(_on_holed)
	golf.stroke_taken.connect(_on_stroke_taken)


func _process(delta: float) -> void:
	if started and not finished:
		_update_clubhouse_music()
	if not started or finished or is_between_holes():
		return
	if freeze_left > 0.0:
		freeze_left = maxf(0.0, freeze_left - delta)
		return
	hole_time_left = maxf(0.0, hole_time_left - delta)
	if hole_time_left <= 0.0:
		_end_run(false, "Time ran out on hole %d." % [score.hole_index + 1])


func _physics_process(delta: float) -> void:
	if phase != Phase.TRANSIT or cart_path == null or cart == null:
		return
	cart_path.tick_crash(cart, delta)


## Called once the HUDs are listening, so the first hole banner is not announced
## to an empty room.
func begin() -> void:
	if started:
		return
	started = true
	var index := clampi(starting_hole, 1, score.pars.size()) - 1
	score.hole_index = index
	if start_on_cart_path:
		_begin_on_cart_path(index)
	elif start_in_clubhouse:
		_begin_in_clubhouse(index)
	else:
		start_hole(index)


func scorecard_text() -> String:
	if phase == Phase.PREP:
		return "Hole %d   Par %d   Warm up   step on the tee to start" % [
			score.hole_index + 1, score.par()
		]
	if phase == Phase.SHOP:
		return "Clubhouse   next hole %d   %s" % [
			score.hole_index + 1, GameState.format_money(score.money)
		]
	if phase == Phase.RETRIEVE:
		return "Pick up your ball   then drive to hole %d" % [score.hole_index + 1]
	if phase == Phase.TRANSIT:
		return "Drive to hole %d   run them down" % [score.hole_index + 1]
	return "Hole %d   Par %d   Strokes %d/%d   Total %s" % [
		score.hole_index + 1, score.par(), score.strokes, score.max_strokes(),
		GameState.format_relative(score.relative_to_par()),
	]


func is_between_holes() -> bool:
	return phase != Phase.PLAYING


func shows_timer() -> bool:
	return not finished and (phase == Phase.PREP or phase == Phase.PLAYING)


func in_clubhouse() -> bool:
	return phase == Phase.SHOP


## Warm-up putting, either on the practice green or in the clubhouse. Nothing hit
## in these phases scores, penalises, or finishes a hole.
func is_practice() -> bool:
	return phase == Phase.PREP or phase == Phase.SHOP


func has_shop() -> bool:
	return shop != null


func can_open_doors(who: Node3D) -> bool:
	if clubhouse == null or not is_instance_valid(clubhouse):
		return false
	if phase != Phase.TRANSIT and phase != Phase.SHOP:
		return false
	return clubhouse.can_open_doors(who)


func can_open_exit(who: Node3D) -> bool:
	if phase != Phase.SHOP or clubhouse == null or not is_instance_valid(clubhouse):
		return false
	return clubhouse.can_open_exit(who)


func station_for(who: Node3D) -> ShopStation:
	if phase != Phase.SHOP or clubhouse == null or not is_instance_valid(clubhouse):
		return null
	return clubhouse.station_for(who)


func npc_for(who: Node3D) -> ClubhouseNpc:
	if phase != Phase.SHOP or clubhouse == null or not is_instance_valid(clubhouse):
		return null
	return clubhouse.npc_for(who)


func beer_cart_for(who: Node3D) -> CartGirl:
	if cart_girl == null or not is_instance_valid(cart_girl):
		return null
	if cart_girl.can_use(who):
		return cart_girl
	return null


func can_retrieve_ball(who: Node3D) -> bool:
	if phase != Phase.RETRIEVE or who == null or ball == null or ball.is_stowed():
		return false
	var offset := who.global_position - ball.global_position
	offset.y = 0.0
	return offset.length() <= RETRIEVE_RANGE


func retrieve_ball(_who: Node3D) -> void:
	if phase != Phase.RETRIEVE or ball == null or ball.is_stowed():
		return
	ball.stow()
	Sfx.play("grab_ball", self)
	_begin_transit()


func shop_count(dept: int = Shop.Dept.WEAPONS) -> int:
	return 0 if shop == null else shop.count(dept)


func shop_item(index: int, dept: int = Shop.Dept.WEAPONS) -> Dictionary:
	return {} if shop == null else shop.item_at(index, dept)


func buy_shop_item(item_id: String, buyer: Player = null) -> bool:
	if shop == null:
		return false
	var ok := shop.buy(item_id, score, weapons(), buyer, cart)
	if ok:
		golf.club_kit = score.club_kit()
		if item_id == "mech":
			MechSuit.spawn_near(buyer)
		scorecard_changed.emit()
	return ok


func shop_listing(choice: int, dept: int = Shop.Dept.WEAPONS, buyer: Player = null) -> String:
	return "" if shop == null else shop.listing(
		choice, score.money, weapons(), dept, score, buyer, cart
	)


func shop_details(choice: int, dept: int = Shop.Dept.WEAPONS, buyer: Player = null) -> String:
	return "" if shop == null else shop.details(
		choice, score.money, weapons(), dept, score, buyer, cart
	)


func shop_title(dept: int = Shop.Dept.WEAPONS) -> String:
	return "Clubhouse" if shop == null else shop.dept_title(dept)


func hole_node() -> Node3D:
	return _hole_node


func shop_owned(item_id: String, buyer: Player = null) -> bool:
	return false if shop == null else shop.is_owned(item_id, weapons(), score, buyer, cart)


func shop_can_buy(item_id: String, buyer: Player = null) -> bool:
	return false if shop == null else shop.can_buy(item_id, score, weapons(), buyer, cart)


func weapons() -> Array[Weapon]:
	var guns: Array[Weapon] = []
	for player in _players:
		guns.append(player.weapon)
	return guns


func _begin_in_clubhouse(index: int) -> void:
	phase = Phase.SHOP
	shop = Shop.new()
	_rebuild_hole(index)
	clubhouse = Clubhouse.create(Vector3.ZERO, 0.0)
	hole_root.add_child(clubhouse)
	_place_clubhouse_at_exit()
	_place_cart()
	_aim_at_practice()
	var snaps: Array[Dictionary] = []
	for i in _players.size():
		var side := -1.0 if i == 0 else 1.0
		snaps.append({
			"local": Vector3(side * 1.4, 1.2, ClubhouseBuild.DEPTH * 0.5 - 2.8),
			"yaw": PI,
		})
	_restore_in_clubhouse(snaps)
	spawner.clear_zombies()
	hole_time_left = GameSettings.hole_seconds() + score.take_bonus_seconds()
	freeze_left = score.take_freeze_seconds()
	scorecard_changed.emit()
	_flash_message(
		"Clubhouse",
		"Playtest spawn. Shop, then walk out the back to hole %d." % [index + 1]
	)
	_Music.enter_clubhouse()


func _begin_on_cart_path(index: int) -> void:
	_rebuild_hole(index)
	golf.release()
	if index < score.pars.size() - 1:
		score.hole_out()
	ball.stow()
	_begin_transit()
	_place_cart_on_path()
	_board_cart()
	_Music.play_level()


func start_hole(index: int) -> void:
	# Every hole is generated around the origin, so the old one has to leave the
	# physics space before the new one arrives or the ball reads a stale lie.
	phase = Phase.PREP
	cart_path = null
	_close_shop()
	_rebuild_hole(index)
	_aim_at_practice()
	# Cart first: it drops any riders where it stood, and the players are then put
	# back on the new tee regardless.
	_place_cart()
	_place_cart_girl()
	_place_players()
	spawner.clear_zombies()
	hole_time_left = GameSettings.hole_seconds() + score.take_bonus_seconds()
	freeze_left = score.take_freeze_seconds()
	scorecard_changed.emit()
	_flash_message("Hole %d   Par %d" % [index + 1, hole.par], _warmup_copy(index))
	Sfx.play("hole_start", self)
	_Music.play_lounge()


func _warmup_copy(index: int) -> String:
	if index == 1:
		return "The hill blocks the drive.\nTake the cart through the culvert."
	if index == 2:
		return "Climb the wall onto the fairway.\nThen jump the cart to the green."
	return "Warm up on the practice green or the climb wall.\nStep onto the tee and interact when you are ready."


func _rebuild_hole(index: int) -> void:
	MechSuit.release_all(get_tree())
	cart_girl = null
	if _hole_node != null:
		hole_root.remove_child(_hole_node)
		_hole_node.queue_free()
		_hole_node = null
	hole = HoleGenerator.generate(index, course_seed)
	_hole_node = HoleBuilder.build(hole)
	hole_root.add_child(_hole_node)
	HoleBuilder.bake_navigation(_hole_node)
	ball.bounds = hole.bounds
	golf.club_kit = score.club_kit()


func can_start_play(who: Node3D) -> bool:
	if phase != Phase.PREP or finished or who == null or hole == null:
		return false
	var offset := who.global_position - hole.tee
	offset.y = 0.0
	return offset.length() <= TEE_READY_RANGE


## Called from the tee: the ball leaves the practice green, the clock starts, and
## the swarm begins arriving. Nothing before this point counts.
func start_play() -> void:
	if phase != Phase.PREP or finished:
		return
	phase = Phase.PLAYING
	golf.release()
	ball.place_at(hole.tee)
	golf.setup(ball, hole.cup, hole.green_span())
	spawner.begin_hole(score.hole_index, hole.spawn_points)
	spawner.place_snipers(hole.sniper_perches())
	scorecard_changed.emit()
	Sfx.play("start_play", self)
	_Music.play_level()
	_flash_message(
		"Hole %d   Par %d" % [score.hole_index + 1, hole.par],
		"%s   %d strokes allowed. Double bogey costs money. Par or better pays." % [
			GameSettings.difficulty_label().to_upper(), score.max_strokes()
		]
	)


func _place_players() -> void:
	_refresh_team()
	var forward := _along_hole()
	var lateral := forward.cross(Vector3.UP).normalized()
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	for i in _players.size():
		var side := -1.0 if i == 0 else 1.0
		var spot := hole.practice_tee + forward * 1.8 + lateral * side * PLAYER_TEE_SPREAD
		_players[i].spawn_at(hole.lift(spot) + Vector3.UP * 1.2, yaw)


## The cart waits behind the tee, off to one side so it is never in the way of the
## first shot. Anyone still riding is put out first, since the old hole is gone.
func _place_cart() -> void:
	if hole != null and hole.has_cart_pad():
		cart.place_at(hole.lift(hole.cart_pad) + Vector3.UP * 0.4, hole.cart_yaw)
		return
	var forward := _along_hole()
	var lateral := forward.cross(Vector3.UP).normalized()
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	var spot := hole.tee - forward * CART_TEE_BACK + lateral * CART_TEE_SIDE
	cart.place_at(hole.lift(spot) + Vector3.UP * 0.4, yaw)


func _place_cart_girl() -> void:
	cart_girl = null
	if hole == null or _hole_node == null:
		return
	cart_girl = CartGirl.spawn_at_hole(hole)
	_hole_node.add_child(cart_girl)


func _summon_cart_girl() -> void:
	if cart_girl == null or not is_instance_valid(cart_girl):
		return
	cart_girl.begin_approach()


## Horizontal, so a downhill hole does not spawn players in the air or underground.
func _along_hole() -> Vector3:
	var forward := hole.cup - hole.tee
	forward.y = 0.0
	return forward.normalized()


func _on_stroke_taken() -> void:
	if is_practice():
		return
	score.add_stroke()
	scorecard_changed.emit()
	if score.strokes == 1:
		_summon_cart_girl()


func _on_ball_rest(_position: Vector3) -> void:
	if finished or is_practice():
		return
	if score.at_stroke_limit():
		_complete_hole(false)


func _on_hazard(kind: String) -> void:
	if finished:
		return
	# A warm-up shot that finds trouble just comes back to the practice mat.
	if is_practice():
		_reset_practice_ball()
		return
	# Water is retrieved by swimming, not replayed from the last lie.
	if kind == "water":
		return
	score.add_stroke()
	scorecard_changed.emit()
	ball.place_at(ball.last_safe_position)
	if score.at_stroke_limit():
		_complete_hole(false)
		return
	_flash_message("Penalty", "One stroke for the %s. Playing from the last spot." % kind)


func _on_holed() -> void:
	if finished:
		return
	if is_practice():
		_reset_practice_ball()
		return
	_complete_hole(true)


func _complete_hole(from_cup: bool) -> void:
	if finished or phase != Phase.PLAYING:
		return
	score.cap_at_limit()
	var strokes := score.strokes
	var par := score.par()
	var relative := strokes - par
	var score_pay := GameState.score_payout(relative)
	var bonus := GameState.time_bonus(hole_time_left) if relative <= 0 else 0
	golf.release()
	if not from_cup:
		ball.close_for_pickup()
	spawner.stop()
	spawner.clear_zombies()
	score.apply_payout(score_pay)
	score.credit(bonus)
	if relative <= 0:
		_cheer_hole_out()
	var pickup := (
		"Pick your ball out of the hole." if from_cup else "Pick up your ball."
	)
	_flash_message(
		("Holed out in %d" % strokes) if from_cup else "Double bogey",
		"%s on the par %d.\n%s\n%s" % [
			_result_name(relative), par, _payout_text(score_pay, bonus), pickup
		]
	)
	score.hole_out()
	scorecard_changed.emit()
	if score.is_course_complete():
		_end_run(true, "Nine holes survived at %s." % GameState.format_relative(score.relative_to_par()))
		return
	Sfx.play("hole_complete", self)
	phase = Phase.RETRIEVE
	_park_cart_for_transit()


func _payout_text(score_pay: int, bonus: int) -> String:
	var bits: PackedStringArray = []
	if score_pay > 0:
		bits.append("Score bonus %s" % GameState.format_money(score_pay))
	elif score_pay < 0:
		bits.append("Penalty %s" % GameState.format_money(score_pay))
	if bonus > 0:
		bits.append("Speed bonus %s" % GameState.format_money(bonus))
	if bits.is_empty():
		return "No bonus"
	return "\n".join(bits)


func _cheer_hole_out() -> void:
	if not GameSettings.is_solo():
		return
	for player in _players:
		if not player.is_cpu() and player.health.is_alive():
			player.celebrate()


func leave_clubhouse() -> void:
	clubhouse_flow.leave(self)


## First interact at the doors: they open, the swarm is gone, and the next hole
## is already waiting out the back.
func arrive_at_clubhouse() -> void:
	clubhouse_flow.arrive(self)


func _aim_at_practice() -> void:
	if ball == null or hole == null:
		return
	golf.release()
	ball.place_at(hole.practice_tee)
	golf.setup(ball, hole.practice_cup, PracticeGreen.span())


func _reset_practice_ball() -> void:
	golf.release()
	if hole != null:
		ball.place_at(hole.practice_tee)


func _begin_transit() -> void:
	clubhouse_flow.begin_transit(self)


func _park_cart_for_transit() -> void:
	clubhouse_flow.park_cart_for_transit(self)


func _place_cart_on_path() -> void:
	clubhouse_flow.place_cart_on_path(self)


func _board_cart() -> void:
	clubhouse_flow.board_cart(self)


func _open_clubhouse() -> void:
	clubhouse_flow.open_clubhouse(self)


func _attach_next_hole() -> void:
	clubhouse_flow.attach_next_hole(self)


func _place_clubhouse_at_exit() -> void:
	clubhouse_flow.place_at_exit(self)


func _capture_in_clubhouse() -> Array[Dictionary]:
	return clubhouse_flow.capture_in_clubhouse(self)


func _restore_in_clubhouse(snaps: Array[Dictionary]) -> void:
	clubhouse_flow.restore_in_clubhouse(self, snaps)


func _refresh_team() -> void:
	for player in _players:
		if player != null and is_instance_valid(player):
			player.health.restore()


## Straight-line follow cannot thread clubhouse doorways, so a CPU still inside
## when you walk out to hole two would stay there. Drop them at your shoulder.
func _rally_cpus() -> void:
	var host: Player
	for player in _players:
		if player != null and not player.is_cpu():
			host = player
			break
	if host == null:
		return
	var n := 0
	for player in _players:
		if player == null or not player.is_cpu():
			continue
		var side := -1.0 if n == 0 else 1.0
		n += 1
		var right := host.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() < 0.01:
			right = Vector3.RIGHT
		else:
			right = right.normalized()
		player.spawn_at(
			host.global_position + right * side * 1.4,
			rad_to_deg(host.rotation.y)
		)


func _cover_fade() -> void:
	get_tree().call_group("hud", "cover_black")


func _reveal_fade() -> void:
	get_tree().call_group("hud", "reveal")


func _close_shop() -> void:
	shop = null
	if clubhouse != null and is_instance_valid(clubhouse):
		clubhouse.queue_free()
	clubhouse = null
	for player in _players:
		player.close_shop()
		player.stop_talk()


func _on_zombie_killed(bounty: int, _killer: Player = null) -> void:
	if finished or phase == Phase.SHOP:
		return
	score.credit(bounty)
	scorecard_changed.emit()


func _clubhouse_fade_far() -> float:
	if clubhouse == null or not is_instance_valid(clubhouse) or hole == null:
		return _Music.CLUBHOUSE_FAR
	return maxf(_flat_to_clubhouse(hole.tee), _Music.CLUBHOUSE_NEAR + 1.0)


func _flat_to_clubhouse(at: Vector3) -> float:
	var offset := at - clubhouse.global_position
	offset.y = 0.0
	return offset.length()


func _update_clubhouse_music() -> void:
	if not _Music.following_clubhouse:
		return
	if clubhouse == null or not is_instance_valid(clubhouse):
		return
	var dist := INF
	for player in _players:
		if player == null or not is_instance_valid(player):
			continue
		dist = minf(dist, _flat_to_clubhouse(player.global_position))
	if dist < INF:
		_Music.set_listener_distance(dist)


func _check_team_wipe() -> void:
	if finished:
		return
	for player in _players:
		if player.health.is_alive():
			return
	_end_run(false, "Both players are down. Nobody left to revive.")


func _end_run(won: bool, reason: String) -> void:
	finished = true
	spawner.stop()
	spawner.clear_zombies()
	golf.release()
	message_changed.emit(
		"COURSE COMPLETE" if won else "GAME OVER",
		"%s\nTotal %d strokes (%s).\nBank %s.\nPress your interact button for a new round." % [
			reason, score.total_strokes(), GameState.format_relative(score.relative_to_par()),
			GameState.format_money(score.money)
		],
		true
	)
	run_ended.emit(won)
	Sfx.play("run_win" if won else "run_lose", self)
	_Music.play_lounge()


## Only the newest banner is allowed to clear the screen, or readying up quickly
## would have the warm-up banner wipe the one that replaced it.
func _flash_message(title: String, body: String) -> void:
	_banner += 1
	var shown := _banner
	message_changed.emit(title, body, true)
	await get_tree().create_timer(HOLE_BANNER_TIME).timeout
	if not finished and shown == _banner:
		message_changed.emit("", "", false)


func _result_name(relative: int) -> String:
	match relative:
		-3:
			return "Albatross"
		-2:
			return "Eagle"
		-1:
			return "Birdie"
		0:
			return "Par"
		1:
			return "Bogey"
		2:
			return "Double bogey"
		_:
			return "%+d" % relative
