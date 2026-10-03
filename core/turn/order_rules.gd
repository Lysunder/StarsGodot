class_name OrderRules
extends RefCounted
## Validates and applies players' orders (spec S11 "Orders"): players in index order, each
## player's orders in list order, each checked against the state at that moment. A rejected order
## changes nothing.

const TYPES := [
	"production_queue",
	"research",
	"planet_settings",
	"waypoint_add",
	"waypoint_change",
	"waypoint_delete",
]


## Applies every order set; returns one "player P order I: reason" line per rejected order.
static func apply_all(
	state: GameState, content: ContentRegistry, order_sets: Array[OrderSet]
) -> PackedStringArray:
	var rejected := PackedStringArray()
	var sorted := order_sets.duplicate()
	sorted.sort_custom(func(a: OrderSet, b: OrderSet) -> bool: return a.player < b.player)
	for order_set: OrderSet in sorted:
		for i in order_set.orders.size():
			var reason := apply(state, content, order_set.player, order_set.orders[i])
			if not reason.is_empty():
				rejected.append("player %d order %d: %s" % [order_set.player, i, reason])
	return rejected


## Applies one order of `player`; returns why it was rejected, or "".
static func apply(
	state: GameState, content: ContentRegistry, player: int, order: Dictionary
) -> String:
	if player < 0 or player >= state.players.size():
		return "no such player"
	match order.get("type"):
		"production_queue":
			return _production_queue(state, content, player, order)
		"research":
			return _research(state, player, order)
		"planet_settings":
			return _planet_settings(state, player, order)
		"waypoint_add", "waypoint_change", "waypoint_delete":
			return _waypoint(state, player, order)
	return "unknown order type %s" % str(order.get("type"))


## Replaces a planet's queue (S11 "Production queue change"). An item keeps its progress only if
## the old queue had an item of the same kind with progress; each old item matches once.
static func _production_queue(
	state: GameState, content: ContentRegistry, player: int, order: Dictionary
) -> String:
	var planet := _own_planet(state, player, order.get("planet"))
	if planet == null:
		return "not the player's planet"
	if not order.get("items") is Array:
		return "items must be a list"
	var owner := state.player(player)
	var fresh: Array[QueueItem] = []
	for d: Variant in order["items"]:
		var errors := PackedStringArray()
		var q := ModelObject.object_from(QueueItem, d, "", errors) as QueueItem
		if not errors.is_empty():
			return "bad queue item: %s" % errors[0]
		if q.count < 0 or q.count > content.constant("constant.limits.queue_count"):
			return "bad queue item count"
		if q.progress < 0 or q.progress > 100:
			return "bad queue item progress"
		if q.is_design():
			var design := (
				owner.starbase_design(q.design) if q.starbase else owner.ship_design(q.design)
			)
			if design == null:
				return "no such design"
		elif not content.has_def(q.item) or not content.ids("production_item").has(q.item):
			return "no such production item"
		fresh.append(q)
	var old := planet.queue
	for q in fresh:
		if q.progress == 0:
			continue
		var matched := false
		for e in old:
			if (
				e.progress != 0
				and e.item == q.item
				and e.design == q.design
				and e.starbase == q.starbase
			):
				e.progress = 0
				matched = true
				break
		if not matched:
			q.progress = 0
	planet.queue = fresh
	return ""


## Research spending and fields (S05, S11).
static func _research(state: GameState, player: int, order: Dictionary) -> String:
	var percent: Variant = order.get("percent")
	var field: Variant = order.get("field")
	var next: Variant = order.get("next")
	if not percent is int or percent < 0 or percent > 100:
		return "research percent must be 0..100"
	if not field is int or field < 0 or field >= ResearchRules.FIELDS:
		return "bad research field"
	if not next is int or next < 0 or next > Player.NEXT_FIELD_LOWEST:
		return "bad next research field"
	var p := state.player(player)
	p.research_percent = percent
	p.research_field = field
	p.next_research_field = next
	return ""


## Planet settings (S09, S11): leftover to research, mass driver destination and speed (kept only
## on a planet with a starbase, which holds them), route.
static func _planet_settings(state: GameState, player: int, order: Dictionary) -> String:
	var planet := _own_planet(state, player, order.get("planet"))
	if planet == null:
		return "not the player's planet"
	var leftover: Variant = order.get("leftover_to_research")
	var target: Variant = order.get("mass_driver_target")
	var warp: Variant = order.get("mass_driver_warp")
	var route: Variant = order.get("route")
	if not leftover is bool:
		return "leftover_to_research must be true or false"
	for v: Variant in [target, route]:
		if not v is int or (v != -1 and state.planet(v) == null):
			return "no such planet"
	if not warp is int or warp < 0 or warp > StateValidator.MAX_DRIVER_WARP:
		return "bad mass driver warp"
	planet.leftover_to_research = leftover
	if planet.starbase != null:
		planet.mass_driver_target = target
		planet.mass_driver_warp = warp
	planet.route = route
	return ""


## Edits a fleet's waypoint list (S11): add inserts at index (0..count), change replaces the
## waypoint at index, delete removes `count` (1 or 2) waypoints from index.
static func _waypoint(state: GameState, player: int, order: Dictionary) -> String:
	var owner: Variant = order.get("owner", player)
	var number: Variant = order.get("fleet")
	var index: Variant = order.get("index")
	if not owner is int or owner != player or not number is int:
		return "not the player's fleet"
	var fleet := state.fleet(player, number)
	if fleet == null:
		return "not the player's fleet"
	if not index is int or index < 0:
		return "bad waypoint index"
	var waypoints := fleet.waypoints
	if order["type"] == "waypoint_delete":
		var count: Variant = order.get("count", 1)
		if not count is int or count < 1 or count > 2 or index + count > waypoints.size():
			return "bad waypoint index"
		for k in count:
			waypoints.remove_at(index)
		return ""
	var errors := PackedStringArray()
	var wp := ModelObject.object_from(Waypoint, order.get("waypoint"), "", errors) as Waypoint
	if not errors.is_empty():
		return "bad waypoint: %s" % errors[0]
	wp.frozen = false
	if order["type"] == "waypoint_add":
		if index > waypoints.size():
			return "bad waypoint index"
		waypoints.insert(index, wp)
	else:
		if index >= waypoints.size():
			return "bad waypoint index"
		waypoints[index] = wp
	return ""


static func _own_planet(state: GameState, player: int, id: Variant) -> Planet:
	if not id is int:
		return null
	var planet := state.planet(id)
	if planet == null or planet.owner != player:
		return null
	return planet
