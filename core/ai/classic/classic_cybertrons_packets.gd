class_name ClassicCybertronsPackets
extends RefCounted
## Cybertrons' mineral packets (spec S22 "Cybertrons", packets; `AI_Cybertrons_PlanPackets`):
## each starbase planet feeds a short planet near by, throws packets at another player's planet,
## or throws one toward a map sector (`AI_ChoosePacketTarget`).

const C := preload("res://core/ai/classic/classic_cybertrons.gd")
const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")

var c: ClassicCybertrons
var w: ClassicWorld
## The sector target chosen last in this pass (`local_13c`), -1 none yet.
var _sector_target := -1


## `AI_Cybertrons_PlanPackets`: each of the player's starbase planets (the own-planet order)
## feeds a short planet near by, throws packets at another player's planet, or throws one toward
## a map sector (spec S22 "Cybertrons", packets).
static func plan(brain: ClassicCybertrons) -> void:
	var k := ClassicCybertronsPackets.new()
	k.c = brain
	k.w = brain.w
	k._plan()


func _plan() -> void:
	for planet in w.own_planets:
		if planet.starbase == null:
			continue
		w.select_planet(planet.id)
		C.P.open(w)
		var changed := _packets_at(planet)
		C.P.commit(w, changed)


func _packets_at(planet: Planet) -> bool:
	var out := C.P.output(w, planet)
	var cost := C.P.queue_cost(w, planet)
	var a := c.a_word(planet.id)
	if a & C.A_LONG_THROW == 0 and C.fort(planet):
		var rich := false
		for m in 3:
			if planet.surface[m] > C.PACKET_RICH:
				rich = true
		if rich:
			var n := (out[3] / 2) / 5
			var target: Planet = null
			if n >= C.PACKET_FEED_MIN:
				target = C.F.nearest_planet(
					w, planet.id, func(p: Planet) -> bool: return _feedable(planet, p)
				)
			if target != null:
				return _feed(planet, target, n)
	if a & C.A_LONG_THROW == 0 and (c.level >= 2 or (c.level == 1 and w.rng.random(3) == 0)):
		var left := out.duplicate()
		for m in 3:
			left[m] -= cost[m]
		var spare: int = left[0] + left[1] + left[2] - C.PACKET_SPARE
		var half := _s16(out[3] / 2)
		var throw := _s16(half - 5) / 5 * C.PACKET_KG
		var amount := mini(throw, spare)
		w.memory[2 * c.planet_count + 1] = amount & 0xFFFF
		w.memory[2 * c.planet_count + 2] = (amount >> 16) & 0xFFFF
		var target: Planet = null
		if spare >= C.PACKET_ATTACK_SPARE:
			target = C.F.nearest_planet(
				w, planet.id, func(p: Planet) -> bool: return _attackable(planet, p)
			)
		if target != null:
			return _attack(planet, target, left, amount)
	return _sector(planet)


## A 16-bit signed value, as the original keeps it.
static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## The feed: up to C.PACKET_FEED_MAX packets of each mineral the target is short of and this planet
## has over C.PACKET_RICH, at the slower of the two drivers.
func _feed(planet: Planet, target: Planet, n: int) -> bool:
	var limit := C.SHORT_FORT if C.fort(target) else C.SHORT_STATION
	var changed := false
	for m in 3:
		if target.surface[m] < limit and planet.surface[m] > C.PACKET_RICH:
			var k := mini(n, C.PACKET_FEED_MAX)
			C.P.add(w, C.P.standard(C.P.PACKETS[m]), k, C.P.Mode.TOP)
			n -= k
			c.set_b_word(target.id, c.b_word(target.id) & ~C.B_SHORT[m])
			changed = true
	if not changed:
		return false
	var mine := Packets.driver(w.state, w.content, planet)
	var theirs := Packets.driver(w.state, w.content, target)
	_set_driver(planet, target.id, mini(mine[0] + mine[1], theirs[0] + theirs[1]))
	return true


## `Pred` at 10a0:2882: one of the player's starbase planets with no packet timer, short of a
## mineral `from` has over C.PACKET_RICH, within 3.5 light years per square of the slower driver.
func _feedable(from: Planet, p: Planet) -> bool:
	if p.owner != w.player or p.starbase == null or c.a_word(p.id) & C.A_TIMER != 0:
		return false
	var short := false
	for m in 3:
		if from.surface[m] > C.PACKET_RICH and c.b_word(p.id) & C.B_SHORT[m] != 0:
			short = true
			break
	if not short:
		return false
	var mine := Packets.driver(w.state, w.content, from)
	var theirs := Packets.driver(w.state, w.content, p)
	var speed := mini(mine[0] + mine[1], theirs[0] + theirs[1])
	# (3.5 x speed^2)^2 against the distance squared
	var reach := speed * speed * C.FEED_REACH[0]
	return reach * reach >= C.F.d2(from.x, from.y, p.x, p.y) * C.FEED_REACH[1] * C.FEED_REACH[1]


