class_name ClassicDesigns
extends RefCounted
## How the classic personalities make and retire designs (spec S22 "Classic designs"): a design
## from a template (a hull and a part class per slot, each slot filled with the best part of its
## class the player can use, as many as the slot holds), a picture and a name drawn from the
## hull's name list, and the starbase designs every classic personality keeps up to date.

const NAME_TRIES := 20
const NAME_NUMBERS := 100
const PICTURES := 4
const STARBASE_NAMES := "ai_design_names.starbase"
const OTHER_NAMES := "ai_design_names.utility"
const STATION := "ai_design_template.space_station"
const FORT := "ai_design_template.orbital_fort"
## Starbase slots that hold forts; the others hold stations (`AI_CreateDesign`).
const FORT_SLOTS := [1, 3, 6, 8]
## The two generations of stations and forts (`AI_UpdateStarbaseDesigns`), and how old the
## newest one gets before the other generation is designed.
const STATION_SLOTS := [0, 2, 4, 5, 7, 9]
const FORT_GENERATION_SLOTS := [1, 3, 6, 8]
const GENERATION_TURNS := 40
const STARBASE_REVIEW_TURN := 50
## Starbase design sizes: 1 small, 2 medium, 3 full.
const FULL := 3
## Part category whose slots a small starbase leaves empty.
const ORBITAL := "orbital"
## Personalities whose small starbases keep their single-part slots.
const KEEPS_SMALL_SLOTS := ["ai_personality.cybertrons"]


## The best part of an `ai_part_class` the player can use, or "" (`AI_BestPartOfClass`): the
## candidate groups in order, each best part first.
static func best_part(w: ClassicWorld, class_id: String) -> String:
	var order := PartRules.tech_order(w.content)
	for group: Array in w.content.get_def("ai_part_class", class_id)["candidates"]:
		for id: String in group:
			if PartRules.available(w.content.part(id), w.me(), order):
				return id
	return ""


## A design from template `template_id`, or null when the player cannot use the hull or a slot's
## class has no part it can use (`AI_OutfitDesign`): every slot holds as many parts as the hull
## allows.
static func from_template(w: ClassicWorld, template_id: String) -> Design:
	var template := w.content.get_def("ai_design_template", template_id)
	var hull := w.content.hull(template["hull"])
	if not PartRules.available(hull, w.me(), PartRules.tech_order(w.content)):
		return null
	var slots: Array = hull["slots"]
	var classes: Array = template["slots"]
	if classes.size() != slots.size():
		return null
	var design := Design.new()
	design.hull = template["hull"]
	for i in slots.size():
		var part := best_part(w, classes[i])
		if part.is_empty():
			return null
		design.parts.append(DesignSlot.new(part, int(slots[i]["max"])))
	return design


## Designs ship slot `slot` from a template, named from the hull's list, and gives the order;
## false when a part is missing or the order is refused.
static func outfit(w: ClassicWorld, slot: int, template_id: String) -> bool:
	var design := from_template(w, template_id)
	if design == null:
		return false
	design.slot = slot
	_name(w, design, false)
	return save(w, design, false)


## A starbase design (`AI_CreateDesign`) of `size` 1 (small) to 3 (full) in starbase slot `slot`:
## a fort in FORT_SLOTS (where a medium fort is a full one), a station elsewhere, unless
## `template_id` names another. Smaller sizes hold fewer parts: slots of 4 or more a quarter (size
## 1) or half (size 2); for size 1 smaller slots one part less, and orbital slots none.
static func create_starbase(
	w: ClassicWorld, slot: int, size: int, template_id: String = ""
) -> bool:
	if template_id.is_empty():
		template_id = FORT if FORT_SLOTS.has(slot) else STATION
		if template_id == FORT and size == 2:
			size = FULL
	var design := from_template(w, template_id)
	if design == null:
		return false
	if size < FULL:
		_shrink(w, design, size)
	design.slot = slot
	_name(w, design, true)
	return save(w, design, true)


static func _shrink(w: ClassicWorld, design: Design, size: int) -> void:
	var keeps := KEEPS_SMALL_SLOTS.has(w.personality_id())
	for entry in design.parts:
		if entry.count >= 4:
			entry.count = entry.count >> (FULL - size)
		elif size < 2 and not keeps:
			var orbital: bool = w.content.part(entry.part)["category"] == ORBITAL
			if orbital or entry.count > 1:
				entry.count -= 1
		if entry.count == 0:
			entry.part = ""


## Stores a design in its slot (`AI_SaveDesign`): a design already there is deleted first; the
## turn is stamped. False when the order is refused.
static func save(w: ClassicWorld, design: Design, starbase: bool) -> bool:
	if _design(w, design.slot, starbase) != null:
		delete(w, design.slot, starbase)
	design.turn_designed = w.state.turn
	design.built = 0
	design.remaining = 0
	var reason := (
		w
		. order(
			{
				"type": "design_change",
				"starbase": starbase,
				"slot": design.slot,
				"design": design.to_dict(),
			}
		)
	)
	if not reason.is_empty():
		return false
	if not starbase:
		# a design made this turn has no rating until the turn is loaded again
		w.ratings["%d/%d" % [w.player, design.slot]] = 0
	return true


## Empties a design slot.
static func delete(w: ClassicWorld, slot: int, starbase: bool) -> void:
	if _design(w, slot, starbase) == null:
		return
	w.order({"type": "design_delete", "starbase": starbase, "slot": slot})


static func _design(w: ClassicWorld, slot: int, starbase: bool) -> Design:
	return w.me().starbase_design(slot) if starbase else w.me().ship_design(slot)


