class_name Minefields
extends RefCounted
## Minefields (spec S13, laying S11): laying mines, the yearly decay and the start-of-turn reset.
## A field's radius is the square root of its mine count: a point is inside when its squared
## distance from the center is at most the mine count.
##
## Not yet: the salvage a destroyed ship leaves (S14).

const TYPES := ["standard", "heavy", "speed_bump"]
## A field holding more than this takes no more mines: a new field is started instead.
const FIELD_MAX := 999999
## Decay (S13): percent per planet inside (the trait parameter; Space Demolition 1), plus this,
## at most DECAY_MAX, plus DETONATE_DECAY for a detonating field; at least MIN_DECAY mines a year
## (not for speed bumps).
const DECAY_BASE := 2
const DECAY_MAX := 50
const DETONATE_DECAY := 25
const MIN_DECAY := 10
## Lay-mines task data word 0: years left; this value lays for ever.
const LAY_FOREVER := 5
const MINE_LAYER_TAG := "mine_layer"
## Per type (standard, heavy, speed bump): the fastest safe warp, the hit chance per light year and
## per warp over it (per 1000), and per damage column (S13 "Damage"): damage per engine and the
## minimum fleet damage. The second column is for fleets with an engine that burns nothing at
## warp 4.
const SAFE_WARP := [4, 6, 5]
const HIT_RATE := [3, 10, 35]
const DAMAGE_PER_ENGINE := [[100, 125], [500, 600], [0, 0]]
const MIN_DAMAGE := [[500, 600], [2000, 2500], [0, 0]]
## The slowest "speed" the hit check counts with, and the fastest.
const SLOWEST := 3
const FASTEST := 10
## Stretches of one type kept along a path.
const MAX_STRETCHES := 8
## The minimum top-up applies to fleets of at most this many ships.
const SMALL_FLEET := 4
const DAMAGE_SCALE := 500
const MESSAGE_DAMAGE_MAX := 0x7FF8
## A field hit loses mines div 20 (at least 10), or from 51 on mines div 100 (at least 50).
const HIT_LOSS := [20, 10, 51, 100, 50]
const FREE_WARP := 4
## Sweeping a speed-bump field takes this fraction of the rate; a sweep takes at least SWEEP_MIN.
const SPEED_BUMP_SWEEP := 3
const SWEEP_MIN := 2


## Mines a year the fleet lays of one type (`Fleet_MineLayRate@1078:1aea`): Σ ships × the design's
## dispenser rates of that type, doubled on the mine layer hulls.
static func lay_rate(fleet: Fleet, owner: Player, type: String, content: ContentRegistry) -> int:
	var total := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design == null or stack.count <= 0:
			continue
		var per_ship := 0
		for slot in design.parts:
			if slot.count > 0 and not slot.part.is_empty():
				var stats: Dictionary = content.part(slot.part).get("stats", {})
				per_ship += slot.count * int(stats.get("mines_" + type, 0))
		if (content.hull(design.hull).get("tags", []) as Array).has(MINE_LAYER_TAG):
			per_ship *= 2
		total += stack.count * per_ship
	return total


## The lay-mines task (S11 "Lay mines", task pass 3). `moving` for a Space Demolition fleet laying
## on its way (half the mines). `task` is the waypoint with the task, whose years count down.
static func lay(
	state: GameState, content: ContentRegistry, fleet: Fleet, task: Waypoint, moving: bool
) -> void:
	var owner := state.player(fleet.owner)
	var word := fleet.owner * 512 + fleet.number
	var goto := {"fleet": fleet.number, "owner": fleet.owner}
	var any := 0
	for type in TYPES:
		any += lay_rate(fleet, owner, type, content)
	if any == 0:
		TurnMessages.add(state, content, fleet.owner, "message.fleet.no_mine_layers", goto, [word])
		return
	if task == fleet.waypoints[0]:
		var words: Array = task.task_data.get("raw", [0, 0, 0, 0, 0])
		var years := int(words[0]) if not words.is_empty() else 0
		if years == 0:
			task.task = "none"
			task.task_data = {}
		elif years != LAY_FOREVER:
			words[0] = years - 1
			task.task_data["raw"] = words
	for t in TYPES.size():
		var rate := lay_rate(fleet, owner, TYPES[t], content)
		if rate == 0:
			continue
		if moving:
			rate /= 2
		var field := _nearest_own_field(state, fleet, TYPES[t])
		var type := "message.fleet.mines_laid"
		if field == null or field.mines > FIELD_MAX:
			field = state.add_minefield(
				fleet.owner, content.constant("constant.limits.space_object_numbers")
			)
			if field == null:
				TurnMessages.add(
					state, content, fleet.owner, "message.fleet.lay_failed", goto, [word]
				)
				continue
			field.x = fleet.x
			field.y = fleet.y
			field.mines = rate
			field.type = TYPES[t]
			field.known_by.assign([fleet.owner])
		else:
			field.x = (fleet.x * rate + field.x * field.mines) / (rate + field.mines)
			field.y = (fleet.y * rate + field.y * field.mines) / (rate + field.mines)
			field.mines += rate
			type = "message.fleet.mines_added"
		TurnMessages.add(state, content, fleet.owner, type, goto, [word, rate])


