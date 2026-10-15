class_name BaselineDesigns
extends RefCounted
## The baseline brain's ship designs (spec S22 "The baseline brain"): a scout (scout hull, the
## engine that goes furthest, the longest-range scanner, a fuel tank) and a colony ship (colony
## ship hull, that engine, a colonizer module); a dock (the cheapest starbase hull that docks
## and refuels ships, bare); a warship (the most advanced combat hull, every weapon slot with the
## strongest weapon, armor slots with the best armor, shield-only slots with the best shield,
## compared by `strength`); a bomber (the most advanced bomber hull, every bomb slot with the bomb
## that kills the most people, compared by `bomb_power`). Other ships are compared by `merit`:
## the fastest warp at which they still go USEFUL_RANGE light-years, then their range there.

const SCOUT := "scout"
const COLONY := "colony"
const DOCK := "dock"
const WARSHIP := "warship"
const BOMBER := "bomber"
const BOMBER_HULLS := ["hull.mini_bomber", "hull.b_17_bomber", "hull.b_52_bomber"]
## Bombs by tag that kill people (installation-only and retro bombs left out).
const KILLING_BOMBS := ["normal", "smart"]
## Combat hulls, least advanced first; the last one the player has is used.
const WAR_HULLS := [
	"hull.destroyer", "hull.cruiser", "hull.battle_cruiser", "hull.battleship", "hull.dreadnought"
]
const WEAPONS := ["beam", "torpedo"]
## Beams that only drain shields are no use on their own.
const SAPPER := "sapper"
const HULLS := {SCOUT: "hull.scout", COLONY: "hull.colony_ship"}
const NAMES := {
	SCOUT: "Pathseeker",
	COLONY: "Homesteader",
	DOCK: "Waystation",
	WARSHIP: "Lancer",
	BOMBER: "Hammerfall",
}
const USEFUL_RANGE := 300
## Ranges are capped here when compared (an engine burning no fuel has unlimited range).
const RANGE_CAP := 99999
## A new design is worth saving at the same warp when it goes this many percent as far.
const BETTER_PCT := 120
const COLONIZER_TAG := "colonizer"
const FUEL_TANK := "part.mechanical.fuel_tank"
const WARP10_SAFE_TAG := "warp10_safe"

var _view: PlayerView
var _content: ContentRegistry


func _init(view: PlayerView, content: ContentRegistry) -> void:
	_view = view
	_content = content


## [warp, range]: the fastest warp at which the design goes USEFUL_RANGE light-years (0 if none)
## and its range there, capped at RANGE_CAP. Warp 10 counts only for warp-10-safe engines (it
## damages the others' ships, S12).
func merit(d: Design) -> Array[int]:
	var top := 10 if _warp10_safe(d) else 9
	for warp in range(top, 0, -1):
		var r := Movement.design_range(d, _view.me(), warp, _content)
		if r >= USEFUL_RANGE:
			return [warp, mini(r, RANGE_CAP)]
	return [0, maxi(Movement.design_range(d, _view.me(), 1, _content), 0)]


func _warp10_safe(d: Design) -> bool:
	var found := false
	for slot in d.parts:
		if slot.part.is_empty() or _content.part(slot.part)["category"] != "engine":
			continue
		found = true
		if not _content.part(slot.part).get("tags", []).has(WARP10_SAFE_TAG):
			return false
	return found


## Whether design `a` is better than `b`: faster, or as fast with BETTER_PCT of the range (`by`
## false: any longer range counts).
func better(a: Design, b: Design, by: bool = true) -> bool:
	var ma := merit(a)
	var mb := merit(b)
	if ma[0] != mb[0]:
		return ma[0] > mb[0]
	return ma[1] * 100 >= mb[1] * (BETTER_PCT if by else 100) and ma[1] > mb[1]


