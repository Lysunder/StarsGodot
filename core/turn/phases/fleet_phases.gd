class_name FleetPhases
extends RefCounted
## Fleet phases (spec S02 5, 9, 15, 16).


## 4: following fleets and waypoints that target fleets (S12).
class ResolveTargets:
	extends Phase

	func _init() -> void:
		super("fleets.resolve_targets")

	func run(ctx: TurnContext) -> void:
		FleetTargets.resolve(ctx.state, ctx.content, ctx.rng())


## 21: waypoints that target fleets, again after the turn's changes (S12).
class Retarget:
	extends Phase

	func _init() -> void:
		super("fleets.retarget")

	func run(ctx: TurnContext) -> void:
		FleetTargets.update(ctx.state, ctx.content, ctx.rng())


## 5: waypoint-0 tasks: task pass 1, colonization, tech update, task pass 2 (S11).
class Waypoint0Tasks:
	extends Phase

	func _init() -> void:
		super("wp0.tasks")

	func run(ctx: TurnContext) -> void:
		# the first task pass clears the marks the start of the turn left (S12 "Waypoint targets")
		for fleet in ctx.state.fleets:
			fleet.claimed = false
		var tasks := WaypointTasks.new(ctx.state, ctx.content, ctx.rng())
		tasks.run_pass(1)
		tasks.resolve()
		ResearchRules.update(ctx.state, ctx.content, [])
		tasks.run_pass(2)
		tasks.resolve()


## 9: fleets move (S12).
class Move:
	extends Phase

	func _init() -> void:
		super("fleets.move")

	func run(ctx: TurnContext) -> void:
		Movement.move_all(ctx.state, ctx.content, ctx.rng())


## 15: refueling and fuel making (S12).
class Refuel:
	extends Phase

	func _init() -> void:
		super("fleets.refuel")

	func run(ctx: TurnContext) -> void:
		Movement.refuel_all(ctx.state, ctx.content)


## 16: waypoint-1 tasks: (battles, S16), task pass 3, colonization, tech update, task pass 4.
class Waypoint1Tasks:
	extends Phase

	func _init() -> void:
		super("wp1.tasks")

	func run(ctx: TurnContext) -> void:
		# battles come first (M9), then bombing: so far only which fleets take part
		Bombing.mark_fleets(ctx.state)
		var tasks := WaypointTasks.new(ctx.state, ctx.content, ctx.rng())
		tasks.run_pass(3)
		tasks.resolve()
		ResearchRules.update(ctx.state, ctx.content, [])
		tasks.run_pass(4)
		tasks.resolve()


## 12: colonists grow in Inner-Strength fleets (S19).
class ColonistGrowth:
	extends Phase

	func _init() -> void:
		super("fleets.is_growth")

	func run(ctx: TurnContext) -> void:
		Repair.grow_colonists(ctx.state, ctx.content, ctx.rng())


## 18: fleets and starbases repair (S19).
class RepairPhase:
	extends Phase

	func _init() -> void:
		super("fleets.repair")

	func run(ctx: TurnContext) -> void:
		Repair.repair_all(ctx.state, ctx.content)
