extends RefCounted
## Supernovae: a turn phase after the random events. Each year, with a chance of CHANCE in 100,
## one planet (drawn from all of them) flares: its radiation rises by RADIATION_JUMP (at most 100)
## and, when someone lives there, half the people die and the owner is told. All draws come from
## the mod's own stream, so the game's other random numbers are untouched.

const CHANCE := 4
const RADIATION_JUMP := 30
const RADIATION := 2
const MAX_VALUE := 100
const MESSAGE := "supernova.message.flare"


func _mod_init(api: ModApi) -> void:
	api.insert_after("production.random_events", Flares.new(api.stream))


class Flares:
	extends Phase
	var stream: String

	func _init(p_stream: String) -> void:
		super("supernova.flares")
		stream = p_stream

	func run(ctx: TurnContext) -> void:
		var rng := ctx.rng(stream)
		if rng.random(100) >= CHANCE:
			return
		var planet: Planet = ctx.state.planets[rng.random(ctx.state.planets.size())]
		var axis := planet.environment[RADIATION]
		planet.environment[RADIATION] = mini(axis + RADIATION_JUMP, MAX_VALUE)
		planet.environment_original[RADIATION] = planet.environment[RADIATION]
		if planet.owner >= 0 and planet.population > 0:
			planet.population /= 2
			TurnMessages.add(
				ctx.state, ctx.content, planet.owner, MESSAGE, {"planet": planet.id}, [planet.id]
			)
