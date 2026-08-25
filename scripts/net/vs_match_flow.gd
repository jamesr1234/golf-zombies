class_name VsMatchFlow
extends Node
## Online VS round: per-player scorecards, one shared clock, host-authored phases.

signal message_changed(title: String, body: String, shown: bool)
signal scorecard_changed()
signal run_ended(won: bool)

enum Phase { PREP, PLAYING, RETRIEVE, TRANSIT, SHOP }

const HOLE_BANNER_TIME := 3.5
const TEE_READY_RANGE := 4.0
const RETRIEVE_RANGE := 3.2
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
var _team_scores: Dictionary = {}
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
			if GameSettings.is_coop_vs():
				node.apply_tint(Palette.seat_color(VsCourse.cart_slot(node, _carts.size() - 1)))
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
	_ensure_team_cards()
	for card in _team_scores.values():
		(card as TeamScore).advance_to(index)
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


func team_score_for(player: Player) -> TeamScore:
	if player == null:
		return _local_team_card()
	return _team_card(CoopVs.team_of(player.seat_index()))


func can_strike(player: Player) -> bool:
	if player == null or not GameSettings.is_coop_vs():
		return true
	var card := team_score_for(player)
	if card == null or card.done_this_hole:
		return false
	return player.seat_index() == card.striker_seat()


func is_striker(player: Player) -> bool:
	return can_strike(player)


func mark_peer_gone(peer_id: int) -> void:
	var card := _scores.get(peer_id) as PlayerScore
	if card != null and not card.done_this_hole:
		card.settle_pickup()


func settle_disconnected(peer_id: int) -> void:
	if GameSettings.is_coop_vs():
		_replace_with_cpu(peer_id)
		return
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


func _replace_with_cpu(peer_id: int) -> void:
	if peer_id == 1:
		return
	var wallet := _scores.get(peer_id) as PlayerScore
	var player := _player_for(peer_id)
	var seat := wallet.seat if wallet != null else -1
	if seat < 0 and player != null:
		seat = player.seat_index()
	if seat < 0:
		return
	var at := Vector3.ZERO
	var yaw := 0.0
	if player != null:
		at = player.global_position
		yaw = rad_to_deg(player.rotation.y)
		_players.erase(player)
		player.queue_free()
	var players_root := get_node_or_null("../Players")
	if players_root != null:
		var leftover := players_root.get_node_or_null("P%d" % peer_id)
		if leftover != null and leftover != player:
			leftover.queue_free()
	NetSession.seats.erase(peer_id)
	var cpu: Player = null
	if vs_spawner != null and multiplayer.is_server():
		cpu = vs_spawner.spawn_cpu_for_seat(seat, self)
	if cpu != null and at != Vector3.ZERO:
		cpu.spawn_at(at, yaw)
	var cpu_id := cpu.peer_id if cpu != null else CoopVs.next_cpu_peer_id(NetSession.seats)
	if cpu == null:
		NetSession.seats[cpu_id] = seat
	if wallet != null:
		wallet.peer_id = cpu_id
		_scores[cpu_id] = wallet
		_scores.erase(peer_id)
	if NetSession.is_host() and NetSession.is_active():
		NetSession._sync_seats.rpc(NetSession.seats, int(GameSettings.mode))
	CoopVs.bind_partners(_players)
	_wire_players()
	_sync_local_score()
	scorecard_changed.emit()
	if multiplayer.is_server():
		_broadcast_scores()


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	settle_disconnected(peer_id)


func cart_for(who: Node3D) -> GolfCart:
	var riding := _riding_cart(who)
	if riding != null:
		return riding
	if GameSettings.is_coop_vs() and course != null:
		var player := who as Player
		if player != null:
			var team_cart := course.cart_for_seat(CoopVs.cart_slot(player.seat_index()), _carts)
			if team_cart != null:
				return team_cart
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


func can_retrieve_ball(who: Node3D) -> bool:
	if not GameSettings.is_coop_vs() or phase != Phase.RETRIEVE or who == null:
		return false
	var player := who as Player
	var owned := _ball_for(player.peer_id if player != null else 0)
	if owned == null or owned.is_stowed():
		return false
	var offset := who.global_position - owned.global_position
	offset.y = 0.0
	return offset.length() <= RETRIEVE_RANGE


