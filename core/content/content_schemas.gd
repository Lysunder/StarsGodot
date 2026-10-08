class_name ContentSchemas
extends RefCounted
## Schemas for every content definition type, and the validator that checks definitions
## against them.
##
## A field spec is a Dictionary with key "t" (kind) plus options:
##   int (min, max), string, bool, enum (values), id, ref (to: a definition type),
##   list (of, min, max), object (fields, required), map (key, value).
## Objects reject unknown fields, so typos are caught. Gameplay numbers must be JSON integers:
## a float anywhere is an error.

const ID_PATTERN := "^[a-z][a-z0-9_]*(\\.[A-Za-z0-9_]+)+$"
const KEY_PATTERN := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$"

const PART_CATEGORIES: Array[String] = [
	"engine",
	"scanner",
	"shield",
	"armor",
	"beam",
	"torpedo",
	"bomb",
	"mining_robot",
	"mine_layer",
	"orbital",
	"planetary",
	"electrical",
	"mechanical",
	"terraform",
]

const _INT0 := {"t": "int", "min": 0}
## What a turn message's parameter is (S21 "Parameter kinds").
const MESSAGE_PARAMS := [
	"number",
	# a design slot of the player who gets the message
	"own_design",
	# a minefield type: 0 standard, 1 heavy, 2 speed bump
	"minefield_type",
	# a minefield: its owner × 512 + its number
	"minefield",
	# a minefield or a packet / salvage pile: kind × 8192 + owner × 512 + number
	"space_object",
	# colonists in hundreds (one word)
	"colonists",
	"amount",
	"population",
	"planet",
	"fleet",
	"fleet_designs",
	"design",
	"player",
	"cargo",
	"field",
	"item",
	"flag",
	"axis",
	"axis_value",
	"object_kind",
	"object",
]
const _TAGS := {"t": "list", "of": {"t": "string"}}
const _TRAIT_LIST := {"t": "list", "of": {"t": "ref", "to": "trait"}}
const _TECH_REQ := {"t": "map", "key": {"t": "ref", "to": "tech_field"}, "value": _INT0}
const _COST := {
	"t": "object",
	"fields": {"ironium": _INT0, "boranium": _INT0, "germanium": _INT0, "resources": _INT0},
	"required": ["ironium", "boranium", "germanium", "resources"],
}
const _INT_MAP := {"t": "map", "key": {"t": "key"}, "value": {"t": "int"}}
const _SLOT := {
	"t": "object",
	"fields":
	{
		"accepts": {"t": "list", "of": {"t": "enum", "values": PART_CATEGORIES}, "min": 1},
		"max": {"t": "int", "min": 1},
		"required": {"t": "bool"},
		# where the slot sits in the designer's hull picture: [x, y] in half-slot grid units
		"at": {"t": "list", "of": _INT0, "min": 2, "max": 2},
	},
	"required": ["accepts", "max"],
}

## A slot of a starting design: a part and how many, or {} for an empty slot.
const _DESIGN_SLOT := {
	"t": "object",
	"fields": {"part": {"t": "ref", "to": "part"}, "count": {"t": "int", "min": 1}},
}
const _STARTING_STARBASE := {
	"t": "object",
	"fields":
	{
		"slot": _INT0,
		"design": {"t": "ref", "to": "starting_design"},
		"built": {"t": "bool"},
		"min_universe_size": _INT0,
		"outside_tutorial": {"t": "bool"},
		"tutorial_only": {"t": "bool"},
	},
	"required": ["slot", "design"],
}
const _STARTING_FLEET := {
	"t": "object",
	"fields":
	{
		"design": {"t": "ref", "to": "starting_design"},
		"count": {"t": "int", "min": 1},
		"extra_planet": {"t": "bool"},
		"min_tech": _TECH_REQ,
		"below_tech": _TECH_REQ,
		"human_only": {"t": "bool"},
		"forbidden_traits": _TRAIT_LIST,
		"min_universe_size": _INT0,
		"outside_tutorial": {"t": "bool"},
		"tutorial_only": {"t": "bool"},
	},
}
const _UPGRADE_CANDIDATE := {
	"t": "object",
	"fields":
	{
		"part": {"t": "ref", "to": "part"},
		"skip_on_hull": {"t": "ref", "to": "hull"},
		"unless_radiation_center_above": {"t": "int"},
	},
	"required": ["part"],
}

const _HAB_AXES := {"t": "list", "of": {"t": "int", "min": -1, "max": 100}, "min": 3, "max": 3}

## Fields every definition has, merged into each type's own fields.
const _COMMON := {"type": {"t": "string"}, "id": {"t": "id"}, "tags": _TAGS}

