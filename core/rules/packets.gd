class_name Packets
extends RefCounted
## Mineral packets and salvage (spec S14): launching packets from a mass driver, their flight,
## decay and impact, and dropping salvage, with its yearly decay.
##
## Not yet: loading from and unloading into salvage and packets, salvage from battles (S16), and
## Packet Physics terraforming on impact.

## A speed setting below this means "the driver's own speed".
const SPEED_SETTING_MIN := 5
## The fastest launch is the best driver part's speed plus this.
const OVERDRIVE_MAX := 3
## Packet minerals are 16-bit: launches and merges stop here.
const MINERAL_MAX := 32760
const MINERAL_OVERFLOW := 32767
## A packet launched this year keeps absorbing launches while its mass is below this (tens of kT).
const MERGE_TENTHS_LIMIT := 1630
## Yearly decay per class, in percent, and the least a decaying mineral loses.
const DECAY_RATES := [0, 10, 25, 50]
const DECAY_MIN := 10
const YEAR_PCT := 100
const HALF_YEAR_PCT := 50
## Impact: shares are per mille; uncaught minerals land at a ninth; damage divisor.
const SHARE := 1000
const LANDING_DIVISOR := 9
const DAMAGE_DIVISOR := 160
const DEFENSE_DIVISOR := 20
const DEFENSE_ROLL := 20
## A planetary defense's `defense` stat is in tenths of a percent.
const DEFENSE_SCALE := 0.001
## Salvage: a pile holds at most this many tens of kT; empty salvage gets random(10) of each.
const PILE_TENTHS_MAX := 3000
const EMPTY_SALVAGE_ROLL := 10
const SALVAGE_DECAY_DIVISOR := 10
const SALVAGE_DECAY_MIN := 10
const MINERALS := ["ironium", "boranium", "germanium"]
## The `space_object` message parameter of a packet or salvage pile: kind 1 above owner and number.
const OBJECT_KIND_PACKET := 8192
const OWNER_SHIFT := 512


## A planet's mass driver (`Planet_GetMassDriverWarp@1040:4f76`): [the best driver part's speed,
## 1 when another slot holds a driver of that same speed]; [0, 0] without an owner or starbase.
static func driver(state: GameState, content: ContentRegistry, planet: Planet) -> Array[int]:
	if planet.owner < 0 or planet.starbase == null:
		return [0, 0]
	var design := state.player(planet.owner).starbase_design(planet.starbase.design)
	if design == null:
		return [0, 0]
	var best := 0
	var pair := 0
	for s in design.parts:
		if s.count == 0 or s.part.is_empty():
			continue
		var w: int = content.part(s.part).get("stats", {}).get("driver_warp", 0)
		if w > best:
			best = w
			pair = 0
		elif w == best and w > 0:
			pair = 1
	return [best, pair]


## Before spending (S09 step 4.2): a packet item needs a driver and a target.
static func can_build(state: GameState, content: ContentRegistry, planet: Planet) -> bool:
	return driver(state, content, planet)[0] > 0 and planet.mass_driver_target >= 0


