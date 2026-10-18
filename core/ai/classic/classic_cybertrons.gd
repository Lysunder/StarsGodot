class_name ClassicCybertrons
extends RefCounted
## The original's Cybertrons (spec S22 "Cybertrons", `AI_Cybertrons`): research by plan, designs
## drawn from template pools (`AI_Cybertrons_Designs`), warship groups gathering and invading
## (`AI_Cybertrons_Invade`), colonist transports filling small colonies
## (`AI_Cybertrons_ColonistTransport`), mine-laying scouts, production by planet
## (`AI_Cybertrons_Economy`) and mineral packets thrown at their own planets and at others'
## (`AI_Cybertrons_PlanPackets`). Per-planet state lives in the working memory: a lasting word A
## per planet from word 1, and a word B per planet after them, cleared every turn.

const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")

const RESEARCH_PLAN := "ai_research_plan.cybertrons"
const RESEARCH_PCT := 17
const TEMPLATE := "ai_design_template.cybertrons_"
## Formula ids (S25 B44, B45, B46): where the fleet passes keep their marks, whose record a packet
## target's timer goes to, and how far a sector target must be.
const MARKS_BASE := "ai.cybertrons_marks_base"
const PACKET_RECORD := "ai.cybertrons_packet_record"
const SECTOR_REACH := "ai.cybertrons_sector_reach"
const LONG_TARGET := "ai.cybertrons_long_target"
## Design slots.
const SCOUT_SLOT := 0
const COLONY_SLOT := 1
const GROUP_FIRST := [6, 10]
## Slots merged into one fleet each turn (`AI_MergeFleetsByHull`), in this order.
const MERGES := [[0], [4, 5], [14, 15], [6, 7, 8, 9], [10, 11, 12, 13]]
const SPLIT_TURN := 80
## Retirement ages: before turn RETIRE_TURNS[i], RETIRE_AGES[i] turns; later the last.
const RETIRE_TURNS := [120, 200, 400]
const RETIRE_AGES := [50, 70, 100, 300]
const ESCORT_START := 3
const ESCORT_MAX := 50
const TROOPS_START := 6
const TROOPS_MAX := 12
## planet_info bytes.
const INFO_OTHERS := 9
const INFO_TARGET := 10
const INFO_COLONY := 15
const HEADED := 0x80
## Memory word A (lasting): bits 0-2 the packet sector, 0x08 a colony ship queued, 0x10 a sector
## packet thrown, 0x60 a packet timer (counts down each turn), 0x80 a packet still on its way.
const A_SECTOR := 0x07
const A_COLONY := 0x08
const A_SECTOR_SENT := 0x10
const A_TIMER := 0x60
const A_TIMER_STEP := 0x20
const A_LONG_THROW := 0x80
## Memory word B (this turn): 0x01 no colony target, 0x06 people unloaded (counts to 3), 0x18
## transports heading there (counts to 3), 0x20 its guards are few, 0x40 guarded; high byte bits
## 1, 2, 4 short of ironium, boranium, germanium.
const B_NO_TARGET := 0x01
const B_UNLOADED := 0x06
const B_UNLOADED_STEP := 0x02
const B_TRANSPORTS := 0x18
const B_TRANSPORT_STEP := 0x08
const B_FEW_GUARDS := 0x20
const B_GUARDED := 0x40
const B_SHORT := [0x100, 0x200, 0x400]
## Starbase designs in these slots are forts (S22 "Starbase designs").
const FORT_SLOTS := [1, 3, 6, 8]
const SHORT_FORT := 10
const SHORT_STATION := 1000
const PACKET_RICH := 700
const PACKET_KG := 70
const PACKET_FEED_MAX := 7
const PACKET_FEED_MIN := 7
const PACKET_SPARE := 210
const PACKET_ATTACK_SPARE := 151
const PACKET_SECTOR_SPARE := 170
const SECTOR_JITTER_PCT := [30, 15]
const MAP_ORIGIN := 1000
## A packet goes at most this many light years per warp squared (feed reach), and an attack
## target within PACKET_ATTACK_REACH per warp squared.
const FEED_REACH := [7, 2]
const ATTACK_REACH := [5, 2]
## Packet decay over a throw: per year of flight, 8/7 with a matched pair of drivers, else 4/3.
const DECAY_PAIR := [8, 7]
const DECAY_SINGLE := [4, 3]
const COLONY_TOO_MANY := 40
const COLONY_GROWTH := 5500
const COLONY_SECOND_GROWTH := 15000
const COLONY_SECOND_TURN := 100
const TRANSPORT_POPULATION := 2000
const TRANSPORT_SHIPS := 50
const SCOUT_SHIPS_MAX := 10000
const ENEMY_NEAR2 := 90000
const SCOUT_SCRAP_TURN := 6
const SCOUT_LAY_TURN := 40
const LAY_FOREVER := 5
const SCOUT_JOIN := [72, 108]
const SCOUT_REACH := 105
const GROUP_JOIN := [100, 200]
const FLEETS_IDLE_MAX := 120
const FLEETS_GROUP_MAX := 250
const FLEETS_GUARD_MAX := 40
const COLONISTS_LOADED := 250
const TRANSPORT_LOAD := 1000
const TRANSPORT_HOME_POPULATION := 2200
const SMALL_COLONY := 200
const COLONY_FULL := 1000
const COLONY_LEVEL := 210
const NEAR_COLONY2 := 160001
const SEEK_REACH := 450
const FLEET_KEEP2 := 62501
const WARP := 4
const GROWTH_PCT := "race.growth_rate_pct"
const SPACE_DOCK := "hull.space_dock"
## The original's packet damage scale, 6.25e-5 as a double: a hair over 1/HIT_SCALE.
const HIT_SCALE := 16000

