class_name PartRules
extends RefCounted
## Which parts and hulls a player can use, and simple design totals (spec S04, S06).

const PICTURES_PER_HULL := 4


## True when the player's tech levels meet the item's requirements and the race's traits allow it
## (`required_traits`: at least one; `forbidden_traits`: none). `tech_order` maps tech field ids to
## their index in the player's tech levels.
static func available(item: Dictionary, player: Player, tech_order: Dictionary) -> bool:
	var tech: Dictionary = item.get("tech", {})
	for field: String in tech:
		if player.tech_levels[tech_order[field]] < int(tech[field]):
			return false
	var traits := traits_of(player.race)
	var required: Array = item.get("required_traits", [])
	if not required.is_empty() and not required.any(func(t: String) -> bool: return traits.has(t)):
		return false
	for t: String in item.get("forbidden_traits", []):
		if traits.has(t):
			return false
	return true


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
