class_name PlanetPhases
extends RefCounted
## Planet phases after the waypoint-1 tasks (spec S02 19, 20).


## 19: Claim Adjuster terraforming (S10 step 6).
class ClaimAdjusterTerraform:
	extends Phase

	func _init() -> void:
		super("planets.ca_terraform")

	func run(ctx: TurnContext) -> void:
		Terraforming.claim_adjuster(ctx.state, ctx.content, ctx.rng())


## 20: remote terraforming by fleets (S10 step 7).
class RemoteTerraform:
	extends Phase

	func _init() -> void:
		super("planets.remote_terraform")

	func run(ctx: TurnContext) -> void:
		Terraforming.remote(ctx.state, ctx.content)
