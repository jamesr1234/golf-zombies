class_name VsMatchFlow
extends Node
## Online VS round: per-player scorecards, one shared clock, host-authored phases.

signal message_changed(title: String, body: String, shown: bool)
signal scorecard_changed()
signal run_ended(won: bool)

enum Phase { PREP, PLAYING, RETRIEVE, TRANSIT, SHOP }

const HOLE_BANNER_TIME := 3.5
const TEE_READY_RANGE := 4.0
const _Music := preload("res://scripts/fx/music.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")

var phase: Phase = Phase.PREP
var hole: HoleData
var finished := false
var started := false
var hole_time_left := 120.0
var freeze_left := 0.0
var score: PlayerScore
var shop: Shop
var ball: GolfBall
var course_seed := 20260816

var _players: Array[Player] = []
var _balls: Array[GolfBall] = []
var _carts: Array[GolfCart] = []
var _scores: Dictionary = {}
var _banner := 0
var _clock_broadcast := 0.0

@onready var course: VsCourse = $"../VsCourse"
@onready var spawner_ai: SpawnDirector = $"../SpawnDirector"
@onready var zombies: Node3D = $"../Zombies"
@onready var vs_spawner: VsSpawner = $"../VsSpawner"


func _ready() -> void:
	course_seed = NetSession.course_seed
	spawner_ai.container = zombies
	spawner_ai.net_factory = vs_spawner
	spawner_ai.zombie_killed.connect(_on_zombie_killed)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
		multiplayer.peer_disconnected.connect(_on_peer_left)
	var pawns := $"../Players"
	if not pawns.child_entered_tree.is_connected(_on_pawn_entered):
		pawns.child_entered_tree.connect(_on_pawn_entered)
	if multiplayer.is_server():
		await get_tree().process_frame
		course.rebuild(0, course_seed)
		vs_spawner.spawn_match(self)
		begin()
		return
	await _wait_for_pawns()
	bind_spawned()
	begin()


func bind_spawned() -> void:
	_players.clear()
	_balls.clear()
	_carts.clear()
	for node in $"../Players".get_children():
		if node is Player:
			_players.append(node)
	for node in $"../Balls".get_children():
		if node is GolfBall:
			_balls.append(node)
	for node in $"../Carts".get_children():
		if node is GolfCart:
			_carts.append(node)
			node.set_multiplayer_authority(1)
			NetSync.attach_cart(node)
	_carts.sort_custom(func(a, b): return String(a.name) < String(b.name))
	_wire_players()


func begin() -> void:
	if started:
		return
	started = true
	start_hole(0)


func start_hole(index: int) -> void:
	phase = Phase.PREP
	course.close_shop(_players)
	hole = course.rebuild(index, course_seed)
	if multiplayer.is_server():
		vs_spawner.plant_hole_mech(hole)
	for card in _scores.values():
		(card as PlayerScore).advance_to(index)
	_sync_local_score()
	## Scene-baked carts exist on every peer. Park them here so a joiner sees
	## the same two-row lot instead of eight carts stacked at the origin.
	course.place_carts(_carts)
	if multiplayer.is_server():
		course.place_balls(_balls)
	## Each pawn is owned by its peer, so the host's spawn_at is overwritten by
	## the joiner's default origin unless that joiner plants itself too.
	course.place_players(_players)
	course.place_cart_girl()
	course.aim_practice(_sessions())
	_reset_clock()
	spawner_ai.clear_zombies()
	scorecard_changed.emit()
	_broadcast_scores()
	_flash_message(
		"Hole %d   Par %d" % [index + 1, hole.par],
		"Warm up. Step onto the tee and interact when you are ready."
	)
	Sfx.play("hole_start", self)
	_Music.play_lounge()


func start_play() -> void:
	if not multiplayer.is_server():
		_request_start.rpc_id(1)
		return
	_do_start_play()