func retrieve_ball(who: Node3D) -> void:
	if not GameSettings.is_coop_vs():
		return
	if NetSession.is_active() and not multiplayer.is_server():
		_request_retrieve.rpc_id(1)
		return
	_do_retrieve(who as Player)


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
	if GameSettings.is_coop_vs():
		return _coop_scorecard()
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


func _coop_scorecard() -> String:
	var card := _local_team_card()
	if card == null:
		return ""
	if phase == Phase.PREP:
		return "Hole %d   Par %d   Warm up" % [card.hole_index + 1, card.par()]
	if phase == Phase.RETRIEVE:
		return "Pick up your ball   then drive to hole %d" % [card.hole_index + 1]
	if phase == Phase.SHOP:
		return "Clubhouse   next hole %d   %s" % [
			card.hole_index + 1,
			GameState.format_money(score.money) if score != null else "",
		]
	if phase == Phase.TRANSIT:
		return "Drive to hole %d" % [card.hole_index + 1]
	return "Hole %d   Par %d   Strokes %d/%d   %s" % [
		card.hole_index + 1, card.par(), card.strokes, card.max_strokes(),
		GameState.format_relative(card.relative_to_par()),
	]


func scoreboard_text() -> String:
	if GameSettings.is_coop_vs():
		if phase == Phase.PLAYING or phase == Phase.PREP:
			return ""
		var local_seat := NetSession.seat_for(multiplayer.get_unique_id())
		return CoopVs.scoreboard_text(_team_scores.values(), local_seat)
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
	if course == null or phase != Phase.TRANSIT or course.cart_path == null:
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
		if GameSettings.is_coop_vs():
			_team_card(CoopVs.team_of(player.seat_index()))
		if not GameSettings.is_coop_vs():
			_connect_player_golf(player)
	if GameSettings.is_coop_vs():
		CoopVs.bind_partners(_players)
		_wire_team_golf()
	_sync_local_score()


func _connect_player_golf(player: Player) -> void:
	if player.golf != null:
		if not player.golf.stroke_taken.is_connected(_on_stroke_taken.bind(player)):
			player.golf.stroke_taken.connect(_on_stroke_taken.bind(player))
	var owned := _ball_for(player.peer_id)
	if owned == null:
		return
	if not owned.holed.is_connected(_on_holed.bind(player)):
		owned.holed.connect(_on_holed.bind(player))
	if not owned.came_to_rest.is_connected(_on_ball_rest.bind(player)):
		owned.came_to_rest.connect(_on_ball_rest.bind(player))
	if not owned.entered_hazard.is_connected(_on_hazard.bind(player)):
		owned.entered_hazard.connect(_on_hazard.bind(player))


func _wire_team_golf() -> void:
	var seen := {}
	for player in _players:
		var team := CoopVs.team_of(player.seat_index())
		if seen.has(team):
			continue
		seen[team] = true
		_connect_player_golf(player)


func _sync_local_score() -> void:
	var local_id := 0
	if multiplayer != null:
		local_id = multiplayer.get_unique_id()
	score = _scores.get(local_id) as PlayerScore
	ball = _ball_for(local_id)
	if course != null:
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
	return CoopVs.ball_for_peer(_balls, peer_id, NetSession.seats)


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
		"Lowest team total wins. Alternate shot. Melee delays. Guns are for zombies."
		if GameSettings.is_coop_vs()
		else "Lowest strokes wins. Melee delays. Guns are for zombies."
	)
	_replicate_event.rpc("play")
	_broadcast_scores()


func _on_stroke_taken(player: Player) -> void:
	if is_practice() or player == null:
		return
	if GameSettings.is_coop_vs():
		_on_team_stroke(player)
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


func _on_team_stroke(player: Player) -> void:
	var card := team_score_for(player)
	if card == null or card.done_this_hole:
		return
	card.add_stroke()
	if player.golf != null and player.score != null:
		player.golf.club_kit = player.score.club_kit()
	scorecard_changed.emit()
	_broadcast_scores()
	if card.strokes == 1:
		_summon_cart_girl()
	if card.at_stroke_limit() and not card.done_this_hole:
		_finish_team(player, false)


