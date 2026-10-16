class_name ClassicProduction
extends RefCounted
## How the classic personalities edit production (spec S22 "Classic production"): what the
## selected planet can build (`BuildProductionList`), queue edits committed as one order
## (`AI_QueueProduction`, `CommitProductionQueue`), and the estimates their choices rest on
## (`AI_EstimatePlanetOutput`, `AI_EstimateQueueCost`, `Production_SimulateQueue`).

## Queue edits: put the item first, last, or make it the whole queue.
enum Mode { TOP, APPEND, REPLACE }

## A list count meaning "as many as you like".
const UNLIMITED := 1023
## The most mines or factories the list offers at once.
const INSTALLATION_CAP := 1020
## Planets with more queue items than this take no more.
const QUEUE_LIMIT := 200
## Years the completion estimate looks ahead; an item not done by then counts as this.
const ESTIMATE_YEARS := 100
## Spending results that end the year's production in the estimate (Production.Status).
const STOPS_YEAR := Production.Status.SOME_BUILT

const MINES := "production_item.mines"
const FACTORIES := "production_item.factories"
const DEFENSES := "production_item.defenses"
const ALCHEMY := "production_item.alchemy"
const AUTO_ALCHEMY := "production_item.auto_alchemy"
const TERRAFORM := "production_item.terraform"
const GENESIS := "production_item.genesis"
const SCANNER := "production_item.planetary_scanner"
const PACKETS := [
	"production_item.ironium_packet",
	"production_item.boranium_packet",
	"production_item.germanium_packet",
	"production_item.mixed_packet",
]
## Auto items in list order, with the trait parameter that keeps a race from them.
const AUTO_ITEMS := [
	["production_item.auto_mines", "colony.skips_auto_mines"],
	["production_item.auto_factories", "colony.skips_auto_factories"],
	["production_item.auto_defenses", "colony.skips_auto_defenses"],
	["production_item.auto_alchemy", ""],
	["production_item.auto_min_terraform", "colony.skips_auto_terraform"],
	["production_item.auto_max_terraform", "colony.skips_auto_terraform"],
	["production_item.auto_packets", ""],
]
const NO_SCANNER_PARAM := "production.no_planetary_scanner"


## A planet's production being edited: the queue as it will be committed, and what can still be
## added (`count` of each list item: how many more, UNLIMITED for any number).
class Edit:
	extends RefCounted
	var planet_id := -1
	var queue: Array[QueueItem] = []
	var buildable: Array[QueueItem] = []

	## The first list item of the same kind as `q`, or null.
	func listed(q: QueueItem) -> QueueItem:
		for b in buildable:
			if ClassicProduction.same(b, q):
				return b
		return null

	## Whether the queue has an item of the same kind as `q`.
	func queued(q: QueueItem) -> bool:
		for e in queue:
			if ClassicProduction.same(e, q):
				return true
		return false


static func standard(item: String, count: int = 0) -> QueueItem:
	return QueueItem.new(item, count)


static func ship(slot: int, count: int = 0) -> QueueItem:
	return QueueItem.of_design(slot, false, count)


static func starbase(slot: int, count: int = 0) -> QueueItem:
	return QueueItem.of_design(slot, true, count)


## Same item, ignoring count and progress.
static func same(a: QueueItem, b: QueueItem) -> bool:
	return a.item == b.item and a.design == b.design and a.starbase == b.starbase


# --- What a planet can build -------------------------------------------------------------------


