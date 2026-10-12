class_name Ruleset
extends RefCounted
## The game's replaceable formulas (MODDING.md §6): each is a Callable registered under an id. The
## Standard formulas are registered by StandardRuleset; a mod's ruleset script may replace them
## while the mods load. The rules fetch a formula by id once and call it.
##
## A Ruleset belongs to one game's content (ContentRegistry.ruleset), never to a global.

var frozen := false
var _formulas := {}
## Objects whose methods are registered, kept alive with the ruleset.
var _owners: Array[Object] = []


## Adds a new formula id.
func register(id: String, formula: Callable) -> void:
	assert(not frozen, "Ruleset: frozen")
	assert(not _formulas.has(id), "Ruleset: '%s' is already registered" % id)
	_put(id, formula)


## Replaces a registered formula (a mod's own version of a rule).
func replace(id: String, formula: Callable) -> void:
	assert(not frozen, "Ruleset: frozen")
	assert(_formulas.has(id), "Ruleset: no formula '%s' to replace" % id)
	_put(id, formula)


func has(id: String) -> bool:
	return _formulas.has(id)


func formula(id: String) -> Callable:
	assert(_formulas.has(id), "Ruleset: no formula '%s'" % id)
	return _formulas[id]


func ids() -> PackedStringArray:
	var out := PackedStringArray(_formulas.keys())
	out.sort()
	return out


func _put(id: String, formula: Callable) -> void:
	_formulas[id] = formula
	var owner := formula.get_object()
	if owner is RefCounted and not _owners.has(owner):
		_owners.append(owner)
