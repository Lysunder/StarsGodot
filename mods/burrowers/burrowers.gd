extends RefCounted
## Burrowers: the trait itself is data (content/traits.json: more room, slower growth); what a
## parameter can't say, the tunnels that bring up minerals, is a turn phase run after mining.

const TRAIT := "burrowers.trait.burrowers"
## People (in units of 100) per kiloton of each mineral the tunnels bring up a year.
const PEOPLE_PER_KT := 100


func _mod_init(api: ModApi) -> void:
	api.insert_after("production.mining", Tunnels.new())


## Each Burrowers planet gains a kiloton of each mineral per PEOPLE_PER_KT people, in planet order.
class Tunnels:
	extends Phase

	func _init() -> void:
		super("burrowers.tunnels")

	func run(ctx: TurnContext) -> void:
		for planet in ctx.state.planets:
			if planet.owner < 0 or planet.population <= 0:
				continue
			if ctx.player(planet.owner).race.primary_trait != TRAIT:
				continue
			var kt := planet.population / PEOPLE_PER_KT
			for m in 3:
				planet.surface[m] += kt