var w: ClassicWorld
var turn := 0
var level := 0
var escort := 0
var troops := 0
## Warship strength the planets build toward (`local_36`).
var wanted := 0
var age := 0
var obsolete := []
## Newest designs: destroyers (slots 4-5), heavies (14-15), transports (2-3); -1 none.
var destroyer := -1
var heavy := -1
var transport := -1
var transport_ships := 0
## The newest warship group (0 for slots 6-9, 1 for 10-13), -1 none.
var group := -1
## The retirement loop's counter, as the warship count reads it (`local_1e`).
var counter := 0
var colony_ships := 0
var own_warships: Array[Fleet] = []
var enemies: Array[Fleet] = []
## Fleet counts of the first pass (`local_38`, `local_44`, `local_42`, `local_40`, `local_3e`).
var scout_fleets := 0
var scout_ships := 0
var idle_warships := 0
var busy_warships := 0
var guard_fleets := 0
var planet_count := 0
var _marks := 0


## One turn of Cybertrons on world `w`.
static func play(world: ClassicWorld) -> void:
	var t := ClassicCybertrons.new()
	t.w = world
	t.turn = world.state.turn
	t.level = world.me().ai_level
	t._play()


func _play() -> void:
	planet_count = w.state.planets.size()
	if w.memory[0] == ClassicWorld.MEMORY_FIRST:
		w.memory.fill(0)
		w.memory[0] = (planet_count + 1) * 2
	w.colony_targets_rated = false
	ClassicDesigns.update_starbase_designs(w)
	ClassicFreight.plan_depots(w)
	ClassicResearch.follow_plan(w, RESEARCH_PLAN, RESEARCH_PCT)
	designs(w)
	for m: Array in MERGES:
		F.merge_by_slots(w, m)
	_thresholds()
	_retire()
	colony_ships = _design_remaining(COLONY_SLOT)
	if turn > SPLIT_TURN:
		var old := []
		for slot in F.DESIGN_SLOTS:
			if obsolete[slot] != 0:
				old.append(slot)
		F.split_slots(w, old)
		F.split_slots(w, [0])
		F.split_slots(w, [1])
		F.split_slots(w, [2, 3])
	_planet_marks()
	_first_pass()
	_last_pass()
	_production()
	var station := ClassicDesigns.newer_starbase(w, 0, 5)
	ClassicPlanning.manage(w, station)
	ClassicCybertronsPackets.plan(self)
	ClassicPlanning.finish_turn(w)


func _thresholds() -> void:
	wanted = 1
	if turn > 50:
		wanted = (turn - 50) / 10 + 1
	if turn > 100:
		wanted += ((turn - 100) / 10) * (turn / 100)
	escort = ESCORT_START
	if turn > 130:
		escort = (turn - 120) / 20 + ESCORT_START
	escort = mini(escort, ESCORT_MAX)
	troops = TROOPS_START
	if turn > 115:
		troops = (turn - 100) / 22 + TROOPS_START
	troops = mini(troops, TROOPS_MAX)
	counter = troops


func _design_remaining(slot: int) -> int:
	var d := w.me().ship_design(slot)
	return 0 if d == null else d.remaining


static func _ships(fleet: Fleet, slot: int) -> int:
	var s := fleet.stack_for(slot)
	return 0 if s == null else s.count


# --- Memory -------------------------------------------------------------------------------------


func a_word(id: int) -> int:
	return w.memory[1 + id]


func set_a_word(id: int, value: int) -> void:
	w.memory[1 + id] = value & 0xFFFF


func b_word(id: int) -> int:
	return w.memory[planet_count + 1 + id]


func set_b_word(id: int, value: int) -> void:
	w.memory[planet_count + 1 + id] = value & 0xFFFF


## The word the fleet passes mark for planet `id` (S25 B44: the original's base is off).
func _mark_word(id: int) -> int:
	return _marks + id