## The best design of `kind` the player could make now, or null when it lacks the hull or a part.
func build(kind: String) -> Design:
	if kind == WARSHIP:
		return _build_warship()
	if kind == BOMBER:
		return _build_bomber()
	if kind == DOCK:
		var dock := cheapest_dock_hull()
		if dock.is_empty():
			return null
		var bare := _view.designer.blank_design(dock)
		bare.name = NAMES[kind]
		return bare
	var hull: String = HULLS[kind]
	if not _view.designer.available_hulls(false).has(hull):
		return null
	var d := _view.designer.blank_design(hull)
	d.name = NAMES[kind]
	var slots: Array = _content.hull(hull)["slots"]
	var engine_at := -1
	for i in slots.size():
		var accepts: Array = slots[i]["accepts"]
		var part := ""
		if accepts.has("engine"):
			engine_at = i
		elif accepts.has("scanner") and kind == SCOUT and accepts.size() == 1:
			part = _best_scanner()
		elif accepts.has("mechanical") and kind == COLONY:
			part = _colonizer()
		elif accepts.has("mechanical") and _available(FUEL_TANK):
			part = FUEL_TANK
		if not part.is_empty():
			d.parts[i].part = part
			d.parts[i].count = int(slots[i]["max"])
	if engine_at < 0:
		return null
	_fit_engine(d, engine_at, int(slots[engine_at]["max"]))
	if kind == COLONY and not _has_colonizer(d):
		return null
	if not PartRules.design_problem(d, false, _view.me(), _content).is_empty():
		return null
	return d


func _build_warship() -> Design:
	var hulls := _view.designer.available_hulls(false)
	var hull := ""
	for h: String in WAR_HULLS:
		if hulls.has(h):
			hull = h
	if hull.is_empty():
		return null
	var d := _view.designer.blank_design(hull)
	d.name = NAMES[WARSHIP]
	var weapon := _best_weapon()
	var armor := _best_by("armor", "armor")
	var shield := _best_by("shield", "shield")
	var slots: Array = _content.hull(hull)["slots"]
	var engine_at := -1
	for i in slots.size():
		var accepts: Array = slots[i]["accepts"]
		var part := ""
		if accepts.has("engine"):
			engine_at = i
		elif accepts.has("beam") or accepts.has("torpedo"):
			part = weapon
		elif accepts.has("armor"):
			part = armor
		elif accepts.has("shield"):
			part = shield
		if not part.is_empty():
			d.parts[i].part = part
			d.parts[i].count = int(slots[i]["max"])
	if engine_at < 0 or weapon.is_empty():
		return null
	_fit_engine(d, engine_at, int(slots[engine_at]["max"]))
	if not PartRules.design_problem(d, false, _view.me(), _content).is_empty():
		return null
	return d


func _build_bomber() -> Design:
	var hulls := _view.designer.available_hulls(false)
	var hull := ""
	for h: String in BOMBER_HULLS:
		if hulls.has(h):
			hull = h
	var bomb := _best_bomb()
	if hull.is_empty() or bomb.is_empty():
		return null
	var d := _view.designer.blank_design(hull)
	d.name = NAMES[BOMBER]
	var slots: Array = _content.hull(hull)["slots"]
	var engine_at := -1
	for i in slots.size():
		var accepts: Array = slots[i]["accepts"]
		if accepts.has("engine"):
			engine_at = i
		elif accepts.has("bomb"):
			d.parts[i].part = bomb
			d.parts[i].count = int(slots[i]["max"])
	if engine_at < 0:
		return null
	_fit_engine(d, engine_at, int(slots[engine_at]["max"]))
	if not PartRules.design_problem(d, false, _view.me(), _content).is_empty():
		return null
	return d


func _best_bomb() -> String:
	var best := ""
	var best_rate := 0
	for part in _view.designer.available_parts(["bomb"]):
		var tags: Array = _content.part(part).get("tags", [])
		if not (tags.has(KILLING_BOMBS[0]) or tags.has(KILLING_BOMBS[1])):
			continue
		var rate := int(_content.part(part).get("stats", {}).get("kill_rate", 0))
		if rate > best_rate:
			best = part
			best_rate = rate
	return best


## A bomber's power: the kill rates of its bombs times their counts.
func bomb_power(d: Design) -> int:
	var total := 0
	for slot in d.parts:
		if not slot.part.is_empty() and _content.part(slot.part)["category"] == "bomb":
			total += int(_content.part(slot.part).get("stats", {}).get("kill_rate", 0)) * slot.count
	return total


