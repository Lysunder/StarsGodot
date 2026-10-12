class_name BattleSetup
extends RefCounted
## Who fights and how battles start (spec S16 "Who fights", "Tokens"): fleets grouped by place,
## each group's sides, then the battle's tokens on their starting squares, shuffled.
##
## A token is a Dictionary in the shape of the battle recording (S16 "The recording").

const STARBASE := 1
const SHIPS := 2
const BOARD := "battle_board.standard"
## Ship classes (the tactic's high four bits, S16 "Tokens").
const CLASS_ARMED := 3
const CLASS_BOMBER := 4
const CLASS_OTHER := 5
const CLASS_FUEL := 6
const CLASS_FREIGHTER := 7
const STARBASE_TACTIC := 5
const STARBASE_TARGETS := 0x11
const NONE := 255
const NO_RANGE := 15
const MAX_INITIATIVE := 63
const DAMAGED_ALL := 100
const STARBASE_MASS := 65535
## Torpedo jamming: product start, rounding, cap.
const JAM_START := 10000
const JAM_MAX := 95
const BEAM_PCT_START := 1000
const BEAM_DAMAGE_MAX := 2550
## Movement: engine speeds count from warp 1-9 below this fuel use; mass per movement point.
const FUEL_LIMIT := 121
const MOVE_BASE := 4
const MOVE_MAX := 8
const MASS_PER_MOVE := 70
const JITTER := 15
const DAMPENER_SLOW := 4
## State bits.
const ALIVE := 1
const TACHYON := 2
const TORPEDOES := 4
const REGENERATES := 8
const STARTED := 16
const COUNTDOWN_SHIFT := 5
const DISENGAGE_COUNTDOWN := 7
const JITTER_SHIFT := 10
const PCT := 100


## S16 "Places": fleets with ships grouped by position, in the order of each group's first fleet;
## the first fleet leads, the others follow in reverse fleet order.
static func places(state: GameState) -> Array[Array]:
	var by_place := {}
	var out: Array[Array] = []
	for fleet in state.fleets:
		if fleet.ship_count() == 0:
			continue
		var key := Vector2i(fleet.x, fleet.y)
		if by_place.has(key):
			(by_place[key] as Array).insert(1, fleet)
		else:
			var group: Array[Fleet] = [fleet]
			by_place[key] = group
			out.append(group)
	return out


## S16 "Hostility": the battle at a group's place, or {} when there is none. The result holds the
## place, `sides`, the `players` present and `fighting` (bit masks), `attack` (per player) and the
## `fleets` in the battle (group order).
static func gather(state: GameState, content: ContentRegistry, group: Array) -> Dictionary:
	var n := state.players.size()
	var attack: Array[int] = []
	attack.resize(n)
	attack.fill(0)
	var present := 0
	var bystanders := 0
	var head: Fleet = group[0]
	var planet: Planet = state.planet(head.planet) if head.planet >= 0 else null
	if planet != null:
		if planet.starbase == null:
			if planet.owner >= 0:
				bystanders |= 1 << planet.owner
		else:
			var owner := state.player(planet.owner)
			present |= 1 << planet.owner
			var who := _who(BattlePlans.plan(owner, 0))
			var design := owner.starbase_design(planet.starbase.design)
			if design != null and is_armed(design, content) and who != 0:
				_attack(state, attack, planet.owner, who)
	var armed_attacker := false
	for fleet: Fleet in group:
		present |= 1 << fleet.owner
		var plan := BattlePlans.plan(state.player(fleet.owner), fleet.battle_plan)
		var who := _who(plan)
		if (
			int(plan.get("primary_target", 0)) != 0
			and who != 0
			and _fleet_armed(state, content, fleet)
		):
			armed_attacker = true
			_attack(state, attack, fleet.owner, who)
	if not armed_attacker:
		return {}
	var fighting := 0
	for p in n:
		fighting |= present & attack[p]
	if fighting == 0:
		return {}
	for i in n:
		if attack[i] & fighting:
			fighting |= 1 << i
		if fighting & (1 << i):
			for j in n:
				if attack[j] & (1 << i):
					attack[i] |= 1 << j
	var changed := true
	while changed:
		changed = false
		for fleet: Fleet in group:
			var o := fleet.owner
			var bit := 1 << o
			if not present & bit or fighting & bit:
				continue
			attack[o] = 0
			var relations := state.player(o).relations
			for q in n:
				if q == o or q >= relations.size() or relations[q] != "friend":
					continue
				if not fighting & (1 << q):
					continue
				if attack[o] & (1 << q):
					attack[o] = 0
					break
				attack[o] |= attack[q]
			if attack[o] == 0:
				present &= ~bit
			else:
				fighting |= bit
			changed = true
	var fleets: Array[Fleet] = []
	for fleet: Fleet in group:
		if present & (1 << fleet.owner):
			fleets.append(fleet)
		else:
			bystanders |= 1 << fleet.owner
	return {
		"planet": head.planet,
		"x": head.x,
		"y": head.y,
		"sides": _bits(fighting),
		"players": present,
		"fighting": fighting,
		"bystanders": bystanders,
		"attack": attack,
		"fleets": fleets,
	}


