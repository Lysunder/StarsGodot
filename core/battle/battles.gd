class_name Battles
extends RefCounted
## The turn's battles (spec S16): at the start of the waypoint 1 step, every place where hostile
## fleets meet fights a battle in turn; each is recorded in `state.battles`, then its results
## follow (S16 "Battle results"): the tech bonus draws, an Alternate Reality planet emptied by the
## loss of its starbase, and the "fought this turn" marks. Destroyed fleets go when all are done.


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
		var planet: Planet = state.planet(battle.planet) if battle.planet >= 0 else null
		var starbase_owner := -1
		if planet != null and planet.starbase != null:
			starbase_owner = planet.owner
			if battle.players & (1 << planet.owner):
				planet.starbase.fought = true
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
					"id": BattleSetup.battle_id(state.turn, index),
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
		finish(state, content, rng, fixes, battle, group, engine, starbase_owner)
	for fleet in state.fleets.duplicate():
		if fleet.stacks.is_empty():
			FleetOrders.delete_fleet(state, fleet, fleet.owner)


## `FinishBattle@10e8:62bc`: an Alternate Reality planet whose starbase was destroyed is emptied;
## then, in player order, who may learn from the ships lost (`TryTechBonus@10e8:6112`, S24).
static func finish(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	fixes: StarsRandom,
	battle: Dictionary,
	group: Array,
	engine: BattleEngine,
	starbase_owner: int
) -> void:
	var planet: Planet = state.planet(battle.planet) if battle.planet >= 0 else null
	var lost_habitat := false
	if planet != null and engine.starbase_destroyed:
		var race := state.player(starbase_owner).race
		if RaceMath.trait_param(race, content, "colony.starbase", 0):
			lost_habitat = true
			PlanetEconomy.depopulate(planet, race, content)
	for p in state.players.size():
		var player := state.player(p)
		if battle.players & (1 << p):
			if lost_habitat:
				continue
			if planet != null and planet.owner >= 0 and planet.owner != p:
				continue
			if battle.sides == 2 and not _has_left(battle, engine, p, starbase_owner):
				continue
			TechGain.try_bonus(player, engine.tech_seen, content, rng)
		elif planet != null and planet.owner == p:
			TechGain.try_bonus(player, engine.tech_seen, content, rng)
		elif _has_fleet(group, p):
			# fix B36: the original tests the bystander mask against the player's number
			var stream := rng if battle.bystanders & p else fixes
			TechGain.try_bonus(player, engine.tech_seen, content, stream)


## Whether player p still has ships in the battle, or its starbase there survived.
static func _has_left(
	battle: Dictionary, engine: BattleEngine, p: int, starbase_owner: int
) -> bool:
	if starbase_owner == p and not engine.starbase_destroyed:
		return true
	for fleet: Fleet in battle.fleets:
		if fleet.owner == p and fleet.ship_count() > 0:
			return true
	return false


static func _has_fleet(group: Array, p: int) -> bool:
	for fleet: Fleet in group:
		if fleet.owner == p:
			return true
	return false
