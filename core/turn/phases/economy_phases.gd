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


## 13b: per planet, resources go to research and the production queue (S09).
class Planets:
	extends Phase

	func _init() -> void:
		super("production.planets")

	func run(ctx: TurnContext) -> void:
		for i in ctx.research_spent.size():
			ctx.research_spent[i] = 0
		var production := Production.new(ctx.state, ctx.content, ctx.rng())
		for planet in ctx.state.planets:
			if planet.owner >= 0:
				production.run_planet(planet, ctx.research_spent)


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