## S16 "Tokens": the battle's tokens, shuffled (draws from `rng`). Fleets whose plan says so drop
## their cargo first; `pile` collects the battle's salvage in deep space.
static func tokens(
	state: GameState, content: ContentRegistry, rng: StarsRandom, battle: Dictionary
) -> Array[Dictionary]:
	var board: Dictionary = content.get_def("battle_board", BOARD)
	var sides: int = battle.sides
	var squares: Array = (board.start_squares as Array)[sides - 1] if sides > 0 else []
	var side_of := {}
	var k := 0
	for p in state.players.size():
		if battle.players & (1 << p):
			side_of[p] = k
			k += 1
	var out: Array[Dictionary] = []
	var dampener := false
	var planet: Planet = state.planet(battle.planet) if battle.planet >= 0 else null
	if planet != null and planet.starbase != null and battle.players & (1 << planet.owner):
		var t := _starbase_token(state, content, planet, _square(squares, side_of[planet.owner]))
		dampener = dampener or t.dampener
		out.append(t.token)
	var pile: Packet = null
	for fleet: Fleet in battle.fleets:
		var owner := state.player(fleet.owner)
		var plan := BattlePlans.plan(owner, fleet.battle_plan)
		var dumped := false
		if plan.get("dump_cargo", false):
			var dropped := _dump_cargo(state, content, rng, fleet, pile)
			dumped = dropped[0]
			if dropped[1] != null:
				pile = dropped[1]
		for stack in fleet.stacks:
			if stack.count <= 0:
				continue
			var t := _ship_token(
				state, content, rng, fleet, stack, _square(squares, side_of[fleet.owner]), dumped
			)
			dampener = dampener or t.dampener
			out.append(t.token)
	for i in out.size():
		var j := i + rng.random(out.size() - i)
		if j != i:
			var swap := out[i]
			out[i] = out[j]
			out[j] = swap
	for token in out:
		token.state |= ALIVE | STARTED
		if token.initiative_low == NONE:
			token.targets &= 0xF0
		var race := state.player(token.owner).race
		if token.shields != 0 and RaceMath.trait_param(race, content, "battle.shield_regen", 0):
			token.state |= REGENERATES
		else:
			token.state &= ~REGENERATES
		if dampener and token.kind != STARBASE:
			token.movement = maxi(token.movement - DAMPENER_SLOW, 0)
	return out


## The battle's number in this turn (S16 "Battle number"): `index` counts from 0.
static func battle_id(turn: int, index: int) -> int:
	return (turn * 256 + 1 + index) % 4096


## Whether a design has a weapon (`Design_IsArmed@10e8:158a`).
static func is_armed(design: Design, content: ContentRegistry) -> bool:
	for slot in design.parts:
		if slot.count > 0 and not slot.part.is_empty():
			if content.part(slot.part).get("category", "") in ["beam", "torpedo"]:
				return true
	return false