## The catcher speed at `p` (its driver and pair; 0 without a starbase).
func _catcher(p: Planet) -> int:
	if p.starbase == null:
		return 0
	var drv := Packets.driver(w.state, w.content, p)
	return drv[0] + drv[1]


## The kilograms of packets that empty planet `p` (its population estimate and defense class) at
## `speed` against `catcher`: the original's float quotient truncated, its hit kept in 16 bits.
static func _packets_needed(p: Planet, speed: int, catcher: int) -> int:
	var people := mini((p.population_estimate & 0xFFF) * 4 + 100, 1000)
	var hit := (((speed * speed - catcher * catcher) & 0xFFFF) * (95 - p.defense_estimate)) & 0xFFFF
	if hit == 0:
		return 0x7FFFFFFF
	var scaled := people * C.HIT_SCALE
	# the scale is a hair over 1/C.HIT_SCALE: an exact quotient comes out one less
	return scaled / hit - (1 if scaled % hit == 0 else 0)


## `Pred` at 10a0:29da: another player's planet with no packet timer, whose owner takes drops,
## without a starbase or with a space dock, not catching at the throw speed, within 2.5 light
## years per square of it, that the stored throw (less its decay on the way) can empty.
func _attackable(from: Planet, p: Planet) -> bool:
	if p.owner == w.player or p.owner == -1 or c.a_word(p.id) & C.A_TIMER != 0:
		return false
	if RaceMath.trait_param(w.state.player(p.owner).race, w.content, "ai.no_colonist_drops", 0):
		return false
	if p.starbase != null:
		var sb := w.state.player(p.owner).starbase_design(p.starbase.design)
		if sb == null or sb.hull != C.SPACE_DOCK:
			return false
	var catcher := _catcher(p)
	var drv := Packets.driver(w.state, w.content, from)
	var speed: int = drv[0] + 3
	if speed == catcher:
		return false
	var d2 := C.F.d2(from.x, from.y, p.x, p.y)
	var s2 := speed * speed
	if d2 * C.ATTACK_REACH[1] * C.ATTACK_REACH[1] > s2 * s2 * C.ATTACK_REACH[0] * C.ATTACK_REACH[0]:
		return false
	if p.population_estimate & 0xFFF == 0:
		return false
	var keep := 0.875 if drv[1] != 0 else 0.75
	var stored := _s16(w.memory[2 * c.planet_count + 1])
	var have := int(pow(keep, sqrt(float(d2)) / s2) * stored)
	return _packets_needed(p, speed, catcher) <= have


## The attack: packets enough to empty the target (at most `amount`), more for the decay on the
## way, of the minerals with the most to spare (`left`); the driver at its top speed plus 3.
func _attack(planet: Planet, target: Planet, left: Array, amount: int) -> bool:
	var drv := Packets.driver(w.state, w.content, planet)
	var catcher := _catcher(target)
	var speed: int = drv[0] + 3
	var s2 := speed * speed
	var d2 := C.F.d2(planet.x, planet.y, target.x, target.y)
	amount = mini(_packets_needed(target, speed, catcher), amount)
	var grow: Array = C.DECAY_PAIR if drv[1] != 0 else C.DECAY_SINGLE
	amount = int(pow(float(grow[0]) / grow[1], sqrt(float(d2)) / s2) * amount)
	var counts := [0, 0, 0]
	while amount > 0:
		var m := 0
		if left[0] < left[1]:
			m = 1
		if left[m] < left[2]:
			m = 2
		counts[m] += 1
		left[m] -= C.PACKET_KG
		amount -= C.PACKET_KG
	for m in 3:
		if counts[m] > 0:
			C.P.add(w, C.P.standard(C.P.PACKETS[m]), counts[m], C.P.Mode.TOP)
	_set_driver(planet, target.id, speed)
	c.set_a_word(target.id, c.a_word(target.id) | C.A_TIMER)
	var a := c.a_word(planet.id)
	if d2 > s2 * s2:
		a |= C.A_LONG_THROW
	c.set_a_word(planet.id, a & ~C.A_SECTOR_SENT)
	return true