func _mark_get(id: int) -> int:
	var i := _mark_word(id)
	return w.memory[i] if i >= 0 and i < w.memory.size() else 0


func _mark_set(id: int, value: int) -> void:
	var i := _mark_word(id)
	if i >= 0 and i < w.memory.size():
		w.memory[i] = value & 0xFFFF


## A two-bit count in `mask` (bits from `step`) raised by one, at most 3.
static func _count_up(value: int, mask: int, step: int) -> int:
	if value & mask < mask:
		value = (value & ~mask) | ((value + step) & mask)
	return value


# --- Designs and retirement --------------------------------------------------------------------


## `AI_Cybertrons_Designs`: designs by turn, drawn from template pools (spec S22 "Cybertrons",
## step 2).
static func designs(world: ClassicWorld) -> void:
	var me := world.me()
	var turn := world.state.turn
	var d := func(slot: int) -> Design: return me.ship_design(slot)
	var scout: Design = d.call(SCOUT_SLOT)
	var frigate: String = world.content.get_def("ai_design_template", TEMPLATE + "scout")["hull"]
	if (
		scout != null
		and scout.hull != frigate
		and me.ai_level >= 2
		and scout.remaining == 0
		and turn > 5
	):
		ClassicDesigns.delete(world, SCOUT_SLOT, false)
	if d.call(SCOUT_SLOT) == null:
		_outfit(world, SCOUT_SLOT, "scout")
	if d.call(4) == null and turn > 30:
		if turn > 75 or not _outfit(world, 4, "destroyer_0"):
			_shrinking(world, 4, "destroyer_%d", 0, 5)
	if d.call(5) == null and d.call(4) != null and d.call(4).turn_designed + 20 < turn:
		if turn > 75 or not _outfit(world, 5, "destroyer_5"):
			_shrinking(world, 5, "destroyer_%d", 5, 5)
	if d.call(2) == null and turn > 20:
		_outfit(world, 2, "privateer_0")
	if d.call(3) == null and d.call(2) != null and d.call(2).turn_designed + 20 < turn:
		_outfit(world, 3, "privateer_1")
	for g in 2:
		var first: int = GROUP_FIRST[g]
		if d.call(first) != null:
			continue
		var six: Design = d.call(6)
		var due := turn > 40 if g == 0 else six != null and six.turn_designed + 30 < turn
		if not due:
			continue
		var slot := first + 2
		var pools := [["nubian_%d", 0, 3], ["battleship_%d", 3, 4], ["battleship_%d", 0, 3]]
		for i in pools.size():
			var pool: Array = pools[i]
			if _shrinking(world, slot, pool[0], pool[1], pool[2]):
				slot -= 1
		if first <= slot:
			var count := first - slot + 3
			var tries := count * 3
			var base := 9 - tries
			while true:
				_shrinking(world, slot, "cruiser_%d", base, tries)
				slot -= 1
				if slot < first:
					break
				tries = 3
				base = 0 if slot == first else 3
		var flag := first + 3
		if not _outfit(world, flag, "nubian_flag"):
			if not _outfit(world, flag, "battleship_flag"):
				if not _outfit(world, flag, "b52_1"):
					_outfit(world, flag, "b52_0")
	for slot in [14, 15]:
		if d.call(slot) != null:
			continue
		var fourteen: Design = d.call(14)
		var due := (
			turn > 30 if slot == 14 else (fourteen != null and fourteen.turn_designed + 20 < turn)
		)
		if not due:
			continue
		if not _shrinking(world, slot, "battleship_%d", 0, 7):
			if not _shrinking(world, slot, "cruiser_%d", 0, 9):
				_shrinking(world, slot, "destroyer_%d", 0, 10)


## Up to `n` tries in `slot`, each drawing one of the first k templates of a pool (k from `n`
## down to 1) starting at pool index `base`; whether one was made.
static func _shrinking(world: ClassicWorld, slot: int, pool: String, base: int, n: int) -> bool:
	var k := n
	while k > 0:
		if _outfit(world, slot, pool % (base + world.rng.random(k))):
			return true
		k -= 1
	return false


static func _outfit(world: ClassicWorld, slot: int, template: String) -> bool:
	return ClassicDesigns.outfit(world, slot, TEMPLATE + template)


