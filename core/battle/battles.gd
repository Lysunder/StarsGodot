class_name Battles
extends RefCounted
## The turn's battles (spec S16): at the start of the waypoint 1 step, every place where hostile
## fleets meet fights a battle in turn; each is recorded in `state.battles`, then its results
## follow (S16 "Battle results"): the messages, the tech bonus tries, an Alternate Reality planet
## emptied by the loss of its starbase, and the "fought this turn" marks. Destroyed fleets go when
## all are done.

## The battle's loss table (per owner × 16 + design slot): BattleEngine.LOSS_HIT, LOSS_LEFT (ships
## left) and the ships killed in the low bits.
const LOSS_LEFT := 0x4000
const LOSS_KILLED := 0x1FFF
const SLOTS := 16
const STARBASE_SLOT := 16
## A design as the messages name it: owner × 32 + slot.
const DESIGN_REF := 32
## An Alternate Reality race that loses more colonists (hundreds) than this gets the "many" text.
const MANY_COLONISTS := 1000
const TWO := 2
const FLEET_WORD := 512


## Fights every battle of the turn. `rng` is the classic stream; `fixes` gives the draws of fix
## B36 that the original does not make.
static func run_all(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fixes: StarsRandom
) -> void:
	state.battles = []
	var index := 0
	for group in BattleSetup.places(state):
		var battle := BattleSetup.gather(state, content, group)
		if battle.is_empty():
			continue
		var place := _place(state, battle, group, BattleSetup.battle_id(state.turn, index))
		if place.starbase_owner >= 0 and battle.players & (1 << place.starbase_owner):
			state.planet(battle.planet).starbase.fought = true
		for fleet: Fleet in battle.fleets:
			fleet.fought = true
		var tokens := BattleSetup.tokens(state, content, rng, battle)
		var start: Array = []
		for t in tokens:
			start.append(BattleEngine.token_record(t).duplicate(true))
		var engine := BattleEngine.new(state, content, rng, battle, tokens)
		var events := engine.run()
		var players: Array[int] = []
		for p in state.players.size():
			if battle.players & (1 << p):
				players.append(p)
		(
			state
			. battles
			. append(
				{
					"id": place.id,
					"sides": battle.sides,
					"players": players,
					"planet": battle.planet,
					"x": battle.x,
					"y": battle.y,
					"tokens": start,
					"events": events,
				}
			)
		)
		index += 1
		finish(state, content, rng, fixes, battle, group, engine, place)
	for fleet in state.fleets.duplicate():
		if fleet.stacks.is_empty():
			FleetOrders.delete_fleet(state, fleet, fleet.owner, true)


## What the results need from before the battle: its id, the starbase's owner (-1 for none) and
## slot, and the ships and designs (per owner) at the place, the starbase counting when its owner
## takes part (`ResolveBattle@10e8:58c0`).
static func _place(state: GameState, battle: Dictionary, group: Array, id: int) -> Dictionary:
	var planet: Planet = state.planet(battle.planet) if battle.planet >= 0 else null
	var out := {"id": id, "starbase_owner": -1, "starbase_slot": 0, "ships": 0, "designs": 0}
	var designs := {}
	for fleet: Fleet in group:
		for stack in fleet.stacks:
			if stack.count > 0:
				out.ships += stack.count
				designs[fleet.owner * SLOTS + stack.design] = true
	out.designs = designs.size()
	if planet != null and planet.starbase != null:
		out.starbase_owner = planet.owner
		out.starbase_slot = planet.starbase.design
		if battle.players & (1 << planet.owner):
			out.ships += 1
			out.designs += 1
	return out


