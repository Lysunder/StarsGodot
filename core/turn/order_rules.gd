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
	"fleet_split",
	"fleet_move_ships",
	"fleet_merge",
	"fleet_repeat",
	"fleet_rename",
	"fleet_battle_plan",
	"player_defaults",
	"design_change",
	"design_delete",
]
const NAME_MAX := 31
const DESIGN_SLOTS := 16


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
		"fleet_split", "fleet_move_ships", "fleet_merge":
			return _fleet_ships(state, content, player, order)
		"fleet_repeat", "fleet_rename", "fleet_battle_plan":
			return _fleet_settings(state, player, order)
		"player_defaults":
			return _player_defaults(state, content, player, order)
		"design_change", "design_delete":
			return _design(state, content, player, order)
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


## The default queue and leftover setting for new colonies (S11 "player_defaults"): standard
## items only, at most `constant.limits.default_queue_items`, progress 0.
static func _player_defaults(
	state: GameState, content: ContentRegistry, player: int, order: Dictionary
) -> String:
	var leftover: Variant = order.get("leftover_to_research")
	var items: Variant = order.get("queue")
	if not leftover is bool:
		return "leftover_to_research must be true or false"
	if not items is Array or items.size() > content.constant("constant.limits.default_queue_items"):
		return "bad default queue"
	var fresh: Array[QueueItem] = []
	for d: Variant in items:
		var errors := PackedStringArray()
		var q := ModelObject.object_from(QueueItem, d, "", errors) as QueueItem
		if not errors.is_empty():
			return "bad queue item: %s" % errors[0]
		if q.is_design() or not content.ids("production_item").has(q.item):
			return "no such production item"
		if q.count < 0 or q.count > content.constant("constant.limits.queue_count"):
			return "bad queue item count"
		q.progress = 0
		fresh.append(q)
	var p := state.player(player)
	p.default_queue = fresh
	p.default_leftover_to_research = leftover
	return ""


## Creates, replaces or deletes a design (S11 `design_change`, `design_delete`).
static func _design(
	state: GameState, content: ContentRegistry, player: int, order: Dictionary
) -> String:
	var starbase: Variant = order.get("starbase")
	var slot: Variant = order.get("slot")
	if not starbase is bool:
		return "starbase must be true or false"
	var limit := content.constant(
		"constant.limits.%s" % ("starbase_designs" if starbase else "ship_designs")
	)
	if not slot is int or slot < 0 or slot >= limit:
		return "bad design slot"
	var p := state.player(player)
	var old := p.starbase_design(slot) if starbase else p.ship_design(slot)
	if order["type"] == "design_delete":
		if old != null:
			_delete_design(state, content, player, slot, starbase)
		return ""
	if old != null and old.remaining != 0:
		return "the design has ships"
	var errors := PackedStringArray()
	var fresh := ModelObject.object_from(Design, order.get("design"), "", errors) as Design
	if not errors.is_empty():
		return "bad design: %s" % errors[0]
	var problem := PartRules.design_problem(fresh, starbase, p, content)
	if not problem.is_empty():
		return problem
	fresh.slot = slot
	fresh.transferred = false
	fresh.built = 0
	fresh.remaining = 0
	if old != null:
		_carry_progress(state, content, p, old, fresh, starbase)
	p.set_design(fresh, starbase)
	return ""


## Fix B19 (S09 step 7a): queue progress of a replaced design is carried over by resources.
static func _carry_progress(
	state: GameState,
	content: ContentRegistry,
	p: Player,
	old: Design,
	fresh: Design,
	starbase: bool
) -> void:
	var old_cost: int = ProductionCosts.design_cost(old, p, content)[ProductionCosts.RESOURCES]
	var new_cost: int = ProductionCosts.design_cost(fresh, p, content)[ProductionCosts.RESOURCES]
	for planet in state.planets:
		if planet.owner != p.index:
			continue
		for q in planet.queue:
			if q.design == old.slot and q.starbase == starbase and q.progress > 0:
				q.progress = mini(100, q.progress * old_cost / maxi(new_cost, 1))