## `AI_FindDesignForHulls` for slots 4-5, 14-15 and 2-3 (the newest of each kept), then the
## warship groups: a group whose first design is older than the age loses its spent designs from
## the top down (the first only when none above it was kept) and marks the others obsolete.
func _retire() -> void:
	age = RETIRE_AGES[-1]
	for i in RETIRE_TURNS.size():
		if turn < RETIRE_TURNS[i]:
			age = RETIRE_AGES[i]
			break
	obsolete = []
	obsolete.resize(F.DESIGN_SLOTS)
	obsolete.fill(0)
	destroyer = ClassicDesigns.newest_in_slots(w, 4, 5, age, obsolete)["slot"]
	if destroyer >= 0:
		obsolete[destroyer] = 0
	heavy = ClassicDesigns.newest_in_slots(w, 14, 15, age, obsolete)["slot"]
	# S25 B47: the original keeps the destroyer here a second time, not the heavy design
	if heavy >= 0:
		obsolete[heavy] = 0
	var t := ClassicDesigns.newest_in_slots(w, 2, 3, age, obsolete)
	transport = t["slot"]
	transport_ships = t["remaining"]
	if transport >= 0:
		obsolete[transport] = 0
	group = -1
	var me := w.me()
	for g in 2:
		var first: int = GROUP_FIRST[g]
		var d := me.ship_design(first)
		if d != null and turn - d.turn_designed > age:
			var top := true
			for slot in range(first + 3, first - 1, -1):
				var s := me.ship_design(slot)
				if s == null:
					continue
				if s.remaining == 0 and (top or slot != first):
					ClassicDesigns.delete(w, slot, false)
				else:
					obsolete[slot] = 1
					top = false
			counter = first - 1
		d = me.ship_design(first)
		if d != null:
			var newest := me.ship_design(GROUP_FIRST[group]) if group >= 0 else null
			if group == -1 or newest.turn_designed < d.turn_designed:
				group = g


# --- Planets -----------------------------------------------------------------------------------


## The planet marks: packet timers count down, the player's starbase planets note which minerals
## run short, and other players' planets get their worth as targets.
func _planet_marks() -> void:
	_marks = w.content.ruleset.formula(MARKS_BASE).call(planet_count, _last_loaded())
	for i in planet_count:
		set_b_word(i, 0)
	for p in w.state.planets:
		if not w.loaded.has(p.id):
			continue
		var a := a_word(p.id)
		if a & A_TIMER != 0:
			set_a_word(p.id, (a & ~A_TIMER) | ((a - A_TIMER_STEP) & A_TIMER))
		if p.owner == w.player or p.owner == -1:
			if p.owner == w.player and p.starbase != null:
				var limit := SHORT_FORT if fort(p) else SHORT_STATION
				var b := b_word(p.id)
				for m in 3:
					if p.surface[m] < limit:
						b |= B_SHORT[m]
				set_b_word(p.id, b)
		else:
			var worth := mini(p.population_estimate / 250 + 1, 6)
			if p.starbase != null:
				worth += 1
			F.info_set(w, p.id, INFO_TARGET, worth)
			F.info_set(w, p.id, INFO_OTHERS, 1)


func _last_loaded() -> int:
	var last := -1
	for p in w.state.planets:
		if w.loaded.has(p.id):
			last = p.id
	return last


static func fort(p: Planet) -> bool:
	return p.starbase != null and FORT_SLOTS.has(p.starbase.design)


# --- Fleets ------------------------------------------------------------------------------------


func _first_warship_slot(fleet: Fleet) -> int:
	for slot in range(4, 14):
		if _ships(fleet, slot) > 0:
			return slot
	return -1


## The first fleet pass: lists, counts and marks.
func _first_pass() -> void:
	for fleet in w.state.fleets.duplicate():
		if not w.colony_targets_rated:
			F.colony_target(w, fleet, false)
		if fleet.owner != w.player:
			enemies.push_front(fleet)
			continue
		if _ships(fleet, 14) > 0 or _ships(fleet, 15) > 0:
			guard_fleets += 1
			continue
		if _ships(fleet, SCOUT_SLOT) > 0:
			scout_fleets += 1
			scout_ships += _ships(fleet, SCOUT_SLOT)
		if _first_warship_slot(fleet) >= 0:
			own_warships.push_front(fleet)
			var next_planet: bool = (
				fleet.waypoints.size() >= 2 and fleet.waypoints[1].target == "planet"
			)
			if counter < 6 or (not next_planet and fleet.planet == -1):
				idle_warships += 1
			else:
				var target: int = fleet.waypoints[1].target_id if next_planet else fleet.planet
				var info: PackedByteArray = w.planet_info[target]
				if info[INFO_TARGET] != 0:
					F.info_set(w, target, INFO_TARGET, info[INFO_TARGET] | HEADED)
				busy_warships += 1
		elif (
			(_ships(fleet, 2) > 0 or _ships(fleet, 3) > 0)
			and fleet.waypoints.size() > 1
			and fleet.cargo[Fleet.CARGO_COLONISTS] > 0
			and fleet.waypoints[1].target == "planet"
		):
			var t: int = fleet.waypoints[1].target_id
			_mark_set(t, _count_up(_mark_get(t), B_TRANSPORTS, B_TRANSPORT_STEP))


## The last fleet pass, each of the player's fleets in fleet order.
func _last_pass() -> void:
	for fleet in w.state.fleets.duplicate():
		if fleet.owner != w.player or not w.state.fleets.has(fleet):
			continue
		_last(fleet)