static func _fleet_armed(state: GameState, content: ContentRegistry, fleet: Fleet) -> bool:
	var owner := state.player(fleet.owner)
	for stack in fleet.stacks:
		if stack.count > 0 and is_armed(owner.ship_design(stack.design), content):
			return true
	return false


static func _who(plan: Dictionary) -> int:
	return int(plan.get("attack", 0)) & BattlePlans.ATTACK_MASK


## A plan's "attack who" (S16 "Hostility" 3) applied to player `p`'s attacks.
static func _attack(state: GameState, attack: Array[int], p: int, who: int) -> void:
	match who:
		BattlePlans.ATTACK_ENEMIES, BattlePlans.ATTACK_NOT_FRIENDS:
			var relations := state.player(p).relations
			for q in state.players.size():
				if q == p:
					continue
				var r: String = relations[q] if q < relations.size() else "neutral"
				if r == "enemy" or (r == "neutral" and who == BattlePlans.ATTACK_NOT_FRIENDS):
					attack[p] |= 1 << q
		BattlePlans.ATTACK_EVERYONE:
			attack[p] = ~(1 << p)
		_:
			attack[p] |= 1 << (who - BattlePlans.ATTACK_PLAYER)


static func _bits(mask: int) -> int:
	var count := 0
	while mask != 0:
		count += mask & 1
		mask >>= 1
	return count


static func _square(squares: Array, k: int) -> int:
	if k >= squares.size():
		return 0
	var xy: Array = squares[k]
	return int(xy[0]) + 16 * int(xy[1])


## The starbase's token (S16 "The starbase").
static func _starbase_token(
	state: GameState, content: ContentRegistry, planet: Planet, square: int
) -> Dictionary:
	var owner := state.player(planet.owner)
	var design := owner.starbase_design(planet.starbase.design)
	var token := _blank(planet.owner, STARBASE, 16 + planet.starbase.design, square)
	token.erase("fleet")
	token.erase("fleet_owner")
	token["planet"] = planet.id
	token.count = 1
	var damage := planet.starbase.damage
	token.damage = damage << 7 | (DAMAGED_ALL if damage > 0 else 0)
	var dampener := _stats(token, design, owner, content, true)
	token.targets = STARBASE_TARGETS
	token.tactic = CLASS_ARMED << 4 | STARBASE_TACTIC
	token.mass = STARBASE_MASS
	token.movement = 0
	return {"token": token, "dampener": dampener}


## A ship stack's token (S16 "Ships").
static func _ship_token(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	fleet: Fleet,
	stack: ShipStack,
	square: int,
	dumped: bool
) -> Dictionary:
	var owner := state.player(fleet.owner)
	var design := owner.ship_design(stack.design)
	var token := _blank(fleet.owner, SHIPS, stack.design, square)
	token.fleet = fleet.number
	token.fleet_owner = fleet.owner
	token.count = stack.count
	token.damage = stack.damage << 7 | stack.damaged_percent
	var dampener := _stats(token, design, owner, content, false)
	var plan := BattlePlans.plan(owner, fleet.battle_plan)
	var ship_class := _class(design, content)
	token.targets = int(plan.get("primary_target", 0)) | int(plan.get("secondary_target", 0)) << 4
	var tactic := int(plan.get("tactic", 0)) & 15 if ship_class == CLASS_ARMED else 0
	token.tactic = ship_class << 4 | tactic
	if tactic == 0:
		token.state = (
			token.state & ~(0x1F << COUNTDOWN_SHIFT) | DISENGAGE_COUNTDOWN << COUNTDOWN_SHIFT
		)
	token.movement = _movement(state, content, rng, fleet, design, token, dumped)
	return {"token": token, "dampener": dampener}


