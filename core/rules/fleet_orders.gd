class_name FleetOrders
extends RefCounted
## Fleet orders (spec S11 "Fleet orders"): splitting a fleet, moving ships between fleets with
## their cargo, fuel and damage, merging fleets, and deleting a fleet (waypoints that target it are
## retargeted).

const PERCENT := 100


## A new empty fleet at the fleet's place with a copy of its waypoints, repeat setting and battle
## plan; null at the fleet limit.
static func split(state: GameState, content: ContentRegistry, fleet: Fleet) -> Fleet:
	var created := state.add_fleet(
		fleet.owner, content.constant("constant.limits.fleets_per_player")
	)
	if created == null:
		return null
	created.x = fleet.x
	created.y = fleet.y
	created.planet = fleet.planet
	for wp in fleet.waypoints:
		created.waypoints.append(wp.copy() as Waypoint)
	created.repeat = fleet.repeat
	created.battle_plan = fleet.battle_plan
	return created


## Moves ships between two fleets of one owner at one place. `ships` maps design slot to count:
## positive from `b` to `a`, negative from `a` to `b`, each limited to what the giver has. Cargo,
## fuel and damage follow the ships; a fleet left without ships is deleted (S11).
static func move_ships(
	state: GameState, content: ContentRegistry, a: Fleet, b: Fleet, ships: Dictionary, player: int
) -> void:
	var owner := state.player(a.owner)
	var fleets: Array[Fleet] = [a, b]
	# Per fleet: [fuel capacity, cargo capacity, fuel capacity lost, cargo capacity lost].
	var caps := [[0, 0, 0, 0], [0, 0, 0, 0]]
	for f in 2:
		for stack in fleets[f].stacks:
			var design := owner.ship_design(stack.design)
			caps[f][0] += stack.count * PartRules.fuel_capacity(design, content)
			caps[f][1] += stack.count * PartRules.cargo_capacity(design, content)
	var designs: Array = ships.keys()
	designs.sort()
	for design: int in designs:
		var giver := 1 if ships[design] > 0 else 0
		var from := fleets[giver].stack_for(design)
		if from == null:
			continue
		var n := mini(absi(ships[design]), from.count)
		if n == 0:
			continue
		var d := owner.ship_design(design)
		caps[giver][2] += n * PartRules.fuel_capacity(d, content)
		caps[giver][3] += n * PartRules.cargo_capacity(d, content)
		_move_stack(fleets[giver], fleets[1 - giver], from, n)
	var losses := [_cargo_lost(a, caps[0]), _cargo_lost(b, caps[1])]
	for f in 2:
		for c in Fleet.CARGO_FUEL + 1:
			fleets[f].cargo[c] -= losses[f][c]
			fleets[1 - f].cargo[c] += losses[f][c]
	for f in fleets:
		if f.ship_count() == 0:
			delete_fleet(state, f, player)


## Moves n ships of one stack from `giver` to `receiver`, damaged ships first (S11 "Damage after a
## ship move", with fix B32), and their share of `paid`.
static func _move_stack(giver: Fleet, receiver: Fleet, from: ShipStack, n: int) -> void:
	var c := from.count
	var d := from.damaged_percent * c / PERCENT
	var to := receiver.stack_for(from.design)
	var c2 := to.count if to != null else 0
	var d2 := to.damaged_percent * c2 / PERCENT if to != null else 0
	var e2 := to.damage if to != null else 0
	to = receiver.add_ships(from.design, n)
	var m := mini(n, d)
	if d == 0:
		if d2 > 0:
			to.damaged_percent = _ceil_div(d2 * PERCENT, to.count)
	elif d2 == 0:
		to.damage = from.damage
		to.damaged_percent = _ceil_div(m * PERCENT, to.count)
	else:
		to.damage = _ceil_div(from.damage * m + e2 * d2, m + d2)
		to.damaged_percent = _ceil_div((m + d2) * PERCENT, to.count)
	for i in from.paid.size():
		var share := from.paid[i] * n / c
		from.paid[i] -= share
		to.paid[i] += share
	from.count -= n
	if d > 0:
		if m == d:
			from.damaged_percent = 0
			from.damage = 0
		else:
			from.damaged_percent = _ceil_div((d - m) * PERCENT, from.count)
	if from.count == 0:
		giver.stacks.erase(from)


## What a fleet loses of each cargo type to the other fleet, from its cargo before the move and
## the capacity it gave away (S11 "Cargo after a ship move").
static func _cargo_lost(fleet: Fleet, caps: Array) -> Array[int]:
	var lost: Array[int] = [0, 0, 0, 0, 0]
	if caps[0] != 0:
		lost[Fleet.CARGO_FUEL] = caps[2] * fleet.cargo[Fleet.CARGO_FUEL] / caps[0]
	if caps[1] == 0:
		return lost
	var total := 0
	for c in Fleet.CARGO_FUEL:
		total += fleet.cargo[c]
	var left: int = caps[3] * total / caps[1]
	if left == 0 or total == 0:
		return lost
	for c in Fleet.CARGO_FUEL:
		var take := mini(left * fleet.cargo[c] / total, left)
		lost[c] += take
		left -= take
	for c in Fleet.CARGO_FUEL:
		if left <= 0:
			break
		if fleet.cargo[c] - lost[c] > 0:
			lost[c] += 1
			left -= 1
	return lost


