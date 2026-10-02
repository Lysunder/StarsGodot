class_name EconomyPhases
extends RefCounted
## The production phase's steps (spec S02 13a-13d): mining, planet production, population
## growth and the tech update.


## 13a: every owned, populated planet is mined by its owner (S08), in planet order.
class Mining:
	extends Phase

	func _init() -> void:
		super("production.mining")

	func run(ctx: TurnContext) -> void:
		var rng := ctx.rng()
		for planet in ctx.state.planets:
			if planet.owner >= 0 and planet.population > 0:
				PlanetEconomy.mine(planet, ctx.player(planet.owner).race, ctx.content, rng)


## 13b: per planet, resources go to the production queue and research (S09). A planet with an
## empty queue puts all its resources into research.
class Planets:
	extends Phase

	func _init() -> void:
		super("production.planets")

	func run(ctx: TurnContext) -> void:
		for i in ctx.research_spent.size():
			ctx.research_spent[i] = 0
		for planet in ctx.state.planets:
			if planet.owner < 0:
				continue
			var race := ctx.player(planet.owner).race
			var resources := PlanetEconomy.resources(planet, race, ctx.content)
			if planet.queue.is_empty():
				ctx.research_spent[planet.owner] += resources
			else:
				push_warning(
					"planet %d: production queues are not implemented yet (S09)" % planet.id
				)


## 13c: owned, populated planets grow or shrink (S08); a planet whose population dies out is
## lost, and unowned planets are cleared.
class Growth:
	extends Phase

	func _init() -> void:
		super("production.growth")

	func run(ctx: TurnContext) -> void:
		for planet in ctx.state.planets:
			if planet.owner >= 0 and planet.population != 0:
				PlanetEconomy.grow(planet, ctx.player(planet.owner).race, ctx.content, true)
			if planet.owner >= 0 and planet.population == 0:
				PlanetEconomy.depopulate(planet, ctx.player(planet.owner).race, ctx.content)
			if planet.owner < 0:
				PlanetEconomy.depopulate(planet, null, ctx.content)


## 13d: research points and new tech levels (S05).
class TechUpdate:
	extends Phase

	func _init() -> void:
		super("production.research")

	func run(ctx: TurnContext) -> void:
		ResearchRules.update(ctx.state, ctx.content, ctx.research_spent)
