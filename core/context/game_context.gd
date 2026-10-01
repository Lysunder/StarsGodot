class_name GameContext
extends RefCounted
## Everything one game needs to run its rules: content, ruleset, RNG streams and hooks.
##
## Code in core/ never reaches for globals or autoloads. It receives a GameContext (or a narrower
## context built from one) as an argument. That lets several games live in one process: AI
## lookahead, parallel tests and harness runs.
##
## The members are placeholders until the systems behind them exist:
## content (M2), ruleset (M2/M6), hooks (M6).

## Frozen ContentRegistry for this game (M2).
var content: RefCounted = null
## Ruleset holding the formula providers selected for this game (M2/M6).
var ruleset: RefCounted = null
## Named RNG streams ("classic", "fixes", one per mod) derived from the game seed (S01).
var rng_streams: RngStreams
## Hook bus for mod and trait scripts (M6).
var hooks: RefCounted = null
## Seed the game was created with. Every RNG stream is derived from it.
var game_seed: int = 0


## classic_from_game_seed: start the classic stream with the original's game-seed method (S01).
func _init(p_game_seed: int = 0, classic_from_game_seed: bool = false) -> void:
	game_seed = p_game_seed
	rng_streams = RngStreams.new(game_seed, classic_from_game_seed)


## The named random stream (S01). Rules draw only from streams obtained here.
func rng(stream_name: String) -> StarsRandom:
	return rng_streams.get_stream(stream_name)
