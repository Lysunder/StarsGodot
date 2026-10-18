class_name ClassicMacintiProduction
extends RefCounted
## Macinti's production pass (spec S22 "Macinti", production): each of the player's starbase
## planets with 200 hundred people throws packets to a poorer driver planet, or queues freighters,
## colony ships, miners, scouts, bombers, warships, genesis devices and nubians.

const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")
const M := preload("res://core/ai/classic/classic_macinti.gd")

const SHIPYARD_POPULATION := 200
const QUEUE_ITEMS_MAX := 24
const PACKET_TURN := 120
const PACKET_DRIVER := 10
const PACKET_POPULATION := 10000
const PACKET_RICH := 5000
const PACKET_FAR2 := 91204
const PACKET_WARP := 11
const PACKET_MAX := 20000
const PACKET_KT := 100
const GENESIS := "production_item.genesis"
const GENESIS_TERRAFORM := 75

var m: ClassicMacinti
var w: ClassicWorld


static func plan(brain: ClassicMacinti) -> void:
	var k := ClassicMacintiProduction.new()
	k.m = brain
	k.w = brain.w
	for planet in brain.w.own_planets:
		k._planet(planet)


func _planet(planet: Planet) -> void:
	if planet.starbase == null or planet.population < SHIPYARD_POPULATION:
		return
	var sb := planet.starbase.design
	if sb == 0 or (sb == 1 and m.turn >= 26):
		return
	w.select_planet(planet.id)
	if planet.queue.size() >= QUEUE_ITEMS_MAX:
		return
	var e := P.open(w)
	for q in e.queue:
		if q.is_design() and not q.starbase:
			P.commit(w, false)
			return
	var res := PlanetEconomy.resources(planet, w.me().race, w.content)
	if _packets(planet, e):
		return
	P.commit(w, _ships(planet, res))


## Packets: from turn PACKET_TURN, a planet with a fast driver and many people (a draw of 1 in 4)
## sends a fifth of a mineral it has over PACKET_RICH of (the first such from a drawn one) to the
## poorest planet in it with a fast driver within reach; the queue is committed at once.
func _packets(planet: Planet, e: P.Edit) -> bool:
	if m.turn <= PACKET_TURN:
		return false
	if Packets.driver(w.state, w.content, planet)[0] < PACKET_DRIVER:
		return false
	if planet.population <= PACKET_POPULATION or w.rng.random(4) != 0:
		return false
	for q in e.queue:
		if not q.is_design() and P.PACKETS.slice(0, 4).has(q.item):
			return false
	var start := w.rng.random(3)
	var k := start
	while k < start + 3 and planet.surface[k % 3] <= PACKET_RICH:
		k += 1
	if k - start == 3:
		return false
	var mineral := k % 3
	var best: Planet = null
	var least := 100000
	for q in w.own_planets:
		if q.surface[mineral] < least and Packets.driver(w.state, w.content, q)[0] >= PACKET_DRIVER:
			if F.d2(planet.x, planet.y, q.x, q.y) < PACKET_FAR2:
				least = q.surface[mineral]
				best = q
	if best == null or least >= planet.surface[mineral] / 5:
		return false
	var n := mini(planet.surface[mineral] / 5, PACKET_MAX) / PACKET_KT
	P.add(w, P.standard(P.PACKETS[mineral]), n, P.Mode.APPEND)
	P.commit(w, true)
	planet.mass_driver_target = best.id
	planet.mass_driver_warp = PACKET_WARP
	(
		w
		. order(
			{
				"type": "planet_settings",
				"planet": planet.id,
				"leftover_to_research": planet.leftover_to_research,
				"mass_driver_target": best.id,
				"mass_driver_warp": PACKET_WARP,
				"route": planet.route,
			}
		)
	)
	return true