## A picture and a name (`AI_NameDesign`). The picture is the first of the hull's four no design
## of that hull has, else one drawn. The name is drawn from the hull's list until no design has
## it (ship names are checked against every ship design, starbase names against the starbase
## designs of the same hull); after NAME_TRIES draws a number is drawn, then a name to go with it.
static func _name(w: ClassicWorld, design: Design, starbase: bool) -> void:
	var designs: Array[Design] = w.me().starbase_designs if starbase else w.me().ship_designs
	var first: int = w.content.hull(design.hull).get("pictures", 0)
	var used := [false, false, false, false]
	for d in designs:
		if d.hull == design.hull and d.picture >= first and d.picture < first + PICTURES:
			used[d.picture - first] = true
	var pick := used.find(false)
	if pick < 0:
		pick = w.rng.random(PICTURES)
	design.picture = first + pick
	var names := names_for(w.content, design.hull, starbase)
	for t in NAME_TRIES:
		var name: String = names[w.rng.random(names.size())]
		var taken := false
		for d in designs:
			if d.name == name and (not starbase or d.hull == design.hull):
				taken = true
				break
		if not taken:
			design.name = name
			return
	var number := w.rng.random(NAME_NUMBERS)
	design.name = "%s %d" % [names[w.rng.random(names.size())], number]


## The names for a hull's designs: the first `ai_design_names` listing the hull, else the list
## for other hulls.
static func names_for(content: ContentRegistry, hull: String, starbase: bool) -> Array:
	if starbase:
		return content.get_def("ai_design_names", STARBASE_NAMES)["names"]
	for id in content.ids("ai_design_names"):
		var def := content.get_def("ai_design_names", id)
		if (def.get("hulls", []) as Array).has(hull):
			return def["names"]
	return content.get_def("ai_design_names", OTHER_NAMES)["names"]


## The newest design among ship slots `low`..`high` (`AI_FindDesignForHulls`): the first of the
## latest turn designed. Designs older than `max_age` turns are deleted when no ships of them are
## left (even the one returned), else marked in `obsolete` (by slot). Returns {slot (-1 none),
## remaining: ships of the slots left, at most 32000}.
static func newest_in_slots(
	w: ClassicWorld, low: int, high: int, max_age: int, obsolete: Array
) -> Dictionary:
	var best := -1
	var best_turn := 0
	var remaining := 0
	for slot in range(low, high + 1):
		var d := w.me().ship_design(slot)
		if d == null:
			continue
		remaining += d.remaining
		if best == -1 or best_turn < d.turn_designed:
			best = slot
			best_turn = d.turn_designed
		if w.state.turn - d.turn_designed > max_age:
			if d.remaining == 0:
				delete(w, slot, false)
			else:
				obsolete[slot] = 1
	return {"slot": best, "remaining": mini(remaining, 32000)}


## Keeps the starbase designs (`AI_UpdateStarbaseDesigns`): a medium station in slot 2 and a full
## one in 4 when 2 is empty, a small fort in 1 when empty, a full fort in 3 when empty. From turn
## STARBASE_REVIEW_TURN, when the newest station (slots 0, 2, 4, 5, 7, 9) is GENERATION_TURNS old,
## the other generation (0, 2, 4 or 5, 7, 9) is designed small, medium, full, unless one of its
## designs still has starbases; likewise forts (1, 3 or 6, 8: small, full) when neither has any.
static func update_starbase_designs(w: ClassicWorld) -> void:
	var p := w.me()
	if p.starbase_design(2) == null:
		create_starbase(w, 2, 2)
		create_starbase(w, 4, 3)
	if p.starbase_design(1) == null:
		create_starbase(w, 1, 1)
	if p.starbase_design(3) == null:
		create_starbase(w, 3, 2)
	if w.state.turn < STARBASE_REVIEW_TURN:
		return
	var newest := _newest_starbase(w, STATION_SLOTS)
	if newest >= 0 and _starbase_turn(w, newest) + GENERATION_TURNS <= w.state.turn:
		var base := 5 if newest < 5 else 0
		var in_use := false
		for slot in [base, base + 2, base + 4]:
			var d := p.starbase_design(slot)
			if d != null and d.remaining != 0:
				in_use = true
				break
		if not in_use:
			create_starbase(w, base, 1)
			create_starbase(w, base + 2, 2)
			create_starbase(w, base + 4, 3)
	newest = _newest_starbase(w, FORT_GENERATION_SLOTS)
	if newest >= 0 and _starbase_turn(w, newest) + GENERATION_TURNS <= w.state.turn:
		var base := 6 if newest < 5 else 1
		var a := p.starbase_design(base)
		var b := p.starbase_design(base + 2)
		if (a == null or a.remaining == 0) and (b == null or b.remaining == 0):
			create_starbase(w, base, 1)
			create_starbase(w, base + 2, 2)


## The last of the latest designed starbase designs among `slots`, or -1.
static func _newest_starbase(w: ClassicWorld, slots: Array) -> int:
	var best := -1
	var best_turn := 0
	for slot: int in slots:
		var d := w.me().starbase_design(slot)
		if d != null and best_turn <= d.turn_designed:
			best = slot
			best_turn = d.turn_designed
	return best


## When a starbase slot's design was made (0 for an empty slot).
static func _starbase_turn(w: ClassicWorld, slot: int) -> int:
	var d := w.me().starbase_design(slot)
	return 0 if d == null else d.turn_designed


## `newer` when its starbase design is newer than `older`'s, else `older`
## (`AI_NewerStarbaseDesign05`, `AI_NewerStarbaseDesign16`).
static func newer_starbase(w: ClassicWorld, older: int, newer: int) -> int:
	var d := w.me().starbase_design(newer)
	if d != null and _starbase_turn(w, older) < d.turn_designed:
		return newer
	return older
