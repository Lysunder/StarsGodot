class_name Terraforming
extends RefCounted
## Terraforming (spec S10): reach from tech, targets toward or away from a race's ideal, single
## steps, the Claim Adjuster's yearly terraforming and remote terraforming by fleets.
##
## Trait parameter: `terraform.instant` (Claim Adjuster). Content: terraforming parts by tag and
## `terraform` value; fleet parts with `remote_terraform`.

const AXIS_TAGS := ["terraform_gravity", "terraform_temperature", "terraform_radiation"]
const TOTAL_TAG := "terraform_total"
const NONE := -1
const MIN_VALUE := 1
const MAX_VALUE := 99


## The reach per axis from the parts `player` can build (S10 step 1).
static func reach(player: Player, content: ContentRegistry) -> Array[int]:
	var order := PartRules.tech_order(content)
	var total := 0
	var axis: Array[int] = [0, 0, 0]
	for id in content.ids("part"):
		var part := content.part(id)
		if part.get("category") != "terraform":
			continue
		var tags: Array = part.get("tags", [])
		var value: int = part.get("stats", {}).get("terraform", 0)
		if not PartRules.available(part, player, order):
			continue
		if tags.has(TOTAL_TAG):
			total = maxi(total, value)
		for i in 3:
			if tags.has(AXIS_TAGS[i]):
				axis[i] = maxi(axis[i], value)
	var out: Array[int] = []
	for i in 3:
		out.append(maxi(total, axis[i]))
	return out


## [low targets, high targets] per axis, NONE for no target (S10 step 2).
static func targets(planet: Planet, race: Race, r: Array[int], improve: bool) -> Array:
	var low: Array[int] = [NONE, NONE, NONE]
	var high: Array[int] = [NONE, NONE, NONE]
	for i in 3:
		if r[i] == 0 or race.is_immune(i):
			continue
		var e := planet.environment[i]
		var o := planet.environment_original[i]
		var lo := o - r[i]
		var hi := o + r[i]
		lo = maxi(lo, MIN_VALUE) if lo < e else NONE
		hi = mini(hi, MAX_VALUE) if e < hi else NONE
		var c := race.hab_center[i]
		if improve:
			if c == e:
				lo = NONE
				hi = NONE
			elif c < e:
				hi = NONE
				if lo != NONE:
					lo = maxi(lo, c)
			else:
				lo = NONE
				if hi != NONE:
					hi = mini(hi, c)
		else:
			var d := absi(e - c)
			var dl := 0 if lo == NONE else absi(lo - c)
			var dh := 0 if hi == NONE else absi(hi - c)
			if d < dl or d < dh:
				if dl < dh:
					lo = NONE
				else:
					hi = NONE
			else:
				lo = NONE
				hi = NONE
		low[i] = lo
		high[i] = hi
	return [low, high]


## Single steps still possible for the planet's owner (S10 step 3).
static func max_steps(planet: Planet, owner: Player, content: ContentRegistry) -> int:
	var t := targets(planet, owner.race, reach(owner, content), true)
	var steps := 0
	for i in 3:
		if t[0][i] != NONE:
			steps += planet.environment[i] - t[0][i]
		if t[1][i] != NONE:
			steps += t[1][i] - planet.environment[i]
	return steps


## One step (S10 step 4): `race` for habitability, `tech` for the reach. Returns false when no axis
## can move.
static func step(
	planet: Planet, race: Race, tech: Player, improve: bool, content: ContentRegistry
) -> bool:
	return step_change(planet, race, tech, improve, content) != 0


## One step, as step(); returns which axis moved and which way: axis + 1, negative when the value
## went down, 0 when no axis could move (the original's `Planet_TerraformStep` result, S21).
static func step_change(
	planet: Planet, race: Race, tech: Player, improve: bool, content: ContentRegistry
) -> int:
	var t := targets(planet, race, reach(tech, content), improve)
	var h0 := Habitability.value(planet.environment, race)
	var best := -1
	var best_score := 0
	for i in 3:
		var target: int = t[0][i] if t[0][i] != NONE else t[1][i]
		if target == NONE:
			continue
		var e := planet.environment[i]
		planet.environment[i] = target
		var h := Habitability.value(planet.environment, race)
		planet.environment[i] = e
		var score := absi(h - h0) * 100 / absi(e - target) + 1
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return 0
	var direction := -1 if t[0][best] != NONE else 1
	planet.environment[best] = clampi(planet.environment[best] + direction, MIN_VALUE, MAX_VALUE)
	return (best + 1) * direction


