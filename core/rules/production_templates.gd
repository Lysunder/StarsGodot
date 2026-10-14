class_name ProductionTemplates
extends RefCounted
## Production templates (S09 "Production templates"; the original's `ZIPPRODDLG@10c8:2d26` and the
## production window's template menu): the default queue for new colonies plus up to three of the
## player's own, each a list of auto-build items and a "contribute only leftover resources to
## research" setting.

## Templates besides the default.
const CUSTOM := 3
## Longest template name.
const NAME_MAX := 12


## Whether the owner's race never gets this item from a template or a new colony's default queue:
## an auto-build item whose effect the race skips (`colony.skips_auto_<effect>`: AR mines,
## factories and defenses, CA terraforming).
static func skips(race: Race, content: ContentRegistry, item: String) -> bool:
	var def := content.get_def("production_item", item)
	if not def.get("auto", false):
		return false
	var effect: String = def.get("effect", "")
	return RaceMath.trait_param(race, content, "colony.skips_auto_" + effect, 0) != 0


## Whether a queue item (dictionary) is an auto-build item.
static func is_auto(content: ContentRegistry, q: Dictionary) -> bool:
	var item: String = q.get("item", "")
	return item != "" and bool(content.get_def("production_item", item).get("auto", false))


## Applying a template to a queue (queue item dictionaries): the queue's auto-build items go, its
## other items stay in order, and the template's items the race doesn't skip follow them, with
## progress 0.
static func apply(queue: Array, template: Array, race: Race, content: ContentRegistry) -> Array:
	var out: Array = []
	for q: Dictionary in queue:
		if not is_auto(content, q):
			out.append(q.duplicate(true))
	for q: Dictionary in template:
		if not skips(race, content, q["item"]):
			var copy := q.duplicate(true)
			copy["progress"] = 0
			out.append(copy)
	return out


## Importing a queue into a template: its auto-build items in order, at most
## `constant.limits.default_queue_items`, progress 0.
static func import_queue(queue: Array, content: ContentRegistry) -> Array:
	var out: Array = []
	var limit: int = content.constant("constant.limits.default_queue_items")
	for q: Dictionary in queue:
		if out.size() >= limit:
			break
		if is_auto(content, q):
			var copy := q.duplicate(true)
			copy["progress"] = 0
			out.append(copy)
	return out
