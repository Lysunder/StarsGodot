class_name BattleEngine
extends RefCounted
## One battle, round by round (spec S16 "Rounds", "Movement", "Firing", "Damage"): tokens move and
## fire, damage lands on the fleets and starbase as it happens, and every move and shot is
## recorded (S16 "The recording").
##
## Tokens are the Dictionaries BattleSetup.tokens makes; the engine adds private keys (starting
## with "_") for its own use and strips them from the record.

const ROUNDS := 16
const BOARD_MAX := 9
const PASSES := 3
const WEIGHT_BOUND := 30000
const FAR := 30000000
const NONE := 255
const LEFT_BATTLE := 255
const MOVES_SHIFT := 14
const COUNTDOWN_MASK := 0x1F << 5
const COUNTDOWN_ONE := 1 << 5
const MAX_INITIATIVE := 63
const KIND_STARBASE := 1
const ALIVE := 1
const FIRED := 16
## Hit kinds (S16 "Damage").
const HIT_SMALL_BEAM := 1
const HIT_BIG_BEAM := 2
const HIT_TORPEDO := 4
const HIT_TORPEDO_MISS := 0x84
const HIT_ABSORBED := 0xC0
const BIG_BEAM_POWER := 200
const STARBASE_DESTROYED := 0xFA00
const LOSS_HIT := 0x8000
const CAPITAL_MISSILES := [
	"part.torpedo.jihad_missile",
	"part.torpedo.juggernaut_missile",
	"part.torpedo.doomsday_missile",
	"part.torpedo.armageddon_missile",
]

var state: GameState
var content: ContentRegistry
var rng: StarsRandom
var tokens: Array[Dictionary] = []
var attack: Array[int] = []
var events: Array[Dictionary] = []
var round_number := 0
var pile: Packet = null
## Initiatives that some weapon has.
var initiatives := {}
## The highest level per tech field of the designs that lost ships (S16 "Battle results").
var tech_seen: Array[int] = TechGain.new_need()
## The starbase was destroyed, or damaged and survived.
var starbase_destroyed := false
var starbase_damaged := false
## Per owner × 16 + design slot of the ships that took armor damage: LOSS_HIT plus the ships
## killed (for the battle messages, S16 "Battle results").
var losses := {}
## The armor damage formulas (S16 "Damage"): `battle.armor_damage`, `battle.starbase_damage`.
var _ship_armor: Callable
var _starbase_armor: Callable
## Estimates of the move being weighed, by tokens, distance and range rule (`_estimate`).
var _estimates := {}
## What each enemy deals and takes over a range of distances, for the move being weighed.
var _kept := {}
## Whether random numbers were drawn since it was last cleared (torpedo_hits).
var _drew := false


func _init(
	p_state: GameState,
	p_content: ContentRegistry,
	p_rng: StarsRandom,
	battle: Dictionary,
	p_tokens: Array[Dictionary]
) -> void:
	state = p_state
	content = p_content
	rng = p_rng
	attack.assign(battle.attack)
	tokens = p_tokens
	_ship_armor = content.ruleset.formula(StandardRuleset.ARMOR_DAMAGE)
	_starbase_armor = content.ruleset.formula(StandardRuleset.STARBASE_DAMAGE)
	for i in tokens.size():
		tokens[i]["_i"] = i
		_link(tokens[i])


## Fights the battle; returns the recorded events.
func run() -> Array[Dictionary]:
	var low := NONE
	var high := -1
	for t in tokens:
		if t.initiative_low != NONE:
			low = mini(low, t.initiative_low)
			high = maxi(high, t.initiative_high)
	var alive := 0
	round_number = 0
	while true:
		alive = 0
		for t in tokens:
			if not t.state & ALIVE:
				continue
			alive |= 1 << t.owner
			t.movement &= 15
			if round_number > 0 and t.shields != 0:
				var race := state.player(t.owner).race
				if RaceMath.trait_param(race, content, "battle.shield_regen", 0):
					_regen_shields(t)
		if _bits(alive) < 2:
			break
		for t in tokens:
			if not t.state & ALIVE:
				continue
			var moves := 0
			if t.kind != KIND_STARBASE:
				moves = moves_this_round(t.movement & 15, round_number)
			t.state = t.state & ~(3 << MOVES_SHIFT) | moves << MOVES_SHIFT
		for p in range(PASSES, 0, -1):
			_movement_pass(p)
		alive = 0
		for t in tokens:
			if t.state & ALIVE:
				t.state = t.state & ~(15 << 10) | rng.random(15) << 10
				alive |= 1 << t.owner
		for i in state.players.size():
			if alive & (1 << i) and attack[i] & alive == 0:
				alive &= ~(1 << i)
		if _bits(alive) < 2:
			break
		if high >= 0:
			for initiative in range(high, low - 1, -1):
				if not initiatives.has(initiative):
					continue
				for idx in range(tokens.size() - 1, -1, -1):
					var t := tokens[idx]
					if initiative < t.initiative_low or initiative > t.initiative_high:
						continue
					alive = 0
					for o in tokens:
						if o.state & ALIVE:
							alive |= 1 << o.owner
					if _bits(alive) < 2:
						break
					if t.state & ALIVE:
						var event := _event(idx, t.square)
						if _fire(idx, initiative, event):
							events.append(event)
							t.state &= ~FIRED
		if _bits(alive) < 2:
			break
		round_number += 1
		if round_number >= ROUNDS:
			break
	return events