## `units` of a packet item completed at `planet` (S14 "Launching"): a new packet, or more minerals
## in the packet launched there this year toward the same target at the same speed.
static func launch(
	state: GameState, content: ContentRegistry, planet: Planet, def: Dictionary, units: int
) -> void:
	var owner := state.player(planet.owner)
	var drv := driver(state, content, planet)
	if drv[0] == 0:
		_planet_message(state, content, planet, "production.packet_lost_no_driver", [planet.id])
		return
	var target := planet.mass_driver_target
	if target < 0:
		_planet_message(state, content, planet, "production.packet_lost_no_target", [planet.id])
		return
	var minerals: Array[int] = [0, 0, 0]
	var kind: String = def.get("mineral", "mixed")
	var per_unit := RaceMath.trait_param(
		owner.race,
		content,
		"production.mixed_packet_minerals" if kind == "mixed" else "production.packet_minerals",
		40 if kind == "mixed" else 100
	)
	for m in 3:
		if kind == "mixed" or MINERALS[m] == kind:
			minerals[m] = mini(per_unit * units, MINERAL_MAX)
	var speed := planet.mass_driver_warp
	if speed < SPEED_SETTING_MIN or speed > drv[0] + OVERDRIVE_MAX:
		speed = drv[0] + drv[1]
	var overdrive := maxi(speed - drv[0] - drv[1], 0)
	var decay := overdrive
	if overdrive < OVERDRIVE_MAX:
		decay += RaceMath.trait_param(owner.race, content, "packet.decay_class_bonus", 0)
	for p in state.packets:
		if (
			p.owner == planet.owner
			and not p.salvage
			and p.x == planet.x
			and p.y == planet.y
			and p.warp == speed
			and p.destination == target
			and p.decay == decay
			and p.mass_tenths < MERGE_TENTHS_LIMIT
		):
			p.mass_tenths = 0
			for m in 3:
				p.minerals[m] += minerals[m]
				if p.minerals[m] > MINERAL_OVERFLOW:
					p.minerals[m] = MINERAL_MAX
				p.mass_tenths += (p.minerals[m] + 9) / 10
			_planet_message(state, content, planet, "production.packet_merged", [planet.id, target])
			return
	var created := state.add_packet(
		planet.owner, false, content.constant("constant.limits.space_object_numbers")
	)
	if created == null:
		_planet_message(state, content, planet, "production.packet_removed", [planet.id])
		return
	created.x = planet.x
	created.y = planet.y
	created.minerals = minerals
	for m in 3:
		created.mass_tenths += (minerals[m] + 9) / 10
	created.warp = speed
	created.decay = decay
	created.destination = target
	_planet_message(state, content, planet, "production.packet_launched", [planet.id, target])


## S02 phase 8 (`after_production` false: every packet in flight moves a full year) and phase 14
## (true: the packets launched this year move half a year), in space-object order (S14 "Flight").
static func move_all(
	state: GameState, content: ContentRegistry, rng: StarsRandom, after_production: bool
) -> void:
	for packet: Packet in state.packets.duplicate():
		if packet.salvage or (after_production and packet.fresh):
			continue
		if packet.minerals[0] == 0 and packet.minerals[1] == 0 and packet.minerals[2] == 0:
			state.packets.erase(packet)
			continue
		packet.fresh = true
		var move := packet.warp * packet.warp
		if after_production:
			move /= 2
		var target := state.planet(packet.destination)
		var dx := target.x - packet.x
		var dy := target.y - packet.y
		var d := sqrt(float(dx * dx + dy * dy))
		if int(d) > move:
			var f := float(move) / d
			var x := packet.x + int(dx * f + (0.5 if dx > 0 else -0.5))
			var y := packet.y + int(dy * f + (0.5 if dy > 0 else -0.5))
			if x != target.x or y != target.y:
				packet.x = x
				packet.y = y
				if after_production:
					decay(state, content, packet, HALF_YEAR_PCT)
				continue
		var pct := clampi(Minefields._mul_div(int(d), YEAR_PCT, move), 0, YEAR_PCT)
		if after_production:
			pct /= 2
		if decay(state, content, packet, pct):
			continue
		_impact(state, content, rng, packet, target)
		state.packets.erase(packet)


## A packet decays for `pct` percent of a year (`Minefield_Decay@10b0:4166`). True when it is gone.
static func decay(state: GameState, content: ContentRegistry, packet: Packet, pct: int) -> bool:
	if packet.decay == 0:
		return false
	var race := state.player(packet.owner).race
	var rate: int = (
		DECAY_RATES[packet.decay]
		* RaceMath.trait_param(race, content, "packet.decay_pct", YEAR_PCT)
		/ YEAR_PCT
	)
	var least := RaceMath.trait_param(race, content, "packet.decay_min", DECAY_MIN)
	var total := 0
	for m in 3:
		var amount := packet.minerals[m]
		if amount != 0:
			var lost := (amount * rate * pct / (YEAR_PCT * YEAR_PCT)) & 0xFFFF
			lost = mini(maxi(lost, least), amount)
			packet.minerals[m] = amount - lost
			total += packet.minerals[m]
	if total == 0:
		state.packets.erase(packet)
		return true
	packet.mass_tenths = (total + 9) / 10
	return false


