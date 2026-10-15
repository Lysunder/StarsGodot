class_name BaselineDesigns
extends RefCounted
## The baseline brain's ship designs (spec S22 "The baseline brain"): a scout (scout hull, the
## engine that goes furthest, the longest-range scanner, a fuel tank) and a colony ship (colony
## ship hull, that engine, a colonizer module). Compared by `merit`: the fastest warp at which it
## still goes USEFUL_RANGE light-years, then its range at that warp.

const SCOUT := "scout"
const COLONY := "colony"
const HULLS := {SCOUT: "hull.scout", COLONY: "hull.colony_ship"}
const NAMES := {SCOUT: "Pathseeker", COLONY: "Homesteader"}
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