## The record of the tokens as they started (call before run) or now.
static func token_record(t: Dictionary) -> Dictionary:
	var out := {}
	for k: String in t:
		if not k.begins_with("_"):
			out[k] = t[k]
	return out


## `GetMovesThisRound@10e8:5872`.
static func moves_this_round(rating: int, round: int) -> int:
	var base := (rating + 2) >> 2
	match rating & 3:
		0:
			return base + (1 if round & 1 == 0 else 0)
		1:
			return base + (0 if round & 3 == 2 else 1)
		3:
			return base + (1 if round & 3 == 0 else 0)
	return base


static func distance(a: int, b: int) -> int:
	return maxi(absi((a & 15) - (b & 15)), absi((a >> 4) - (b >> 4)))


func _link(t: Dictionary) -> void:
	var owner := state.player(t.owner)
	if t.kind == KIND_STARBASE:
		t["_planet"] = state.planet(t.planet)
		t["_design"] = owner.starbase_design(t.design - 16)
	else:
		if not t.has("_fleet"):
			t["_fleet"] = state.fleet(t.fleet_owner, t.fleet)
		t["_design"] = owner.ship_design(t.design)
	var design: Design = t._design
	var weapons: Array[Dictionary] = []
	var max_beam := -1
	for slot in design.parts:
		if slot.count <= 0 or slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var category: String = part.get("category", "")
		if category not in ["beam", "torpedo"]:
			continue
		var stats: Dictionary = part.get("stats", {})
		var w := {
			"part": slot.part,
			"torpedo": category == "torpedo",
			"count": slot.count,
			"power": int(stats.get("power", 0)),
			"range": int(stats.get("range", 0)) + (1 if t.kind == KIND_STARBASE else 0),
			"part_range": int(stats.get("range", 0)),
			"initiative": mini(int(stats.get("initiative", 0)) + t.computer_initiative, 63),
			"accuracy": int(stats.get("accuracy", 0)),
			"sapper": part.get("tags", []).has("sapper"),
			"gatling": part.get("tags", []).has("gatling"),
			"capital": slot.part in CAPITAL_MISSILES,
		}
		weapons.append(w)
		initiatives[w.initiative] = true
		if category == "beam" and not w.sapper:
			max_beam = maxi(max_beam, w.part_range)
	t["_weapons"] = weapons
	t["_max_beam"] = max_beam
	t["_armor"] = int(PartRules.armor(design, content, owner.race))


func _bits(mask: int) -> int:
	var n := 0
	while mask != 0:
		n += mask & 1
		mask >>= 1
	return n


func _event(idx: int, square: int) -> Dictionary:
	var t := tokens[idx]
	return {
		"token": idx,
		"square": square,
		"round": round_number,
		"countdown": (t.state >> 5) & 15,
		"hits": [],
	}


func _regen_shields(t: Dictionary) -> void:
	var full := PartRules.shields(t._design, content, state.player(t.owner).race)
	t.shields = mini(t.shields + full / 10, full)


# --- Movement --------------------------------------------------------------------------------