func _last(fleet: Fleet) -> void:
	var current := false
	for slot in F.DESIGN_SLOTS:
		if _ships(fleet, slot) > 0 and obsolete[slot] == 0:
			current = true
			break
	if not current:
		if fleet.planet != -1:
			var p := w.state.planet(fleet.planet)
			if p != null and p.owner == w.player and (p.starbase != null or w.rng.random(5) == 0):
				F.set_task(w, fleet, "scrap")
				return
		if fleet.waypoints.size() > 1 and fleet.planet == -1:
			return
		if F.return_home(w, fleet, false):
			return
	var guards := _ships(fleet, 14) > 0 or _ships(fleet, 15) > 0
	if guards and fleet.planet != -1:
		_guards(fleet)
		return
	var first := _first_warship_slot(fleet)
	if first >= 0:
		_warships(fleet, first)
	elif fleet.waypoints.size() < 2:
		if turn < SCOUT_SCRAP_TURN and _ships(fleet, SCOUT_SLOT) > 0:
			F.set_task(w, fleet, "scrap")
		elif _ships(fleet, COLONY_SLOT) > 0:
			_colony_ship(fleet)
		elif _ships(fleet, 2) > 0 or _ships(fleet, 3) > 0:
			if fleet.battle_plan != 4:
				w.select_fleet(fleet)
				w.order({"type": "fleet_battle_plan", "fleet": fleet.number, "plan": 4})
			colonist_transport(fleet)
		else:
			_scouts(fleet)


## Guard fleets (slots 14-15) at a planet mark it guarded, and few when their recent ships number
## under twice the wanted strength.
func _guards(fleet: Fleet) -> void:
	var me := w.me()
	var n := 0
	for slot in [14, 15]:
		var d := me.ship_design(slot)
		var designed := d.turn_designed if d != null else 0
		if turn - designed < age - 10:
			n += _ships(fleet, slot)
	if n > 0:
		var m := _mark_get(fleet.planet) | B_GUARDED
		m = (m & ~B_FEW_GUARDS) | (B_FEW_GUARDS if n < wanted * 2 else 0)
		_mark_set(fleet.planet, m)


## Warship fleets (slots 4-13): without destroyers they invade; with them they hunt when strong
## or under way. Either may then join a fleet of their kind.
func _warships(fleet: Fleet, first: int) -> void:
	if _ships(fleet, 4) < 1:
		invade(fleet)
		if fleet.waypoints.size() == 1 and w.rng.random(100) < 75:
			if first < 10:
				F.join_nearest(w, fleet, 6, 9, GROUP_JOIN[0], GROUP_JOIN[1])
			else:
				F.join_nearest(w, fleet, 10, 13, GROUP_JOIN[0], GROUP_JOIN[1])
		return
	if wanted <= _ships(fleet, 4) * 2 or fleet.waypoints.size() > 1:
		F.direct_warship(w, fleet, own_warships, enemies, w.state.settings.computer_alliances)
	if fleet.waypoints.size() == 1 and w.rng.random(100) < 75:
		F.join_nearest(w, fleet, 4, 5, GROUP_JOIN[0], GROUP_JOIN[1])


## Colony ships: to the colony target, loading people at one of the player's planets; with no
## target the planet they are at is marked.
func _colony_ship(fleet: Fleet) -> void:
	var target: int = F.colony_target(w, fleet, false)["planet"]
	if target == -1:
		var here := fleet.waypoints[0]
		if here.target == "planet":
			_mark_set(here.target_id, _mark_get(here.target_id) | B_NO_TARGET)
		return
	w.select_fleet(fleet)
	if fleet.planet != -1 and w.state.planet(fleet.planet).owner == w.player:
		ClassicFreight.move_cargo(
			w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, COLONISTS_LOADED
		)
	if F.send_to_colonize(w, fleet, target) and fleet.waypoints.size() > 1:
		F.info_set(w, fleet.waypoints[1].target_id, INFO_COLONY, 4)


## Scouts (mine-laying frigates): after turn SCOUT_LAY_TURN, unless too few scout fleets are out
## (and joining another), sometimes to a random planet near by; otherwise they lay mines where
## they are.
func _scouts(fleet: Fleet) -> void:
	if not (
		_ships(fleet, SCOUT_SLOT) > 0 and turn > SCOUT_LAY_TURN and fleet.waypoints.size() == 1
	):
		return
	if (
		not (scout_fleets < 56 and (scout_fleets < 41 or w.rng.random(3) == 0))
		and F.join_nearest(w, fleet, 0, 0, SCOUT_JOIN[0], SCOUT_JOIN[1])
	):
		return
	if _ships(fleet, SCOUT_SLOT) > 6 and w.rng.random(5) == 0:
		var t := F.random_planet(w, fleet.x, fleet.y, SCOUT_REACH, true)
		if t != -1 and fleet.planet != t:
			F.clear_task(w, fleet)
			F.go(w, fleet, F.planet_waypoint(w, t, WARP, "lay_mines"))
			return
	if fleet.waypoints[0].task != "lay_mines":
		F.set_task(w, fleet, "lay_mines", {"raw": [LAY_FOREVER, LAY_FOREVER, 0, 0, 0]})


