class_name ClassicMacinti
extends RefCounted
## The original's Macinti (spec S22 "Macinti", `AI_Macinti`): research by plan, designs by tech
## and turn (`AI_Macinti_Designs`), starbase designs reviewed by age (`AI_Macinti_ReviewDesigns`),
## production by planet (packets between rich planets, colony ships, miners, scouts, bombers,
## warships, nubians, genesis devices), miners moving to rich planets, freighters moving people
## (`AI_Macinti_MovePopulation`), warships invading (`AI_Macinti_Invade`) or hunting.

const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")

const RESEARCH_PLAN := "ai_research_plan.macinti"
const RESEARCH_PCT := 15
const TEMPLATE := "ai_design_template.macinti_"
## Formula ids (S25 B51, B52): the design whose ships cap scout building, and whether a count of
## leading rich minerals means all three.
const SCOUT_CAP_DESIGN := "ai.macinti_scout_cap_design"
const ALL_RICH := "ai.macinti_all_rich"
## Design slots.
const SCOUT_SLOT := 0
const COLONY_SLOT := 1
const EARLY_COLONY_SLOT := 7
const MINER_SLOTS := [14, 15]
const SPLIT_TURN := 80
const EARLY_TURN := 40
## Retirement ages: before turn RETIRE_TURNS[i], RETIRE_AGES[i] turns; later the last.
const RETIRE_TURNS := [120, 200]
const RETIRE_AGES := [50, 70, 100]
const MINER_AGE := 5000
const ESCORT_START := 6
const ESCORT_MAX := 50
const TROOPS_START := 6
const TROOPS_MAX := 12
## Tags of parts the original looks up by number: the Galaxy Scoop, the Alien Miner and the
## Trans-Galactic Super Scoop.
const GALAXY_SCOOP := "part.engine.galaxy_scoop"
const ALIEN_MINER := "part.mining_robot.alien_miner"
const SUPER_SCOOP := "part.engine.trans_galactic_super_scoop"
const COLONY_HULL := "hull.colony_ship"
const NUBIAN_HULL := "hull.nubian"
const BATTLESHIP_HULL := "hull.battleship"
## planet_info bytes.
const INFO_OTHERS := 9
const INFO_TARGET := 10
const INFO_OWN := 13
const INFO_PEOPLE := 14
const HEADED := 0x80
const WARP := 4
const SEEK_REACH := 450
const FLEET_KEEP2 := 62501
const OBJECT_KEEP2 := 40000

var w: ClassicWorld
var turn := 0
var level := 0
var escort := 0
var troops := 0
var obsolete := []
## Slot 7 still holds the early colony design (a colony ship hull before turn 40).
var early_colony := false
## The last warship slot (7, or 6 while slot 7 holds the early colony design).
var last_warship := 7
## Newest designs: nubians (12-13) and their ships, miners (14-15), freighters (10-11), bombers
## (8-9), warships (2-4 and 5-last); -1 none.
var nubian := -1
var nubian_ships := 0
var miner := -1
var freighter := -1
var bomber := -1
var warship_a := -1
var warship_b := -1
var colony_slot := COLONY_SLOT
var colony := {}
var verdicts := PackedByteArray()
## Fleet counts (`local_a2`, `local_a6`, `local_aa`, `local_a8`, `local_ac`).
var miner_fleets := 0
var scout_fleets := 0
var scout_fleets_at_start := 0
var nubian_fleets := 0
var freighter_fleets := 0
var warship_fleets := 0
var genesis_left := 0
var own_warships: Array[Fleet] = []
var enemies: Array[Fleet] = []


## One turn of Macinti on world `w`.
static func play(world: ClassicWorld) -> void:
	var t := ClassicMacinti.new()
	t.w = world
	t.turn = world.state.turn
	t.level = world.me().ai_level
	t._play()