## One movement pass (S16 "Rounds" 3): heaviest first.
func _movement_pass(p: int) -> void:
	var bound := WEIGHT_BOUND
	while true:
		var next := 0
		for idx in tokens.size():
			var t := tokens[idx]
			if not t.state & ALIVE or t.mass == 0xFFFF:
				continue
			var jitter: int = (t.state >> 10) & 15
			var weight: int = t.mass + _div((jitter - 7) * t.mass * 2, 100)
			if next < weight and weight < bound:
				if moves_this_round(t.movement & 15, round_number) != 0:
					next = weight
			if weight == bound and (t.state >> MOVES_SHIFT) >= p:
				_move_token(idx, p)
		bound = next
		if next == 0:
			break


func _move_token(idx: int, p: int) -> void:
	var t := tokens[idx]
	var event := _event(idx, 0)
	var before: int = t.square
	if t.tactic & 15 == 0:
		# a disengaging token's move is always recorded
		before = NONE
		if t.state & COUNTDOWN_MASK == 0:
			event.square = LEFT_BATTLE
			t.state &= ~ALIVE
			events.append(event)
			return
		t.state -= COUNTDOWN_ONE
	_token_move(idx, p)
	t.state = (t.state + (3 << MOVES_SHIFT)) & 0xFFFF
	if t.kind == KIND_STARBASE or (t.square == before and t.initiative_low != NONE):
		return
	event.square = t.square
	events.append(event)


## `Token_Move@10e8:3c7a`.
func _token_move(idx: int, _p: int) -> void:
	var t := tokens[idx]
	# nothing changes while the token weighs its move: its estimates hold for every square
	_estimates.clear()
	_kept.clear()
	var cx: int = t.square & 15
	var cy: int = t.square >> 4
	if t.kind == KIND_STARBASE:
		t.state |= FIRED
		return
	var mask: int = attack[t.owner]
	var tactic: int = t.tactic & 15
	var primary := _has_primary(t, mask)
	var grid: Array[int] = []
	grid.resize(9)
	grid.fill(FAR)
	var chosen := _choose_target(t, mask)
	var radius: int = chosen[0]
	var target_square: int = chosen[1]
	var best := FAR
	var best_distance := 0
	var ties := 0
	var dest: int = t.square
	for x in range(maxi(cx - radius, 0), mini(cx + radius, BOARD_MAX) + 1):
		for y in range(maxi(cy - radius, 0), mini(cy + radius, BOARD_MAX) + 1):
			var square := y << 4 | x
			var score := _rate_position(t, square, primary, mask)
			if tactic == 0:
				for o in tokens:
					if o.square == square and o.owner == t.owner:
						score += 2
				if t.square == square:
					score -= 1
			var d := distance(t.square, square)
			if d < 2:
				grid[(x - cx + 1) * 3 + (y - cy + 1)] = score
			if score < best or (score == best and d <= best_distance):
				if score == best and d == best_distance:
					ties += 1
					if rng.random(ties) != 0:
						continue
				else:
					ties = 1
					best = score
					best_distance = d
				dest = square
	if target_square != NONE:
		dest = target_square
	var nx := cx
	var ny := cy
	if distance(t.square, dest) > 1:
		var dx: int = (dest & 15) - cx
		var dy: int = (dest >> 4) - cy
		if absi(dx) == absi(dy):
			nx += 1 if dx > 0 else -1
			ny += 1 if dy > 0 else -1
		elif dx == 0:
			var row := 0 if dy < 0 else 2
			ny += row - 1
			nx += _pick([grid[row], grid[3 + row], grid[6 + row]]) - 1
		elif dy == 0:
			var col := 0 if dx < 0 else 2
			nx += col - 1
			ny += _pick([grid[col * 3], grid[col * 3 + 1], grid[col * 3 + 2]]) - 1
		else:
			var sx := 2 if dx > 0 else 0
			var sy := 2 if dy > 0 else 0
			var diagonal := grid[sx * 3 + sy]
			var straight_x := sx
			var straight_y := sy
			if absi(dy) < absi(dx):
				straight_y = 1
			else:
				straight_x = 1
			var straight := grid[straight_x * 3 + straight_y]
			var take_diagonal := diagonal < straight
			if diagonal == straight:
				take_diagonal = rng.random(2) == 0
			if take_diagonal:
				nx += sx - 1
				ny += sy - 1
			else:
				nx += straight_x - 1
				ny += straight_y - 1
		dest = ny << 4 | nx
	if best != FAR:
		if (dest & 15) <= BOARD_MAX and (dest & 0xF0) <= 0x90:
			t.square = dest
	t.state |= FIRED