func can_start_play(who: Node3D) -> bool:
	if phase != Phase.PREP or finished or who == null or hole == null:
		return false
	var offset := who.global_position - hole.tee
	offset.y = 0.0
	return offset.length() <= TEE_READY_RANGE


func is_between_holes() -> bool:
	return phase != Phase.PLAYING


func is_practice() -> bool:
	return phase == Phase.PREP or phase == Phase.SHOP


func shows_timer() -> bool:
	return not finished and (phase == Phase.PREP or phase == Phase.PLAYING)


func in_clubhouse() -> bool:
	return phase == Phase.SHOP


func has_shop() -> bool:
	return course.shop != null


func hole_node() -> Node3D:
	return course.hole_node


func score_for(player: Player) -> PlayerScore:
	if player == null:
		return score
	return _scores.get(player.peer_id, score) as PlayerScore


func mark_peer_gone(peer_id: int) -> void:
	var card := _scores.get(peer_id) as PlayerScore
	if card != null and not card.done_this_hole:
		card.settle_pickup()


func settle_disconnected(peer_id: int) -> void:
	mark_peer_gone(peer_id)
	var player := _player_for(peer_id)
	if player != null:
		_players.erase(player)
		player.queue_free()
	var owned := _ball_for(peer_id)
	if owned != null:
		_balls.erase(owned)
		owned.queue_free()
	var players_root := get_node_or_null("../Players")
	var balls_root := get_node_or_null("../Balls")
	if players_root != null:
		var pawn := players_root.get_node_or_null("P%d" % peer_id)
		if pawn != null and pawn != player:
			pawn.queue_free()
	if balls_root != null:
		var ball_node := balls_root.get_node_or_null("Ball%d" % peer_id)
		if ball_node != null and ball_node != owned:
			ball_node.queue_free()
	_sync_local_score()
	scorecard_changed.emit()
	if multiplayer.is_server():
		_broadcast_scores()
		if _all_done():
			_complete_hole()


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	settle_disconnected(peer_id)


func cart_for(who: Node3D) -> GolfCart:
	var riding := _riding_cart(who)
	if riding != null:
		return riding
	var best: GolfCart
	var best_d := 999.0
	for cart in _carts:
		if not cart.can_board(who as Player):
			continue
		var d := who.global_position.distance_to(cart.global_position)
		if d < best_d:
			best_d = d
			best = cart
	return best


func can_retrieve_ball(_who: Node3D) -> bool:
	return false


func retrieve_ball(_who: Node3D) -> void:
	pass


func can_open_doors(who: Node3D) -> bool:
	if course.clubhouse == null or not is_instance_valid(course.clubhouse):
		return false
	if phase != Phase.TRANSIT and phase != Phase.SHOP:
		return false
	return course.clubhouse.can_open_doors(who)


func can_open_exit(who: Node3D) -> bool:
	if phase != Phase.SHOP or course.clubhouse == null:
		return false
	return course.clubhouse.can_open_exit(who)


func station_for(who: Node3D) -> ShopStation:
	if phase != Phase.SHOP or course.clubhouse == null:
		return null
	return course.clubhouse.station_for(who)


func npc_for(who: Node3D) -> ClubhouseNpc:
	if phase != Phase.SHOP or course.clubhouse == null:
		return null
	return course.clubhouse.npc_for(who)


func beer_cart_for(who: Node3D) -> CartGirl:
	if course.cart_girl == null or not is_instance_valid(course.cart_girl):
		return null
	if course.cart_girl.can_use(who):
		return course.cart_girl
	return null


func leave_clubhouse() -> void:
	if not multiplayer.is_server():
		_request_leave.rpc_id(1)
		return
	_do_leave()


func arrive_at_clubhouse() -> void:
	if not multiplayer.is_server():
		_request_arrive.rpc_id(1)
		return
	_do_arrive()