## `AI_Cybertrons_ColonistTransport`: at one of the player's planets a transport loads people
## from a big one (else unloads); at another player's planet without a starbase whose owner takes
## drops it drops them and turns home; then it heads, with people, for a small or underfilled
## colony near by (none: it unloads here), or, empty, for a big starbase planet. In deep space it
## heads for the nearest planet.
func colonist_transport(fleet: Fleet) -> void:
	var here: Planet = w.state.planet(fleet.planet) if fleet.planet != -1 else null
	var target: Planet = null
	if here == null:
		target = nearest_planet_to(fleet.x, fleet.y)
	else:
		var loaded := false
		w.select_fleet(fleet)
		if here.owner == w.player:
			if here.population <= TRANSPORT_POPULATION:
				ClassicFreight.move_cargo(
					w, fleet, {"planet": here.id}, Fleet.CARGO_COLONISTS, -TRANSPORT_LOAD
				)
			else:
				ClassicFreight.move_cargo(
					w, fleet, {"planet": here.id}, Fleet.CARGO_COLONISTS, TRANSPORT_LOAD
				)
				loaded = true
		elif (
			here.owner == -1
			or RaceMath.trait_param(
				w.state.player(here.owner).race, w.content, "ai.no_colonist_drops", 0
			)
			or here.starbase != null
		):
			loaded = fleet.cargo[Fleet.CARGO_COLONISTS] > 0
		else:
			var drop := F.planet_waypoint(w, here.id, 0, "transport")
			var cargo := []
			for c in 5:
				cargo.append(
					{"action": "unload_all" if c == Fleet.CARGO_COLONISTS else "none", "amount": 0}
				)
			drop.task_data = {"cargo": cargo}
			var wp0 := fleet.waypoints[0]
			if wp0.target == "planet" and wp0.target_id == here.id:
				F.change(w, fleet, 0, drop)
			elif fleet.waypoints.size() > 1:
				F.change(w, fleet, 1, drop)
			F.return_home(w, fleet, false)
		if not loaded:
			target = F.nearest_planet(w, here.id, _big_home)
		else:
			target = F.nearest_planet(w, here.id, func(p: Planet) -> bool: return _small(here, p))
			if target == null:
				target = F.nearest_planet(
					w, here.id, func(p: Planet) -> bool: return _underfilled(here, p)
				)
			if target == null:
				if here.owner == w.player:
					ClassicFreight.move_cargo(
						w, fleet, {"planet": here.id}, Fleet.CARGO_COLONISTS, -TRANSPORT_LOAD
					)
					_mark_set(here.id, _count_up(_mark_get(here.id), B_UNLOADED, B_UNLOADED_STEP))
			else:
				_mark_set(
					target.id, _count_up(_mark_get(target.id), B_TRANSPORTS, B_TRANSPORT_STEP)
				)
	if target != null:
		var warp := Retargeting.default_warp(fleet, w.me(), w.content, true)
		F.go(w, fleet, F.planet_waypoint(w, target.id, warp))


func nearest_planet_to(x: int, y: int) -> Planet:
	var best: Planet = null
	var best_d := 1000000000
	for p in w.state.planets:
		var d := F.d2(x, y, p.x, p.y)
		if d < best_d:
			best = p
			best_d = d
	return best


## `Pred_MyStarbasePlanetPop2200`.
func _big_home(p: Planet) -> bool:
	return p.owner == w.player and p.population > TRANSPORT_HOME_POPULATION and p.starbase != null


## `AI_IsSmallNearbyColony`: one of the player's planets under SMALL_COLONY with no transport
## heading there, within reach of `from`.
func _small(from: Planet, p: Planet) -> bool:
	var t := b_word(p.id) & B_TRANSPORTS
	if t == B_TRANSPORTS or p.owner != w.player or p.population >= SMALL_COLONY or t != 0:
		return false
	return F.d2(from.x, from.y, p.x, p.y) < NEAR_COLONY2


## `AI_IsUnderfilledNearbyColony`: one of the player's planets whose people, with COLONY_LEVEL
## per transport heading there, stay under COLONY_FULL, within reach of `from`.
func _underfilled(from: Planet, p: Planet) -> bool:
	var t := b_word(p.id) & B_TRANSPORTS
	if t == B_TRANSPORTS or p.owner != w.player:
		return false
	if p.population + (t >> 3) * COLONY_LEVEL >= COLONY_FULL:
		return false
	return F.d2(from.x, from.y, p.x, p.y) < NEAR_COLONY2


