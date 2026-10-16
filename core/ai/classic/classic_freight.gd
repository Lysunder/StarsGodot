class_name ClassicFreight
extends RefCounted
## The classic personalities' cargo (spec S22 "Classic freight"): moving cargo, how many colony
## ships to keep (`AI_CountColonyShips`), freighter runs (`AI_PlanTransport`,
## `AI_PickUpSalvage`) and the freighter depots kept in the memory (`AI_PlanFreighterDepots`).

const F := preload("res://core/ai/classic/classic_fleets.gd")

## Colony ships are counted from this turn; easy computer players count on even turns only.
const COLONY_COUNT_TURN := 30
## Freighter runs: the speed and the years a leg takes (distance div RUN_SPEED, rounded up).
const RUN_SPEED := 25
const RUN_WARP := 4
## Freighters look at salvage this far (each axis, toward smaller coordinates any distance).
const SALVAGE_REACH := 200
const MIN_LOAD := 10
const FULL_HOME_SCORE := 25000
## Depots (`AI_PlanFreighterDepots`).
const DEPOT_TURN := 20
const DEPOTS_MAX := 64
const DEPOT_MIN_POPULATION := 80
const DEPOT_MIN_VALUE := 7000
const DEPOT_MIN_INSTALLATIONS := 20
const DEPOT_SPACING2 := 2500
const DEPOT_SHARE_BELOW := 4

# --- Cargo -------------------------------------------------------------------------------------


## Moves up to `amount` of cargo `c` between the fleet and `other` (a planet, fleet or salvage
## partner as in a cargo_transfer order): positive loads the fleet, negative unloads it; held to
## what the giver has and the taker can hold (`AI_MoveCargo`, `AI_DropColonists`). Returns the
## amount moved.
static func move_cargo(
	w: ClassicWorld, fleet: Fleet, other: Dictionary, c: int, amount: int
) -> int:
	if amount == 0:
		return 0
	var before := fleet.cargo[c]
	var amounts := [0, 0, 0, 0, 0]
	amounts[c] = amount
	w.order({"type": "cargo_transfer", "fleet": fleet.number, "other": other, "amounts": amounts})
	return absi(fleet.cargo[c] - before)


# --- Colony ships ------------------------------------------------------------------------------


## `AI_CountColonyShips`: {build: whether to build another colony ship, count: the player's fleets
## with ships of colony designs}. Before COLONY_COUNT_TURN always (on easy only on even turns);
## later while there are few (at most universe size index x 20 + 10, and with the player's planets
## at most four fifths of all planets) and the colony designs built do not exceed planets plus
## colony fleets by 26 or more, or on a draw with fewer than 5.
static func colony_ships(w: ClassicWorld) -> Dictionary:
	var out := {"build": false, "count": 0}
	if w.me().ai_level == 0 and w.state.turn % 2 == 1:
		return out
	if w.state.turn < COLONY_COUNT_TURN:
		out.build = true
		return out
	var slots := []
	var built := 0
	for d in w.me().ship_designs:
		if F.hulls_of(w, F.COLONY).has(d.hull):
			slots.append(d.slot)
			built += d.built
	if slots.is_empty():
		return out
	var count := 0
	for f in w.state.fleets:
		if f.owner == w.player and slots.any(func(s: int) -> bool: return F.has_slot(f, s)):
			count += 1
	out.count = count
	var size := w.state.settings.universe_width / 400 - 1
	if count > size * 20 + 10:
		return out
	var planets := (
		w.state.planets.filter(func(p: Planet) -> bool: return p.owner == w.player).size()
	)
	if planets + count > w.state.planets.size() * 4 / 5:
		return out
	var over := built - (planets + count)
	if over >= 0 and over < 26:
		out.build = true
	elif count < 5 and w.rng.random(2) == 0:
		out.build = true
	return out


# --- Freighter runs ----------------------------------------------------------------------------


static func _years(fleet: Fleet, p: Planet) -> int:
	var d := int(Vector2(fleet.x - p.x, fleet.y - p.y).length())
	return maxi((d + RUN_SPEED - 1) / RUN_SPEED, 1)


