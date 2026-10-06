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
		# the last growth worked out, kept from planet to planet as the original does (S21)
		var growth := 0
		for planet in ctx.state.planets:
			if planet.owner >= 0 and planet.population != 0:
				var race := ctx.player(planet.owner).race
				var before := planet.population
				PlanetEconomy.grow(planet, race, ctx.content, true)
				growth = planet.population - before
				if growth < 0 and planet.population > 0:
					_shrink_message(ctx, planet, race, growth)
			if planet.owner >= 0 and planet.population == 0 and planet.extra_colonists == 0:
				var race := ctx.player(planet.owner).race
				var orbit := RaceMath.trait_param(race, ctx.content, "message.orbital_colony", 0)
				var kind := "message.planet.died" if growth < 0 else "message.planet.abandoned"
				if orbit:
					kind += "_orbit"
				_message(ctx, planet, kind, [planet.id])
			if planet.owner >= 0 and planet.population == 0:
				PlanetEconomy.depopulate(planet, ctx.player(planet.owner).race, ctx.content)
			if planet.owner < 0:
				PlanetEconomy.depopulate(planet, null, ctx.content)

	## S21: a planet that lost colonists this year: from-and-to on a hostile planet, how many on a
	## crowded one.
	func _shrink_message(ctx: TurnContext, planet: Planet, race: Race, growth: int) -> void:
		if PlanetEconomy.hab_value(planet, race) < 0:
			var before := planet.population - growth
			_message(ctx, planet, "message.planet.shrank", [planet.id, before, planet.population])
		else:
			_message(ctx, planet, "message.planet.overcrowded", [planet.id, -growth])

	func _message(ctx: TurnContext, planet: Planet, type: String, params: Array) -> void:
		TurnMessages.add(ctx.state, ctx.content, planet.owner, type, {"planet": planet.id}, params)


## 13d: research points and new tech levels (S05).
class TechUpdate:
	extends Phase

	func _init() -> void:
		super("production.research")

	func run(ctx: TurnContext) -> void:
		ResearchRules.update(ctx.state, ctx.content, ctx.research_spent)