## The index (0-2) of the lowest of three grid ratings, ties broken by `random(count)`.
func _pick(values: Array) -> int:
	var low := FAR
	var count := 0
	for v: int in values:
		if v <= low:
			if v == low:
				count += 1
			else:
				low = v
				count = 1
	var k := rng.random(count)
	for i in 3:
		if values[i] == low:
			if k == 0:
				return i
			k -= 1
	return 1


## `Token_HasPrimaryTargets@10e8:37f0`.
func _has_primary(t: Dictionary, mask: int) -> bool:
	var primary: int = t.targets & 15
	if primary == 0:
		return false
	for o in tokens:
		if o.owner == t.owner or not mask & (1 << o.owner) or not o.state & ALIVE:
			continue
		if is_target_class(o, primary):
			return true
	return false


## `Token_IsTargetClass@10e8:38ea`.
static func is_target_class(t: Dictionary, target: int) -> bool:
	var ship_class: int = t.tactic >> 4
	match target:
		1:
			return true
		2:
			return t.kind == KIND_STARBASE
		3, 6, 7:
			return ship_class == target
		4:
			return ship_class == 4 or ship_class == 7
		5:
			return ship_class == 5 or ship_class == 7 or ship_class == 6
	return false


## `Token_ChooseTarget@10e8:356e`: [squares to look at, a square to head for or NONE].
func _choose_target(t: Dictionary, mask: int) -> Array[int]:
	var moves: int = t.state >> MOVES_SHIFT
	var far_range: int = t.ranges & 15
	var near_range: int = t.ranges >> 4
	var reach := far_range + moves
	var target_class: int = (t.targets & 15) if _has_primary(t, mask) else (t.targets >> 4)
	var beam_range := far_range
	if far_range == 3:
		beam_range = t._max_beam
	if near_range < far_range and ((t.tactic & 15) == 5 or (t.tactic & 15) == 3):
		reach = moves + near_range
	var best := 10
	var square := NONE
	for o in tokens:
		if o.owner == t.owner or not mask & (1 << o.owner) or not o.state & ALIVE:
			continue
		if not is_target_class(o, target_class & 15):
			continue
		var d := distance(t.square, o.square)
		if (o.state >> MOVES_SHIFT) >= moves:
			d += 1
		if d <= reach:
			if o.shields != 0 or far_range == beam_range or (moves + beam_range) >= d:
				return [moves, NONE]
		if d < best and _estimate(t, 0, o, false) > 0:
			best = d
			square = o.square
	return [1, square]


## `Token_RatePosition@10e8:3966`.
func _rate_position(t: Dictionary, square: int, primary: bool, mask: int) -> int:
	var most_dealt := 0
	var taken_sum := 0
	var target_class: int = (t.targets & 15) if primary else (t.targets >> 4)
	var tactic: int = t.tactic & 15
	var my_moves: int = t.state >> MOVES_SHIFT
	for o in tokens:
		if not o.state & ALIVE or o.owner == t.owner or not mask & (1 << o.owner):
			continue
		var d := distance(o.square, square)
		var low := d
		var high := d
		if my_moves <= (o.state >> MOVES_SHIFT):
			low = maxi(d - 1, 0)
			for ex in [(o.square & 15) - 1, (o.square & 15) + 1]:
				for ey in [(o.square >> 4) - 1, (o.square >> 4) + 1]:
					var cell: int = clampi(ey, 0, BOARD_MAX) << 4 | clampi(ex, 0, BOARD_MAX)
					high = maxi(high, distance(square, cell))
		# the same for every square at these distances: remembered for the move being weighed
		var key: int = ((o._i * 64 + low) * 64 + high) * 2 + (1 if primary else 0)
		var kept: Array = _kept.get(key, [])
		if kept.is_empty():
			var drew := _drew
			_drew = false
			var is_target := is_target_class(o, target_class & 15)
			var best := FAR
			kept = [0, 0]
			for dist in range(low, high + 1):
				var dealt := _estimate(t, dist, o, false) if is_target else 0
				var taken := _estimate(o, dist, t, tactic == 0)
				# the enemy picks the distance: its own tactic, from its side (taken, dealt swapped)
				var score := tactic_score(taken, dealt, o.tactic & 15)
				if score <= best:
					best = score
					kept = [dealt, taken]
			if not _drew:
				_kept[key] = kept
			_drew = _drew or drew
		most_dealt = maxi(most_dealt, kept[0])
		taken_sum += kept[1]
	return tactic_score(most_dealt, taken_sum, tactic)


