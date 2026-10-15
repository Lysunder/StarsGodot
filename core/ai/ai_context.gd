class_name AiContext
extends RefCounted
## What a computer player works from (spec S22 "The AI step"): its view of the game, the content,
## the random stream it draws from, its personality and difficulty level. It gives the turn's
## orders through `order`; they are checked and applied like a human player's (S11).

var view: PlayerView
var content: ContentRegistry
var rng: StarsRandom
## The personality's content definition (`ai_personality`).
var personality: Dictionary
## Difficulty, 0 (easiest) to ComputerPlayers.LEVELS.size() - 1.
var level: int
## The brain's declared settings by key (AiBrains.settings), for their defaults.
var declared := {}
var orders: OrderSet


func _init(
	p_view: PlayerView,
	p_content: ContentRegistry,
	p_rng: StarsRandom,
	p_personality: Dictionary,
	p_level: int
) -> void:
	view = p_view
	content = p_content
	rng = p_rng
	personality = p_personality
	level = p_level
	orders = OrderSet.new(p_view.player, p_view.state.turn)
	for s: Dictionary in AiBrains.settings(str(p_personality.get("brain", ""))):
		declared[s["key"]] = s


func me() -> Player:
	return view.me()


## A personality setting: the level's own value if the personality sets one, else its general
## value, else the brain's declared default, else `fallback`.
func param(key: String, fallback: int = 0) -> int:
	var levels: Array = personality.get("levels", [])
	if level >= 0 and level < levels.size() and levels[level].has(key):
		return int(levels[level][key])
	var params: Dictionary = personality.get("params", {})
	if params.has(key):
		return int(params[key])
	if declared.has(key):
		return int(declared[key]["default"])
	return fallback


func order(o: Dictionary) -> void:
	orders.add(o)