const TYPES := {
	"tech_field":
	{
		"fields": {"order": _INT0},
		"required": ["order"],
	},
	"trait":
	{
		"fields":
		{
			"kind": {"t": "enum", "values": ["primary", "lesser"]},
			"order": _INT0,
			"cost": {"t": "int"},
			"params": _INT_MAP,
			"excludes": _TRAIT_LIST,
		},
		"required": ["kind", "cost"],
	},
	"part":
	{
		"fields":
		{
			"category": {"t": "enum", "values": PART_CATEGORIES},
			"tech": _TECH_REQ,
			"mass": _INT0,
			"cost": _COST,
			"stats": _INT_MAP,
			"fuel_table": {"t": "list", "of": _INT0, "min": 11, "max": 11},
			"miniaturize": {"t": "bool"},
			"required_traits": _TRAIT_LIST,
			"forbidden_traits": _TRAIT_LIST,
			# needs the Mystery Trader's item for this part (Player.trader_parts)
			"mystery_trader": {"t": "bool"},
		},
		"required": ["category", "mass", "cost"],
	},
	"hull":
	{
		"fields":
		{
			"starbase": {"t": "bool"},
			"tech": _TECH_REQ,
			"mass": _INT0,
			"cost": _COST,
			"armor": _INT0,
			"fuel": _INT0,
			"cargo": _INT0,
			"initiative": _INT0,
			"pictures": _INT0,
			"rank": _INT0,
			"dock": {"t": "int", "min": -1},
			# the hull's class for battle-plan targets and reports: 0 colony, 1 freighter, 2 escort,
			# 3 capital, 4 utility, 5 bomber, 6 miner, 7 fuel transport (S12, S16)
			"class": {"t": "int", "min": 0, "max": 7},
			"stats": _INT_MAP,
			"slots": {"t": "list", "of": _SLOT, "min": 1},
			# the cargo bay in the designer's hull picture: [x1, y1, x2, y2], half-slot grid units
			"cargo_area": {"t": "list", "of": _INT0, "min": 4, "max": 4},
			# needs the Mystery Trader's item for this hull (Player.trader_parts)
			"mystery_trader": {"t": "bool"},
			"required_traits": _TRAIT_LIST,
			"forbidden_traits": _TRAIT_LIST,
		},
		"required": ["mass", "cost", "armor", "slots"],
	},
	"constant":
	{
		"fields": {"value": {"t": "int"}},
		"required": ["value"],
	},
	"name_list":
	{
		"fields": {"names": {"t": "list", "of": {"t": "string"}, "min": 1}},
		"required": ["names"],
	},
	"starting_design":
	{
		"fields":
		{
			"hull": {"t": "ref", "to": "hull"},
			"slots": {"t": "list", "of": _DESIGN_SLOT},
			"picture": _INT0,
		},
		"required": ["hull", "slots"],
	},
	"starting_setup":
	{
		"fields":
		{
			"trait": {"t": "ref", "to": "trait"},
			"tech": _TECH_REQ,
			"tech_bonus": _TECH_REQ,
			"tech_bonus_outside_tutorial": _TECH_REQ,
			"starbases": {"t": "list", "of": _STARTING_STARBASE},
			"homeworld_starbase": _INT0,
			"homeworld_mass_driver_warp": _INT0,
			"homeworld_installations": {"t": "bool"},
			"homeworld_scanner": {"t": "bool"},
			"fleets": {"t": "list", "of": _STARTING_FLEET},
		},
		"required": ["trait"],
	},
	"part_upgrade":
	{
		"fields":
		{
			"from": {"t": "list", "of": {"t": "ref", "to": "part"}, "min": 1},
			"candidates": {"t": "list", "of": _UPGRADE_CANDIDATE, "min": 1},
		},
		"required": ["from", "candidates"],
	},
	"message":
	{
		"fields":
		{
			# one kind per parameter, in order (S21 "Parameter kinds")
			"params": {"t": "list", "of": {"t": "enum", "values": MESSAGE_PARAMS}},
			# computer players get it too
			"ai": {"t": "bool"},
			# types with the same group are filtered together (S21 "Filters")
			"filter_group": {"t": "string"},
		},
		"required": ["params"],
	},
	"battle_plan_default":
	{
		"fields":
		{
			"order": _INT0,
			"tactic": _INT0,
			"primary_target": _INT0,
			"secondary_target": _INT0,
			"attack": _INT0,
		},
		"required": ["order", "tactic", "primary_target", "secondary_target", "attack"],
	},
	"production_item":
	{
		"fields":
		{
			"order": _INT0,
			"effect":
			{
				"t": "enum",
				"values":
				[
					"mines",
					"factories",
					"defenses",
					"alchemy",
					"terraform",
					"packet",
					"genesis",
					"scanner",
				],
			},
			"auto": {"t": "bool"},
			"builds": {"t": "ref", "to": "production_item"},
			"minimum": {"t": "bool"},
			"best": {"t": "bool"},
			"part": {"t": "ref", "to": "part"},
			"mineral": {"t": "enum", "values": ["ironium", "boranium", "germanium", "mixed"]},
		},
		"required": ["order", "effect"],
	},
	"race_preset":
	{
		"fields":
		{
			"order": _INT0,
			"primary_trait": {"t": "ref", "to": "trait"},
			"lesser_traits": _TRAIT_LIST,
			"hab_low": _HAB_AXES,
			"hab_center": _HAB_AXES,
			"hab_high": _HAB_AXES,
			"growth_rate": _INT0,
			"resources_per_colonist": _INT0,
			"factory_output": _INT0,
			"factory_cost": _INT0,
			"factories_operated": _INT0,
			"mine_output": _INT0,
			"mine_cost": _INT0,
			"mines_operated": _INT0,
			"research_costs": {"t": "list", "of": {"t": "int", "min": 0, "max": 2}, "min": 1},
			"leftover_points": {"t": "enum", "values": Race.LEFTOVER},
			"techs_start_at_3": {"t": "bool"},
			"cheap_factories": {"t": "bool"},
			"random": {"t": "bool"},
		},
		"required": ["order", "primary_trait"],
	},
}


