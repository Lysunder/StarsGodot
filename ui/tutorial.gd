class_name Tutorial
extends RefCounted
## The tutorial (M11 step 11; our own, not the original's): a small game against one easy
## computer player, and a list of steps the coach panel (TutorialCoach) walks through. A step's
## text is the content strings `tutorial.<step>.title` and `tutorial.<step>.text` (HelpText markup);
## a step moves on when its condition holds, or when the player chooses Next for a step without one.

## [step id, condition id ("" = Next)], in order.
const STEPS := [
	["welcome", ""],
	["select_home", ""],
	["queue", "queue"],
	["research", "research"],
	["scout", "scout"],
	["colonize", "colonize"],
	["generate", "generate"],
	["messages", ""],
	["colony", "colony"],
	["done", ""],
]
const SEED := 2401
const OPPONENT := ["automitrons", 0]


## The tutorial game: the smallest universe, the default race, one computer player at the easiest
## level, no random events.
static func options() -> NewGame.Options:
	var o := NewGame.Options.new()
	o.size = 0
	o.seed = SEED
	o.flags.assign(["no_random_events"])
	o.opponents.assign([{"ai": OPPONENT[0], "level": OPPONENT[1], "personality": {}}])
	return o


static func step_id(step: int) -> String:
	return STEPS[step][0] if step >= 0 and step < STEPS.size() else ""


static func needs_next(step: int) -> bool:
	return step >= 0 and step < STEPS.size() and (STEPS[step][1] as String).is_empty()


## Whether step `step`'s condition holds: in `view` (the player's view with this turn's orders),
## with `orders` given so far, and the year the tutorial began.
static func done(step: int, view: PlayerView, orders: OrderSet, start_turn: int) -> bool:
	if step < 0 or step >= STEPS.size():
		return false
	var me := view.me()
	match STEPS[step][1]:
		"queue":
			var home := view.state.planet(me.homeworld)
			return home != null and home.owner == view.player and not home.queue.is_empty()
		"research":
			return orders.orders.any(func(o: Dictionary) -> bool: return o["type"] == "research")
		"scout":
			return view.fleets().any(
				func(f: Fleet) -> bool:
					return _hull(f, me) == "hull.scout" and f.waypoints.size() > 1
			)
		"colonize":
			return view.fleets().any(
				func(f: Fleet) -> bool:
					return f.waypoints.any(func(w: Waypoint) -> bool: return w.task == "colonize")
			)
		"generate":
			return view.state.turn > start_turn
		"colony":
			var owned := 0
			for p in view.state.planets:
				if p.owner == view.player:
					owned += 1
			return owned > 1
	return false


static func _hull(f: Fleet, me: Player) -> String:
	if f.stacks.is_empty():
		return ""
	var d := me.ship_design(f.stacks[0].design)
	return d.hull if d != null else ""