## `FinishBattle@10e8:62bc`: an Alternate Reality planet whose starbase was destroyed is emptied;
## then, in player order, each player's message about the battle and its try at learning from the
## ships lost (`TryTechBonus@10e8:6112`, S24).
static func finish(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	fixes: StarsRandom,
	battle: Dictionary,
	group: Array,
	engine: BattleEngine,
	place: Dictionary
) -> void:
	var planet: Planet = state.planet(battle.planet) if battle.planet >= 0 else null
	var where: Array = [-1, planet.id] if planet != null else [battle.x, battle.y]
	var starbase_owner: int = place.starbase_owner
	var colonists := -1
	if planet != null and engine.starbase_destroyed:
		var race := state.player(starbase_owner).race
		if RaceMath.trait_param(race, content, "colony.starbase", 0):
			colonists = planet.population
			PlanetEconomy.depopulate(planet, race, content)
	var table: Dictionary = engine.losses.duplicate()
	for fleet: Fleet in group:
		for stack in fleet.stacks:
			if stack.count > 0:
				var key := fleet.owner * SLOTS + stack.design
				table[key] = table.get(key, 0) | LOSS_LEFT
	var keys := table.keys()
	keys.sort()
	var ctx := {
		"state": state,
		"content": content,
		"battle": battle,
		"group": group,
		"engine": engine,
		"place": place,
		"table": table,
		"keys": keys,
		"where": where,
		"goto": {"battle": place.id},
	}
	for p in state.players.size():
		var player := state.player(p)
		if battle.players & (1 << p):
			if colonists >= 0:
				var type := "habitat_destroyed"
				if p == starbase_owner:
					type = "habitat_lost_many" if colonists > MANY_COLONISTS else "habitat_lost"
				_send(ctx, p, type, [_starbase_ref(place), colonists])
				continue
			var learns := _report(ctx, p)
			if learns and (planet == null or planet.owner < 0 or planet.owner == p):
				_try(ctx, rng, player, "tech_gained")
		elif planet != null and planet.owner == p:
			TurnMessages.add(
				state,
				content,
				p,
				"message.battle.seen_from_planet",
				{"planet": planet.id},
				[planet.id]
			)
			_try(ctx, rng, player, "tech_gained_orbit")
		else:
			var watcher := _first_fleet(group, p)
			if watcher == null:
				continue
			TurnMessages.add(
				state,
				content,
				p,
				"message.battle.seen_by_fleet",
				{"fleet": watcher.number, "owner": watcher.owner},
				[watcher.owner * FLEET_WORD + watcher.number] + where
			)
			# fix B36: the original tests the bystander mask against the player's number
			_try(ctx, rng if battle.bystanders & p else fixes, player, "tech_gained_watching")


## A tech bonus try and, when it gains something, its message (goto research).
static func _try(ctx: Dictionary, rng: StarsRandom, player: Player, type: String) -> void:
	var state: GameState = ctx.state
	var engine: BattleEngine = ctx.engine
	var gained := TechGain.try_bonus(player, engine.tech_seen, ctx.content, rng)
	if gained <= 0:
		return
	var field := gained - 1
	var amount := ResearchRules.level_cost(player, field, ctx.content, state.settings.slow_tech)
	TurnMessages.add(
		state,
		ctx.content,
		player.index,
		"message.battle." + type,
		{"research": true},
		ctx.where + [field, amount]
	)


## Player p's message about the battle (S16 "Battle messages"); returns whether p may learn from
## it (in a battle of two sides, only when something of p's is left).
static func _report(ctx: Dictionary, p: int) -> bool:
	var battle: Dictionary = ctx.battle
	var place: Dictionary = ctx.place
	var table: Dictionary = ctx.table
	var own := -1
	var enemy := -1
	var race := -1
	var own_lost := 0
	var enemy_lost := 0
	for key: int in ctx.keys:
		if table[key] == 0:
			continue
		if key / SLOTS == p:
			own = key
			own_lost += table[key] & LOSS_KILLED
		else:
			enemy = key
			race = key / SLOTS
			enemy_lost += table[key] & LOSS_KILLED
	if battle.sides == TWO and place.ships == TWO:
		return _duel(ctx, p, own, enemy)
	if battle.sides == TWO and place.designs == TWO:
		return _stacks(ctx, p, own, enemy)
	var engine: BattleEngine = ctx.engine
	var starbase_owner: int = place.starbase_owner
	var own_total := own_lost
	var enemy_total := enemy_lost
	for fleet: Fleet in ctx.group:
		if fleet.owner == p:
			own_total += fleet.ship_count()
		else:
			enemy_total += fleet.ship_count()
	if starbase_owner == p:
		own_total += 1
		if engine.starbase_destroyed:
			own_lost += 1
	elif starbase_owner >= 0:
		enemy_total += 1
		race = starbase_owner
		if engine.starbase_destroyed:
			enemy_lost += 1
	if race < 0:
		# no other side's ships in the table: the original shows the planet's owner
		race = (ctx.state as GameState).planet(battle.planet).owner if battle.planet >= 0 else p
	var own_ref := _starbase_ref(place) if starbase_owner == p else _ref(own)
	var enemy_ref := _starbase_ref(place) if race == starbase_owner else _ref(enemy)
	var type := ""
	var params: Array = [race]
	if battle.sides == TWO:
		if enemy_lost == enemy_total:
			if enemy_total == 1:
				if own_lost == 0:
					type = "won_one"
					params += [own_total, enemy_ref]
				else:
					type = "won_one_with_losses"
					params += [own_total, enemy_ref, own_lost]
			elif own_lost == 0:
				if own_total == 1:
					type = "one_won"
					params += [own_ref, enemy_lost]
				else:
					type = "won"
					params += [own_total]
			else:
				type = "won_with_losses"
				params += [own_total, own_lost]
		elif own_lost == own_total:
			if own_lost == 1:
				if enemy_lost == 0:
					type = "lost_one"
					params += [own_ref, enemy_total]
				else:
					type = "lost_one_with_kills"
					params += [own_ref, enemy_total, enemy_lost]
			elif enemy_lost == 0:
				if enemy_total == 1:
					type = "lost_to_one"
					params += [own_lost, enemy_ref]
				else:
					type = "lost"
					params += [enemy_total]
			else:
				type = "lost_with_kills"
				params += [enemy_total, enemy_lost]
		elif own_total == 1:
			type = "one_drawn"
			params += [own_ref, enemy_total, enemy_lost]
		elif enemy_total == 1:
			type = "drawn_against_one"
			params += [own_total, enemy_ref, own_lost]
		else:
			type = "drawn"
			params += [own_total, enemy_total, own_lost, enemy_lost]
	else:
		params = [battle.sides]
		if own_lost == 0 and enemy_lost == enemy_total:
			type = "melee_won"
			params += [own_total]
		elif own_lost == 0 or (enemy_lost == 0 and own_lost != own_total):
			type = "melee"
			params += [own_lost, own_total, enemy_lost, enemy_total]
		elif enemy_lost == 0:
			type = "melee_lost"
			params += [own_total, enemy_total]
		elif enemy_lost == enemy_total:
			type = "melee_won_with_losses"
			params += [own_lost, own_total]
		elif own_lost == own_total:
			type = "melee_lost_with_kills"
			params += [own_total, enemy_total, enemy_lost]
		else:
			type = "fought"
			params = []
	_send(ctx, p, type, params)
	return battle.sides != TWO or own_total != own_lost


