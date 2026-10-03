class_name FleetPhases
extends RefCounted
## Fleet phases (spec S02 5, 9, 15, 16).


## 5: waypoint-0 tasks: task pass 1, colonization, tech update, task pass 2 (S11).
class Waypoint0Tasks:
	extends Phase

	func _init() -> void:
		super("wp0.tasks")

	func run(ctx: TurnContext) -> void:
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
		var tasks := WaypointTasks.new(ctx.state, ctx.content, ctx.rng())
		tasks.run_pass(3)
		tasks.resolve()
		ResearchRules.update(ctx.state, ctx.content, [])
		tasks.run_pass(4)
		tasks.resolve()