## What the planet can build, in the original's list order, each with how many more: ship designs
## a dock there can hold, starbase designs but the one it has, the genesis device, packets when it
## has a mass driver, factories and mines (up to INSTALLATION_CAP) and defenses up to their
## maximum, alchemy, a planetary scanner when it has none, terraforming steps it still has, and the
## auto items. Designs that came with transferred ships are never listed.
static func buildable(w: ClassicWorld, planet: Planet) -> Array[QueueItem]:
	var out: Array[QueueItem] = []
	var p := w.state.player(planet.owner)
	var race := p.race
	var content := w.content
	if planet.starbase != null:
		var base := p.starbase_design(planet.starbase.design)
		var dock: int = 0 if base == null else int(content.hull(base.hull).get("dock", 0))
		if dock != 0:
			for d in p.ship_designs:
				if not d.transferred and (dock < 0 or PartRules.mass(d, content) <= dock):
					out.append(ship(d.slot, UNLIMITED))
	for d in p.starbase_designs:
		if d.transferred or (planet.starbase != null and planet.starbase.design == d.slot):
			continue
		out.append(starbase(d.slot, 1))
	var order := PartRules.tech_order(content)
	var genesis: String = content.get_def("production_item", GENESIS)["part"]
	if PartRules.available(content.part(genesis), p, order):
		out.append(standard(GENESIS, 1))
	if Packets.driver(w.state, content, planet)[0] > 0:
		for id: String in PACKETS:
			out.append(standard(id, UNLIMITED))
	var room := PlanetEconomy.max_factories(planet, race, content) - planet.factories
	if room > 0:
		out.append(standard(FACTORIES, mini(room, INSTALLATION_CAP)))
	room = PlanetEconomy.max_mines(planet, race, content) - planet.mines
	if room > 0:
		out.append(standard(MINES, mini(room, INSTALLATION_CAP)))
	room = PlanetEconomy.max_defenses(planet, race) - planet.defenses
	if room > 0:
		out.append(standard(DEFENSES, room))
	out.append(standard(ALCHEMY, UNLIMITED))
	if not planet.has_scanner and not RaceMath.trait_param(race, content, NO_SCANNER_PARAM, 0):
		out.append(standard(SCANNER, 1))
	room = Terraforming.max_steps(planet, p, content)
	if room > 0:
		out.append(standard(TERRAFORM, room))
	for entry: Array in AUTO_ITEMS:
		if entry[1].is_empty() or not RaceMath.trait_param(race, content, entry[1], 0):
			out.append(standard(entry[0], UNLIMITED))
	return out


## Opens the selected planet's production for editing (`BuildProductionList`): the queue is
## copied, each item is held to what the list offers (and the list's count lowered by it), and an
## item the list does not have becomes alchemy x0.
static func open(w: ClassicWorld) -> Edit:
	var e := Edit.new()
	var planet := w.cur_planet
	e.planet_id = planet.id
	for q in planet.queue:
		e.queue.append(q.copy() as QueueItem)
	e.buildable = buildable(w, planet)
	for q in e.queue:
		var b := e.listed(q)
		if b == null:
			q.item = ALCHEMY
			q.design = -1
			q.starbase = false
			q.count = 0
			continue
		q.count = mini(q.count, b.count)
		if b.count != UNLIMITED:
			b.count -= q.count
	w.editing = e
	return e


## Adds an item to the selected planet's queue (`AI_QueueProduction`). With no edit open, one is
## opened, the count held to what the list offers (0 when it is not listed) and committed after;
## with one open the count is taken as it is (its low 10 bits, as the original stores it). A
## planet with more than QUEUE_LIMIT items takes nothing.
static func add(w: ClassicWorld, item: QueueItem, count: int, mode: Mode) -> void:
	if w.cur_planet != null and w.cur_planet.queue.size() > QUEUE_LIMIT:
		return
	var own := w.editing == null
	var e: Edit = open(w) if own else w.editing
	if own:
		var b := e.listed(item)
		count = 0 if b == null else mini(count, b.count)
	if count != 0:
		var q := item.copy() as QueueItem
		# the original keeps 10 bits of the count
		q.count = count & UNLIMITED
		q.progress = 0
		match mode:
			Mode.TOP:
				e.queue.insert(0, q)
			Mode.APPEND:
				e.queue.append(q)
			Mode.REPLACE:
				e.queue.clear()
				e.queue.append(q)
	if own:
		commit(w, count != 0)


## Ends the edit (`CommitProductionQueue`): when `changed`, the queue is given as the planet's
## order and the planet copy reloaded. A design item for an empty slot is left out (the original
## sends it and the year's production drops it).
static func commit(w: ClassicWorld, changed: bool) -> void:
	var e: Edit = w.editing
	w.editing = null
	if e == null or not changed:
		return
	var me := w.me()
	var items := []
	for q in e.queue:
		if q.is_design():
			var d := me.starbase_design(q.design) if q.starbase else me.ship_design(q.design)
			if d == null:
				continue
		items.append(q.to_dict())
	w.order({"type": "production_queue", "planet": e.planet_id, "items": items})
	w.reload_planet()


# --- Estimates ---------------------------------------------------------------------------------