## The sector throw: a planet without a throw under way picks a new sector, and one packet goes
## toward the planet there when this planet has a mineral to spare; a planet whose long throw is
## under way only times its target.
func _sector(planet: Planet) -> bool:
	var a := c.a_word(planet.id)
	if a & C.A_SECTOR_SENT != 0 and a & C.A_LONG_THROW == 0:
		c.set_a_word(planet.id, a & ~C.A_SECTOR_SENT)
		return false
	var target := -1
	if a & C.A_LONG_THROW == 0:
		var r := w.rng.random(7)
		var sector := r + 1 if a & C.A_SECTOR == r else r
		a = (a & ~C.A_SECTOR) | (sector & C.A_SECTOR)
		c.set_a_word(planet.id, a)
		_sector_target = choose_packet_target(planet, a & C.A_SECTOR)
		target = _sector_target
		if target == -1:
			return false
	else:
		# S25 B48: the original times the target chosen last in this pass
		target = w.content.ruleset.formula(C.LONG_TARGET).call(
			planet.mass_driver_target, _sector_target
		)
	var changed := false
	var record: int = w.content.ruleset.formula(C.PACKET_RECORD).call(target)
	var word := 1 + record
	if (
		word >= 0
		and word < w.memory.size()
		and w.memory[word] & C.A_TIMER == 0
		and _spare_packet(planet)
	):
		w.memory[word] = (w.memory[word] | C.A_TIMER) & 0xFFFF
		a = c.a_word(planet.id)
		a = (a & ~C.A_SECTOR_SENT) | (C.A_SECTOR_SENT if a & C.A_LONG_THROW == 0 else 0)
		c.set_a_word(planet.id, a)
		changed = true
	else:
		c.set_a_word(planet.id, c.a_word(planet.id) & ~C.A_SECTOR_SENT)
	var drv := Packets.driver(w.state, w.content, planet)
	var speed := drv[0] + 3
	if c.a_word(planet.id) & C.A_LONG_THROW == 0:
		_set_driver(planet, target, speed)
	else:
		c.set_a_word(planet.id, c.a_word(planet.id) & ~C.A_LONG_THROW)
		_set_driver(planet, planet.mass_driver_target, speed)
	return changed


## `AI_PlanetHasSpareResources`: one packet of the mineral with the most to spare after the
## queue, when that is at least C.PACKET_SECTOR_SPARE.
func _spare_packet(planet: Planet) -> bool:
	var out := C.P.output(w, planet)
	var cost := C.P.queue_cost(w, planet)
	var m := 0
	if out[0] - cost[0] < out[1] - cost[1]:
		m = 1
	if out[m] - cost[m] < out[2] - cost[2]:
		m = 2
	if out[m] - cost[m] < C.PACKET_SECTOR_SPARE:
		return false
	C.P.add(w, C.P.standard(C.P.PACKETS[m]), 1, C.P.Mode.TOP)
	return true


## `AI_ChoosePacketTarget`: the point where a line from `planet` in direction `sector` (0 east,
## then by eighths) leaves the map, moved along the edge by a draw and in by a draw within the
## throw's yearly reach; the planet nearest that point, unless it is the player's own or nearer
## than that reach. -1 for none.
func choose_packet_target(planet: Planet, sector: int) -> int:
	var size: int = w.state.settings.universe_width
	var speed := Packets.driver(w.state, w.content, planet)[0] + 3
	var s2 := speed * speed
	var x := planet.x - C.MAP_ORIGIN
	var y := planet.y - C.MAP_ORIGIN
	match sector:
		0:
			x = size
		1:
			if size - x > y:
				x += y
				y = 0
			else:
				y += x - size
				x = size
		2:
			y = 0
		3:
			if y < x:
				x -= y
				y = 0
			else:
				y -= x
				x = 0
		4:
			x = 0
		5:
			if size - x > y:
				y += x
				x = 0
			else:
				x += y - size
				y = size
		6:
			y = size
		7:
			if y < x:
				y += size - x
				x = size
			else:
				x += size - y
				y = size
	# W x 0.3 and W x 0.15 at the x87's precision: both doubles are a hair under, so exact
	# products truncate one lower
	var d := w.rng.random(_under(size * 3, 10)) - _under(size * 3, 20)
	if x == 0 or x == size:
		var spill := 0
		y += d
		if y > size:
			spill = y - size
			y = size
		elif y < 0:
			spill = -y
			y = 0
		if x == 0:
			x += spill
		else:
			x -= spill
	else:
		var spill := 0
		x += d
		if x > size:
			spill = x - size
			x = size
		elif x < 0:
			spill = -x
			x = 0
		if y == 0:
			y += spill
		else:
			y -= spill
	var inward := w.rng.random(s2)
	if y == 0:
		y += inward
	elif y == size:
		y -= inward
	elif x == 0:
		x += inward
	elif x == size:
		x -= inward
	var found := c.nearest_planet_to(x + C.MAP_ORIGIN, y + C.MAP_ORIGIN)
	if found == null or found.owner == w.player:
		return -1
	var reach: int = w.content.ruleset.formula(C.SECTOR_REACH).call(s2)
	if C.F.d2(found.x, found.y, planet.x, planet.y) < reach:
		return -1
	return found.id


## n / d truncated, one lower when exact (n times a double a hair under 1/d).
static func _under(n: int, d: int) -> int:
	return n / d - (1 if n % d == 0 else 0)


## Sets the planet's mass driver target and speed (a `planet_settings` order).
func _set_driver(planet: Planet, target: int, warp: int) -> void:
	planet.mass_driver_target = target
	planet.mass_driver_warp = warp
	(
		w
		. order(
			{
				"type": "planet_settings",
				"planet": planet.id,
				"leftover_to_research": planet.leftover_to_research,
				"mass_driver_target": target,
				"mass_driver_warp": warp,
				"route": planet.route,
			}
		)
	)
