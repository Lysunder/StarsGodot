class_name PartRules
extends RefCounted
## Which parts and hulls a player can use, and simple design totals (spec S04, S06).


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


## Tech field id -> index in tech level arrays (the fields' `order`).
static func tech_order(content: ContentRegistry) -> Dictionary:
	var out := {}
	for id in content.ids("tech_field"):
		out[id] = int(content.tech_field(id)["order"])
	return out