func shop_count(dept: int = Shop.Dept.WEAPONS) -> int:
	return 0 if course.shop == null else course.shop.count(dept)


func shop_item(index: int, dept: int = Shop.Dept.WEAPONS) -> Dictionary:
	return {} if course.shop == null else course.shop.item_at(index, dept)


func shop_title(dept: int = Shop.Dept.WEAPONS) -> String:
	return "Clubhouse" if course.shop == null else course.shop.dept_title(dept)


func shop_listing(choice: int, dept: int = Shop.Dept.WEAPONS, buyer: Player = null) -> String:
	var card := score_for(buyer)
	return "" if course.shop == null else course.shop.listing(
		choice, card.money, _guns(buyer), dept, card, buyer, cart_for(buyer)
	)


func shop_details(choice: int, dept: int = Shop.Dept.WEAPONS, buyer: Player = null) -> String:
	var card := score_for(buyer)
	return "" if course.shop == null else course.shop.details(
		choice, card.money, _guns(buyer), dept, card, buyer, cart_for(buyer)
	)


func shop_owned(item_id: String, buyer: Player = null) -> bool:
	return false if course.shop == null else course.shop.is_owned(
		item_id, _guns(buyer), score_for(buyer), buyer, cart_for(buyer)
	)


func shop_can_buy(item_id: String, buyer: Player = null) -> bool:
	return false if course.shop == null else course.shop.can_buy(
		item_id, score_for(buyer), _guns(buyer), buyer, cart_for(buyer)
	)


func buy_shop_item(item_id: String, buyer: Player = null) -> bool:
	if course.shop == null or buyer == null:
		return false
	if NetSession.is_active() and not multiplayer.is_server():
		_request_buy.rpc_id(1, item_id)
		return true
	var card := score_for(buyer)
	var ok := course.shop.buy(item_id, card, _guns(buyer), buyer, cart_for(buyer))
	if ok:
		if buyer.golf != null:
			buyer.golf.club_kit = card.club_kit()
		scorecard_changed.emit()
		_broadcast_scores()
		_broadcast_loadout(buyer)
		_broadcast_look(buyer)
		if item_id == "mech":
			MechSuit.spawn_near(buyer)
		_WorldFx.announce_sfx(self, "purchase")
	return ok


func scorecard_text() -> String:
	if score == null:
		return ""
	if phase == Phase.PREP:
		return "Hole %d   Par %d   Warm up" % [score.hole_index + 1, score.par()]
	if phase == Phase.SHOP:
		return "Clubhouse   next hole %d   %s" % [
			score.hole_index + 1, GameState.format_money(score.money)
		]
	if phase == Phase.TRANSIT:
		return "Drive to hole %d" % [score.hole_index + 1]
	return "Hole %d   Par %d   Strokes %d/%d   %s" % [
		score.hole_index + 1, score.par(), score.strokes, score.max_strokes(),
		GameState.format_relative(score.relative_to_par()),
	]


func scoreboard_text() -> String:
	var bits: PackedStringArray = []
	for player in _players:
		var card := score_for(player)
		if card == null:
			continue
		var mark := "*" if player.peer_id == multiplayer.get_unique_id() else ""
		bits.append("%s%s %s" % [
			mark, _seat_name(card.seat), GameState.format_relative(card.relative_to_par())
		])
	return "   ".join(bits)


func _process(delta: float) -> void:
	if not started or finished or is_between_holes():
		return
	if not owns_clock():
		return
	if freeze_left > 0.0:
		freeze_left = maxf(0.0, freeze_left - delta)
		return
	hole_time_left = maxf(0.0, hole_time_left - delta)
	_clock_broadcast += delta
	if _clock_broadcast >= 1.0:
		_clock_broadcast = 0.0
		_broadcast_scores()
	if hole_time_left <= 0.0:
		_timeout_hole()


func owns_clock() -> bool:
	return not NetSession.defers_world()