## `AI_PlanTransport`: a freighter's next run, from its depot `home`. Each planet is scored by
## what it offers per year of travel (RUN_SPEED a year): a full freighter scores
## FULL_HOME_SCORE at home (20 per percent full, per year, from 35% full); another of the player's
## planets without a starbase (or one queued) by the share of the freighter its minerals fill
## (all three, or mostly the scarcest at home when that is under half of the next, only it when
## under a quarter); Robotoids also carry people from home (with 1101 people or 301) to thinly
## peopled planets (65). Planets other freighters of its kind head for are passed over. Salvage
## nearby may score better. The freighter loads at the target (unloads at home), at RUN_WARP;
## Robotoids leaving home with people for a planet take some along. Returns the target planet or
## salvage, or -1.
static func plan_transport(w: ClassicWorld, fleet: Fleet, home: Planet) -> int:
	for p in w.state.planets:
		F.info_set(w, p.id, 14, 0)
	var first_slot := F.stacks_of(fleet)[0].design if not F.stacks_of(fleet).is_empty() else 0
	var scarce := 0
	var low := 1000000000
	var second := 1000000000
	for m in 3:
		if home.surface[m] < low:
			second = low
			low = home.surface[m]
			scarce = m
	var mode := (1 if low < second >> 1 else 0) + (1 if low < second >> 2 else 0)
	for f in w.state.fleets:
		if f.owner != w.player or f.waypoints.size() < 2 or f == fleet:
			continue
		var next := f.waypoints[1]
		if next.target == "planet" and F.has_slot(f, first_slot) and next.target_id != home.id:
			F.info_set(w, next.target_id, 14, 1)
	var owner := w.me()
	var cap := cargo_capacity(fleet, owner, w.content)
	if cap < 1:
		return -1
	var space := cap - fleet.cargo[0] - fleet.cargo[1] - fleet.cargo[2] - fleet.cargo[3]
	var full := 100 - space * 100 / cap
	var best := 0
	var target: Planet = null
	var robotoids := w.personality_id() == ClassicWorld.ROBOTOIDS
	var at_home := fleet.planet == home.id
	for p in w.state.planets:
		var info: PackedByteArray = w.planet_info[p.id]
		if p.id == fleet.planet or info[14] != 0:
			continue
		var score := 0
		if p.owner == -1 and info[1] & 0x80:
			score = (info[1] & 0x7F) * 500 / _years(fleet, p)
		elif p.owner != w.player and not _people_wanted(robotoids, at_home, home, p):
			if info[3] == 0 or info[3] & 0x80 or not at_home:
				continue
			score = _own_score(fleet, home, p, info, mode, scarce, cap, full, at_home)
		elif p.owner != w.player:
			score = 65 * 100 / _years(fleet, p)
		else:
			score = _own_score(fleet, home, p, info, mode, scarce, cap, full, at_home)
		if score > best:
			best = score
			target = p
	var target_id := target.id if target != null else -1
	var found := pick_up_salvage(w, fleet, mode, scarce, full, cap, best, target_id)
	var salvage: Packet = found.salvage
	target_id = found.target
	if found.picked and _space(fleet, owner, w.content) == 0:
		salvage = null
		target = home
		target_id = home.id
	if target_id == -1:
		return -1
	var wp: Waypoint
	if salvage == null:
		target = w.state.planet(target_id)
		wp = F.planet_waypoint(w, target_id, RUN_WARP, "transport")
	else:
		wp = Waypoint.new(salvage.x, salvage.y)
		wp.target = "packet"
		wp.target_owner = salvage.owner
		wp.target_id = salvage.number
		wp.warp = RUN_WARP
	var actions := ["load_all", "load_all", "load_all", "none", "none"]
	if salvage == null and home.id == target_id:
		actions = ["unload_all", "unload_all", "unload_all", "none", "none"]
	var amounts := [0, 0, 0, 0, 0]
	if robotoids and at_home and salvage == null and target.owner != -1:
		var n := _people_to_take(w, home, target)
		if n >= 0:
			w.select_fleet(fleet)
			move_cargo(w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, n)
			actions[3] = "unload_all"
	if salvage == null:
		if home.id != target_id and mode != 0:
			if mode == 2 or space <= target.surface[scarce]:
				for m in 3:
					if m != scarce:
						actions[m] = "none"
			elif target.owner != -1:
				for m in 3:
					actions[m] = "fill_percent"
					amounts[m] = 66 if m == scarce else 33
	else:
		wp.task = "none"
	if wp.task == "transport":
		var cargo := []
		for c in 5:
			cargo.append({"action": actions[c], "amount": amounts[c]})
		wp.task_data = {"cargo": cargo}
	return target_id if F.go(w, fleet, wp) else -1