## S13 "Hits during movement": checks the fleet's path toward its next waypoint over `distance`
## light years. Returns -1 (no hit) or how far it got: then it has been damaged and stops there.
static func check_path(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet, distance: int
) -> int:
	var owner := state.player(fleet.owner)
	var bonus := RaceMath.trait_param(owner.race, content, "minefield.speed_bonus", 0)
	var speed := SLOWEST
	while speed < FASTEST and distance - 1 > speed * speed:
		speed += 1
	if speed <= SLOWEST + bonus:
		return -1
	var to := fleet.waypoints[1]
	if to.x == fleet.x and to.y == fleet.y:
		return -1
	# per type: the stretches of the path inside fields, [[enter, leave], ...] sorted by enter
	var stretches := [[], [], []]
	for field in state.minefields:
		if field.owner == fleet.owner or _friendly(state, field.owner, fleet.owner):
			continue
		var cut := _crossing(fleet.x, fleet.y, to.x, to.y, field, distance)
		if not cut.is_empty():
			_add_stretch(stretches[TYPES.find(field.type)], cut[0], cut[1])
	var next := [0, 0, 0]
	while true:
		var t := -1
		var nearest := 10000
		for k in 3:
			if next[k] < stretches[k].size() and stretches[k][next[k]][0] < nearest:
				nearest = stretches[k][next[k]][0]
				t = k
		if t < 0:
			return -1
		var stretch: Array = stretches[t][next[t]]
		next[t] += 1
		if speed <= SAFE_WARP[t] + bonus:
			continue
		var chance: int = (speed - bonus - SAFE_WARP[t]) * HIT_RATE[t]
		for ly in range(stretch[1] - stretch[0]):
			if rng.random(1000) < chance:
				var at: int = stretch[0] + ly
				_hit(state, content, rng, fleet, t, at)
				return at
	return -1


## The stretch of the segment from (x1, y1) toward (x2, y2), cut at `length`, inside the field:
## [enter, leave] in light years along it, or [] (`SegmentCircleIntersect@1038:ae30`). Fix B01:
## a vertical path projects the field's center properly (the original takes its start point).
static func _crossing(x1: int, y1: int, x2: int, y2: int, field: Minefield, length: int) -> Array:
	var dx := x2 - x1
	var dy := y2 - y1
	var px: int
	var py: int
	if dx == 0:
		px = x1
		py = field.y
	else:
		var dd := dx * dx + dy * dy
		px = _trunc_div(x1 * dy * dy + field.x * dx * dx + (field.y - y1) * dy * dx, dd)
		py = _trunc_div((px - x1) * dy, dx) + y1
	var off2 := (py - field.y) * (py - field.y) + (px - field.x) * (px - field.x)
	if off2 >= field.mines:
		return []
	var along := int(sqrt(float((px - x1) * (px - x1) + (py - y1) * (py - y1))))
	var half := int(sqrt(float(field.mines - off2)))
	# the nearest point is behind the start: count it negative
	var ahead := true
	if dx > 0:
		ahead = px >= x1
	elif dx < 0:
		ahead = px <= x1
	elif dy > 0:
		ahead = py >= y1
	else:
		ahead = py <= y1
	if not ahead:
		along = -along
	var enter := maxi(along - half, 0)
	var leave := mini(along + half, length)
	if leave > 0 and enter < length:
		return [enter, leave]
	return []


