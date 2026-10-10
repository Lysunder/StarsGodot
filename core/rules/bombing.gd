class_name Bombing
extends RefCounted
## Bombing (`DoBombing@10e8:6e2a`), after the battles of the waypoint 1 step (S02). Not built yet
## beyond which fleets take part, which scanning reads (S15): the bombs themselves come with M9.


## Fleets that would bomb: when one of a player's fleets orbits another player's planet without a
## starbase and its battle plan attacks that player, every fleet of the player at that planet is
## marked (`Bombing_SumFleetBombs@1030:0d6a` marks them all, bombers or not).
static func mark_fleets(state: GameState) -> void:
	for fleet in state.fleets:
		if fleet.at_bombing or fleet.ship_count() == 0 or fleet.planet < 0:
			continue
		var planet := state.planet(fleet.planet)
		if planet.owner < 0 or planet.owner == fleet.owner or planet.starbase != null:
			continue
		if not BattlePlans.attacks(state, fleet, planet.owner):
			continue
		for other in state.fleets:
			if other.owner == fleet.owner and other.planet == fleet.planet:
				other.at_bombing = true