## `AI_Cybertrons_Invade`: a warship group gathers at the player's planets until it has the
## escort and the flagships, then sets out for the best target (as Robotoids, without troops or
## drops); a weakened group goes back to a starbase planet.
func invade(fleet: Fleet) -> void:
	var s := (
		2 * (_ships(fleet, 8) + _ships(fleet, 12))
		+ _ships(fleet, 6)
		+ _ships(fleet, 7)
		+ _ships(fleet, 10)
		+ _ships(fleet, 11)
	)
	var t := _ships(fleet, 9) + _ships(fleet, 13)
	if fleet.waypoints.size() > 1:
		var next := fleet.waypoints[1]
		if F.d2(fleet.x, fleet.y, next.x, next.y) < FLEET_KEEP2 or next.target != "fleet":
			if next.target == "fleet":
				return
			if next.target == "planet":
				var p := w.state.planet(next.target_id)
				if p == null:
					return
				if p.owner != -1 and (p.owner != w.player or p.starbase != null):
					return
				if int(w.seen_turn.get(p.id, 0)) != turn:
					return
	w.select_fleet(fleet)
	if fleet.planet == -1:
		F.send_to_nearest_enemy(w, fleet, SEEK_REACH)
		return
	var here := w.state.planet(fleet.planet)
	var target: Planet = null
	var set_out := false
	if here.owner == w.player:
		if s < escort or t < troops:
			if level < 2:
				return
			if s <= escort * 2 and s < 60:
				return
			if w.rng.random(10) > 4 and (s <= escort * 3 or w.rng.random(10) > 6):
				if s < 121 or w.rng.random(10) > 6:
					return
		set_out = true
	elif s < escort >> 1 or t < mini(troops / 2 - 1, 3):
		F.clear_task(w, fleet)
		if (
			level > 1
			and (
				(s > escort * 2 and w.rng.random(10) < 5)
				or (s > escort * 4 and w.rng.random(10) < 7)
				or (s > 120 and w.rng.random(10) < 7)
			)
		):
			set_out = true
		else:
			target = F.nearest_planet(
				w,
				here.id,
				func(p: Planet) -> bool: return p.owner == w.player and p.starbase != null
			)
	elif here.owner != -1:
		return
	else:
		set_out = true
	if set_out:
		if w.state.settings.computer_alliances:
			target = F.best_planet(
				w, here.id, func(p: Planet) -> int: return F.target_score(w, here, p, true)
			)
		if target == null:
			target = F.best_planet(
				w, here.id, func(p: Planet) -> int: return F.target_score(w, here, p, false)
			)
	var wp: Waypoint
	if target == null:
		var prey := F.nearest_fleet(w, fleet, func(f: Fleet) -> bool: return f.owner != w.player)
		if prey == null:
			return
		wp = F.fleet_waypoint(prey, WARP)
	else:
		var info: PackedByteArray = w.planet_info[target.id]
		F.info_set(w, target.id, INFO_TARGET, info[INFO_TARGET] | HEADED)
		wp = F.planet_waypoint(w, target.id, WARP)
	F.go(w, fleet, wp)


# --- Production --------------------------------------------------------------------------------


## Each of the player's planets (shuffled order): terraforming, colony ships, transports, scouts,
## then the economy's choice (`AI_Cybertrons_Economy`).
func _production() -> void:
	var me := w.me()
	for planet in w.own_planets:
		w.select_planet(planet.id)
		P.open(w)
		var changed := _plan_planet(planet, me)
		P.commit(w, changed)