func _physics_process(delta: float) -> void:
	if phase != Phase.TRANSIT or course.cart_path == null:
		return
	for cart in _carts:
		course.cart_path.tick_crash(cart, delta)


func _wire_players() -> void:
	var pars := HoleGenerator.pars()
	for player in _players:
		player.flow = self
		player.score = _scores.get(player.peer_id) as PlayerScore
		if player.score == null:
			var card := PlayerScore.new(pars)
			card.peer_id = player.peer_id
			card.seat = NetSession.seat_for(player.peer_id)
			_scores[player.peer_id] = card
			player.score = card
		player.golf = _session_for(player.peer_id)
		player.cart = cart_for(player)
		if player.golf != null:
			player.golf.club_kit = player.score.club_kit()
			if not player.golf.stroke_taken.is_connected(_on_stroke_taken.bind(player)):
				player.golf.stroke_taken.connect(_on_stroke_taken.bind(player))
		var owned := _ball_for(player.peer_id)
		if owned != null:
			if not owned.holed.is_connected(_on_holed.bind(player)):
				owned.holed.connect(_on_holed.bind(player))
			if not owned.came_to_rest.is_connected(_on_ball_rest.bind(player)):
				owned.came_to_rest.connect(_on_ball_rest.bind(player))
			if not owned.entered_hazard.is_connected(_on_hazard.bind(player)):
				owned.entered_hazard.connect(_on_hazard.bind(player))
	_sync_local_score()


func _sync_local_score() -> void:
	var local_id := multiplayer.get_unique_id()
	score = _scores.get(local_id) as PlayerScore
	ball = _ball_for(local_id)
	hole = course.hole
	shop = course.shop


func _sessions() -> Array:
	var sessions: Array = []
	for ball_node in _balls:
		var golf := ball_node.get_node_or_null("Golf") as GolfController
		if golf != null:
			sessions.append(golf)
	return sessions


func _session_for(peer_id: int) -> GolfController:
	var owned := _ball_for(peer_id)
	if owned == null:
		return null
	return owned.get_node_or_null("Golf") as GolfController


func _ball_for(peer_id: int) -> GolfBall:
	for owned in _balls:
		if owned.owner_peer == peer_id:
			return owned
	return null


func _guns(buyer: Player) -> Array[Weapon]:
	var guns: Array[Weapon] = []
	if buyer != null:
		guns.append(buyer.weapon)
	return guns


func _riding_cart(who: Node3D) -> GolfCart:
	var player := who as Player
	if player == null:
		return null
	for cart in _carts:
		if cart.is_riding(player):
			return cart
	return null


func _reset_clock() -> void:
	hole_time_left = GameSettings.hole_seconds()
	freeze_left = 0.0
	_clock_broadcast = 0.0
	for card in _scores.values():
		hole_time_left += (card as PlayerScore).take_bonus_seconds()
		freeze_left += (card as PlayerScore).take_freeze_seconds()


func _do_start_play() -> void:
	if phase != Phase.PREP or finished:
		return
	phase = Phase.PLAYING
	course.close_shop(_players)
	course.aim_play(_sessions())
	spawner_ai.begin_hole(score.hole_index if score else 0, hole.spawn_points)
	spawner_ai.place_snipers(hole.sniper_perches())
	scorecard_changed.emit()
	Sfx.play("start_play", self)
	_Music.play_level()
	_flash_message(
		"Hole %d   Par %d" % [hole.index + 1, hole.par],
		"Lowest strokes wins. Melee delays. Guns are for zombies."
	)
	_replicate_event.rpc("play")
	_broadcast_scores()


func _on_stroke_taken(player: Player) -> void:
	if is_practice() or player == null:
		return
	var card := score_for(player)
	card.add_stroke()
	if player.golf != null:
		player.golf.club_kit = card.club_kit()
	scorecard_changed.emit()
	_broadcast_scores()
	if card.strokes == 1:
		_summon_cart_girl()
	if card.at_stroke_limit() and not card.done_this_hole:
		_pickup(player)