func _play() -> void:
	var me := w.me()
	ClassicResearch.follow_plan(w, RESEARCH_PLAN, RESEARCH_PCT)
	_early_colony()
	F.merge_by_slots(w, [2, 3, 4, 5, 6, 8, 9] if early_colony else [2, 3, 4, 5, 6, 7, 8, 9])
	F.merge_by_slots(w, [0])
	F.merge_by_slots(w, [14, 15])
	F.merge_by_slots(w, [12, 13])
	_thresholds()
	_retire()
	if turn > SPLIT_TURN:
		var old := []
		for slot in F.DESIGN_SLOTS:
			if obsolete[slot] != 0:
				old.append(slot)
		F.split_slots(w, old)
		# S25 B49: the original's flag arrays overlap the obsolete list here
		F.split_slots(w, [0])
		F.split_slots(w, [1])
		F.split_slots(w, [14, 15])
		F.split_slots(w, [10, 11])
	designs(w)
	verdicts = review_designs(w)
	w.macinti_verdicts = verdicts
	colony = ClassicFreight.colony_ships(w)
	var c1 := me.ship_design(COLONY_SLOT)
	var c7 := me.ship_design(EARLY_COLONY_SLOT)
	colony_slot = COLONY_SLOT
	if not _engine_is(c1, GALAXY_SCOOP) and c7 != null and c7.hull == COLONY_HULL:
		colony_slot = EARLY_COLONY_SLOT
	if colony_slot == COLONY_SLOT and early_colony and c1 != null and turn - c1.turn_designed > 5:
		obsolete[EARLY_COLONY_SLOT] = 2
	for p in w.state.planets:
		F.info_set(w, p.id, INFO_PEOPLE, 0)
	_count_fleets()
	for p in w.state.planets:
		F.info_set(w, p.id, INFO_OWN, 0)
	for p in w.own_planets:
		F.info_set(w, p.id, INFO_OWN, 1)
	genesis_left = 0
	if turn >= 121 and _available(SUPER_SCOOP):
		genesis_left = mini(w.planet_count / 20, 10)
	for p in w.state.planets:
		if w.loaded.has(p.id) and p.owner != w.player and p.owner != -1:
			var worth := mini(p.population_estimate / 250 + 1, 6)
			if p.starbase != null:
				worth += 1
			F.info_set(w, p.id, INFO_TARGET, worth)
			F.info_set(w, p.id, INFO_OTHERS, 1)
	ClassicMacintiProduction.plan(self)
	ClassicMacintiFleets.direct(self)
	ClassicPlanning.manage(w, 0)
	ClassicPlanning.finish_turn(w)


func _early_colony() -> void:
	var me := w.me()
	var c7 := me.ship_design(EARLY_COLONY_SLOT)
	early_colony = false
	if turn < EARLY_TURN or (c7 != null and c7.hull == COLONY_HULL):
		early_colony = true
		if _available(GALAXY_SCOOP) and c7 != null and c7.remaining == 0:
			ClassicDesigns.delete(w, EARLY_COLONY_SLOT, false)
			early_colony = false
	last_warship = 7 - (1 if early_colony else 0)


func _thresholds() -> void:
	escort = ESCORT_START
	if turn > 130:
		escort = (turn - 120) / 20 + ESCORT_START
	escort = mini(escort, ESCORT_MAX)
	troops = TROOPS_START
	if turn > 115:
		troops = (turn - 100) / 22 + TROOPS_START
	troops = mini(troops, TROOPS_MAX)


## Whether the player can use part `id` (`LookupPart`).
func _available(id: String) -> bool:
	return PartRules.available(w.content.part(id), w.me(), PartRules.tech_order(w.content))


static func _engine_is(d: Design, id: String) -> bool:
	return d != null and not d.parts.is_empty() and d.parts[0].part == id


static func _part_in(d: Design, slot: int, id: String) -> bool:
	return d != null and d.parts.size() > slot and d.parts[slot].part == id


static func ships(fleet: Fleet, slot: int) -> int:
	if slot < 0:
		return 0
	var s := fleet.stack_for(slot)
	return 0 if s == null else s.count


## `AI_FindDesignForHulls` for each slot group, nubians and miners kept; an old miner without
## Alien Miners in its third slot makes way once the player has them.
func _retire() -> void:
	var age: int = RETIRE_AGES[-1]
	for i in RETIRE_TURNS.size():
		if turn < RETIRE_TURNS[i]:
			age = RETIRE_AGES[i]
			break
	obsolete = []
	obsolete.resize(F.DESIGN_SLOTS)
	obsolete.fill(0)
	var me := w.me()
	var n := ClassicDesigns.newest_in_slots(w, 12, 13, age, obsolete)
	nubian = n["slot"]
	nubian_ships = n["remaining"]
	for slot in [12, 13]:
		var d := me.ship_design(slot)
		if obsolete[slot] != 0 and d != null and d.hull == NUBIAN_HULL:
			obsolete[slot] = 0
	miner = ClassicDesigns.newest_in_slots(w, 14, 15, MINER_AGE, obsolete)["slot"]
	if me.ship_design(15) != null and _available(ALIEN_MINER):
		var d14 := me.ship_design(14)
		var d15 := me.ship_design(15)
		var t := -1
		if not _part_in(d14, 2, ALIEN_MINER):
			t = 14
		elif (
			not _part_in(d15, 2, ALIEN_MINER)
			and _available(GALAXY_SCOOP)
			and not _engine_is(d14, GALAXY_SCOOP)
		):
			t = 15
		if t != -1:
			var d := me.ship_design(t)
			if d == null or d.remaining == 0:
				ClassicDesigns.delete(w, t, false)
			else:
				# S25 B50: the original marks slot 14 whichever it meant
				obsolete[t] = 3
	freighter = ClassicDesigns.newest_in_slots(w, 10, 11, age, obsolete)["slot"]
	bomber = ClassicDesigns.newest_in_slots(w, 8, 9, age, obsolete)["slot"]
	warship_a = ClassicDesigns.newest_in_slots(w, 2, 4, age, obsolete)["slot"]
	warship_b = ClassicDesigns.newest_in_slots(w, 5, last_warship, age, obsolete)["slot"]


