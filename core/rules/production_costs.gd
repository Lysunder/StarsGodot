class_name ProductionCosts
extends RefCounted
## What production items cost a player (spec S09 steps 1-2b). A cost is [ironium, boranium,
## germanium, resources].
##
## Trait parameters (S09 "Mod hooks"): `production.miniaturization_per_level` / `_max` and
## `production.cost_at_tech_level_pct` (BET), `cost.<category>_adjust_pct`,
## `cost.tag.<tag>_adjust_pct` and `cost.<category>_resources_pct` (part prices by kind),
## `production.defense_cost_pct` (IS), `production.alchemy_cost` (MA), `production.terraform_cost`
## (TT) and `production.terraform_cost_pct` (CA), the packet costs (PP, IT), and
## `production.starbase_adjust_pct` (ISB, AR).

const MINERALS := ["ironium", "boranium", "germanium"]
const RESOURCES := 3
## Credit for a replaced part in a starbase upgrade: [similar part, other kind of part], tenths.
const UPGRADE_CREDIT := [8, 7]


static func of(cost: Dictionary) -> Array[int]:
	return [cost["ironium"], cost["boranium"], cost["germanium"], cost["resources"]]


## A part's or hull's price for a player (S09 step 2). `def` is the part or hull definition.
static func part_cost(def: Dictionary, player: Player, content: ContentRegistry) -> Array[int]:
	var cost := of(def["cost"])
	var race := player.race
	var margin := 1
	if def.get("miniaturize", true):
		margin = _tech_margin(def, player, content)
		if margin > 0:
			var levels := mini(
				margin, content.constant("constant.production.miniaturization_levels")
			)
			var per := _param(race, content, "production.miniaturization_per_level")
			var pct := mini(per * levels, _param(race, content, "production.miniaturization_max"))
			for i in 4:
				if cost[i] != 0:
					cost[i] = maxi(cost[i] - (cost[i] * pct + 50) / 100, 1)
	var category: String = def.get("category", "")
	var adjusted := false
	for tag: String in def.get("tags", []):
		var tag_pct := RaceMath.trait_param(race, content, "cost.tag.%s_adjust_pct" % tag, 100)
		if tag_pct != 100:
			_adjust(cost, tag_pct)
			adjusted = true
			break
	if not adjusted and not category.is_empty():
		_adjust(cost, RaceMath.trait_param(race, content, "cost.%s_adjust_pct" % category, 100))
		var res_pct := RaceMath.trait_param(race, content, "cost.%s_resources_pct" % category, 100)
		cost[RESOURCES] = cost[RESOURCES] * res_pct / 100
	if margin < 1 and _requires_tech(def):
		var at_level := RaceMath.trait_param(
			race, content, "production.cost_at_tech_level_pct", 100
		)
		for i in 4:
			cost[i] = cost[i] * at_level / 100
	return cost


## A design's price (S09 step 2a): hull plus each slot's parts.
static func design_cost(design: Design, player: Player, content: ContentRegistry) -> Array[int]:
	var cost := part_cost(content.hull(design.hull), player, content)
	for slot in design.parts:
		if slot.part.is_empty() or slot.count == 0:
			continue
		var each := part_cost(content.part(slot.part), player, content)
		for i in 4:
			cost[i] += slot.count * each[i]
	return cost


## The price of a starbase design built where `old` stands (S09 step 2b), before the starbase
## adjustments of step 1.
static func upgrade_cost(
	new: Design, old: Design, player: Player, content: ContentRegistry
) -> Array[int]:
	var cost := design_cost(new, player, content)
	if new.hull != old.hull:
		var old_cost := design_cost(old, player, content)
		for i in 4:
			cost[i] = maxi(cost[i] - old_cost[i] / 2, cost[i] / 2)
		return cost
	var hull := part_cost(content.hull(new.hull), player, content)
	for i in 4:
		cost[i] -= hull[i]
	for k in old.parts.size():
		if k >= new.parts.size():
			break
		var o_slot := old.parts[k]
		var n_slot := new.parts[k]
		if o_slot.count == 0 or n_slot.count == 0 or o_slot.part.is_empty():
			continue
		if n_slot.part.is_empty():
			continue
		var o_def := content.part(o_slot.part)
		var n_def := content.part(n_slot.part)
		var o_each := part_cost(o_def, player, content)
		var n_each := part_cost(n_def, player, content)
		for i in 4:
			var o := o_slot.count * o_each[i]
			var n := n_slot.count * n_each[i]
			var credit: int
			if o_slot.part == n_slot.part:
				credit = mini(n, o)
			else:
				var tenths: int = UPGRADE_CREDIT[0 if o_def["category"] == n_def["category"] else 1]
				credit = n - maxi(n - tenths * o / 10, (10 - tenths) * n / 10)
			cost[i] = maxi(cost[i] - credit, 0)
	return cost


