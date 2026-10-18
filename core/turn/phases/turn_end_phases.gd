class_name TurnEndPhases
extends RefCounted
## Phases at the end of a turn (spec S02 22, 23, 24, 26, 27).


## 22: the population and defense estimates other players see (S15 "Estimates").
class Estimates:
	extends Phase

	func _init() -> void:
		super("planets.estimates")

	func run(ctx: TurnContext) -> void:
		PlanetEstimates.update(ctx.state, ctx.content, ctx.rng())


## 23: the year advances.
class Advance:
	extends Phase

	func _init() -> void:
		super("turn.advance")

	func run(ctx: TurnContext) -> void:
		ctx.state.turn += 1
		for p in ctx.state.players:
			p.tech_bonus_taken = false


## 24: scores, ranks, eliminations and victory (S20).
class ScoreUpdate:
	extends Phase

	func _init() -> void:
		super("score.update")

	func run(ctx: TurnContext) -> void:
		Score.update(ctx.state, ctx.content)
		Score.note_history(ctx.state)


## 26: one draw the original stores in its settings word (purpose open, S02).
class RandomSettings:
	extends Phase

	const DRAW := 8

	func _init() -> void:
		super("turn.random_settings")

	func run(ctx: TurnContext) -> void:
		ctx.rng().random(DRAW)


## 27: the original draws one value per file it writes, player files first, then the host
## file (S01). We make the same draws without writing those files. Writing each player's file
## also runs that player's scanning, which records minefields and wormholes seen (S15); what
## each player saw then goes into its planet history (S15 "Planet history").
class FileDraws:
	extends Phase

	const DRAW := 2000

	func _init() -> void:
		super("files.write")

	## Each player's file: scanning (S15; Space Demolition draws), the orders that change with it,
	## then the file's draw; then the host file's draw.
	func run(ctx: TurnContext) -> void:
		ctx.state.views.clear()
		for p in ctx.state.players.size():
			var sight := Scanning.record_player(ctx.state, ctx.content, p, ctx.rng())
			Retargeting.run(ctx.state, ctx.content, p, sight)
			ctx.rng().random(DRAW)
		ctx.rng().random(DRAW)
		_drop_lone_colonists(ctx.state)
		Scanning.finish(ctx.state)
		PlanetHistory.note_all(ctx.state)

	## The host file has no installations for an unowned planet without mines, factories or
	## defenses, so the single colonists left there are gone when the turn is loaded (S08
	## "Depopulation").
	func _drop_lone_colonists(state: GameState) -> void:
		for planet in state.planets:
			if planet.owner < 0 and planet.mines == 0 and planet.factories == 0:
				if planet.defenses == 0:
					planet.extra_colonists = 0
