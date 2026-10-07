class_name PartRules
extends RefCounted
## Which parts and hulls a player can use, and simple design totals (spec S04, S06).

const SHIELD_MAX := 65535

const PICTURES_PER_HULL := 4


## True when the player's tech levels meet the item's requirements and the race may use it
## (race_may_use: `required_traits` at least one, `forbidden_traits` none, a Mystery Trader item
## only once the player has it). `tech_order` maps tech field ids to
## their index in the player's tech levels.
static func available(item: Dictionary, player: Player, tech_order: Dictionary) -> bool:
	var tech: Dictionary = item.get("tech", {})
	for field: String in tech:
		if player.tech_levels[tech_order[field]] < int(tech[field]):
			return false
	return race_may_use(item, player)


## True when the race's traits allow the item and, for a Mystery Trader item, the player has it
## (`Part_NeedsMysteryTraderItem`); tech levels are not checked.
static func race_may_use(item: Dictionary, player: Player) -> bool:
	if item.get("mystery_trader", false) and not player.trader_parts.has(item.get("id", "")):
		return false
	var traits := traits_of(player.race)
	var required: Array = item.get("required_traits", [])
	if not required.is_empty() and not required.any(func(t: String) -> bool: return traits.has(t)):
		return false
	for t: String in item.get("forbidden_traits", []):
		if traits.has(t):
			return false
	return true


## Why a design is not one the player can make (S04, S11 `design_change`), or "": hull of the
## right kind, one entry per hull slot, parts accepted by their slots within the maximum count,
## a picture among the hull's four, and only hulls and parts the player can use.
static func design_problem(
	design: Design, starbase: bool, player: Player, content: ContentRegistry
) -> String:
	if not content.ids("hull").has(design.hull):
		return "no such hull"
	var hull := content.hull(design.hull)
	if bool(hull.get("starbase", false)) != starbase:
		return "wrong kind of hull"
	if design_picture(design.picture, hull) != design.picture:
		return "bad picture"
	var order := tech_order(content)
	if not available(hull, player, order):
		return "hull not available"
	var slots: Array = hull["slots"]
	if design.parts.size() != slots.size():
		return "one entry per hull slot"
	for i in slots.size():
		var entry := design.parts[i]
		if entry.part.is_empty():
			if entry.count != 0:
				return "an empty slot has no count"
			continue
		if not content.ids("part").has(entry.part):
			return "no such part"
		var part := content.part(entry.part)
		if not (slots[i]["accepts"] as Array).has(part["category"]):
			return "a slot does not accept that part"
		if entry.count < 1 or entry.count > int(slots[i]["max"]):
			return "bad part count"
		if not available(part, player, order):
			return "part not available"
	return ""


## The race's trait ids: the primary trait and the lesser traits.
static func traits_of(race: Race) -> Array[String]:
	var out: Array[String] = [race.primary_trait]
	out.append_array(race.lesser_traits)
	return out


## Fuel capacity of a design in mg (S04): hull fuel plus each part's `fuel_capacity`.
static func fuel_capacity(design: Design, content: ContentRegistry) -> int:
	var total: int = content.hull(design.hull).get("fuel", 0)
	for slot in design.parts:
		if not slot.part.is_empty():
			total += (
				slot.count * int(content.part(slot.part).get("stats", {}).get("fuel_capacity", 0))
			)
	return total


## A design's mass in kT (S04): hull plus each slot's parts.
static func mass(design: Design, content: ContentRegistry) -> int:
	var total: int = content.hull(design.hull).get("mass", 0)
	for slot in design.parts:
		if not slot.part.is_empty():
			total += slot.count * int(content.part(slot.part).get("mass", 0))
	return total


## A design's cargo capacity in kT (S04): the hull's plus each part's `cargo_capacity`.
static func cargo_capacity(design: Design, content: ContentRegistry) -> int:
	var total: int = content.hull(design.hull).get("cargo", 0)
	for slot in design.parts:
		if not slot.part.is_empty():
			total += (
				slot.count * int(content.part(slot.part).get("stats", {}).get("cargo_capacity", 0))
			)
	return total


## A design's engine part (the part in its first engine slot) and whether that slot is full;
## ["", false] without one.
static func engine(design: Design, content: ContentRegistry) -> Array:
	var slots: Array = content.hull(design.hull)["slots"]
	for i in slots.size():
		if (slots[i]["accepts"] as Array).has("engine"):
			var s := design.parts[i] if i < design.parts.size() else DesignSlot.new()
			return [s.part, s.count >= int(slots[i].get("max", 1)) and not s.part.is_empty()]
	return ["", false]


## A design's armor (S04): the hull's plus each slot's `armor` stat times its count, armor parts
## scaled by the owner's `design.armor_part_pct` (Regenerating Shields: 50).
static func armor(design: Design, content: ContentRegistry, race: Race = null) -> int:
	var total: int = content.hull(design.hull).get("armor", 0)
	var pct := 100
	if race != null:
		pct = RaceMath.trait_param(race, content, "design.armor_part_pct", 100)
	for slot in design.parts:
		if slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var each: int = part.get("stats", {}).get("armor", 0)
		if part.get("category", "") == "armor":
			each = each * pct / 100
		total += slot.count * each
	return total


## A design's shields per ship (`Design_GetShields@1030:0a0e`): every part's `shield` stat times its
## count, scaled by the race's `design.shield_pct` (Regenerating Shields 140), at most 65,535.
static func shields(design: Design, content: ContentRegistry, race: Race = null) -> int:
	var total := 0
	for slot in design.parts:
		if slot.count > 0 and not slot.part.is_empty():
			total += slot.count * int(content.part(slot.part).get("stats", {}).get("shield", 0))
	if race != null:
		total = total * RaceMath.trait_param(race, content, "design.shield_pct", 100) / 100
	return mini(total, SHIELD_MAX)


## A starbase design's mass driver speed (S09, S14): the best `driver_warp` among its parts, one
## more when two parts share that best speed; 0 without a driver.
static func driver_warp(design: Design, content: ContentRegistry) -> int:
	var best := 0
	var pair := 0
	for s in design.parts:
		if s.count == 0 or s.part.is_empty():
			continue
		var w: int = content.part(s.part).get("stats", {}).get("driver_warp", 0)
		if w > best:
			best = w
			pair = 0
		elif w == best and w > 0:
			pair = 1
	return best + pair if best > 0 else 0


## The best part of `category` with `stat` the player can use (highest stat), or "".
static func best_part(
	category: String, stat: String, player: Player, content: ContentRegistry
) -> String:
	var order := tech_order(content)
	var best := ""
	var best_value := 0
	for id in content.ids("part"):
		var part := content.part(id)
		var value: int = part.get("stats", {}).get(stat, 0)
		if part["category"] == category and value > best_value and available(part, player, order):
			best = id
			best_value = value
	return best


## Tech field id -> index in tech level arrays (the fields' `order`).
static func tech_order(content: ContentRegistry) -> Dictionary:
	var out := {}
	for id in content.ids("tech_field"):
		out[id] = int(content.tech_field(id)["order"])
	return out


## A design picture within its hull's four (S04): a value outside them becomes the hull's first
## picture plus the value's last two bits.
static func design_picture(picture: int, hull: Dictionary) -> int:
	var first: int = hull.get("pictures", 0)
	if picture >= first and picture < first + PICTURES_PER_HULL:
		return picture
	return first + (picture & (PICTURES_PER_HULL - 1))