## S02 phase 19: Claim Adjuster planets change permanently now and then, and terraform at once.
static func claim_adjuster(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	var chance := content.constant("constant.terraform.permanent_chance")
	var population := content.constant("constant.terraform.permanent_population")
	for planet in state.planets:
		if planet.owner < 0:
			continue
		var owner := state.player(planet.owner)
		var race := owner.race
		if not RaceMath.trait_param(race, content, "terraform.instant", 0):
			continue
		var a := rng.random(3)
		var o := planet.environment_original[a]
		if (
			not race.is_immune(a)
			and race.hab_center[a] != o
			and rng.random(chance) == 0
			and (planet.population >= population or rng.random(population) < planet.population)
		):
			planet.environment_original[a] = o - 1 if race.hab_center[a] < o else o + 1
			TurnMessages.add(
				state,
				content,
				planet.owner,
				"message.planet.environment_improved",
				{"planet": planet.id},
				[planet.id, a]
			)
		var t := targets(planet, race, reach(owner, content), true)
		var changed := false
		for i in 3:
			if t[0][i] != NONE:
				planet.environment[i] = t[0][i]
				changed = true
			elif t[1][i] != NONE:
				planet.environment[i] = t[1][i]
				changed = true
		if changed:
			TurnMessages.add(
				state,
				content,
				planet.owner,
				"message.planet.auto_terraformed",
				{"planet": planet.id},
				[planet.id, PlanetEconomy.hab_value(planet, race)]
			)


## S02 phase 20: fleets with remote terraforming parts terraform the planet they are at.
static func remote(state: GameState, content: ContentRegistry) -> void:
	for fleet in state.fleets:
		if fleet.ship_count() == 0 or fleet.planet < 0:
			continue
		var planet := state.planet(fleet.planet)
		if planet == null or planet.owner < 0:
			continue
		var fleet_owner := state.player(fleet.owner)
		var power := _power(fleet, fleet_owner, content)
		if power == 0:
			continue
		var friendly := (
			fleet.owner == planet.owner
			or (
				planet.owner < fleet_owner.relations.size()
				and fleet_owner.relations[planet.owner] == "friend"
			)
		)
		if not friendly and planet.starbase != null:
			continue
		var race := state.player(planet.owner).race
		var before := PlanetEconomy.hab_value(planet, race)
		for k in power:
			if not step(planet, race, fleet_owner, friendly, content):
				break
		var after := PlanetEconomy.hab_value(planet, race)
		var word := fleet.owner * 512 + fleet.number
		var kind := "improved" if friendly else "degraded"
		var goto := {"fleet": fleet.number, "owner": fleet.owner}
		if after != before:
			TurnMessages.add(
				state,
				content,
				fleet.owner,
				"message.fleet.terraform_" + kind,
				goto,
				[word, planet.id, before, after]
			)
		else:
			TurnMessages.add(
				state,
				content,
				fleet.owner,
				"message.fleet.terraform_" + kind + "_stuck",
				goto,
				[word, planet.id, before]
			)
		if fleet.owner != planet.owner and after != before:
			TurnMessages.add(
				state,
				content,
				planet.owner,
				"message.fleet.terraform_" + kind,
				{"planet": planet.id},
				[word, planet.id, before, after]
			)


static func _power(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var power := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design == null or stack.count <= 0:
			continue
		var per_ship := 0
		for slot in design.parts:
			if not slot.part.is_empty():
				per_ship += (
					slot.count
					* int(content.part(slot.part).get("stats", {}).get("remote_terraform", 0))
				)
		power += stack.count * per_ship
	return power