## `Tactic_Score@10e8:3bdc` (lower is better).
static func tactic_score(a: int, b: int, tactic: int) -> int:
	match tactic:
		0, 2:
			return b
		1, 5:
			return -a
		3, 4:
			if a == 0:
				return b
			var r := _div(-a * 100, b + 1)
			return -1 if r >= 0 else r
	return 0


## estimate() remembered for the move being weighed (`_token_move` clears it), unless working it
## out drew random numbers (small torpedo volleys): those draws are made every time, as the
## original makes them.
func _estimate(a: Dictionary, d: int, t: Dictionary, ignore: bool) -> int:
	var key: int = ((a._i * 1024 + t._i) * 64 + d) * 2 + (1 if ignore else 0)
	if _estimates.has(key):
		return _estimates[key]
	var drew := _drew
	_drew = false
	var value := estimate(a, d, t, ignore)
	if not _drew:
		_estimates[key] = value
	_drew = _drew or drew
	return value


## `Token_EstimateDamage@10e8:315a`: what token `a` would do to token `t` at distance `d`;
## `ignore` ignores range and caps.
func estimate(a: Dictionary, d: int, t: Dictionary, ignore: bool) -> int:
	if not ignore and (a.ranges & 15) < d:
		return 0
	var total := 0
	for w: Dictionary in a._weapons:
		var out_of_range: bool = d > w.range
		if out_of_range and not ignore:
			continue
		var damage := 0
		if not w.torpedo:
			damage = w.power * w.count
			if a.beam_damage_pct != 0:
				damage = _div(a.beam_damage_pct * damage, 100)
			if d > 0 and w.range > 0:
				damage += _div(_div(damage * d, -10), w.range)
			if t.beam_defense_pct < 100:
				damage = _div(t.beam_defense_pct * damage, 100)
			if w.sapper:
				damage = mini(damage, a.count * t.shields)
			if out_of_range:
				damage = maxi(_div(damage, d + 10 - w.range), w.count)
			damage *= a.count
		else:
			var n: int = a.count * w.count * 200
			var hits := torpedo_hits(n, t, w.accuracy, a.torpedo_accuracy)
			damage = _div(w.power * hits, 200)
			if t.shields != 0:
				damage += _div(w.power * (n - hits), 1600)
			if out_of_range:
				damage = _div(damage, d + 10 - w.range)
				if damage < w.count:
					damage = w.count
		total += damage
	var armor: int = t._armor
	var strength: int = (armor + t.shields) * t.count
	if t.damage != 0 and strength > 0:
		var pts: int = t.damage >> 7
		var pct: int = t.damage & 0x7F
		strength += _div(_div(_div(pts * armor, -10) * pct, 10) * t.count, 500)
		if strength < 1:
			strength = 1
	if strength < total and not ignore:
		total = strength
	return total


## `CalcTorpedoHits@10e8:41b4`.
func torpedo_hits(n: int, t: Dictionary, accuracy: int, bonus: int) -> int:
	if n == 0 or accuracy == 0:
		return 0
	var jam: int = t.torpedo_jamming
	if jam != 0 and bonus != 0:
		jam -= bonus
		if jam < 0:
			bonus = -jam
			jam = 0
		else:
			bonus = 0
	var a: int = accuracy
	if bonus != 0:
		a = _div((100 - bonus) * (accuracy - 100), 100) + 100
	elif jam != 0:
		a = _div((100 - jam) * accuracy, 100)
	if a < 1:
		a = 1
	if a >= 100:
		return n
	if n > 200:
		return _div(a * n, 100)
	var hits := 0
	_drew = true
	for i in n:
		if rng.random(100) < a:
			hits += 1
	return hits


# --- Firing ----------------------------------------------------------------------------------


## `Token_Fire@10e8:4310`: true when something was hit.
func _fire(idx: int, initiative: int, event: Dictionary) -> bool:
	var t := tokens[idx]
	var mask: int = attack[t.owner]
	var hits_before: int = (event.hits as Array).size()
	for w: Dictionary in t._weapons:
		if w.initiative != initiative:
			continue
		if w.gatling:
			_fire_gatling(t, w, mask, event)
			continue
		var beams := 0
		var torpedoes := 0
		if w.torpedo:
			torpedoes = t.count * w.count
		else:
			beams = t.count * w.power * w.count
		while beams > 0 or torpedoes > 0:
			var target := _best_target(t, w, mask, true)
			if target < 0:
				target = _best_target(t, w, mask, false)
			if target < 0:
				break
			var o := tokens[target]
			var d := distance(o.square, t.square)
			if not w.torpedo:
				beams = _beam_shot(t, w, target, d, beams, event)
			else:
				torpedoes = _torpedo_volley(t, w, target, torpedoes, event)
	return (event.hits as Array).size() > hits_before