class Report:
	extends RefCounted
	## [pointer, message] pairs; pointers are JSON pointers relative to the definition.
	var errors: Array = []
	## [pointer, type, id] for every reference, resolved by the registry once all mods are loaded.
	var refs: Array = []


static func has_type(type_name: String) -> bool:
	return TYPES.has(type_name)


## Spec for a whole definition of the given type (common fields included).
static func def_spec(type_name: String) -> Dictionary:
	var own: Dictionary = TYPES[type_name]
	var fields: Dictionary = _COMMON.duplicate()
	fields.merge(own["fields"])
	var required: Array = ["type", "id"]
	required.append_array(own["required"])
	return {"t": "object", "fields": fields, "required": required}


static func validate_def(def: Dictionary) -> Report:
	var report := Report.new()
	var type_name: Variant = def.get("type")
	if not (type_name is String) or not has_type(type_name):
		report.errors.append(["/type", "unknown definition type %s" % JSON.stringify(type_name)])
		return report
	_check(def, def_spec(type_name), "", report)
	return report


static func _check(value: Variant, spec: Dictionary, pointer: String, report: Report) -> void:
	match spec["t"]:
		"int":
			if value is float:
				report.errors.append([pointer, "must be an integer, not %s" % str(value)])
			elif not (value is int):
				report.errors.append([pointer, "must be an integer"])
			else:
				if spec.has("min") and value < spec["min"]:
					report.errors.append([pointer, "must be at least %d" % spec["min"]])
				if spec.has("max") and value > spec["max"]:
					report.errors.append([pointer, "must be at most %d" % spec["max"]])
		"string":
			if not (value is String) or value.is_empty():
				report.errors.append([pointer, "must be a non-empty string"])
		"bool":
			if not (value is bool):
				report.errors.append([pointer, "must be true or false"])
		"enum":
			if not (value is String) or not spec["values"].has(value):
				report.errors.append(
					[pointer, "must be one of: %s" % ", ".join(PackedStringArray(spec["values"]))]
				)
		"id":
			if not (value is String) or not _matches(ID_PATTERN, value):
				report.errors.append([pointer, "must be an id like 'part.beam.laser'"])
		"key":
			if not (value is String) or not _matches(KEY_PATTERN, value):
				report.errors.append([pointer, "must be a lowercase key like 'max_pop_pct'"])
		"ref":
			if not (value is String) or not _matches(ID_PATTERN, value):
				report.errors.append([pointer, "must be the id of a %s" % spec["to"]])
			else:
				report.refs.append([pointer, spec["to"], value])
		"list":
			if not (value is Array):
				report.errors.append([pointer, "must be a list"])
				return
			if value.size() < spec.get("min", 0):
				report.errors.append([pointer, "needs at least %d entries" % spec["min"]])
			if spec.has("max") and value.size() > spec["max"]:
				report.errors.append([pointer, "allows at most %d entries" % spec["max"]])
			for i in value.size():
				_check(value[i], spec["of"], "%s/%d" % [pointer, i], report)
		"object":
			_check_object(value, spec, pointer, report)
		"map":
			if not (value is Dictionary):
				report.errors.append([pointer, "must be an object"])
				return
			for key: String in value:
				var key_pointer := pointer + "/" + JsonReader.pointer_escape(key)
				_check(key, spec["key"], key_pointer, report)
				_check(value[key], spec["value"], key_pointer, report)


static func _check_object(
	value: Variant, spec: Dictionary, pointer: String, report: Report
) -> void:
	if not (value is Dictionary):
		report.errors.append([pointer, "must be an object"])
		return
	var fields: Dictionary = spec["fields"]
	for key: String in value:
		var key_pointer := pointer + "/" + JsonReader.pointer_escape(key)
		if not fields.has(key):
			report.errors.append([key_pointer, 'unknown field "%s"' % key])
		else:
			_check(value[key], fields[key], key_pointer, report)
	for key: String in spec.get("required", []):
		if not value.has(key):
			report.errors.append([pointer, 'missing required field "%s"' % key])


static func _matches(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null