func _on_ball_rest(_position: Vector3, player: Player) -> void:
	if finished or is_practice() or player == null:
		return
	var card := score_for(player)
	if card.at_stroke_limit():
		_pickup(player)


func _on_hazard(kind: String, player: Player) -> void:
	if finished or player == null:
		return
	var owned := _ball_for(player.peer_id)
	if is_practice():
		if owned != null and hole != null:
			owned.place_at(hole.practice_tee)
		return
	if kind == "water":
		return
	var card := score_for(player)
	card.add_stroke()
	scorecard_changed.emit()
	_broadcast_scores()
	if owned != null:
		owned.place_at(owned.last_safe_position)
	if card.at_stroke_limit():
		_pickup(player)


func _on_holed(player: Player) -> void:
	if finished or is_practice() or player == null:
		return
	_finish_player(player, true)


func _pickup(player: Player) -> void:
	var owned := _ball_for(player.peer_id)
	if owned != null:
		owned.close_for_pickup()
		owned.stow()
	_finish_player(player, false)


func _finish_player(player: Player, from_cup: bool) -> void:
	var card := score_for(player)
	if card.done_this_hole:
		return
	if from_cup:
		card.finish_hole()
	else:
		card.settle_pickup()
	var owned := _ball_for(player.peer_id)
	if owned != null and not owned.is_stowed():
		owned.stow()
	if player.golf != null:
		player.golf.release()
	scorecard_changed.emit()
	if _all_done():
		_complete_hole()
	else:
		_broadcast_scores()


func _all_done() -> bool:
	if _players.is_empty():
		return false
	for player in _players:
		if not score_for(player).done_this_hole:
			return false
	return true


func _timeout_hole() -> void:
	for player in _players:
		if not score_for(player).done_this_hole:
			_pickup(player)


func _complete_hole() -> void:
	if phase != Phase.PLAYING:
		return
	spawner_ai.stop()
	spawner_ai.clear_zombies()
	var last := true
	for card in _scores.values():
		if not (card as PlayerScore).is_course_complete():
			last = false
			break
	if last:
		_end_run()
		return
	for card in _scores.values():
		(card as PlayerScore).advance_to((card as PlayerScore).hole_index + 1)
	_sync_local_score()
	phase = Phase.TRANSIT
	_rally_to_carts()
	course.begin_transit(_carts, _players)
	_replicate_event.rpc("transit")
	spawner_ai.begin_transit(score.hole_index, course.cart_path.spawn_points)
	scorecard_changed.emit()
	_flash_message("Next tee", "Eight carts. Steal the wheel. Follow the arrows.")
	_broadcast_scores()
	_Music.play_level()


func _rally_to_carts() -> void:
	for player in _players:
		if player != null and is_instance_valid(player) and player.health != null:
			player.health.restore()


func _do_arrive() -> void:
	if phase != Phase.TRANSIT:
		return
	phase = Phase.SHOP
	spawner_ai.stop()
	spawner_ai.clear_zombies()
	if course.cart_path != null:
		course.cart_path.hide_arrows()
	if course.clubhouse != null:
		course.clubhouse.open_doors()
	get_tree().call_group("hud", "cover_black")
	course.attach_next_hole(score.hole_index, course_seed, _players, _carts)
	hole = course.hole
	shop = course.shop
	_reset_clock()
	get_tree().call_group("hud", "reveal")
	scorecard_changed.emit()
	_replicate_event.rpc("shop")
	_broadcast_scores()
	_Music.enter_clubhouse()


func _do_leave() -> void:
	if finished:
		return
	phase = Phase.PREP
	course.leave_to_prep(_players)
	shop = course.shop
	hole = course.hole
	course.aim_practice(_sessions())
	scorecard_changed.emit()
	_replicate_event.rpc("prep")
	_broadcast_scores()


