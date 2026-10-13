class_name TechGain
extends RefCounted
## Tech gained from other players' ships (spec S24, partial): the bonus a planet owner may get
## when ships are scrapped at its starbase.
##
## Also the battle bonus (S16 "Battle results") and the invasion bonus (S17). The "need" lists hold
## the six fields' levels, then the chance (percent) of learning each Mystery Trader part seen
## (S18 items by bit: each design looked at adds its count of that part, at most 25).

const GATE_ROLL := 100
## The roll must be above this.
const GATE_PASS := 49
const TRADER_PART_KINDS := 13
const FIELD_TRIES := 6
## Where the Mystery Trader parts' chances start in a need list, and their cap.
const PARTS_SEEN := 6
const PART_CHANCE_MAX := 25


## An empty need list: six fields, then the 13 Mystery Trader items.
static func new_need() -> Array[int]:
	var need: Array[int] = []
	need.resize(PARTS_SEEN + TRADER_PART_KINDS)
	need.fill(0)
	return need


## The highest level of each tech field the fleet's ships need (hull and parts in use).
static func tech_needed(fleet: Fleet, owner: Player, content: ContentRegistry) -> Array[int]:
	var need := new_need()
	for stack in fleet.stacks:
		if stack.count > 0:
			note_design(owner.ship_design(stack.design), need, content)
	return need


## Raises `need` to the levels the design's hull and parts in use need (`NoteDesignTech@1078:244c`).
static func note_design(design: Design, need: Array[int], content: ContentRegistry) -> void:
	_note(content.hull(design.hull), need, content)
	for slot in design.parts:
		if not slot.part.is_empty() and slot.count > 0:
			var part := content.part(slot.part)
			_note(part, need, content)
			var bit := int(part.get("trader_bit", -1))
			if bit >= 0 and need.size() > PARTS_SEEN + bit:
				var at := PARTS_SEEN + bit
				need[at] = mini(need[at] + slot.count, PART_CHANCE_MAX)


## A Mystery Trader part learned from wreckage (`try_bonus` returned -(bit + 1)): its message
## (goto the item), naming where the battle (or invasion) was.
static func wreckage_message(
	state: GameState, content: ContentRegistry, player: int, gained: int, where: Array
) -> void:
	var item := MysteryTrader.item_of(content, -gained - 1)
	var kind := (
		"message.battle.wreckage_hull"
		if content.type_of(item) == "hull"
		else "message.battle.wreckage_part"
	)
	TurnMessages.add(state, content, player, kind, {"item": item}, where)


static func _note(def: Dictionary, need: Array[int], content: ContentRegistry) -> void:
	var tech: Dictionary = def.get("tech", {})
	for field: String in tech:
		var order := int(content.tech_field(field)["order"])
		need[order] = maxi(need[order], int(tech[field]))


## Once per turn per player: a 50% roll, then a Mystery Trader part seen (13 tries: a part the
## player lacks, learned when `random(100)` is below its chance), then up to six random fields
## where `need` is above the player's level; the first such field gets the research cost of the
## player's next level in it. Returns the field + 1, -(bit + 1) for a part (its id added to
## `trader_parts`), or 0. `TryTechBonus@10e8:6112`.
static func try_bonus(
	player: Player, need: Array[int], content: ContentRegistry, rng: StarsRandom
) -> int:
	if player.tech_bonus_taken or rng.random(GATE_ROLL) <= GATE_PASS:
		return 0
	for i in TRADER_PART_KINDS:
		var bit := rng.random(TRADER_PART_KINDS)
		var chance: int = need[PARTS_SEEN + bit] if need.size() > PARTS_SEEN + bit else 0
		var item := MysteryTrader.item_of(content, bit)
		if chance > 0 and not player.trader_parts.has(item) and rng.random(GATE_ROLL) < chance:
			player.trader_parts.append(item)
			player.trader_parts.sort()
			player.tech_bonus_taken = true
			return -(bit + 1)
	for i in FIELD_TRIES:
		var field := rng.random(ResearchRules.FIELDS)
		if player.tech_levels[field] < need[field]:
			player.research_points[field] += ResearchRules.level_cost(player, field, content, false)
			player.tech_bonus_taken = true
			return field + 1
	return 0