## The first count of the player's fleets, and colonists heading for planets marked.
func _count_fleets() -> void:
	for fleet in w.state.fleets:
		if fleet.owner != w.player:
			continue
		if miner != -1 and (ships(fleet, 14) != 0 or ships(fleet, 15) != 0):
			miner_fleets += 1
		if ships(fleet, SCOUT_SLOT) != 0:
			scout_fleets += 1
		if nubian != -1 and (ships(fleet, 12) != 0 or ships(fleet, 13) != 0):
			nubian_fleets += 1
		if freighter != -1 and (ships(fleet, 10) != 0 or ships(fleet, 11) != 0):
			freighter_fleets += 1
			if (
				fleet.planet == -1
				and fleet.waypoints.size() > 1
				and fleet.waypoints[1].target == "planet"
				and fleet.cargo[Fleet.CARGO_COLONISTS] > 0
			):
				var t: int = fleet.waypoints[1].target_id
				var info: PackedByteArray = w.planet_info[t]
				F.info_set(w, t, INFO_PEOPLE, info[INFO_PEOPLE] | 1)
		for slot in range(2, 10):
			if ships(fleet, slot) != 0:
				warship_fleets += 1
				break
	scout_fleets_at_start = scout_fleets


# --- Designs -----------------------------------------------------------------------------------


## `AI_Macinti_Designs`: designs by tech level and turn (spec S22 "Macinti", step 3).
static func designs(world: ClassicWorld) -> void:
	var me := world.me()
	var turn := world.state.turn
	var order := PartRules.tech_order(world.content)
	var lv := func(field: String) -> int: return me.tech_levels[order["tech_field." + field]]
	var en: int = lv.call("energy")
	var wp: int = lv.call("weapons")
	var pr: int = lv.call("propulsion")
	var co: int = lv.call("construction")
	var el: int = lv.call("electronics")
	var bi: int = lv.call("biotech")
	var d := func(slot: int) -> Design: return me.ship_design(slot)
	var high := me.ai_level >= 2
	for slot in MINER_SLOTS:
		if d.call(slot) != null:
			continue
		if high and slot == 15 and co < 15:
			continue
		if not _outfit(world, slot, "ultra_miner" if high else "maxi_miner") and slot == 14:
			_outfit(world, slot, "miner" if high else "mini_miner")
	if d.call(12) == null and wp >= 5 and pr >= 6:
		if not _outfit(world, 12, "nubian_1"):
			_tries(world, 12, "destroyer_a%d")
	if d.call(13) == null and wp >= 10 and pr >= 9:
		if not _outfit(world, 13, "nubian_1"):
			_tries(world, 13, "destroyer_b%d")
	if d.call(10) == null:
		if not _outfit(world, 10, "freighter_large"):
			_outfit(world, 10, "freighter_medium")
	if d.call(11) == null:
		_outfit(world, 11, "freighter_large")
	var two: Design = d.call(2)
	if turn < 20 and two != null and two.remaining == 0:
		ClassicDesigns.delete(world, 2, false)
	for slot in [2, 3, 4]:
		if d.call(slot) != null:
			continue
		var before: Design = d.call(slot - 1)
		var designed := before.turn_designed if before != null else 0
		if slot == 2 or turn - designed > 20:
			_tries(world, slot, "cruiser_%d")
	if turn < EARLY_TURN and d.call(EARLY_COLONY_SLOT) == null:
		_outfit(world, EARLY_COLONY_SLOT, "colony_ship")
	var one: Design = d.call(COLONY_SLOT)
	if (
		PartRules.available(world.content.part(GALAXY_SCOOP), me, order)
		and one != null
		and one.remaining == 0
		and not _engine_is(one, GALAXY_SCOOP)
	):
		ClassicDesigns.delete(world, COLONY_SLOT, false)
		_outfit(world, COLONY_SLOT, "colony_ship")
	for slot in [5, 6, 7]:
		if d.call(slot) != null:
			continue
		var before: Design = d.call(slot - 1)
		if slot != 5 and (before == null or turn - before.turn_designed <= 20):
			continue
		var pool := "battleship_a%d" if slot == 5 else "battleship_b%d"
		if slot == 7 and world.rng.random(2) != 0:
			pool = "battleship_a%d"
		if world.rng.random(3) != 0 and _outfit(world, slot, "nubian_0"):
			continue
		_tries(world, slot, pool)
	for slot in [8, 9]:
		if d.call(slot) != null or wp < 14:
			continue
		var before: Design = d.call(slot - 1)
		if slot != 8 and (before == null or turn - before.turn_designed <= 15):
			continue
		if not _outfit(world, slot, "battleship_flag"):
			_outfit(world, slot, "b52_%d" % (slot - 8))
	var scout: Design = d.call(SCOUT_SLOT)
	var frigate: String = world.content.get_def("ai_design_template", TEMPLATE + "scout")["hull"]
	if (
		(scout == null or scout.hull != frigate)
		and high
		and (scout == null or scout.remaining == 0)
		and bi >= 4
		and el >= 5
		and co >= 6
		and pr >= 6
		and en >= 6
	):
		ClassicDesigns.delete(world, SCOUT_SLOT, false)
		_outfit(world, SCOUT_SLOT, "scout")