## The ships and items a planet adds; whether it added any.
func _ships(planet: Planet, res: int) -> bool:
	var me := w.me()
	var changed := false
	if (
		m.freighter != -1
		and m.freighter_fleets < 64
		and m.freighter_fleets < w.planet_count / 4
		and w.rng.random(3) == 0
	):
		m.freighter_fleets += 1
		P.add(w, P.ship(m.freighter), 1, P.Mode.APPEND)
		changed = true
	var count: int = m.colony["count"]
	if (
		(
			(m.colony["build"] and (count < 41 or (m.turn < 121 and count < 101)))
			or w.rng.random(100) < 8
		)
		and (count < 50 or m.turn < 121)
	):
		for k in 3:
			if planet.surface[k] < 30:
				return changed
		if F.has_nearby_unclaimed(w, planet):
			m.colony["count"] = count + 1
			P.add(w, P.ship(m.colony_slot), 1, P.Mode.APPEND)
			changed = true
			if m.turn < 5:
				return changed
			var rate := (
				me.race.growth_rate
				* RaceMath.trait_param(me.race, w.content, "race.growth_rate_pct", 100)
				/ 100
			)
			var growth := planet.population * rate
			if growth > 2300 and res > 35 and m.level > 0:
				m.colony["count"] = m.colony["count"] + 1
				P.add(w, P.ship(m.colony_slot), 1, P.Mode.APPEND)
				if growth > 3600 and res > 50 and m.level > 1:
					P.add(w, P.ship(m.colony_slot), 1, P.Mode.APPEND)
	var miner := me.ship_design(m.miner) if m.miner != -1 else null
	if miner != null and m.miner_fleets < 60 and miner.remaining < 5000 and w.rng.random(2) == 0:
		var rate := 0
		for f in w.state.fleets:
			if f.planet == planet.id and M.ships(f, m.miner) > 0 and f.owner == w.player:
				rate = WaypointTasks.mining_rate(f, me, w.content)
				break
		if rate < 1001:
			var conc := (
				3 * (planet.concentration[0] + planet.concentration[1] + planet.concentration[2])
			)
			if (rate < conc and conc > 150) or (m.miner_fleets < 30 and w.rng.random(10) != 0):
				m.miner_fleets += 1
				P.add(w, P.ship(m.miner), 1, P.Mode.APPEND)
				changed = true
	var scout := me.ship_design(M.SCOUT_SLOT)
	var frigate: String = w.content.get_def("ai_design_template", M.TEMPLATE + "scout")["hull"]
	var cap_slot: int = w.content.ruleset.formula(M.SCOUT_CAP_DESIGN).call(m.miner)
	var cap := me.ship_design(cap_slot) if cap_slot >= 0 else null
	if (
		scout != null
		and scout.hull == frigate
		and m.scout_fleets < 60
		and (cap == null or cap.remaining < 7500)
		and w.rng.random(4) == 0
	):
		var n := 0
		for f in w.state.fleets:
			if f.planet == planet.id and M.ships(f, M.SCOUT_SLOT) > 0 and f.owner == w.player:
				n = M.ships(f, M.SCOUT_SLOT)
				break
		if (n < 10 or (n < 17 and w.rng.random(10) == 0)) and w.rng.random(n * 2 + 1) == 0:
			m.scout_fleets += 3
			P.add(w, P.ship(M.SCOUT_SLOT), 4, P.Mode.APPEND)
			changed = true
	var lead := 0
	while lead < 3 and planet.surface[lead] > 4999:
		lead += 1
	var rich: bool = w.content.ruleset.formula(M.ALL_RICH).call(lead)
	if m.bomber != -1 and m.warship_fleets < 140 and (m.warship_fleets < 60 or res > 2000):
		var build := m.warship_fleets > 110 and w.rng.random(3) == 0
		if not build:
			for f in w.state.fleets:
				if (
					f.planet == planet.id
					and f.owner == w.player
					and ClassicMacintiFleets.strong(m, f)
				):
					build = M.ships(f, 8) + M.ships(f, 9) < m.troops
					break
		if build:
			m.warship_fleets += 2
			P.add(w, P.ship(m.bomber), 12 if rich else 4, P.Mode.APPEND)
			return true
	if m.genesis_left > 0 and planet.population > 10000:
		var queued := false
		for q in (w.editing as P.Edit).queue:
			if not q.is_design() and q.item == GENESIS:
				queued = true
		if not queued:
			var lead2 := 0
			while lead2 < 3 and planet.surface[lead2] > 1999:
				lead2 += 1
			if not w.content.ruleset.formula(M.ALL_RICH).call(lead2):
				var conc: int = (
					planet.concentration[0] + planet.concentration[1] + planet.concentration[2]
				)
				if (
					conc < 15
					or (conc < 30 and w.rng.random(3) != 0)
					or (conc < 60 and w.rng.random(5) != 0)
				):
					m.genesis_left -= 1
					P.add(w, P.standard(GENESIS), 1, P.Mode.APPEND)
					P.add(w, P.standard(P.TERRAFORM), GENESIS_TERRAFORM, P.Mode.APPEND)
					changed = true
	if (
		m.warship_a != -1
		and m.warship_fleets < 130
		and m.turn > 20
		and (m.warship_fleets < 50 or res > 2000)
		and (rich or w.rng.random(3) == 0)
	):
		var slot := m.warship_a
		if m.warship_b != -1 and w.rng.random(3) == 0:
			slot = m.warship_b
		m.warship_fleets += 1
		P.add(w, P.ship(slot), 10 if rich else 2, P.Mode.APPEND)
		changed = true
		if rich:
			return changed
	if m.nubian != -1:
		var most := 80 if m.turn < 120 else 60
		if m.nubian_fleets < most and m.nubian_ships < 2000:
			var left := P.output(w, planet)
			var cost := P.queue_cost(w, planet)
			for k in 4:
				left[k] -= cost[k]
				if left[k] < 0:
					return changed
			var unit := ProductionCosts.design_cost(me.ship_design(m.nubian), me, w.content)
			var n := 0
			while n < 20:
				var ok := true
				for k in 4:
					left[k] -= unit[k]
					if left[k] < 0:
						ok = false
						break
				if not ok:
					break
				n += 1
			if n > 0:
				P.add(w, P.ship(m.nubian), n, P.Mode.APPEND)
				m.nubian_fleets += 1
				changed = true
	return changed
