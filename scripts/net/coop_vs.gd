class_name CoopVs
extends Object
## Online "Coop Multiplayer VS": 8 teams of 2, always 16 seats.
## Seats 0..15 pair as team = seat / 2, slot A/B = seat % 2.
## One TeamScore, one TeamBall{team}, and one Cart{team} per team.

const TEAM_SIZE := 2
const TEAM_COUNT := 8
const FIELD_SIZE := TEAM_COUNT * TEAM_SIZE
const MAX_OVER_PAR := 4
const SEAT_NAMES: PackedStringArray = [
	"Cyan", "Amber", "Magenta", "Lime", "Violet", "Pink", "Blue", "Ice",
]


static func team_of(seat: int) -> int:
	if seat < 0:
		return 0
	return seat / TEAM_SIZE


static func pair_index(seat: int) -> int:
	return posmod(seat, TEAM_SIZE)


static func partner_seat(seat: int) -> int:
	return team_of(seat) * TEAM_SIZE + (1 - pair_index(seat))


static func seat_for_team(team: int, slot: int) -> int:
	return clampi(team, 0, TEAM_COUNT - 1) * TEAM_SIZE + posmod(slot, TEAM_SIZE)


static func tee_seat(team: int) -> int:
	return seat_for_team(team, 0)


static func cart_slot(seat: int) -> int:
	return team_of(seat)


static func next_striker(seat: int) -> int:
	return partner_seat(seat)


static func ball_name(team: int) -> String:
	return "TeamBall%d" % team


static func cart_name(team: int) -> String:
	return "Cart%d" % team


static func cpu_fill_count(human_count: int) -> int:
	return maxi(0, FIELD_SIZE - maxi(0, human_count))


static func cpu_peer_id(index: int) -> int:
	return -1 - index


static func is_cpu_peer(peer_id: int) -> bool:
	return peer_id < 0


static func next_cpu_peer_id(seats: Dictionary) -> int:
	var index := 0
	while seats.has(cpu_peer_id(index)):
		index += 1
	return cpu_peer_id(index)


static func seat_name(seat: int) -> String:
	return SEAT_NAMES[posmod(team_of(seat), SEAT_NAMES.size())]


static func team_name(team: int) -> String:
	return SEAT_NAMES[posmod(team, SEAT_NAMES.size())]


static func player_label(seat: int) -> String:
	var letter := "A" if pair_index(seat) == 0 else "B"
	return "%s %s" % [team_name(team_of(seat)), letter]


static func tint_index(seat: int) -> int:
	return team_of(seat)


static func filled_seats(human_seats: Dictionary) -> Dictionary:
	var next: Dictionary = human_seats.duplicate()
	var used: Array = next.values()
	var cpu_n := 0
	for seat in FIELD_SIZE:
		if used.has(seat):
			continue
		next[cpu_peer_id(cpu_n)] = seat
		cpu_n += 1
	return next


static func seat_taken(seats: Dictionary, seat: int, except_peer := 0) -> bool:
	for peer_id in seats.keys():
		if int(seats[peer_id]) == seat and int(peer_id) != except_peer:
			return true
	return false


static func apply_seat_claim(seats: Dictionary, peer_id: int, seat: int) -> bool:
	if seat < 0 or seat >= FIELD_SIZE:
		return false
	if seat_taken(seats, seat, peer_id):
		return false
	seats[peer_id] = seat
	return true


## One stroke total per team. Pass TeamScore cards, not two PlayerScores.
static func team_relative(cards: Array) -> Dictionary:
	var totals := {}
	for card in cards:
		var team_card := card as TeamScore
		if team_card == null:
			continue
		totals[team_card.team] = team_card.relative_to_par()
	return totals


static func winning_team(cards: Array) -> int:
	var totals := team_relative(cards)
	var best_team := -1
	var best := 0
	for team in totals.keys():
		var rel := int(totals[team])
		if best_team < 0 or rel < best or (rel == best and int(team) < best_team):
			best = rel
			best_team = int(team)
	return best_team


static func scoreboard_text(cards: Array, local_seat := -1) -> String:
	var totals := team_relative(cards)
	var bits: PackedStringArray = []
	for team in TEAM_COUNT:
		if not totals.has(team):
			continue
		var mark := "*" if team_of(local_seat) == team else ""
		bits.append("%s%s %s" % [
			mark, team_name(team), GameState.format_relative(int(totals[team]))
		])
	return "   ".join(bits)


static func winner_line(cards: Array) -> String:
	var team := winning_team(cards)
	if team < 0:
		return "Nine holes done."
	var totals := team_relative(cards)
	return "Team %s wins at %s.\nPress interact for a new round." % [
		team_name(team), GameState.format_relative(int(totals.get(team, 0)))
	]


static func bind_partners(players: Array) -> void:
	for player in players:
		var pawn := player as Player
		if pawn == null:
			continue
		pawn.partner = partner_in(pawn, players)


static func ball_for_peer(balls: Array, peer_id: int, seats: Dictionary) -> GolfBall:
	if GameSettings.is_coop_vs():
		var team := team_of(int(seats.get(peer_id, -1)))
		for node in balls:
			var owned := node as GolfBall
			if owned == null:
				continue
			if owned.team == team or String(owned.name) == ball_name(team):
				return owned
		return null
	for node in balls:
		var owned := node as GolfBall
		if owned != null and owned.owner_peer == peer_id:
			return owned
	return null


static func partner_in(player: Player, players: Array) -> Player:
	if player == null:
		return null
	var other_seat := partner_seat(player.seat_index())
	for node in players:
		var other := node as Player
		if other == null or other == player:
			continue
		if other.seat_index() == other_seat:
			return other
	return null