func _in_reach(t: Dictionary, o: Dictionary, w: Dictionary, mask: int) -> bool:
	if not o.state & ALIVE or o.owner == t.owner or not mask & (1 << o.owner):
		return false
	return distance(o.square, t.square) <= w.range


func _fire_gatling(t: Dictionary, w: Dictionary, mask: int, event: Dictionary) -> void:
	var base: int = t.count * w.power * w.count
	if t.beam_damage_pct != 0:
		base = _div(t.beam_damage_pct * base, 100)
	var kind := HIT_BIG_BEAM if w.power >= BIG_BEAM_POWER else HIT_SMALL_BEAM
	for target in tokens.size():
		var o := tokens[target]
		if not _in_reach(t, o, w, mask):
			continue
		if not is_target_class(o, t.targets & 15) and not is_target_class(o, t.targets >> 4):
			continue
		var damage := base
		if o.beam_defense_pct < 100:
			damage = _div(o.beam_defense_pct * damage, 100)
		_take_damage(target, [damage], 0, kind, w.sapper, null, event)


## The best target for a weapon (S16 "Firing"), or -1.
func _best_target(t: Dictionary, w: Dictionary, mask: int, primary: bool) -> int:
	var target_class: int = (t.targets & 15) if primary else (t.targets >> 4)
	var best := 0
	var chosen := -1
	for target in tokens.size():
		var o := tokens[target]
		if not _in_reach(t, o, w, mask) or not is_target_class(o, target_class):
			continue
		var cost := stored_cost(o._design, state.player(o.owner))
		var value: int = ((cost[3] + cost[1]) * o.count & 0xFFFF) * 100
		var armor: int = o._armor * o.count
		var shields: int = o.shields * o.count
		if o.damage != 0:
			var pts: int = o.damage >> 7
			armor += _div(_div(_div(pts * o._armor, -10) * (o.damage & 0x7F), 10) * o.count, 500)
		if armor <= 0:
			armor = 1
		var score := 0
		if not w.torpedo:
			if o.beam_defense_pct < 100:
				value = _div(value * o.beam_defense_pct, 100)
			if w.sapper:
				score = _div(value * 100 + shields - 1, shields) if shields > 0 else 0
			else:
				score = maxi(_div(value * 100, armor + shields + 1), 1)
		else:
			var acc := _accuracy(w.accuracy, t.torpedo_accuracy, o.torpedo_jamming)
			if acc > 0:
				var m := 1 if w.capital else 0
				var x := _div(shields * 100, _div(acc, 2) + _div(100 - acc, 8))
				var y := _div((_div(x * acc, -200) + armor) * 100, (m + 1) * acc) + x
				var z := _div(armor * 200, acc)
				var low := mini(y, z)
				if low > 0:
					score = maxi(_div(value, low), 1)
		if score > best:
			best = score
			chosen = target
	return chosen


## Torpedo accuracy against a target (S16 "Firing").
static func _accuracy(accuracy: int, bonus: int, jamming: int) -> int:
	if jamming <= bonus:
		return accuracy + _div((bonus - jamming) * (100 - accuracy), 100)
	return accuracy + _div(accuracy * (jamming - bonus), -100)


func _beam_shot(
	t: Dictionary, w: Dictionary, target: int, d: int, pool: int, event: Dictionary
) -> int:
	var o := tokens[target]
	var damage: int = pool
	if t.beam_damage_pct != 0:
		damage = _div(t.beam_damage_pct * damage, 100)
	if o.beam_defense_pct < 100:
		damage = _div(o.beam_defense_pct * damage, 100)
	# the fall-off uses the part's own range (no starbase +1), unlike the estimate
	if d > 0 and w.part_range > 0:
		damage = _div((100 - _div(10 * d, w.part_range)) * damage, 100)
	var kind := HIT_BIG_BEAM if w.power >= BIG_BEAM_POWER else HIT_SMALL_BEAM
	var before: int = damage
	var left := [damage]
	_take_damage(target, left, 0, kind, w.sapper, null, event)
	if left[0] < 1 or before < 1:
		return 0
	var share: int
	if pool >= 65536 or left[0] >= 65536:
		share = int(float(pool) / float(before) * float(left[0]))
	else:
		share = _div(pool * left[0], before)
	return mini(pool - 1, share)