static func _blank(owner: int, kind: int, design: int, square: int) -> Dictionary:
	return {
		"fleet": 0,
		"fleet_owner": 0,
		"owner": owner,
		"kind": kind,
		"design": design,
		"square": square,
		"computer_initiative": 0,
		"initiative_low": NONE,
		"initiative_high": NONE,
		"torpedo_jamming": 0,
		"torpedo_accuracy": 0,
		"beam_damage_pct": 0,
		"beam_defense_pct": PCT,
		"mass": 0,
		"shields": 0,
		"count": 0,
		"damage": 0,
		"targets": 0,
		"tactic": 0,
		"ranges": NONE,
		"movement": 0,
		"state": 0,
	}


## Computer initiative, accuracy, weapons, jamming, beam percents and shields
## (`Token_InitStats`, `Token_ComputeWeapons`); returns whether the design has an Energy Dampener.
static func _stats(
	token: Dictionary, design: Design, owner: Player, content: ContentRegistry, starbase: bool
) -> bool:
	var hull_initiative := int(content.hull(design.hull).get("initiative", 0))
	var computers := 0
	var accuracy := 0
	for slot in design.parts:
		if slot.count <= 0 or slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var stats: Dictionary = part.get("stats", {})
		var weapon: bool = part.get("category", "") in ["beam", "torpedo"]
		if not weapon:
			computers += slot.count * int(stats.get("initiative", 0))
		var share := int(stats.get("torpedo_accuracy", 0))
		if share > 0:
			for i in slot.count:
				accuracy += (PCT - accuracy) * share / PCT
	var bonus := mini(hull_initiative + computers, MAX_INITIATIVE)
	token.computer_initiative = bonus
	token.torpedo_accuracy = accuracy
	var low := -1
	var high := -1
	var near := -1
	var far := -1
	var jam := JAM_START
	var beam_damage := BEAM_PCT_START
	var beam_defense := BEAM_PCT_START
	var dampener := false
	for slot in design.parts:
		if slot.count <= 0 or slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var stats: Dictionary = part.get("stats", {})
		var tags: Array = part.get("tags", [])
		var category: String = part.get("category", "")
		var jamming := int(stats.get("jamming", 0))
		var boost := int(stats.get("beam_damage_pct", 0))
		var deflect := int(stats.get("beam_deflection", 0))
		for i in slot.count:
			if jamming > 0:
				jam = jam * (PCT - jamming) / PCT
			if boost > 0:
				beam_damage = (boost + PCT) * beam_damage / PCT
			if deflect > 0:
				beam_defense = (PCT - deflect) * beam_defense / PCT
		dampener = dampener or tags.has("energy_dampener")
		if tags.has("tachyon_detector"):
			token.state |= TACHYON
		if category not in ["beam", "torpedo"]:
			continue
		if category == "torpedo":
			token.state |= TORPEDOES
		var initiative := mini(int(stats.get("initiative", 0)) + bonus, MAX_INITIATIVE)
		var reach := int(stats.get("range", 0)) + (1 if starbase else 0)
		near = reach if near < 0 or reach < near else near
		far = maxi(far, reach)
		low = initiative if low < 0 or initiative < low else low
		high = maxi(high, initiative)
	if jam != JAM_START:
		token.torpedo_jamming = mini(PCT - (jam + 50) / PCT, JAM_MAX)
	if starbase:
		token.torpedo_jamming -= token.torpedo_jamming >> 2
	if beam_damage != BEAM_PCT_START:
		token.beam_damage_pct = mini(beam_damage, BEAM_DAMAGE_MAX) / 10
	token.beam_defense_pct = beam_defense / 10
	token.ranges = (near & 15) << 4 | (far & 15)
	token.initiative_low = low & 0xFF
	token.initiative_high = high & 0xFF
	token.shields = PartRules.shields(design, content, owner.race)
	return dampener


## Ship class (`Token_SetClass@10e8:15f0`).
static func _class(design: Design, content: ContentRegistry) -> int:
	if is_armed(design, content):
		return CLASS_ARMED
	for slot in design.parts:
		if slot.count <= 0 or slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var tags: Array = part.get("tags", [])
		if part.get("category", "") == "bomb" or tags.has("orbital_construction"):
			return CLASS_BOMBER
		if slot.part == "part.beam.multi_contained_munition":
			return CLASS_BOMBER
	if content.hull(design.hull).get("tags", []).has("fuel_transport"):
		return CLASS_FUEL
	if PartRules.cargo_capacity(design, content) > 0:
		return CLASS_FREIGHTER
	return CLASS_OTHER


