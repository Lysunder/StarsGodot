class_name TurnContext
extends RefCounted
## What the phases of one turn work on: the game state, the content, and per-turn values that
## pass between phases.

var state: GameState
var content: ContentRegistry
## Resources each player put into research this year (production, S09; spent by the tech
## update, S05).
var research_spent: Array[int] = []


func _init(p_state: GameState, p_content: ContentRegistry) -> void:
	state = p_state
	content = p_content
	research_spent.resize(state.players.size())


## The named random stream (S01). Phases draw only from streams obtained here.
func rng(stream_name: String = RngStreams.CLASSIC) -> StarsRandom:
	return state.rng.get_stream(stream_name)


func player(index: int) -> Player:
	return state.players[index]