func _end_run() -> void:
	finished = true
	spawner_ai.stop()
	var winner := _winner_line()
	message_changed.emit("COURSE COMPLETE", winner, true)
	run_ended.emit(true)
	Sfx.play("run_win", self)
	_Music.play_lounge()
	_replicate_end.rpc(winner)


func _winner_line() -> String:
	var best: PlayerScore
	for card in _scores.values():
		var current := card as PlayerScore
		if best == null or current.relative_to_par() < best.relative_to_par():
			best = current
	if best == null:
		return "Nine holes done."
	return "%s wins at %s.\nPress interact for a new round." % [
		_seat_name(best.seat), GameState.format_relative(best.relative_to_par())
	]


func _on_zombie_killed(bounty: int, killer: Player = null) -> void:
	if finished or phase == Phase.SHOP:
		return
	var card := score_for(killer) if killer != null else score
	if card != null:
		card.credit(bounty)
		scorecard_changed.emit()


func _seat_name(seat: int) -> String:
	var names: PackedStringArray = [
		"Cyan", "Amber", "Magenta", "Lime", "Violet", "Pink", "Blue", "Ice",
	]
	return names[posmod(seat, names.size())]


func _flash_message(title: String, body: String) -> void:
	_banner += 1
	var shown := _banner
	message_changed.emit(title, body, true)
	await get_tree().create_timer(HOLE_BANNER_TIME).timeout
	if not finished and shown == _banner:
		message_changed.emit("", "", false)


@rpc("any_peer", "reliable")
func _request_start() -> void:
	if multiplayer.is_server() and can_start_play(_player_for(multiplayer.get_remote_sender_id())):
		_do_start_play()


@rpc("any_peer", "reliable")
func _request_arrive() -> void:
	if multiplayer.is_server():
		_do_arrive()


@rpc("any_peer", "reliable")
func _request_leave() -> void:
	if multiplayer.is_server():
		_do_leave()