## What a queue item costs at a planet: one unit (`per_unit`) or the whole count, progress not
## counted; nothing for a design slot that is empty.
static func item_cost(w: ClassicWorld, planet: Planet, q: QueueItem, per_unit: bool) -> Array[int]:
	var p := w.state.player(planet.owner)
	if q.is_design():
		var d := p.starbase_design(q.design) if q.starbase else p.ship_design(q.design)
		if d == null:
			return [0, 0, 0, 0]
	var cost := ProductionCosts.unit_cost(planet, q, p, w.content)
	if not per_unit:
		for i in 4:
			cost[i] *= q.count
	return cost


## This year's minerals and resources (`AI_EstimatePlanetOutput`): the surface plus this year's
## mining (-1 each for a planet with no people), and the resources less the research share. The
## share is left in when the selected planet copy (not necessarily this planet) gives only its
## leftovers to research.
static func output(w: ClassicWorld, planet: Planet) -> Array[int]:
	var out: Array[int] = []
	if planet.owner < 0 or planet.population == 0:
		out.assign([planet.surface[0] - 1, planet.surface[1] - 1, planet.surface[2] - 1])
		out.append(0)
		return out
	var race := w.state.player(planet.owner).race
	var copy := planet.copy() as Planet
	PlanetEconomy.mine(copy, race, w.content, null)
	out.assign([copy.surface[0], copy.surface[1], copy.surface[2]])
	var r := PlanetEconomy.resources(planet, race, w.content)
	var leftover := w.cur_planet != null and w.cur_planet.leftover_to_research
	if not leftover:
		r -= r * w.me().research_percent / 100
	out.append(r)
	return out


## The whole queue's cost (`AI_EstimateQueueCost`): every item at its full count, auto items
## included.
static func queue_cost(w: ClassicWorld, planet: Planet) -> Array[int]:
	var total: Array[int] = [0, 0, 0, 0]
	for q in planet.queue:
		var c := item_cost(w, planet, q, false)
		for i in 4:
			total[i] += c[i]
	return total


## When queue item `index` of `planet`'s queue is first built and done (`FormatQueueItemETA`,
## `Production_SimulateQueue`): [first year, last year], 1 being this year. Each year the planet
## (a copy) mines, then spends its resources less the research share on the items in order, as
## production does (S09 step 5; an auto alchemy item is passed over, its effect going to the item
## after it, unless it is the last, which may then build up to INSTALLATION_CAP); what an item
## carries over is spent first the next year; built mines and factories count from then on; the
## people grow. An item still not done after ESTIMATE_YEARS - 1 years counts as ESTIMATE_YEARS;
## an item never begun before an auto item stops is [0, 0], and an auto alchemy item that is not
## the last is [-1, -1].
static func completion(w: ClassicWorld, planet: Planet, index: int) -> Array[int]:
	var copy := planet.copy() as Planet
	var owner := w.state.player(copy.owner)
	var race := owner.race
	var production := Production.new(w.state, w.content, StarsRandom.new(1))
	var queue := copy.queue
	var first := 0
	var carry: QueueItem = null
	for year in range(1, ESTIMATE_YEARS):
		PlanetEconomy.mine(copy, race, w.content, null)
		var r := PlanetEconomy.resources(copy, race, w.content)
		if not copy.leftover_to_research:
			r -= r * owner.research_percent / 100
		var avail: Array[int] = [copy.surface[0], copy.surface[1], copy.surface[2], r]
		var alchemy_above := false
		for i in range(-1, queue.size()):
			var q: QueueItem = carry if i == -1 else queue[i]
			if q == null or q.count == 0:
				continue
			if not q.is_design() and q.item == AUTO_ALCHEMY:
				if i < queue.size() - 1:
					if i == index:
						return [-1, -1]
					alchemy_above = true
					continue
				q.count = INSTALLATION_CAP
			var result := production.spend(copy, owner, q, avail, alchemy_above)
			if i >= 0 and result.carry != null:
				carry = result.carry
			if i == index:
				if result.built > 0 and first == 0:
					first = year
				if result.status == Production.Status.AUTO_SHARE_NONE:
					return [first, year - 1] if first != 0 else [0, 0]
				if result.status <= Production.Status.AUTO_SHARE_BUILT:
					return [first, year]
			alchemy_above = false
			if not q.is_design():
				var effect: String = w.content.get_def("production_item", q.item)["effect"]
				if effect == "mines":
					copy.mines += result.built
				elif effect == "factories":
					copy.factories += result.built
			if result.status >= STOPS_YEAR:
				break
		for m in 3:
			copy.surface[m] = avail[m]
		PlanetEconomy.grow(copy, race, w.content, true)
	return [first if first != 0 else ESTIMATE_YEARS, ESTIMATE_YEARS]
