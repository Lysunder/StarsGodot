class_name TechGain
extends RefCounted
## Tech gained from other players' ships (spec S24, partial): the bonus a planet owner may get
## when ships are scrapped at its starbase.
##
## Not yet: Mystery Trader parts among the scrapped parts (none are marked in content; their
## draws are made), battle and invasion gains.

const GATE_ROLL := 100
## The roll must be above this.
const GATE_PASS := 49
const TRADER_PART_KINDS := 13
const FIELD_TRIES := 6


## The highest level of each tech field the fleet's ships need (hull and parts in use).
static func tech_needed(fleet: Fleet, owner: Player, content: ContentRegistry) -> Array[int]:
	var need: Array[int] = [0, 0, 0, 0, 0, 0]
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var design := owner.ship_design(stack.design)
		_note(content.hull(design.hull), need, content)
		for slot in design.parts:
			if not slot.part.is_empty() and slot.count > 0:
				_note(content.part(slot.part), need, content)
	return need


static func _note(def: Dictionary, need: Array[int], content: ContentRegistry) -> void:
	var tech: Dictionary = def.get("tech", {})
	for field: String in tech:
		var order := int(content.tech_field(field)["order"])
		need[order] = maxi(need[order], int(tech[field]))


## Once per turn per player: a 50% roll, then a Mystery Trader part seen, then up to six random
## fields where `need` is above the player's level; the first such field gets the research cost
## of the player's next level in it. Returns the field + 1, or 0. `TryTechBonus@10e8:6112`.
static func try_bonus(
	player: Player, need: Array[int], content: ContentRegistry, rng: StarsRandom
) -> int:
	if player.tech_bonus_taken or rng.random(GATE_ROLL) <= GATE_PASS:
		return 0
	for i in TRADER_PART_KINDS:
		rng.random(TRADER_PART_KINDS)
	for i in FIELD_TRIES:
		var field := rng.random(ResearchRules.FIELDS)
		if player.tech_levels[field] < need[field]:
			player.research_points[field] += ResearchRules.level_cost(player, field, content, false)
			player.tech_bonus_taken = true
			return field + 1
	return 0