## S02 phase 11: packets in flight decay a full year; salvage decays a tenth (a fresh pile only
## stops being fresh).
static func decay_all(state: GameState, content: ContentRegistry) -> void:
	for packet: Packet in state.packets.duplicate():
		if not packet.salvage:
			decay(state, content, packet, YEAR_PCT)
			continue
		if packet.fresh:
			packet.fresh = false
			continue
		var total := 0
		for m in 3:
			if packet.minerals[m] != 0:
				var lost := maxi(packet.minerals[m] / SALVAGE_DECAY_DIVISOR, SALVAGE_DECAY_MIN)
				packet.minerals[m] = maxi(packet.minerals[m] - lost, 0)
				total += packet.minerals[m]
		if total == 0:
			state.packets.erase(packet)
		else:
			packet.mass_tenths = (total + 9) / 10


## S14 "Impact": the target's driver catches its share, the minerals land, and what wasn't caught
## kills colonists and destroys defenses.
static func _impact(
	state: GameState, content: ContentRegistry, rng: StarsRandom, packet: Packet, planet: Planet
) -> void:
	var drv := driver(state, content, planet)
	var catch := drv[0] + drv[1]
	# S15: a Packet Physics packet sees the starbase whose driver catches it in full
	var sender := state.player(packet.owner).race
	if catch > 0 and RaceMath.trait_param(sender, content, "packet.reveals_catcher", 0):
		var base := state.player(planet.owner).starbase_design(planet.starbase.design)
		if base != null:
			base.revealed_to[packet.owner] = true
	var caught := catch * catch
	if planet.owner >= 0:
		var race := state.player(planet.owner).race
		caught = (
			caught * RaceMath.trait_param(race, content, "packet.catch_pct", YEAR_PCT) / YEAR_PCT
		)
	var speed := packet.warp * packet.warp
	var share := 0
	var k := catch
	if caught >= speed:
		share = SHARE
	elif catch > 0:
		k = caught
		share = caught * SHARE / speed
	var landing := (SHARE - share) / LANDING_DIVISOR + share
	var total := 0
	for m in 3:
		var amount := maxi(packet.minerals[m], 0)
		total += amount
		planet.surface[m] += amount * landing / SHARE
	var params := [planet.id, packet.owner, total]
	if share == SHARE:
		_planet_message(state, content, planet, "planet.packet_caught", params)
		return
	var damage := (speed - k) * total / DAMAGE_DIVISOR
	if planet.owner < 0:
		return
	var race := state.player(planet.owner).race
	damage = int(_uncovered(state, content, planet) * damage)
	if damage == 0 or RaceMath.trait_param(race, content, "packet.no_damage", 0):
		var type := "planet.packet_caught" if k > 0 else "planet.packet_harmless"
		_planet_message(state, content, planet, type, params)
		return
	var killed := maxi(_int32(planet.population * damage) / SHARE, damage)
	if killed < 0 or killed >= planet.population:
		_planet_message(
			state, content, planet, "planet.packet_wiped_out", [planet.id, packet.owner]
		)
		PlanetEconomy.depopulate(planet, race, content)
		return
	var destroyed := planet.defenses * damage / SHARE
	if destroyed == 0 and planet.defenses != 0:
		destroyed = 1 if rng.random(DEFENSE_ROLL) < damage else 0
	destroyed = mini(maxi(destroyed, damage / DEFENSE_DIVISOR), planet.defenses)
	var said := [planet.id, total, packet.owner, killed]
	if destroyed == 0:
		var type := "planet.packet_damage_partly_caught" if k > 0 else "planet.packet_damage"
		_planet_message(state, content, planet, type, said)
	else:
		var type := (
			"planet.packet_damage_defenses_partly_caught"
			if k > 0
			else "planet.packet_damage_defenses"
		)
		_planet_message(state, content, planet, type, said + [destroyed])
	planet.defenses -= destroyed
	planet.population -= killed