@rpc("any_peer", "reliable")
func _request_buy(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var buyer := _player_for(multiplayer.get_remote_sender_id())
	if buyer != null:
		buy_shop_item(item_id, buyer)


@rpc("authority", "call_remote", "reliable")
func _replicate_event(kind: String) -> void:
	match kind:
		"play":
			phase = Phase.PLAYING
			course.close_shop(_players)
			course.aim_play(_sessions())
			_Music.play_level()
		"transit":
			phase = Phase.TRANSIT
			course.begin_transit(_carts, _players)
			_Music.play_level()
		"shop":
			phase = Phase.SHOP
			if course.cart_path != null:
				course.cart_path.hide_arrows()
			if course.clubhouse != null:
				course.clubhouse.open_doors()
			get_tree().call_group("hud", "cover_black")
			course.attach_next_hole(score.hole_index if score else 0, course_seed, _players, _carts)
			hole = course.hole
			shop = course.shop
			get_tree().call_group("hud", "reveal")
			_Music.enter_clubhouse()
		"prep":
			phase = Phase.PREP
			course.leave_to_prep(_players)
			shop = course.shop
			hole = course.hole
			course.aim_practice(_sessions())
	_sync_local_score()
	scorecard_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _replicate_end(reason: String) -> void:
	finished = true
	message_changed.emit("COURSE COMPLETE", reason, true)
	run_ended.emit(true)


func _summon_cart_girl() -> void:
	if course == null or course.cart_girl == null:
		return
	if not is_instance_valid(course.cart_girl):
		return
	course.cart_girl.begin_approach()


func note_beer_sale(player: Player) -> void:
	if player == null:
		return
	scorecard_changed.emit()
	if multiplayer.is_server():
		_broadcast_scores()
		_apply_beers.rpc(player.peer_id, player.buzz.held)


func _broadcast_look(buyer: Player) -> void:
	if not multiplayer.is_server() or buyer == null or buyer.body == null:
		return
	_apply_apparel.rpc(buyer.peer_id, buyer.body.worn)


func _broadcast_loadout(buyer: Player) -> void:
	if not multiplayer.is_server() or buyer == null or buyer.weapon == null:
		return
	var paths: PackedStringArray = []
	for stats in buyer.weapon.loadout:
		if stats != null and stats.resource_path != "":
			paths.append(stats.resource_path)
	_apply_loadout.rpc(buyer.peer_id, buyer.weapon.index, paths)


@rpc("authority", "call_remote", "reliable")
func _apply_beers(peer_id: int, held: int) -> void:
	var player := _player_for(peer_id)
	if player != null:
		player.apply_held_beers(held)


@rpc("authority", "call_remote", "reliable")
func _apply_apparel(peer_id: int, worn: Dictionary) -> void:
	var player := _player_for(peer_id)
	if player == null:
		return
	for item_id in worn.values():
		var item := ShopStock.wear_by_id(String(item_id))
		if not item.is_empty():
			player.wear_apparel(item)


@rpc("authority", "call_remote", "reliable")
func _apply_loadout(peer_id: int, gun_index: int, paths: PackedStringArray) -> void:
	var player := _player_for(peer_id)
	if player == null or player.weapon == null:
		return
	player.weapon.apply_replicated_loadout(gun_index, paths)


@rpc("authority", "call_remote", "reliable")
func _apply_scores(payload: Dictionary, clock: float, phase_value: int) -> void:
	hole_time_left = clock
	phase = phase_value as Phase
	for peer_id in payload.keys():
		var card := _scores.get(int(peer_id)) as PlayerScore
		if card == null:
			card = PlayerScore.new(HoleGenerator.pars())
			card.peer_id = int(peer_id)
			_scores[int(peer_id)] = card
		var row: Dictionary = payload[peer_id]
		card.strokes = int(row.get("strokes", 0))
		card.money = int(row.get("money", 0))
		card.hole_index = int(row.get("hole_index", 0))
		card.done_this_hole = bool(row.get("done", false))
		card.club_id = String(row.get("club_id", ClubKit.STARTER_ID))
		card.barrier_charges = int(row.get("barrier", card.barrier_charges))
		card.mech_bought = bool(row.get("mech", card.mech_bought))
		var packed: PackedInt32Array = row.get("results", PackedInt32Array())
		if packed.size() == card.results.size():
			card.results = packed
	_sync_local_score()
	scorecard_changed.emit()


func _broadcast_scores() -> void:
	if not multiplayer.is_server():
		return
	var payload := {}
	for peer_id in _scores.keys():
		var card: PlayerScore = _scores[peer_id]
		payload[peer_id] = {
			"strokes": card.strokes,
			"money": card.money,
			"hole_index": card.hole_index,
			"done": card.done_this_hole,
			"club_id": card.club_id,
			"results": card.results,
			"seat": card.seat,
			"barrier": card.barrier_charges,
			"mech": card.mech_bought,
		}
	_apply_scores.rpc(payload, hole_time_left, int(phase))


func _on_pawn_entered(node: Node) -> void:
	var player := node as Player
	if player == null:
		return
	if not _players.has(player):
		_players.append(player)
		_wire_players()
	if hole != null and player.is_multiplayer_authority():
		course.place_player(player, maxi(1, _players.size()))


func _wait_for_pawns() -> void:
	var needed := NetSession.peer_ids()
	if needed.is_empty():
		needed = PackedInt32Array([multiplayer.get_unique_id()])
	for _i in 80:
		var ready := true
		for peer_id in needed:
			if $"../Players".get_node_or_null("P%d" % peer_id) == null:
				ready = false
				break
		if ready:
			return
		await get_tree().create_timer(0.05).timeout


func _player_for(peer_id: int) -> Player:
	for player in _players:
		if player.peer_id == peer_id:
			return player
	return null