func _on_ball_rest(_position: Vector3, player: Player) -> void:
	if finished or is_practice() or player == null:
		return
	if GameSettings.is_coop_vs():
		var team_card := team_score_for(player)
		if team_card == null:
			return
		if team_card.at_stroke_limit():
			_finish_team(player, false)
		elif not team_card.done_this_hole:
			team_card.advance_turn()
			_broadcast_scores()
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
	if GameSettings.is_coop_vs():
		var team_card := team_score_for(player)
		if team_card == null or team_card.done_this_hole:
			return
		team_card.add_stroke()
		scorecard_changed.emit()
		_broadcast_scores()
		if owned != null:
			owned.place_at(owned.last_safe_position)
		if team_card.at_stroke_limit():
			_finish_team(player, false)
		else:
			team_card.advance_turn()
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
	if GameSettings.is_coop_vs():
		_finish_team(player, true)
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


func _finish_team(player: Player, from_cup: bool) -> void:
	var card := team_score_for(player)
	if card == null or card.done_this_hole:
		return
	if from_cup:
		card.finish_hole()
	else:
		card.settle_pickup()
	var owned := _ball_for(player.peer_id)
	if owned != null:
		owned.close_for_pickup()
	_release_team_golf(card.team)
	scorecard_changed.emit()
	if _all_done():
		_complete_hole()
	else:
		_broadcast_scores()


func _release_team_golf(team: int) -> void:
	for player in _players:
		if CoopVs.team_of(player.seat_index()) != team:
			continue
		if player.golf != null:
			player.golf.release()


func _all_done() -> bool:
	if GameSettings.is_coop_vs():
		_ensure_team_cards()
		return TeamScore.everyone_done(_team_scores.values())
	if _players.is_empty():
		return false
	for player in _players:
		if not score_for(player).done_this_hole:
			return false
	return true


func _timeout_hole() -> void:
	if GameSettings.is_coop_vs():
		_ensure_team_cards()
		for card in _team_scores.values():
			var team_card := card as TeamScore
			if team_card.done_this_hole:
				continue
			team_card.settle_pickup()
			var owned := _team_ball(team_card.team)
			if owned != null:
				owned.close_for_pickup()
		_complete_hole()
		return
	for player in _players:
		if not score_for(player).done_this_hole:
			_pickup(player)


func _complete_hole() -> void:
	if phase != Phase.PLAYING:
		return
	if GameSettings.is_coop_vs():
		_complete_coop_hole()
		return
	_stop_spawners()
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
	if course != null:
		course.begin_transit(_carts, _players)
	_replicate_if_in_tree("transit")
	if spawner_ai != null and course != null and course.cart_path != null:
		spawner_ai.begin_transit(score.hole_index, course.cart_path.spawn_points)
	scorecard_changed.emit()
	_flash_message("Next tee", "Eight carts. Steal the wheel. Follow the arrows.")
	_broadcast_scores()
	_Music.play_level()


func _complete_coop_hole() -> void:
	_stop_spawners()
	if _teams_course_complete():
		_end_run()
		return
	for card in _team_scores.values():
		var team_card := card as TeamScore
		team_card.advance_to(team_card.hole_index + 1)
	for card in _scores.values():
		(card as PlayerScore).advance_to((card as PlayerScore).hole_index + 1)
	_sync_local_score()
	_begin_coop_transit()


func _stop_spawners() -> void:
	if spawner_ai == null:
		return
	spawner_ai.stop()
	spawner_ai.clear_zombies()


func _do_retrieve(player: Player) -> void:
	if player == null or not can_retrieve_ball(player):
		return
	var owned := _ball_for(player.peer_id)
	if owned == null or owned.is_stowed():
		return
	owned.stow()
	Sfx.play("grab_ball", self)
	if _all_team_balls_stowed():
		_begin_coop_transit()


func _all_team_balls_stowed() -> bool:
	if _balls.is_empty():
		return false
	for owned in _balls:
		if owned != null and not owned.is_stowed():
			return false
	return true


func _stow_remaining_balls() -> void:
	for owned in _balls:
		if owned != null and not owned.is_stowed():
			owned.stow()