## One unit of a queue item on a planet (S09 step 1).
static func unit_cost(
	planet: Planet, item: QueueItem, player: Player, content: ContentRegistry
) -> Array[int]:
	if item.is_design():
		return _design_unit_cost(planet, item, player, content)
	var race := player.race
	var def := content.get_def("production_item", item.item)
	var cost: Array[int] = [0, 0, 0, 0]
	match def["effect"]:
		"mines":
			cost[RESOURCES] = race.mine_cost
		"factories":
			var germ := content.constant("constant.production.factory_germanium")
			cost[2] = germ - (1 if race.cheap_factories else 0)
			cost[RESOURCES] = race.factory_cost
		"defenses":
			cost = of(content.part(def["part"])["cost"])
			var pct := RaceMath.trait_param(race, content, "production.defense_cost_pct", 100)
			for i in 4:
				cost[i] = cost[i] * pct / 100
		"alchemy":
			cost[RESOURCES] = _param(race, content, "production.alchemy_cost")
		"terraform":
			cost[RESOURCES] = (
				_param(race, content, "production.terraform_cost")
				* RaceMath.trait_param(race, content, "production.terraform_cost_pct", 100)
				/ 100
			)
		"packet":
			var mixed: bool = def["mineral"] == "mixed"
			var amount := _param(
				race,
				content,
				(
					"production.mixed_packet_mineral_cost"
					if mixed
					else "production.packet_mineral_cost"
				)
			)
			for m in 3:
				if mixed or MINERALS[m] == def["mineral"]:
					cost[m] = amount
			cost[RESOURCES] = _param(race, content, "production.packet_resource_cost")
		"genesis", "scanner":
			cost = part_cost(content.part(def["part"]), player, content)
	return cost


static func _design_unit_cost(
	planet: Planet, item: QueueItem, player: Player, content: ContentRegistry
) -> Array[int]:
	if not item.starbase:
		return design_cost(player.ship_design(item.design), player, content)
	var design := player.starbase_design(item.design)
	var cost: Array[int]
	if planet.starbase != null:
		cost = upgrade_cost(design, player.starbase_design(planet.starbase.design), player, content)
	else:
		cost = design_cost(design, player, content)
	var adjust := RaceMath.trait_param(player.race, content, "production.starbase_adjust_pct", 100)
	_adjust(cost, adjust)
	var price := content.constant("constant.production.starbase_price_pct")
	for i in 4:
		cost[i] = (cost[i] * price + 99) / 100
	return cost


## The smallest margin (player level - required level) over the required fields, or the
## player's lowest level for a part without requirements.
static func _tech_margin(def: Dictionary, player: Player, content: ContentRegistry) -> int:
	var tech: Dictionary = def.get("tech", {})
	var margin := 100
	for field: String in tech:
		var need := int(tech[field])
		if need > 0:
			var order := int(content.tech_field(field)["order"])
			margin = mini(margin, player.tech_levels[order] - need)
	if margin == 100:
		for level in player.tech_levels:
			margin = mini(margin, level)
	return margin


static func _requires_tech(def: Dictionary) -> bool:
	var tech: Dictionary = def.get("tech", {})
	for field: String in tech:
		if int(tech[field]) > 0:
			return true
	return false


## c + c * (pct - 100) / 100 per component: 75 takes a quarter off (rounding the price up),
## 125 adds a quarter (rounding down).
static func _adjust(cost: Array[int], pct: int) -> void:
	if pct == 100:
		return
	for i in cost.size():
		cost[i] += cost[i] * (pct - 100) / 100


## A trait parameter whose default is the content constant of the same name.
static func _param(race: Race, content: ContentRegistry, name: String) -> int:
	var default := content.constant("constant." + name)
	return RaceMath.trait_param(race, content, name, default)