## Up to five tries, each a draw of 4 picking pool template 0-3.
static func _tries(world: ClassicWorld, slot: int, pool: String) -> bool:
	for i in 5:
		if _outfit(world, slot, pool % world.rng.random(4)):
			return true
	return false


static func _outfit(world: ClassicWorld, slot: int, template: String) -> bool:
	return ClassicDesigns.outfit(world, slot, TEMPLATE + template)


## `AI_Macinti_ReviewDesigns`: a verdict per starbase slot (0 keep, 1 could not be made, 2 refresh,
## 3 replace) that the production pass upgrades by (ClassicPlanning).
static func review_designs(world: ClassicWorld) -> PackedByteArray:
	var me := world.me()
	var turn := world.state.turn
	var v := PackedByteArray()
	v.resize(10)
	v.fill(0)
	var base_templates := ["", "dock", "station", "ultra_station"]
	for slot in [1, 2, 3]:
		var d := me.starbase_design(slot)
		if d != null and d.remaining != 0:
			var age := turn - d.turn_designed
			if age < 35:
				var dock := me.starbase_design(1)
				var docked := dock != null and dock.parts.size() == 8
				if turn < 26 or slot != 1 or docked:
					v[slot] = 0
				else:
					v[slot] = 3
			elif age < 50:
				v[slot] = 2
			else:
				v[slot] = 3
		else:
			var size := 1 if slot < 3 else 2
			var made := ClassicDesigns.create_starbase(
				world, slot, size, TEMPLATE + base_templates[slot]
			)
			v[slot] = 0 if made else 1
	var best := -1
	for slot in [1, 2, 3]:
		if v[slot] <= 1:
			continue
		if best == -1 or v[best] < v[slot]:
			best = slot
		elif v[best] == v[slot]:
			var a := me.starbase_design(slot)
			var b := me.starbase_design(best)
			if (a.turn_designed if a else 0) < (b.turn_designed if b else 0):
				best = slot
	for slot in [1, 2, 3]:
		if v[slot] > 1 and slot != best:
			v[slot] = 0
	var generation_templates := ["", "", "", "station_std", "ultra_station_b", "death_star"]
	for g in 2:
		var first := 4 + 3 * g
		var in_use := false
		for k in 3:
			var d := me.starbase_design(first + k)
			if d != null and d.remaining != 0:
				in_use = true
				break
		if in_use:
			continue
		for k in 3:
			for t in [5, 4, 3]:
				var template: String = generation_templates[t]
				var id := (
					"ai_design_template.space_station"
					if template == "station_std"
					else TEMPLATE + template
				)
				if ClassicDesigns.create_starbase(world, first + k, k + 1, id):
					break
	for slot in range(4, 10):
		v[slot] = 1 if me.starbase_design(slot) == null else 0
	var t4 := me.starbase_design(4)
	var t7 := me.starbase_design(7)
	var newer := 4
	var older := 7
	if (t4.turn_designed if t4 else 0) < (t7.turn_designed if t7 else 0):
		newer = 7
		older = 4
	var od := me.starbase_design(older)
	var mark := 2 if turn - (od.turn_designed if od else 0) < 30 else 3
	for k in 3:
		v[older + k] = mark
	var nd := me.starbase_design(newer)
	var hulls := [
		"hull.orbital_fort", "hull.space_dock", "hull.space_station", "hull.ultra_station"
	]
	var rank := hulls.find(nd.hull) if nd != null else 0
	if rank == -1:
		rank = 4
	if rank < 4:
		v[3] = 2
		if rank < 3:
			v[2] = 2
	return v


# --- Formulas (S25) ----------------------------------------------------------------------------


## B51 fixed: scouts are capped by the scout design's ships.
static func scout_cap_design(_miner_slot: int) -> int:
	return SCOUT_SLOT


## B52 fixed: all three minerals lead.
static func all_rich(count: int) -> bool:
	return count == 3