func _torpedo_volley(t: Dictionary, w: Dictionary, target: int, n: int, event: Dictionary) -> int:
	var o := tokens[target]
	var hits := torpedo_hits(n, o, w.accuracy, t.torpedo_accuracy)
	var armor: int = o._armor * o.count
	var shields: int = o.shields * o.count
	if o.damage != 0:
		var pts: int = o.damage >> 7
		armor += _div(_div(_div(pts * o._armor, -10) * (o.damage & 0x7F), 10) * o.count, 500)
	var power: int = w.power
	if w.capital and shields <= 0:
		power *= 2
	var used_hits := hits
	var used_misses := n - hits
	var k: int = o.count
	if k < n and hits * power > armor:
		while k <= n:
			var h := _div(hits * k + n - 1, n)
			var misses := k - h
			var left := maxi(shields - _div(misses * power, 8), 0)
			var to_armor := _div(h * power, 2)
			left -= to_armor
			if left < 0:
				to_armor -= left
			used_hits = h
			used_misses = misses
			if to_armor >= armor:
				break
			k += 1
	var miss_damage := _div(used_misses * power, 8)
	if miss_damage > 0:
		_take_damage(target, [miss_damage], 0, HIT_TORPEDO_MISS, true, null, event)
	var half := _div(used_hits * power, 2)
	var allowed := [used_hits + used_misses]
	_take_damage(target, [half], half, HIT_TORPEDO, false, allowed, event)
	return n - (used_hits + used_misses)


# --- Damage ----------------------------------------------------------------------------------


## `Token_TakeDamage@10e8:5234`. `damage` is a one-element array (what is left comes back in it);
## `armor_part` goes to armor whatever the shields do; `kills` (one-element array or null) caps
## the ships destroyed. Returns whether a hit was recorded.
func _take_damage(
	target: int,
	damage: Array,
	armor_part: int,
	kind: int,
	sapper: bool,
	kills: Variant,
	event: Dictionary
) -> bool:
	var o := tokens[target]
	var hit := {"target": target, "kind": kind, "killed": 0, "shield_damage": 0, "damage": 0}
	var left: int = damage[0]
	if o.shields == 0:
		if sapper:
			return false
	else:
		var pool: int = o.shields * o.count
		if pool <= left:
			left -= pool
			hit.shield_damage = pack(pool)
			o.shields = 0
		else:
			hit.shield_damage = pack(left)
			o.shields = _div(pool - left, o.count)
			left = 0
	if (left == 0 or sapper) and armor_part == 0:
		hit.damage = o.damage
		damage[0] = left
		if kind & HIT_TORPEDO:
			hit.kind = kind | HIT_ABSORBED
		_record_hit(hit, event)
		return true
	var allowed: int = kills[0] if kills != null else 0x7FFFFFFF
	var x := left + armor_part
	if o.kind == KIND_STARBASE:
		_starbase_damage(o, x, hit)
		damage[0] = 0
		_record_hit(hit, event)
		return true
	var key: int = o.owner * 16 + o.design
	losses[key] = losses.get(key, 0) | LOSS_HIT
	if o.tactic & 15 == 1:
		o.tactic &= 0xF0
		o.state = o.state & ~COUNTDOWN_MASK | 7 << 5
	var result: Array = _ship_armor.call(o, x, allowed)
	var count: int = result[0]
	x = result[1]
	allowed = result[2]
	var killed: int = o.count - count
	hit.killed = killed
	if killed > 0:
		_record_losses(o, killed)
	if count != 0:
		var stack := (o._fleet as Fleet).stack_for(o.design)
		if stack != null:
			stack.damage = o.damage >> 7
			stack.damaged_percent = o.damage & 0x7F
		x = 0
	damage[0] = x - armor_part if x > armor_part else 0
	hit.damage = o.damage
	if kills != null:
		kills[0] = allowed
	_record_hit(hit, event)
	return true


func _record_hit(hit: Dictionary, event: Dictionary) -> void:
	(event.hits as Array).append(hit)


## Shield damage as recorded (`PackLongToWord`): 13 bits, shifted right by 2 while too big, the
## shifts on top. Score records pack ship counts the same way (S20).
static func pack(value: int) -> int:
	var shifts := 0
	while value & ~0x1FFF:
		value >>= 2
		shifts += 1
	return shifts << 13 | value