func _begin_coop_transit() -> void:
	if phase != Phase.PLAYING and phase != Phase.RETRIEVE:
		return
	_stow_remaining_balls()
	phase = Phase.TRANSIT
	_rally_to_carts()
	if course != null:
		course.begin_transit(_carts, _players)
	_replicate_if_in_tree("transit")
	if spawner_ai != null and course != null and course.cart_path != null:
		var next_hole := _local_team_card().hole_index if _local_team_card() != null else 0
		spawner_ai.begin_transit(next_hole, course.cart_path.spawn_points)
	scorecard_changed.emit()
	_flash_message("Next tee", "Eight carts. Steal the wheel. Follow the arrows.")
	_broadcast_scores()
	_Music.play_level()


func _replicate_if_in_tree(kind: String) -> void:
	if is_inside_tree():
		_replicate_event.rpc(kind)


func _teams_course_complete() -> bool:
	_ensure_team_cards()
	for card in _team_scores.values():
		if not (card as TeamScore).is_course_complete():
			return false
	return true


func _team_card(team: int) -> TeamScore:
	var card := _team_scores.get(team) as TeamScore
	if card == null:
		card = TeamScore.new(HoleGenerator.pars())
		card.team = team
		_team_scores[team] = card
	return card


func _ensure_team_cards() -> void:
	for team in CoopVs.TEAM_COUNT:
		_team_card(team)


func _local_team_card() -> TeamScore:
	var local_id := 0
	if multiplayer != null:
		local_id = multiplayer.get_unique_id()
	var seat := NetSession.seat_for(local_id)
	if seat < 0:
		seat = 0
	return _team_card(CoopVs.team_of(seat))


func _team_ball(team: int) -> GolfBall:
	for owned in _balls:
		if owned != null and (owned.team == team or String(owned.name) == CoopVs.ball_name(team)):
			return owned
	return null


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
	_stop_spawners()
	var winner := _winner_line()
	message_changed.emit("COURSE COMPLETE", winner, true)
	run_ended.emit(true)
	Sfx.play("run_win", self)
	_Music.play_lounge()
	if is_inside_tree():
		_replicate_end.rpc(winner)


func _winner_line() -> String:
	if GameSettings.is_coop_vs():
		return CoopVs.winner_line(_team_scores.values())
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
	return CoopVs.seat_name(seat)


func _flash_message(title: String, body: String) -> void:
	_banner += 1
	var shown := _banner
	message_changed.emit(title, body, true)
	if not is_inside_tree():
		return
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
func _request_retrieve() -> void:
	if not multiplayer.is_server():
		return
	var player := _player_for(multiplayer.get_remote_sender_id())
	if can_retrieve_ball(player):
		_do_retrieve(player)


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
		"retrieve":
			phase = Phase.RETRIEVE
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
func _apply_scores(payload: Dictionary, clock: float, phase_value: int, teams: Dictionary = {}) -> void:
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
		card.seat = int(row.get("seat", card.seat))
		card.club_id = String(row.get("club_id", ClubKit.STARTER_ID))
		card.barrier_charges = int(row.get("barrier", card.barrier_charges))
		card.mech_bought = bool(row.get("mech", card.mech_bought))
		var packed: PackedInt32Array = row.get("results", PackedInt32Array())
		if packed.size() == card.results.size():
			card.results = packed
	for team in teams.keys():
		var card := _team_card(int(team))
		var row: Dictionary = teams[team]
		card.strokes = int(row.get("strokes", 0))
		card.hole_index = int(row.get("hole_index", 0))
		card.done_this_hole = bool(row.get("done", false))
		card.striker_slot = int(row.get("striker", card.striker_slot))
		var team_packed: PackedInt32Array = row.get("results", PackedInt32Array())
		if team_packed.size() == card.results.size():
			card.results = team_packed
	_sync_local_score()
	scorecard_changed.emit()


func _broadcast_scores() -> void:
	if not is_inside_tree() or multiplayer == null or not multiplayer.is_server():
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
	var teams := {}
	for team in _team_scores.keys():
		var card: TeamScore = _team_scores[team]
		teams[team] = {
			"strokes": card.strokes,
			"hole_index": card.hole_index,
			"done": card.done_this_hole,
			"results": card.results,
			"striker": card.striker_slot,
		}
	_apply_scores.rpc(payload, hole_time_left, int(phase), teams)


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
