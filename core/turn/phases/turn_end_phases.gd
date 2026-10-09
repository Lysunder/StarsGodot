class_name TurnEndPhases
extends RefCounted
## Phases at the end of a turn (spec S02 23, 26, 27).


## 23: the year advances.
class Advance:
	extends Phase

	func _init() -> void:
		super("turn.advance")

	func run(ctx: TurnContext) -> void:
		ctx.state.turn += 1
		for p in ctx.state.players:
			p.tech_bonus_taken = false


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
## also runs that player's scanning, which records minefields and wormholes seen (S15).
class FileDraws:
	extends Phase

	const DRAW := 2000

	func _init() -> void:
		super("files.write")

	func run(ctx: TurnContext) -> void:
		for i in ctx.state.players.size() + 1:
			ctx.rng().random(DRAW)
		Scanning.record_all(ctx.state, ctx.content)