## The weapon with the most damage it can deal: power x (range + 1) x accuracy percent (beams
## always hit); sappers left out.
func _best_weapon() -> String:
	var best := ""
	var best_score := -1
	for part in _view.designer.available_parts(WEAPONS):
		if part.contains(SAPPER):
			continue
		var score := _weapon_score(part)
		if score >= best_score:
			best = part
			best_score = score
	return best


func _weapon_score(part: String) -> int:
	var stats: Dictionary = _content.part(part).get("stats", {})
	var accuracy := int(stats.get("accuracy", 100))
	return int(stats.get("power", 0)) * (int(stats.get("range", 0)) + 1) * accuracy


func _best_by(category: String, stat: String) -> String:
	var best := ""
	var best_value := -1
	for part in _view.designer.available_parts([category]):
		var v := int(_content.part(part).get("stats", {}).get(stat, 0))
		if v >= best_value:
			best = part
			best_value = v
	return best


## A warship's strength: the weapons' scores times what it can take (armor + shields).
func strength(d: Design) -> int:
	var attack := 0
	var shields := 0
	for slot in d.parts:
		if slot.part.is_empty():
			continue
		var category: String = _content.part(slot.part)["category"]
		if WEAPONS.has(category) and not slot.part.contains(SAPPER):
			attack += _weapon_score(slot.part) * slot.count
		shields += int(_content.part(slot.part).get("stats", {}).get("shield", 0)) * slot.count
	return attack * (PartRules.armor(d, _content, _view.me().race) + shields)


## Whether a ship design carries weapons (beams or torpedoes).
func is_armed(d: Design) -> bool:
	if d == null:
		return false
	for slot in d.parts:
		if not slot.part.is_empty() and WEAPONS.has(_content.part(slot.part)["category"]):
			return true
	return false


## The available starbase hull with a dock that costs the fewest resources, "" for none.
func cheapest_dock_hull() -> String:
	var best := ""
	var best_cost := 0
	for hull in _view.designer.available_hulls(true):
		var def := _content.hull(hull)
		if int(def.get("dock", 0)) == 0:
			continue
		var cost := int(def.get("cost", {}).get("resources", 0))
		if best.is_empty() or cost < best_cost:
			best = hull
			best_cost = cost
	return best


## Whether a starbase design is a dock of ours: that hull, no parts.
func is_dock(d: Design) -> bool:
	if d == null or int(_content.hull(d.hull).get("dock", 0)) == 0:
		return false
	for slot in d.parts:
		if not slot.part.is_empty():
			return false
	return true


func _available(part: String) -> bool:
	return _view.designer.available_parts([_content.part(part)["category"]]).has(part)


## The engine with the best merit (the most advanced on ties).
func _fit_engine(d: Design, at: int, count: int) -> void:
	var best := ""
	var best_merit: Array[int] = [-1, -1]
	for engine in _view.designer.available_parts(["engine"]):
		d.parts[at].part = engine
		d.parts[at].count = count
		var m := merit(d)
		if m[0] > best_merit[0] or (m[0] == best_merit[0] and m[1] >= best_merit[1]):
			best = engine
			best_merit = m
	d.parts[at].part = best
	d.parts[at].count = count if not best.is_empty() else 0


func _best_scanner() -> String:
	var best := ""
	var best_range := -1
	for part in _view.designer.available_parts(["scanner"]):
		var r := int(_content.part(part).get("stats", {}).get("scan_range", 0))
		if r >= best_range:
			best = part
			best_range = r
	return best


func _colonizer() -> String:
	for part in _view.designer.available_parts(["mechanical"]):
		if _content.part(part).get("tags", []).has(COLONIZER_TAG):
			return part
	return ""


func _has_colonizer(d: Design) -> bool:
	for slot in d.parts:
		if not slot.part.is_empty() and _content.part(slot.part).get("tags", []).has(COLONIZER_TAG):
			return true
	return false