## Merges `others` into `target`: ships, cargo and `paid` are added, damage combined per design,
## and the merged fleets deleted (S11 "fleet_merge").
static func merge(state: GameState, target: Fleet, others: Array[Fleet], player: int) -> void:
	var damaged := {}
	var total := {}
	var all: Array[Fleet] = [target]
	all.append_array(others)
	for f in all:
		for stack in f.stacks:
			if stack.count == 0 or (stack.damaged_percent == 0 and stack.damage == 0):
				continue
			var k := maxi(stack.damaged_percent * stack.count / PERCENT, 1)
			damaged[stack.design] = damaged.get(stack.design, 0) + k
			total[stack.design] = total.get(stack.design, 0) + k * stack.damage
	for f in others:
		for stack in f.stacks:
			var to := target.add_ships(stack.design, stack.count)
			for i in stack.paid.size():
				to.paid[i] += stack.paid[i]
		for c in Fleet.CARGO_FUEL + 1:
			target.cargo[c] += f.cargo[c]
		delete_fleet(state, f, player)
	for stack in target.stacks:
		var k: int = damaged.get(stack.design, 0)
		if k == 0 or stack.count == 0:
			stack.damaged_percent = 0
			stack.damage = 0
		else:
			stack.damaged_percent = _ceil_div(k * PERCENT, stack.count)
			stack.damage = total[stack.design] / k


## A deleted ship design takes its ships out of every fleet of the owner (S11 `design_delete`):
## the cargo and fuel that went with their capacity are lost, and a fleet left without ships is
## deleted. Damage of the other ships is unchanged.
static func remove_design_ships(
	state: GameState, content: ContentRegistry, owner: int, slot: int
) -> void:
	var player := state.player(owner)
	var fleets: Array[Fleet] = state.fleets_of(owner)
	for fleet in fleets:
		var stack := fleet.stack_for(slot)
		if stack == null or stack.count <= 0:
			continue
		if fleet.stacks.size() == 1:
			delete_fleet(state, fleet, owner)
			continue
		var caps := [0, 0, 0, 0]
		for s in fleet.stacks:
			var design := player.ship_design(s.design)
			caps[0] += s.count * PartRules.fuel_capacity(design, content)
			caps[1] += s.count * PartRules.cargo_capacity(design, content)
		var gone := player.ship_design(slot)
		caps[2] = stack.count * PartRules.fuel_capacity(gone, content)
		caps[3] = stack.count * PartRules.cargo_capacity(gone, content)
		var lost := _cargo_lost(fleet, caps)
		for c in Fleet.CARGO_FUEL + 1:
			fleet.cargo[c] -= lost[c]
		fleet.stacks.erase(stack)


## Removes a fleet; waypoints of other fleets that target it now target what is at its position:
## another fleet (the first of `preferred_owner`, else the first in fleet order), else the planet,
## else deep space (S11 "Deleting a fleet").
static func delete_fleet(state: GameState, fleet: Fleet, preferred_owner: int) -> void:
	state.remove_fleet(fleet)
	var here: Fleet = null
	for f in state.fleets:
		if f.x == fleet.x and f.y == fleet.y:
			if here == null or (here.owner != preferred_owner and f.owner == preferred_owner):
				here = f
	for f in state.fleets:
		for wp in f.waypoints:
			if (
				wp.target != "fleet"
				or wp.target_owner != fleet.owner
				or wp.target_id != fleet.number
			):
				continue
			if here != null:
				wp.target_owner = here.owner
				wp.target_id = here.number
			elif fleet.planet >= 0:
				wp.target = "planet"
				wp.target_owner = -1
				wp.target_id = fleet.planet
			else:
				wp.target = "none"
				wp.target_owner = -1
				wp.target_id = -1


static func _ceil_div(a: int, b: int) -> int:
	return (a + b - 1) / b


## A fleet's main design (`Fleet_MainDesign@1030:27e4`): the design with the most ships, the
## first slot on ties; a hull tagged `fuel_transport` counts one ship less. Returns [slot, how
## many designs the fleet has]; slot 16 for an empty fleet.
static func main_design(fleet: Fleet, owner: Player, content: ContentRegistry) -> Array[int]:
	var best := 16
	var best_count := 0
	var kinds := 0
	for slot in 16:
		var stack := fleet.stack_for(slot)
		var n := 0 if stack == null else stack.count
		if n <= 0:
			continue
		kinds += 1
		if n > best_count:
			best = slot
			best_count = n
			var design := owner.ship_design(slot)
			var tags: Array = content.hull(design.hull).get("tags", []) if design != null else []
			if tags.has("fuel_transport"):
				best_count = n - 1
	return [best, kinds]


## A fleet as a "described" message parameter (S21 `fleet_designs`, `Fleet_MsgRef`): number +
## 512 x main design slot, + 8192 when it has more than one design.
static func designs_word(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var main := main_design(fleet, owner, content)
	return fleet.number + 512 * main[0] + (8192 if main[1] > 1 else 0)


## The cargo the lost ships' capacity held is lost, as when ships move to another fleet (S11).
## Returns what was lost, per cargo type.
static func cargo_after_losses(
	fleet: Fleet, owner: Player, content: ContentRegistry, lost: Dictionary
) -> Array[int]:
	var caps := [0, 0, 0, 0]
	var counts := {}
	for stack in fleet.stacks:
		counts[stack.design] = stack.count
	for slot: int in lost:
		counts[slot] = counts.get(slot, 0) + int(lost[slot])
	for slot: int in counts:
		var design := owner.ship_design(slot)
		var n: int = counts[slot]
		var gone: int = lost.get(slot, 0)
		caps[0] += n * PartRules.fuel_capacity(design, content)
		caps[1] += n * PartRules.cargo_capacity(design, content)
		caps[2] += gone * PartRules.fuel_capacity(design, content)
		caps[3] += gone * PartRules.cargo_capacity(design, content)
	var losses := _cargo_lost(fleet, caps)
	for c in Fleet.CARGO_FUEL + 1:
		fleet.cargo[c] -= losses[c]
	return losses