## The share of a packet's damage the planet's defenses don't stop (`Planet_DefenseCoverage`):
## (1 - best x 0.001)^n as a 32-bit float, n the operable defenses; 1 without defenses.
static func _uncovered(state: GameState, content: ContentRegistry, planet: Planet) -> float:
	if planet.defenses == 0:
		return 1.0
	var owner := state.player(planet.owner)
	var best := PartRules.best_part("planetary", "defense", owner, content)
	if best.is_empty():
		return 1.0
	var value: int = content.part(best).get("stats", {}).get("defense", 0)
	var n := mini(planet.defenses, PlanetEconomy.operable_defenses(planet, owner.race))
	var single := PackedFloat32Array([pow(1.0 - value * DEFENSE_SCALE, n)])
	return single[0]


## Wraps a product to 32 bits, as the original's long arithmetic does.
static func _int32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## S14 "Salvage" (`DropSalvage@10e8:183a`): `amounts` (three minerals) left by `owner` at a point,
## onto `pile` when given, else onto a new pile; full piles spill into new ones. Returns the last
## pile, or null (on a planet's position, or no free number).
static func drop_salvage(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	owner: int,
	x: int,
	y: int,
	amounts: Array[int],
	pile: Packet = null
) -> Packet:
	for pl in state.planets:
		if pl.x == x and pl.y == y:
			return null
	var left := amounts.duplicate()
	var total: int = left[0] + left[1] + left[2]
	while total == 0:
		for m in 3:
			left[m] = rng.random(EMPTY_SALVAGE_ROLL)
		total = left[0] + left[1] + left[2]
	var limit := content.constant("constant.limits.space_object_numbers")
	if pile == null:
		pile = _new_pile(state, owner, x, y, limit)
		if pile == null:
			return null
	else:
		for m in 3:
			left[m] += pile.minerals[m]
			total += pile.minerals[m]
			pile.minerals[m] = 0
		pile.mass_tenths = 0
	pile.fresh = true
	while total >= 1:
		for m in 3:
			if pile.mass_tenths * 10 + left[m] <= PILE_TENTHS_MAX * 10:
				pile.mass_tenths += (left[m] + 9) / 10
				pile.minerals[m] += left[m]
				total -= left[m]
				left[m] = 0
			else:
				var take := (PILE_TENTHS_MAX - pile.mass_tenths) * 10
				pile.mass_tenths = PILE_TENTHS_MAX
				pile.minerals[m] += take
				left[m] -= take
				total -= take
				pile = _new_pile(state, owner, x, y, limit)
				if pile == null:
					return null
			if total < 1:
				break
	return pile


static func _new_pile(state: GameState, owner: int, x: int, y: int, limit: int) -> Packet:
	var pile := state.add_packet(owner, true, limit)
	if pile != null:
		pile.x = x
		pile.y = y
	return pile


## How many more kT a packet or pile takes from a transfer (`TransferCargo@1048:3aec`): the
## rounding room of its recorded mass, `mass_tenths` x 10 minus its minerals.
static func slack(packet: Packet) -> int:
	return packet.mass_tenths * 10 - packet.minerals[0] - packet.minerals[1] - packet.minerals[2]


## The salvage pile at exactly this point (any owner's), or null.
static func salvage_at(state: GameState, x: int, y: int) -> Packet:
	for p in state.packets:
		if p.salvage and p.x == x and p.y == y:
			return p
	return null


## A packet or salvage pile as a `space_object` message parameter (S21).
static func object_word(packet: Packet) -> int:
	return OBJECT_KIND_PACKET + packet.owner * OWNER_SHIFT + packet.number


static func goto_of(packet: Packet) -> Dictionary:
	return {"packet": packet.number, "owner": packet.owner}


static func _planet_message(
	state: GameState, content: ContentRegistry, planet: Planet, type: String, params: Array
) -> void:
	TurnMessages.add(state, content, planet.owner, "message." + type, {"planet": planet.id}, params)