## Adds a stretch to one type's sorted list (at most MAX_STRETCHES): it joins the stretch it
## overlaps, which then takes in the following stretches it reaches.
static func _add_stretch(list: Array, enter: int, leave: int) -> void:
	var k := 0
	while k < list.size() and enter > list[k][0]:
		k += 1
	if k == list.size():
		if k < MAX_STRETCHES:
			list.append([enter, leave])
		return
	if leave < list[k][0] - 1:
		if list.size() < MAX_STRETCHES:
			list.insert(k, [enter, leave])
		return
	list[k][0] = mini(list[k][0], enter)
	if leave > list[k][1]:
		list[k][1] = leave
		var j := k + 1
		while j < list.size() and list[j][0] <= leave:
			j += 1
		if leave < list[j - 1][1]:
			list[k][1] = list[j - 1][1]
		for i in range(j - 1, k, -1):
			list.remove_at(i)


static func _trunc_div(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if (a < 0) == (b < 0) else -q


## The field's owner counts the fleet's owner as a friend (such fields are harmless).
static func _friendly(state: GameState, field_owner: int, player: int) -> bool:
	var relations := state.player(field_owner).relations
	return player < relations.size() and relations[player] == "friend"


## A hit of a field of type `t` at `at` light years along the fleet's path: damage per design
## (S13 "Damage from one hit", fix B04), the field that was hit loses mines, messages.
static func _hit(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet, t: int, at: int
) -> void:
	var owner := state.player(fleet.owner)
	fleet.mine_hit = true
	var to := fleet.waypoints[1]
	var dx := to.x - fleet.x
	var dy := to.y - fleet.y
	# the path length rounded to the nearest light year (seen: 37.6 counts 38, mine1 turn 31)
	var length := int(sqrt(float(dx * dx + dy * dy)) + 0.5)
	var x := fleet.x + _mul_div(dx, at, length)
	var y := fleet.y + _mul_div(dy, at, length)
	var described := FleetOrders.designs_word(fleet, owner, content)
	var result := _damage(fleet, owner, content, t, false)
	var total: int = result[0]
	var destroyed: int = result[1]
	# ships lost leave their minerals as salvage (S14; fix B35: the lost ships' share)
	var pile: Packet = null
	if destroyed > 0:
		var minerals: Array[int] = result[2]
		pile = Packets.drop_salvage(
			state, content, rng, fleet.owner, x, y, minerals, Packets.salvage_at(state, x, y)
		)
	var field := _field_hit(state, fleet, TYPES[t], x, y)
	var obj := 32768 + fleet.owner * 512 + fleet.number
	var goto := {"fleet": fleet.number, "owner": fleet.owner}
	var place := [x, y]
	if fleet.ship_count() == 0:
		var word := fleet.owner * 512 + fleet.number
		if pile != null:
			TurnMessages.add(
				state,
				content,
				fleet.owner,
				"message.fleet.mine_annihilated_salvage",
				Packets.goto_of(pile),
				[Packets.object_word(pile), described, field.owner, t] + place
			)
			TurnMessages.add(
				state,
				content,
				field.owner,
				"message.minefield.annihilated_yours",
				Packets.goto_of(pile),
				[Packets.object_word(pile), word, t] + place
			)
		else:
			TurnMessages.add(
				state,
				content,
				fleet.owner,
				"message.fleet.mine_annihilated",
				{},
				[described, field.owner, t] + place
			)
			TurnMessages.add(
				state,
				content,
				field.owner,
				"message.minefield.annihilated_yours",
				{"minefield": field.number, "owner": field.owner},
				[field.owner * 512 + field.number, word, t] + place
			)
	elif total == 0:
		TurnMessages.add(
			state,
			content,
			fleet.owner,
			"message.fleet.mine_stopped",
			goto,
			[obj, field.owner, t] + place
		)
		TurnMessages.add(
			state, content, field.owner, "message.fleet.mine_stopped_yours", goto, [obj, t] + place
		)
	elif destroyed == 0:
		TurnMessages.add(
			state,
			content,
			fleet.owner,
			"message.fleet.mine_damaged",
			goto,
			[obj, field.owner, t] + place + [total]
		)
		TurnMessages.add(
			state,
			content,
			field.owner,
			"message.fleet.mine_damaged_yours",
			goto,
			[obj, t] + place + [total]
		)
	else:
		TurnMessages.add(
			state,
			content,
			fleet.owner,
			"message.fleet.mine_destroyed_some",
			goto,
			[obj, field.owner, t] + place + [total, destroyed]
		)
		TurnMessages.add(
			state,
			content,
			field.owner,
			"message.fleet.mine_destroyed_some_yours",
			goto,
			[obj, t] + place + [total, destroyed]
		)
	# the field loses mines; the fleet's owner has seen it
	var loss := field.mines / HIT_LOSS[0]
	if loss < HIT_LOSS[2]:
		loss = maxi(loss, HIT_LOSS[1])
	else:
		loss = maxi(field.mines / HIT_LOSS[3], HIT_LOSS[4])
	if loss >= field.mines:
		state.minefields.erase(field)
	else:
		field.mines -= loss
		_mark(field.known_by, fleet.owner)
		_mark(field.seen_by, fleet.owner)


## Damage from one mine hit of type `t` (S13 "Damage from one hit", fix B04): [raw damage before
## shields (at most MESSAGE_DAMAGE_MAX), ships lost, the minerals the lost ships took (all the
## cargo's when the whole fleet is lost)]. Stacks whose ships all die leave the fleet
## (taking their share of the cargo); the others are damaged. `spare_layers`: stacks on mine layer
## hulls take nothing (their owner's own detonating field).
static func _damage(
	fleet: Fleet, owner: Player, content: ContentRegistry, t: int, spare_layers: bool
) -> Array:
	var column := 1 if _has_free_engine(fleet, owner, content) else 0
	var per_engine: int = DAMAGE_PER_ENGINE[t][column]
	var total := 0
	var destroyed := 0
	var ships := fleet.ship_count()
	var lost := {}
	if per_engine > 0:
		var top_up: int = MIN_DAMAGE[t][column] - per_engine * ships
		if ships > SMALL_FLEET or top_up < 1:
			top_up = 0
		for stack: ShipStack in fleet.stacks.duplicate():
			var design := owner.ship_design(stack.design)
			if spare_layers and _is_mine_layer(design, content):
				continue
			var n := stack.count
			var engines := _engines(design)
			# fix B04: the top-up is shared by the stacks in proportion to their ships
			var raw := (n * per_engine + top_up * n / ships) * engines
			total += raw
			var armor := PartRules.armor(design, content, owner.race)
			var absorbed := mini(PartRules.shields(design, content, owner.race) * n, raw / 2)
			var damaged_ships := stack.damaged_percent * n / 100
			var old := damaged_ships * armor * stack.damage / DAMAGE_SCALE
			var per_ship := (old - absorbed + raw) / n
			if per_ship > armor:
				destroyed += n
				lost[stack.design] = n
				design.remaining -= n
				fleet.stacks.erase(stack)
			else:
				stack.damaged_percent = 100
				stack.damage = maxi(per_ship * DAMAGE_SCALE / armor, 1)
	var minerals: Array[int] = [0, 0, 0]
	if destroyed > 0 and fleet.ship_count() > 0:
		var losses := FleetOrders.cargo_after_losses(fleet, owner, content, lost)
		minerals.assign(losses.slice(0, 3))
	elif destroyed > 0:
		for m in 3:
			minerals[m] = fleet.cargo[m]
			fleet.cargo[m] = 0
	return [mini(total, MESSAGE_DAMAGE_MAX), destroyed, minerals]


static func _is_mine_layer(design: Design, content: ContentRegistry) -> bool:
	return (content.hull(design.hull).get("tags", []) as Array).has(MINE_LAYER_TAG)


## S13 "Detonation": every fleet with ships inside a detonating field takes one hit of its type,
## wherever it is going, friends and the field's owner included (the owner's mine layer hulls
## excepted). No rolls. Fix B03: the original checks a fleet against the first detonating field
## that contains it only; here every detonating field hits it.
static func _detonate(state: GameState, content: ContentRegistry, field: Minefield) -> void:
	var t := TYPES.find(field.type)
	var place := [field.x, field.y]
	for fleet in state.fleets:
		if fleet.stacks.is_empty() or _distance2(fleet.x, fleet.y, field) > field.mines:
			continue
		var owner := state.player(fleet.owner)
		var described := FleetOrders.designs_word(fleet, owner, content)
		var result := _damage(fleet, owner, content, t, fleet.owner == field.owner)
		var total: int = result[0]
		var destroyed: int = result[1]
		if total == 0:
			continue
		fleet.mine_hit = true
		var word := fleet.owner * 512 + fleet.number
		var obj := 32768 + word
		var goto := {"fleet": fleet.number, "owner": fleet.owner}
		var foreign := fleet.owner != field.owner
		if fleet.stacks.is_empty():
			if foreign:
				TurnMessages.add(
					state,
					content,
					fleet.owner,
					"message.fleet.mine_annihilated",
					{},
					[described, field.owner, t] + place
				)
				TurnMessages.add(
					state,
					content,
					field.owner,
					"message.minefield.annihilated_yours",
					{"minefield": field.number, "owner": field.owner},
					[field.owner * 512 + field.number, word, t] + place
				)
			else:
				TurnMessages.add(
					state,
					content,
					field.owner,
					"message.minefield.annihilated_own",
					{},
					[described, t] + place
				)
		elif destroyed == 0:
			if foreign:
				TurnMessages.add(
					state,
					content,
					fleet.owner,
					"message.fleet.detonation_damaged",
					goto,
					[obj, field.owner, t] + place + [total]
				)
			TurnMessages.add(
				state,
				content,
				field.owner,
				"message.fleet.detonation_damaged_yours",
				goto,
				[obj, t] + place + [total]
			)
		else:
			if foreign:
				TurnMessages.add(
					state,
					content,
					fleet.owner,
					"message.fleet.detonation_destroyed_some",
					goto,
					[obj, field.owner, t] + place + [total, destroyed]
				)
			TurnMessages.add(
				state,
				content,
				field.owner,
				"message.fleet.detonation_destroyed_some_yours",
				goto,
				[obj, t] + place + [total, destroyed]
			)


## The field of this type, of another player and not a friend, the hit point is deepest inside.
static func _field_hit(state: GameState, fleet: Fleet, type: String, x: int, y: int) -> Minefield:
	var best: Minefield = null
	var best_depth := 100000000
	for field in state.minefields:
		if field.owner == fleet.owner or _friendly(state, field.owner, fleet.owner):
			continue
		if field.type != type:
			continue
		var depth := _distance2(x, y, field) - field.mines
		if depth < best_depth:
			best = field
			best_depth = depth
	return best


## Engines per ship of a design (its engine slot's count).
static func _engines(design: Design) -> int:
	for slot in design.parts:
		if not slot.part.is_empty() and slot.part.begins_with("part.engine."):
			return slot.count
	return 0


## Any ship's engine burns no fuel at warp 4 (the second damage column).
static func _has_free_engine(fleet: Fleet, owner: Player, content: ContentRegistry) -> bool:
	for stack in fleet.stacks:
		var engine := PartRules.engine(owner.ship_design(stack.design), content)
		if not engine[0].is_empty():
			var table: Array = content.part(engine[0]).get("fuel_table", [])
			if table.size() > FREE_WARP and int(table[FREE_WARP]) == 0:
				return true
	return false


## Windows' MulDiv: a × b / c rounded to the nearest, halves away from zero.
static func _mul_div(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	var n := a * b
	var q := (absi(n) * 2 + absi(c)) / (absi(c) * 2)
	return q if (n < 0) == (c < 0) else -q


## The player's field of this type that contains the fleet and is nearest to it, or null.
static func _nearest_own_field(state: GameState, fleet: Fleet, type: String) -> Minefield:
	var best: Minefield = null
	var best_d2 := 10000000
	for field in state.minefields:
		if field.owner != fleet.owner or field.type != type:
			continue
		var d2 := _distance2(fleet.x, fleet.y, field)
		if d2 <= field.mines and d2 < best_d2:
			best = field
			best_d2 = d2
	return best


## S02 phase 17 (S13 "Sweeping", `SweepMinefields@10b0:45c4`): every fleet with a sweep rate, in
## fleet order, sweeps each field (in field order) of another player that it is inside and that
## its battle plan attacks; then every starbase with a sweep rate does the same from its planet,
## for the fields of players its owner doesn't count as friends.
static func sweep_all(state: GameState, content: ContentRegistry) -> void:
	for fleet in state.fleets:
		var rate := fleet_sweep_rate(fleet, state.player(fleet.owner), content)
		if rate <= 0:
			continue
		var word := fleet.owner * 512 + fleet.number
		var goto := {"fleet": fleet.number, "owner": fleet.owner}
		for field in state.minefields.duplicate():
			if field.owner == fleet.owner:
				continue
			if not BattlePlans.attacks(state, fleet, field.owner):
				continue
			var d2 := _distance2(fleet.x, fleet.y, field)
			if d2 > field.mines:
				continue
			var swept := _swept(field, rate, d2)
			var t := TYPES.find(field.type)
			TurnMessages.add(
				state,
				content,
				fleet.owner,
				"message.fleet.swept_mines",
				goto,
				[word, swept, field.owner, t, field.x, field.y]
			)
			_sweep(state, content, field, swept, t, fleet.owner)
	for pl in state.planets:
		if pl.starbase == null or pl.owner < 0:
			continue
		var owner := state.player(pl.owner)
		var design := owner.starbase_design(pl.starbase.design)
		var rate := PartRules.sweep_rate(design, content) if design != null else 0
		if rate <= 0:
			continue
		for field in state.minefields.duplicate():
			if field.owner == pl.owner or _friendly(state, pl.owner, field.owner):
				continue
			var d2 := _distance2(pl.x, pl.y, field)
			if d2 > field.mines:
				continue
			var swept := _swept(field, rate, d2)
			var t := TYPES.find(field.type)
			TurnMessages.add(
				state,
				content,
				pl.owner,
				"message.planet.swept_mines",
				{"planet": pl.id},
				[pl.id, swept, field.owner, t, field.x, field.y]
			)
			# fix B34: the original marks the last fleet's owner as knowing the field
			_sweep(state, content, field, swept, t, pl.owner)


## A fleet's sweep rate (`Fleet_SweepRate@1078:1ca2`): Σ ships × the design's sweep rate (S04).
static func fleet_sweep_rate(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var total := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design != null and stack.count > 0:
			total += stack.count * PartRules.sweep_rate(design, content)
	return total


## Mines one sweep at `rate` takes from `field`, the sweeper at squared distance `d2` from its
## center: a third of the rate in a speed-bump field, at least SWEEP_MIN; never so many that the
## sweeper ends up outside (the field keeps d2 − 1), never more than the field has.
static func _swept(field: Minefield, rate: int, d2: int) -> int:
	var amount := rate / SPEED_BUMP_SWEEP if field.type == "speed_bump" else rate
	amount = maxi(amount, SWEEP_MIN)
	if field.mines - amount < d2 - 1:
		amount = field.mines - d2 + 1
	return mini(amount, field.mines)


## The field loses `swept` mines (telling its owner); a field left with none disappears, else the
## sweeper's owner now knows it.
static func _sweep(
	state: GameState, content: ContentRegistry, field: Minefield, swept: int, t: int, by: int
) -> void:
	TurnMessages.add(
		state,
		content,
		field.owner,
		"message.minefield.swept",
		{"minefield": field.number, "owner": field.owner},
		[field.owner * 512 + field.number, swept, t, field.x, field.y]
	)
	field.mines -= swept
	if field.mines < 1:
		state.minefields.erase(field)
	else:
		_mark(field.known_by, by)


## Adds a player to a sorted player list.
static func _mark(players: Array[int], player: int) -> void:
	if not players.has(player):
		players.append(player)
		players.sort()


## S02 phase 7: each field's "seen this turn" record starts empty (scanning sets it, S15).
static func reset_all(state: GameState) -> void:
	for field in state.minefields:
		field.seen_by.clear()


## S02 phase 11 (minefields), in field order: a field ordered to detonate damages the fleets inside
## it (`_detonate`); then it loses a share of its mines, more with planets inside and when it
## detonated; a field that would lose all its mines disappears. Fleets left without ships go.
static func decay_all(state: GameState, content: ContentRegistry) -> void:
	for field in state.minefields.duplicate():
		if field.detonate:
			_detonate(state, content, field)
		var owner := state.player(field.owner)
		var per_planet := RaceMath.trait_param(owner.race, content, "minefield.decay_per_planet", 4)
		var rate := mini(per_planet * planets_inside(state, field) + DECAY_BASE, DECAY_MAX)
		if field.detonate:
			rate += DETONATE_DECAY
		var lost := maxi(field.mines * rate / 100, rate)
		if field.type != "speed_bump":
			lost = maxi(lost, MIN_DECAY)
		if field.mines <= lost:
			state.minefields.erase(field)
		else:
			field.mines -= lost
	for fleet in state.fleets.duplicate():
		if fleet.stacks.is_empty():
			FleetOrders.delete_fleet(state, fleet, fleet.owner)


## Planets inside the field (`Minefield_Radius@1100:01a0`, which counts them).
static func planets_inside(state: GameState, field: Minefield) -> int:
	var n := 0
	for pl in state.planets:
		if _distance2(pl.x, pl.y, field) <= field.mines:
			n += 1
	return n


static func _distance2(x: int, y: int, field: Minefield) -> int:
	return (x - field.x) * (x - field.x) + (y - field.y) * (y - field.y)