## Battle movement (`Design_BattleMovement@10e8:216e`); sets the token's mass and weight jitter.
static func _movement(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	fleet: Fleet,
	design: Design,
	token: Dictionary,
	dumped: bool
) -> int:
	var base := _engine_move(design, content)
	var engines: int = base[1]
	if engines == 0:
		return 0
	var owner := state.player(fleet.owner)
	var move: int = base[0]
	move += RaceMath.trait_param(owner.race, content, "battle.movement_bonus", 0)
	var mass := PartRules.mass(design, content)
	var capacity := PartRules.cargo_capacity(design, content)
	if capacity > 0:
		var fleet_capacity := 0
		for stack in fleet.stacks:
			if stack.count > 0:
				fleet_capacity += (
					stack.count * PartRules.cargo_capacity(owner.ship_design(stack.design), content)
				)
		var cargo := 0
		for c in Fleet.CARGO_FUEL:
			cargo += fleet.cargo[c]
		if fleet_capacity > 0:
			mass += cargo * capacity / fleet_capacity
		if dumped:
			move -= 1
	token.state |= rng.random(JITTER) << JITTER_SHIFT
	token.mass = mass
	move -= mass / MASS_PER_MOVE / engines
	return clampi(move, 0, MOVE_MAX)


## A design's battle movement on its own, without a fleet (no race bonus, no cargo, no draw): what
## the ship rating uses (S20 `Design_Evaluate`, which calls `Design_BattleMovement` without one).
static func design_movement(design: Design, content: ContentRegistry) -> int:
	var base := _engine_move(design, content)
	var engines: int = base[1]
	if engines == 0:
		return 0
	var move: int = base[0] - PartRules.mass(design, content) / MASS_PER_MOVE / engines
	return clampi(move, 0, MOVE_MAX)


## [the engines' speed plus movement parts, less MOVE_BASE; the first engine slot's count] (0
## engines: no movement).
static func _engine_move(design: Design, content: ContentRegistry) -> Array[int]:
	var engine := ""
	var engines := 0
	var halves := 0
	var extra := 0
	for slot in design.parts:
		if slot.count <= 0 or slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var stats: Dictionary = part.get("stats", {})
		if part.get("category", "") == "engine" and engine.is_empty():
			engine = slot.part
			engines = slot.count
		halves += slot.count * int(stats.get("battle_move_halves", 0))
		extra += slot.count * int(stats.get("battle_move", 0))
	if engine.is_empty() or engines == 0:
		return [0, 0]
	var engine_part := content.part(engine)
	var speed := 10
	if not engine_part.get("tags", []).has("warp10_safe"):
		var table: Array = engine_part.get("fuel_table", [])
		speed = 9
		while speed > 0 and int(table[speed]) >= FUEL_LIMIT:
			speed -= 1
	return [speed + extra + (halves + 1) / 2 - MOVE_BASE, engines]


## `Fleet_DumpCargo@10e8:173e`: a fleet with minerals aboard drops them onto the planet, or as
## salvage in deep space. Returns [dumped, the battle's salvage pile].
static func _dump_cargo(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet, pile: Packet
) -> Array:
	var minerals: Array[int] = [fleet.cargo[0], fleet.cargo[1], fleet.cargo[2]]
	if minerals[0] == 0 and minerals[1] == 0 and minerals[2] == 0:
		return [false, null]
	if fleet.planet >= 0:
		var planet := state.planet(fleet.planet)
		for m in 3:
			planet.surface[m] += minerals[m]
	else:
		pile = Packets.drop_salvage(
			state, content, rng, fleet.owner, fleet.x, fleet.y, minerals, pile
		)
	for m in 3:
		fleet.cargo[m] = 0
	return [true, pile]