static func unpack(word: int) -> int:
	return (word & 0x1FFF) << (((word >> 13) & 7) * 2)


func _starbase_damage(o: Dictionary, x: int, hit: Dictionary) -> void:
	var planet: Planet = o._planet
	var v: int = _starbase_armor.call(o, x)
	if v >= 0:
		starbase_damaged = true
		planet.starbase.damage = v
		hit.damage = (planet.starbase.damage << 7) & 0xFFFF
	else:
		hit.damage = STARBASE_DESTROYED
		hit.killed = 1
		o.state &= ~ALIVE
		o.count = 0
		starbase_destroyed = true
		(o._design as Design).remaining -= 1
		var race := state.player(planet.owner).race
		if not RaceMath.trait_param(race, content, "colony.starbase", 0):
			planet.starbase = null
			# a planet without a starbase keeps no mass driver settings (S09 6b)
			planet.mass_driver_target = -1
			planet.mass_driver_warp = 0
			# `Queue_RemoveShipItems`, `Queue_RemovePacketItems`: ship designs and packets go,
			# starbase designs start over
			var kept: Array[QueueItem] = []
			for q in planet.queue:
				if (q.is_design() and not q.starbase) or _is_packet(q):
					continue
				if q.is_design():
					q.progress = 0
				kept.append(q)
			planet.queue = kept
	if hit.damage & 0xFF80:
		hit.damage = hit.damage & 0xFF80 | 100
		o.damage = hit.damage


func _is_packet(q: QueueItem) -> bool:
	if q.is_design():
		return false
	var def := content.get_def("production_item", q.item)
	return def.get("effect", "") == "packet" and not def.get("auto", false)


## `Token_RecordLosses@10e8:4f0c`: the fleet loses the ships; cargo and salvage follow them, and
## the design's technology is noted for the tech bonus.
func _record_losses(o: Dictionary, killed: int) -> void:
	var fleet: Fleet = o._fleet
	var owner := state.player(fleet.owner)
	TechGain.note_design(o._design, tech_seen, content)
	var key: int = o.owner * 16 + o.design
	losses[key] = losses.get(key, 0) + killed
	(o._design as Design).remaining -= killed
	o.count -= killed
	if o.count == 0:
		o.state &= ~ALIVE
	var stack := fleet.stack_for(o.design)
	stack.count -= killed
	if stack.count <= 0:
		fleet.stacks.erase(stack)
	var lost_cargo: Array[int] = [0, 0, 0, 0, 0]
	if fleet.ship_count() == 0:
		lost_cargo.assign(fleet.cargo)
		fleet.cargo.assign([0, 0, 0, 0, 0])
	else:
		lost_cargo = FleetOrders.cargo_after_losses(fleet, owner, content, {o.design: killed})
	var cost := stored_cost(o._design, owner)
	if RaceMath.trait_param(owner.race, content, "battle.salvage_at_current_tech", 0):
		# recomputed without the new-tech double price (the original turns it off here)
		cost = ProductionCosts.design_cost(o._design, owner, content, true)
	var minerals: Array[int] = []
	for m in 3:
		minerals.append(_div(cost[m] * killed, 3) + lost_cargo[m])
	var planet: Planet = state.planet(fleet.planet) if fleet.planet >= 0 else null
	if planet != null:
		var share := 8 if planet.starbase != null else 5
		for m in 3:
			planet.surface[m] += _div(share * minerals[m], 10)
	else:
		var total := 0
		for m in 3:
			minerals[m] -= minerals[m] >> 2
			total += minerals[m]
		if total != 0:
			pile = Packets.drop_salvage(
				state, content, rng, fleet.owner, fleet.x, fleet.y, minerals, pile
			)


## The design's cost as the original keeps it: computed with the owner's tech levels when the turn
## started (current levels outside turn generation).
func stored_cost(design: Design, owner: Player) -> Array[int]:
	if owner.tech_levels_at_start.is_empty():
		return ProductionCosts.design_cost(design, owner, content)
	var now := owner.tech_levels
	owner.tech_levels = owner.tech_levels_at_start
	var cost := ProductionCosts.design_cost(design, owner, content)
	owner.tech_levels = now
	return cost


## Integer division truncating toward zero, as the original's C does.
static func _div(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := absi(a) / absi(b)
	return q if (a < 0) == (b < 0) else -q