## The fleet's cargo room (`Fleet_GetCapacity(fleet, 2)`).
static func cargo_capacity(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var total := 0
	for s in fleet.stacks:
		total += s.count * PartRules.cargo_capacity(owner.ship_design(s.design), content)
	return total


static func _space(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var cap := cargo_capacity(fleet, owner, content)
	return cap - fleet.cargo[0] - fleet.cargo[1] - fleet.cargo[2] - fleet.cargo[3]


## Robotoids at home with people to spare: a planet with few people (estimate) is worth carrying
## people to.
static func _people_wanted(robotoids: bool, at_home: bool, home: Planet, p: Planet) -> bool:
	if not robotoids or not at_home:
		return false
	if home.population >= 1101 and p.population_estimate <= 61:
		return true
	return home.population >= 301 and p.population_estimate <= 14


## The score of one of the player's planets (or a planet marked in planet_info byte 3).
static func _own_score(
	fleet: Fleet,
	home: Planet,
	p: Planet,
	info: PackedByteArray,
	mode: int,
	scarce: int,
	cap: int,
	full: int,
	at_home: bool
) -> int:
	if p == home:
		if full <= 34:
			return 0
		if full == 100:
			return FULL_HOME_SCORE
		return full * 20 / _years(fleet, p)
	if p.starbase != null:
		return 0
	if not p.queue.is_empty() and p.queue[0].is_design() and p.queue[0].starbase:
		return 0
	if info[2] != 0 and not info[2] & 0x80 and at_home:
		return FULL_HOME_SCORE
	var minerals := 0
	if mode == 2:
		minerals = p.surface[scarce]
	else:
		for m in 3:
			minerals += p.surface[m] if mode == 0 or m == scarce else p.surface[m] >> 1
	if minerals <= 9:
		return 0
	var pct := mini(minerals * 100 / cap, 100 - full)
	return pct * 100 / _years(fleet, p)


## How many people (hundreds) Robotoids take from home to `target`: to their own small planets a
## share of home's people by its size (unless the target has 1000 or two thirds of home's), to
## another player's planets 300 (100 when home has 900 or fewer); -1 for none.
static func _people_to_take(w: ClassicWorld, home: Planet, target: Planet) -> int:
	var pop := home.population
	if target.owner != w.player:
		return 300 if pop > 900 else 100
	if target.population >= 1000 or target.population * 3 / 2 >= pop or pop <= 500:
		return -1
	var pct: int
	if pop > 2000:
		pct = 10
	elif pop > 1500:
		pct = 8
	elif pop > 1000:
		pct = 5
	else:
		pct = (pop - 400) / 100
	return pop * pct / 100


## `AI_PickUpSalvage`: salvage where the freighter is is loaded (the scarce mineral first when
## `mode` is set, then everything unless `mode` is 2); salvage within SALVAGE_REACH scores like a
## planet and may become the target. Returns {picked, salvage (or null), target}.
static func pick_up_salvage(
	w: ClassicWorld,
	fleet: Fleet,
	mode: int,
	scarce: int,
	full: int,
	cap: int,
	best: int,
	target: int
) -> Dictionary:
	var out := {"picked": false, "salvage": null, "target": target}
	for s: Packet in w.state.packets.duplicate():
		if not s.salvage:
			continue
		var dx := fleet.x - s.x
		var dy := fleet.y - s.y
		if dx == 0 and dy == 0:
			var other := {"packet": s.number, "owner": s.owner}
			if mode != 0 and s.minerals[scarce] != 0:
				move_cargo(w, fleet, other, scarce, s.minerals[scarce])
			if mode != 2:
				for m in 3:
					if s.minerals[m] != 0:
						move_cargo(w, fleet, other, m, s.minerals[m])
			out.picked = true
			continue
		if maxi(dx, dy) > SALVAGE_REACH:
			continue
		var amount := 0
		if mode == 2:
			amount = s.minerals[scarce]
		else:
			for m in 3:
				amount += s.minerals[m] if mode == 0 or m == scarce else s.minerals[m] >> 1
		if amount <= 9:
			continue
		var pct := mini(amount * 100 / cap, 100 - full)
		var d := int(Vector2(dx, dy).length())
		var years := maxi((d + RUN_SPEED - 1) / RUN_SPEED, 1)
		var score := pct * 100 / years
		if score > best:
			best = score
			out.salvage = s
			out.target = s.number
	return out


# --- Depots ------------------------------------------------------------------------------------


static func _mem(w: ClassicWorld, record: int, word: int) -> int:
	return w.memory[ClassicWorld.DEPOT_FIRST + record * ClassicWorld.DEPOT_WORDS + word]


static func _mem_set(w: ClassicWorld, record: int, word: int, value: int) -> void:
	w.memory[ClassicWorld.DEPOT_FIRST + record * ClassicWorld.DEPOT_WORDS + word] = value


## `AI_PlanFreighterDepots` (not Cybertrons or Macinti), from turn DEPOT_TURN: depots on planets
## the player lost are dropped; the player's planets with a starbase (shuffled order) become
## depots, then rich planets (population DEPOT_MIN_POPULATION, concentration squared x 4 plus
## surface over the three minerals DEPOT_MIN_VALUE, DEPOT_MIN_INSTALLATIONS mines and factories;
## Robotoids not within 50 light years of another depot), up to DEPOTS_MAX. Each freighter
## not yet at a depot joins the nearest depot with room (DEPOT_FLEETS); a depot with fewer than
## DEPOT_SHARE_BELOW freighters takes one from the first depot with two more.
static func plan_depots(w: ClassicWorld) -> void:
	var pid := w.personality_id()
	if pid == ClassicWorld.CYBERTRONS or pid == ClassicWorld.MACINTI:
		return
	if w.memory[0] < 3:
		w.memory[ClassicWorld.DEPOT_COUNT] = 0
	if w.state.turn < DEPOT_TURN:
		return
	if w.memory[ClassicWorld.DEPOT_COUNT] < 0 or w.memory[ClassicWorld.DEPOT_COUNT] > DEPOTS_MAX:
		w.memory[ClassicWorld.DEPOT_COUNT] = 0
	var kept := 0
	for i in w.memory[ClassicWorld.DEPOT_COUNT]:
		var n := _mem(w, i, 1)
		if n < 0 or n > ClassicWorld.DEPOT_FLEETS:
			_mem_set(w, i, 1, 0)
		var p := w.state.planet(_mem(w, i, 0))
		if p != null and p.owner == w.player:
			if kept != i:
				for k in ClassicWorld.DEPOT_WORDS:
					_mem_set(w, kept, k, _mem(w, i, k))
			kept += 1
	w.memory[ClassicWorld.DEPOT_COUNT] = kept
	for p in w.own_planets:
		if p.starbase != null and w.depot_of_planet(p.id) < 0 and kept < DEPOTS_MAX:
			_mem_set(w, kept, 0, p.id)
			_mem_set(w, kept, 1, 0)
			kept += 1
			w.memory[ClassicWorld.DEPOT_COUNT] = kept
	for p in w.state.planets:
		if kept >= DEPOTS_MAX:
			break
		if p.owner != w.player or p.starbase != null or p.population < DEPOT_MIN_POPULATION:
			continue
		var value := 0
		for m in 3:
			value += p.concentration[m] * p.concentration[m] * 4 + p.surface[m]
		if value < DEPOT_MIN_VALUE:
			continue
		if p.mines < DEPOT_MIN_INSTALLATIONS or p.factories < DEPOT_MIN_INSTALLATIONS:
			continue
		var clash := false
		for i in kept:
			var at := _mem(w, i, 0)
			if at == p.id:
				clash = true
				break
			if pid == ClassicWorld.ROBOTOIDS:
				var q := w.state.planet(at)
				if F.d2(q.x, q.y, p.x, p.y) < DEPOT_SPACING2:
					clash = true
					break
		if not clash:
			_mem_set(w, kept, 0, p.id)
			_mem_set(w, kept, 1, 0)
			kept += 1
			w.memory[ClassicWorld.DEPOT_COUNT] = kept
	for f in w.state.fleets:
		if f.owner != w.player or not F.is_freighter(w, f):
			continue
		var id := ClassicWorld.fleet_id(f)
		if depot_of_fleet(w, id) >= 0:
			continue
		var best := -1
		var best_d := 10000000
		for i in kept:
			if _mem(w, i, 1) >= ClassicWorld.DEPOT_FLEETS:
				continue
			var q := w.state.planet(_mem(w, i, 0))
			var d := F.d2(q.x, q.y, f.x, f.y)
			if d < best_d:
				best = i
				best_d = d
		if best >= 0:
			var n := _mem(w, best, 1)
			_mem_set(w, best, 2 + n, id)
			_mem_set(w, best, 1, n + 1)
	for i in kept:
		var n := _mem(w, i, 1)
		if n >= DEPOT_SHARE_BELOW:
			continue
		for j in kept:
			var m := _mem(w, j, 1)
			if m >= n + 2:
				_mem_set(w, j, 1, m - 1)
				_mem_set(w, i, 2 + n, _mem(w, j, 2 + m - 1))
				_mem_set(w, i, 1, n + 1)
				break
	w.memory[0] = kept * ClassicWorld.DEPOT_WORDS * 2 + 4


## The depot record a freighter (fleet id word) belongs to, or -1.
static func depot_of_fleet(w: ClassicWorld, id: int) -> int:
	for i in w.memory[ClassicWorld.DEPOT_COUNT]:
		var n := _mem(w, i, 1)
		for k in n:
			if _mem(w, i, 2 + k) == id:
				return i
	return -1
