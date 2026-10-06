class_name Production
extends RefCounted
## Each planet's production for the year (spec S09 steps 3-6): research share, the queue, and
## what completed units do.
##
## Not yet: packets (S14), route following for new fleets (S11), and
## default orders for Alternate Reality miners. Such items are dropped from the queue with a
## warning.

enum Status {
	DONE,
	AUTO_SHARE_BUILT,
	AUTO_SHARE_NONE,
	AUTO_SHORT_BUILT,
	AUTO_SHORT_NONE,
	SOME_BUILT,
	PROGRESS,
	NO_PROGRESS,
}

const AUTO_UNLIMITED := 1000
const MERGE_HEADROOM := 32766
const UNSUPPORTED := ["packet"]


class SpendResult:
	extends RefCounted
	var built := 0
	var status: Status = Status.NO_PROGRESS
	## An item to put at the top of the queue (S09 step 5), or null.
	var carry: QueueItem = null


var _state: GameState
var _content: ContentRegistry
var _rng: StarsRandom


func _init(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	_state = state
	_content = content
	_rng = rng


## Production of one planet (S09 step 3); adds the research resources to `research`.
func run_planet(planet: Planet, research: Array[int]) -> void:
	var owner := planet.owner
	var player := _state.player(owner)
	var r := PlanetEconomy.resources(planet, player.race, _content)
	if planet.queue.is_empty():
		research[owner] += r
		return
	if not planet.leftover_to_research:
		var share := r * player.research_percent / 100
		research[owner] += share
		r -= share
	if r == 0:
		return
	var avail: Array[int] = [planet.surface[0], planet.surface[1], planet.surface[2], r]
	_build_queue(planet, player, avail)
	for m in 3:
		planet.surface[m] = avail[m]
	research[owner] += avail[3]


# --- Step 4: the queue -------------------------------------------------------------------------


func _build_queue(planet: Planet, player: Player, avail: Array[int]) -> void:
	var queue := planet.queue
	var i := 0
	var alchemy_above := false
	while planet.owner >= 0 and i < queue.size():
		var item := queue[i]
		if item.count == 0 or not _buildable(planet, player, item):
			i = _remove(queue, i, alchemy_above)
			alchemy_above = false
			continue
		var def := {} if item.is_design() else _content.get_def("production_item", item.item)
		if def.get("auto", false) and def["effect"] == "alchemy" and i < queue.size() - 1:
			alchemy_above = true
			i += 1
			continue
		var result := _spend(planet, player, item, avail, alchemy_above)
		if result.built > 0:
			if not _complete(planet, player, item, result.built) and not def.get("auto", false):
				item.count = 0
		if planet.owner < 0:
			return
		if result.status == Status.DONE:
			i = _remove(queue, i, alchemy_above)
			alchemy_above = false
		elif result.status <= Status.AUTO_SHORT_NONE:
			i += 1
			alchemy_above = false
		else:
			if result.carry != null:
				queue.insert(0, result.carry)
			return


## Removes item i (and the auto alchemy item above it); returns the index of the next item.
static func _remove(queue: Array[QueueItem], i: int, alchemy_above: bool) -> int:
	var first := i - (1 if alchemy_above else 0)
	for k in i - first + 1:
		queue.remove_at(first)
	return first


## The checks of S09 step 4.2; may lower the count. False: the item is removed.
func _buildable(planet: Planet, player: Player, item: QueueItem) -> bool:
	if item.is_design():
		if item.starbase:
			return player.starbase_design(item.design) != null
		return player.ship_design(item.design) != null
	var def := _content.get_def("production_item", item.item)
	var effect: String = def["effect"]
	if UNSUPPORTED.has(effect):
		push_warning("planet %d: %s items are not implemented yet" % [planet.id, effect])
		return false
	if def.get("auto", false):
		return true
	if effect == "scanner":
		return not planet.has_scanner
	if effect in ["mines", "factories", "defenses", "terraform"]:
		var room := (
			Terraforming.max_steps(planet, player, _content)
			if effect == "terraform"
			else _maximum(planet, player.race, effect) - _built(planet, effect)
		)
		if item.count > room:
			if room <= 0:
				return false
			item.count = room
	return true


func _maximum(planet: Planet, race: Race, effect: String) -> int:
	match effect:
		"mines":
			return PlanetEconomy.max_mines(planet, race, _content)
		"factories":
			return PlanetEconomy.max_factories(planet, race, _content)
	return PlanetEconomy.max_defenses(planet, race)


static func _built(planet: Planet, effect: String) -> int:
	match effect:
		"mines":
			return planet.mines
		"factories":
			return planet.factories
	return planet.defenses


# --- Step 5: spending --------------------------------------------------------------------------


func _spend(
	planet: Planet, player: Player, item: QueueItem, avail: Array[int], alchemy_above: bool
) -> SpendResult:
	var out := SpendResult.new()
	var cost := ProductionCosts.unit_cost(planet, item, player, _content)
	var def := {} if item.is_design() else _content.get_def("production_item", item.item)
	var auto: bool = def.get("auto", false)
	var count := item.count
	if auto:
		var room := maxi(_auto_room(planet, player, def), 0)
		if room < count or def["effect"] == "alchemy":
			count = room
	var progress := item.progress
	var spent: Array[int] = []
	for i in 4:
		spent.append(cost[i] * progress / 100)
	var short_of_minerals := false
	while count > 0:
		var covered := true
		for i in 4:
			if avail[i] < cost[i] - spent[i]:
				covered = false
		if covered:
			for i in 4:
				avail[i] -= cost[i] - spent[i]
				spent[i] = 0
			out.built += 1
			count -= 1
			progress = 0
			continue
		var reach := 100
		var by_mineral := false
		var by_resources := false
		var shortfall := 0
		for i in 4:
			if cost[i] <= 0:
				continue
			var pct := 100
			if avail[i] < cost[i]:
				var t := avail[i] + spent[i]
				pct = maxi((t + 1) * 100 / cost[i] - 1, t * 100 / cost[i])
			if pct < reach:
				reach = pct
				shortfall = cost[i] - spent[i] - avail[i]
				if i == ProductionCosts.RESOURCES:
					by_resources = true
				else:
					by_mineral = true
		if not by_mineral or not auto:
			for i in 4:
				var d := cost[i] * reach / 100 - spent[i]
				avail[i] -= d
				spent[i] += d
			progress = reach
			if not alchemy_above or by_resources:
				break
		elif not alchemy_above:
			short_of_minerals = true
			break
		var rate := ProductionCosts._param(player.race, _content, "production.alchemy_cost")
		var n := mini(avail[3] / rate, shortfall)
		if n > 0:
			for m in 3:
				avail[m] += n
			avail[3] -= n * rate
		if n != shortfall:
			if avail[3] > 0:
				var x := avail[3]
				var carry := QueueItem.new(_alchemy_item(), 1)
				carry.progress = maxi((x + 1) * 100 / rate - 1, x * 100 / rate)
				avail[3] -= carry.progress * rate / 100
				out.carry = carry
			break
	if out.built > 0 and not item.is_design() and def["effect"] == "alchemy":
		for m in 3:
			avail[m] += out.built
	if short_of_minerals:
		out.status = Status.AUTO_SHORT_BUILT if out.built >= 1 else Status.AUTO_SHORT_NONE
	elif not auto or count != 0:
		if out.built != 0:
			out.status = Status.DONE if count == 0 else Status.SOME_BUILT
		else:
			out.status = Status.NO_PROGRESS if progress == item.progress else Status.PROGRESS
	else:
		out.status = Status.AUTO_SHARE_NONE if out.built < 1 else Status.AUTO_SHARE_BUILT
	if not auto:
		item.count = count
		item.progress = progress
	elif out.carry == null and progress != 0:
		out.carry = QueueItem.new(def["builds"], 1)
		out.carry.progress = progress
	return out


## How many units an auto item may build this year (S09 step 5).
func _auto_room(planet: Planet, player: Player, def: Dictionary) -> int:
	var race := player.race
	var next := PlanetEconomy.next_population(planet, race, _content)
	match def["effect"]:
		"terraform":
			var steps := Terraforming.max_steps(planet, player, _content)
			if steps > 0 and def.get("minimum", false):
				var shrinking := PlanetEconomy.grow(planet, race, _content, false) < 0
				if not shrinking and PlanetEconomy.hab_value(planet, race) > 0:
					return 0
			return steps
		"mines":
			return PlanetEconomy.operable_mines(planet, race, _content, next) - planet.mines
		"factories":
			return PlanetEconomy.operable_factories(planet, race, _content, next) - planet.factories
		"defenses":
			return PlanetEconomy.operable_defenses(planet, race, next) - planet.defenses
	return AUTO_UNLIMITED


func _alchemy_item() -> String:
	for id in _content.ids("production_item"):
		var def := _content.get_def("production_item", id)
		if def["effect"] == "alchemy" and def.has("builds"):
			return def["builds"]
	return ""


# --- Step 6: completed units -------------------------------------------------------------------


## Applies `built` completed units; false when nothing was installed or built.
func _complete(planet: Planet, player: Player, item: QueueItem, built: int) -> bool:
	if item.is_design():
		if item.starbase:
			return _complete_starbase(planet, player, item.design)
		return _complete_ships(planet, player, item.design, built)
	var def := _content.get_def("production_item", item.item)
	match def["effect"]:
		"mines", "factories", "defenses":
			var effect: String = def["effect"]
			var n := mini(built, _maximum(planet, player.race, effect) - _built(planet, effect))
			if n < 1:
				return false
			match effect:
				"mines":
					planet.mines += n
				"factories":
					planet.factories += n
				_:
					planet.defenses += n
		"terraform":
			for k in built:
				Terraforming.step(planet, player.race, player, true, _content)
		"genesis":
			for k in built:
				_genesis(planet, player)
		"scanner":
			planet.has_scanner = true
	return true


func _genesis(planet: Planet, player: Player) -> void:
	if not RaceMath.trait_param(player.race, _content, "production.genesis_keeps_installations", 0):
		planet.mines = 0
		planet.factories = 0
		planet.defenses = 0
		planet.has_scanner = false
	for i in 3:
		planet.surface[i] = 0
		var a := _rng.random(50)
		var b := _rng.random(50)
		planet.environment_original[i] = a + b + 1
		planet.environment[i] = planet.environment_original[i]
		var c := _rng.random(40)
		var d := _rng.random(40)
		planet.concentration[i] = c + d + 25


func _available(design: Design, player: Player) -> bool:
	if design == null:
		return false
	var order := PartRules.tech_order(_content)
	if not PartRules.available(_content.hull(design.hull), player, order):
		return false
	for slot in design.parts:
		if slot.count > 0 and not slot.part.is_empty():
			if not PartRules.available(_content.part(slot.part), player, order):
				return false
	return true


func _complete_ships(planet: Planet, player: Player, slot: int, n: int) -> bool:
	if planet.starbase == null:
		return false
	var design := player.ship_design(slot)
	if not _available(design, player):
		return false
	var limit := _content.constant("constant.limits.fleets_per_player")
	if _state.fleets_of(player.index).size() >= limit:
		return _merge_ships(planet, player, design, n)
	var fleet := _state.add_fleet(player.index, limit)
	fleet.x = planet.x
	fleet.y = planet.y
	fleet.planet = planet.id
	fleet.add_ships(slot, n)
	design.built += n
	design.remaining += n
	fleet.cargo[Fleet.CARGO_FUEL] = PartRules.fuel_capacity(design, _content) * n
	var wp := Waypoint.new(planet.x, planet.y)
	wp.target = "planet"
	wp.target_id = planet.id
	fleet.waypoints.append(wp)
	if planet.route >= 0:
		push_warning("planet %d: new fleets do not follow routes yet (S11)" % planet.id)
	return true


## At the fleet limit new ships join a fleet at the planet (S09 step 6a.2).
func _merge_ships(planet: Planet, player: Player, design: Design, n: int) -> bool:
	for fleet in _state.fleets_of(player.index):
		if fleet.x != planet.x or fleet.y != planet.y:
			continue
		var stack := fleet.stack_for(design.slot)
		var have := 0 if stack == null else stack.count
		if have >= MERGE_HEADROOM - n:
			continue
		if stack == null or have == 0 or stack.damaged_percent == 0:
			stack = fleet.add_ships(design.slot, n)
			stack.damaged_percent = 0
			stack.damage = 0
		else:
			var armor := maxi(PartRules.armor(design, _content, player.race), 1)
			var damaged := maxi(have * stack.damaged_percent / 100, 1)
			var points := stack.damage * armor / 10 * damaged / 50
			fleet.add_ships(design.slot, n)
			var pct := damaged * 100 / (have + n)
			if pct == 0:
				pct = 1
			stack.damaged_percent = pct
			var now_damaged := maxi(pct * (have + n) / 100, 1)
			stack.damage = points * 5 / now_damaged * 100 / armor
		design.built += n
		design.remaining += n
		return true
	return false


func _complete_starbase(planet: Planet, player: Player, slot: int) -> bool:
	var design := player.starbase_design(slot)
	if not _available(design, player):
		return false
	if planet.starbase != null:
		var old := player.starbase_design(planet.starbase.design)
		if old != null and _rank(design) < _rank(old):
			_drop_ship_items(planet)
		if old != null:
			old.remaining -= 1
	else:
		planet.starbase = Starbase.new()
	planet.starbase.design = slot
	var warp := _driver_warp(design)
	if warp > 0:
		planet.mass_driver_warp = warp
	else:
		planet.mass_driver_target = -1
		planet.mass_driver_warp = 0
		var kept: Array[QueueItem] = []
		for q in planet.queue:
			if q.is_design() or _content.get_def("production_item", q.item)["effect"] != "packet":
				kept.append(q)
		planet.queue = kept
	design.built += 1
	design.remaining += 1
	return true


func _rank(design: Design) -> int:
	return _content.hull(design.hull).get("rank", 0)


## Removes ship items; starbase items lose their progress (S09 step 6b.2).
static func _drop_ship_items(planet: Planet) -> void:
	var kept: Array[QueueItem] = []
	for q in planet.queue:
		if q.is_design() and not q.starbase:
			continue
		if q.is_design():
			q.progress = 0
		kept.append(q)
	planet.queue = kept


## The best mass driver warp of a starbase design, plus one when two slots hold drivers of that
## warp.
func _driver_warp(design: Design) -> int:
	return PartRules.driver_warp(design, _content)