## One ship (or starbase) against one: `own` and `enemy` are loss table keys, -1 for the starbase.
static func _duel(ctx: Dictionary, p: int, own: int, enemy: int) -> bool:
	var type := "duel_drawn"
	var learns := true
	if _gone(ctx, own, true):
		type = "duel_lost_to_damaged" if _hit(ctx, enemy) else "duel_lost"
		learns = false
	elif _gone(ctx, enemy, true):
		type = "duel_won_damaged" if _hit(ctx, own) else "duel_won"
	_send(ctx, p, type, [_key_ref(ctx, own), _key_ref(ctx, enemy)])
	return learns


## One design's ships (or a starbase) against another's.
static func _stacks(ctx: Dictionary, p: int, own: int, enemy: int) -> bool:
	var table: Dictionary = ctx.table
	var own_count: int = 1 if own < 0 else table[own] & LOSS_KILLED
	var enemy_count: int = 1 if enemy < 0 else table[enemy] & LOSS_KILLED
	# the original adds every other fleet's ships of the enemy's slot, whoever owns them
	for fleet: Fleet in ctx.group:
		if fleet.owner == p and own >= 0:
			own_count += _slot_count(fleet, own % SLOTS)
		elif enemy >= 0:
			enemy_count += _slot_count(fleet, enemy % SLOTS)
	var type := "stacks_drawn"
	var learns := true
	if _gone(ctx, own, false):
		type = "stacks_lost_to_damaged" if _hit(ctx, enemy) else "stacks_lost"
		learns = false
	elif _gone(ctx, enemy, false):
		type = "stacks_won_damaged" if _hit(ctx, own) else "stacks_won"
	var params := [_key_ref(ctx, own), own_count, _key_ref(ctx, enemy), enemy_count]
	_send(ctx, p, type, params)
	return learns


## Whether the side of `key` (-1: the starbase) was destroyed: in a duel, when it lost a ship; else
## when none of its ships are left.
static func _gone(ctx: Dictionary, key: int, duel: bool) -> bool:
	if key < 0:
		return (ctx.engine as BattleEngine).starbase_destroyed
	var entry: int = ctx.table[key]
	return entry & LOSS_KILLED != 0 if duel else entry & LOSS_LEFT == 0


static func _hit(ctx: Dictionary, key: int) -> bool:
	if key < 0:
		return (ctx.engine as BattleEngine).starbase_damaged
	return ctx.table[key] & BattleEngine.LOSS_HIT != 0


static func _key_ref(ctx: Dictionary, key: int) -> int:
	return _starbase_ref(ctx.place) if key < 0 else _ref(key)


static func _ref(key: int) -> int:
	return (key / SLOTS) * DESIGN_REF + key % SLOTS if key >= 0 else 0


static func _starbase_ref(place: Dictionary) -> int:
	return maxi(place.starbase_owner, 0) * DESIGN_REF + STARBASE_SLOT + place.starbase_slot


static func _send(ctx: Dictionary, p: int, type: String, params: Array) -> void:
	TurnMessages.add(
		ctx.state, ctx.content, p, "message.battle." + type, ctx.goto, ctx.where + params
	)


static func _slot_count(fleet: Fleet, slot: int) -> int:
	var stack := fleet.stack_for(slot)
	return stack.count if stack != null else 0


static func _first_fleet(group: Array, p: int) -> Fleet:
	for fleet: Fleet in group:
		if fleet.owner == p:
			return fleet
	return null