static func _delete_design(
	state: GameState, content: ContentRegistry, player: int, slot: int, starbase: bool
) -> void:
	if starbase:
		for planet in state.planets:
			if (
				planet.owner == player
				and planet.starbase != null
				and planet.starbase.design == slot
			):
				planet.starbase = null
				var kept: Array[QueueItem] = []
				for q in planet.queue:
					var packet: bool = (
						not q.is_design()
						and content.get_def("production_item", q.item).get("effect", "") == "packet"
					)
					if not (q.is_design() and not q.starbase) and not packet:
						kept.append(q)
				planet.queue = kept
	else:
		FleetOrders.remove_design_ships(state, content, player, slot)
	for planet in state.planets:
		if planet.owner != player:
			continue
		var kept: Array[QueueItem] = []
		for q in planet.queue:
			if not (q.is_design() and q.design == slot and q.starbase == starbase):
				kept.append(q)
		planet.queue = kept
	state.player(player).remove_design(slot, starbase)


## Split, ship moves and merges (S11 "Fleet orders").
static func _fleet_ships(
	state: GameState, content: ContentRegistry, player: int, order: Dictionary
) -> String:
	var fleet := _own_fleet(state, player, order)
	if fleet == null:
		return "not the player's fleet"
	match order["type"]:
		"fleet_split":
			if FleetOrders.split(state, content, fleet) == null:
				return "too many fleets"
		"fleet_move_ships":
			var other: Variant = order.get("other")
			var b := state.fleet(player, other) if other is int else null
			if b == null or b == fleet:
				return "not the player's fleet"
			if b.x != fleet.x or b.y != fleet.y:
				return "fleets are not at the same place"
			if not order.get("ships") is Array:
				return "ships must be a list"
			var ships := {}
			for e: Variant in order["ships"]:
				var design: Variant = e.get("design") if e is Dictionary else null
				var count: Variant = e.get("count") if e is Dictionary else null
				if not design is int or design < 0 or design >= DESIGN_SLOTS:
					return "bad design slot"
				if not count is int:
					return "bad ship count"
				ships[design] = ships.get(design, 0) + count
			FleetOrders.move_ships(state, content, fleet, b, ships, player)
		"fleet_merge":
			if not order.get("fleets", []) is Array:
				return "fleets must be a list"
			var others: Array[Fleet] = []
			var listed: Array = order.get("fleets", [])
			if listed.is_empty():
				for f in state.fleets_of(player):
					if f != fleet and f.x == fleet.x and f.y == fleet.y:
						others.append(f)
			for number: Variant in listed:
				var f := state.fleet(player, number) if number is int else null
				if f != null and f != fleet and f.x == fleet.x and f.y == fleet.y:
					if not others.has(f):
						others.append(f)
			FleetOrders.merge(state, fleet, others, player)
	return ""


## Repeat orders, name and battle plan (S11 "Fleet orders").
static func _fleet_settings(state: GameState, player: int, order: Dictionary) -> String:
	var fleet := _own_fleet(state, player, order)
	if fleet == null:
		return "not the player's fleet"
	match order["type"]:
		"fleet_repeat":
			if not order.get("repeat") is bool:
				return "repeat must be true or false"
			fleet.repeat = order["repeat"]
		"fleet_rename":
			var fleet_name: Variant = order.get("name")
			if not fleet_name is String or fleet_name.length() > NAME_MAX:
				return "bad fleet name"
			fleet.name = fleet_name
		"fleet_battle_plan":
			var plan: Variant = order.get("plan")
			if not plan is int or plan < 0 or plan >= state.player(player).battle_plans.size():
				return "no such battle plan"
			fleet.battle_plan = plan
	return ""


static func _own_fleet(state: GameState, player: int, order: Dictionary) -> Fleet:
	var owner: Variant = order.get("owner", player)
	var number: Variant = order.get("fleet")
	if not owner is int or owner != player or not number is int:
		return null
	return state.fleet(player, number)


static func _own_planet(state: GameState, player: int, id: Variant) -> Planet:
	if not id is int:
		return null
	var planet := state.planet(id)
	if planet == null or planet.owner != player:
		return null
	return planet