func _plan_planet(planet: Planet, me: Player) -> bool:
	var rate := (
		me.race.growth_rate * RaceMath.trait_param(me.race, w.content, GROWTH_PCT, 100) / 100
	)
	var growth := planet.population * rate
	var out := P.output(w, planet)
	var cost := P.queue_cost(w, planet)
	for i in 4:
		if out[i] < cost[i]:
			return false
	var changed := false
	var hab := PlanetEconomy.hab_value(planet, me.race)
	var hab_t := F.terraformed_hab(w, planet)
	var spare_res := out[3] - cost[3]
	if hab < 10:
		P.add(w, P.standard(P.TERRAFORM), spare_res / PACKET_KG + 1, P.Mode.APPEND)
		return true
	if hab < hab_t and spare_res > PACKET_KG:
		P.add(w, P.standard(P.TERRAFORM), 1, P.Mode.APPEND)
		changed = true
	if planet.starbase == null or fort(planet):
		return changed
	var a := a_word(planet.id)
	var b := b_word(planet.id)
	if (
		(a & A_COLONY == 0 or growth > COLONY_GROWTH)
		and b & B_NO_TARGET == 0
		and colony_ships < COLONY_TOO_MANY
	):
		P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
		set_a_word(planet.id, a | A_COLONY)
		changed = true
		if growth > COLONY_SECOND_GROWTH and turn < COLONY_SECOND_TURN:
			P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
	else:
		set_a_word(planet.id, a & ~A_COLONY)
	if (
		planet.population > TRANSPORT_POPULATION
		and me.ship_design(2) != null
		and transport_ships < TRANSPORT_SHIPS
		and b & B_UNLOADED < 2
		and (
			F.nearest_planet(w, planet.id, func(p: Planet) -> bool: return _underfilled(planet, p))
			!= null
		)
	):
		P.add(w, P.ship(transport), 1, P.Mode.APPEND)
		changed = true
	var scout := me.ship_design(SCOUT_SLOT)
	var frigate: String = w.content.get_def("ai_design_template", TEMPLATE + "scout")["hull"]
	if (
		scout != null
		and scout.hull == frigate
		and w.rng.random(4) == 0
		and scout_ships < SCOUT_SHIPS_MAX
	):
		var n := 0
		for f in w.state.fleets:
			if f.planet == planet.id and _ships(f, SCOUT_SLOT) > 0 and f.owner == w.player:
				n = _ships(f, SCOUT_SLOT)
				break
		if (n < 10 or (n < 17 and w.rng.random(10) == 0)) and w.rng.random(n * 2 + 1) == 0:
			P.add(w, P.ship(SCOUT_SLOT), 4, P.Mode.APPEND)
			changed = true
	var guard := heavy if b & B_FEW_GUARDS != 0 else -1
	if guard == -1 and b & B_GUARDED == 0 and guard_fleets < FLEETS_GUARD_MAX:
		var enemy := F.nearest_planet(
			w, planet.id, func(p: Planet) -> bool: return p.owner != w.player and p.owner != -1
		)
		var near := enemy != null and F.d2(planet.x, planet.y, enemy.x, enemy.y) <= ENEMY_NEAR2
		guard = heavy if w.rng.random(100) < (50 if near else 10) else -1
	var dest := destroyer if idle_warships <= FLEETS_IDLE_MAX else -1
	var grp := group if busy_warships <= FLEETS_GROUP_MAX else -1
	var r := economy(planet, dest, grp, guard)
	if r != 0:
		changed = true
	if r == 1:
		busy_warships += 1
	elif r == 2:
		guard_fleets += 1
	elif r == 3:
		idle_warships += 1
	return changed


## `AI_Cybertrons_Economy`: with mines and factories mostly in use (else seldom), the newest
## warship group, a guard, or a destroyer. Returns 1, 2, 3 for what it added, 0 for nothing.
func economy(planet: Planet, dest: int, grp: int, guard: int) -> int:
	var r1 := w.rng.random(100)
	var me := w.me()
	var mines_room := maxi(
		(
			PlanetEconomy.operable_mines(planet, me.race, w.content)
			- PlanetEconomy.effective_mines(planet, me.race, w.content)
		),
		0
	)
	var factories := PlanetEconomy.operable_factories(planet, me.race, w.content)
	var factories_room := maxi(factories - mini(planet.factories, factories), 0)
	var odds := 90 if mines_room < 100 or factories_room < 100 else 60
	if w.rng.random(100) < odds:
		return 0
	if grp != -1 and r1 > 50:
		var first: int = GROUP_FIRST[grp]
		if me.ship_design(first) != null:
			P.add(w, P.ship(first), 2, P.Mode.APPEND)
		if me.ship_design(first + 1) != null:
			P.add(w, P.ship(first + 1), 2, P.Mode.APPEND)
		if me.ship_design(first + 2) != null and w.rng.random(100) < 75:
			P.add(w, P.ship(first + 2), 1, P.Mode.APPEND)
		if me.ship_design(first + 3) != null and w.rng.random(100) < 50:
			P.add(w, P.ship(first + 3), 1, P.Mode.APPEND)
		return 1
	if guard != -1 and r1 > 25:
		P.add(w, P.ship(guard), 1, P.Mode.APPEND)
		return 2
	if dest != -1:
		P.add(w, P.ship(dest), 1, P.Mode.APPEND)
		return 3
	return 0


# --- Formulas (S25) ----------------------------------------------------------------------------


## B44 fixed: the fleet passes mark the planets' own B words.
static func marks_base(planets: int, _last_loaded: int) -> int:
	return planets + 1


## B45 fixed: the target's own record (none: no record, -2).
static func packet_record(target: int) -> int:
	return target if target >= 0 else -2


## B46 fixed: the reach squared in full.
static func sector_reach(s2: int) -> int:
	return s2 * s2


## B48 fixed: a planet whose long throw is under way times its driver's target.
static func long_target(driver_target: int, _last_chosen: int) -> int:
	return driver_target
