class_name GameSettings
extends ModelObject
## Universe and rule options of one game (S03; generation inputs S07, victory S20).

const DENSITIES := ["sparse", "normal", "dense", "packed"]
const POSITIONS := ["close", "moderate", "farther", "distant"]

## Light years; positions run from 1000 to 1000 + width on both axes.
var universe_width: int = 400
var density: String = "normal"
var player_positions: String = "moderate"
var max_minerals: bool = false
var slow_tech: bool = false
var accelerated_start: bool = false
var no_random_events: bool = false
var computer_alliances: bool = false
var public_scores: bool = false
var galaxy_clumping: bool = false
## Reseeds the classic stream every turn (S01).
var tutorial: bool = false
## Victory conditions (S20).
var victory: Dictionary = {}
## Ruleset hash of the content registry, and the enabled mods as {"id", "version"} (M2).
var ruleset_hash: String = ""
var mods: Array = []


func _schema() -> Array:
	return [
		["universe_width", Kind.INT],
		["density", Kind.ENUM, DENSITIES],
		["player_positions", Kind.ENUM, POSITIONS],
		["max_minerals", Kind.BOOL],
		["slow_tech", Kind.BOOL],
		["accelerated_start", Kind.BOOL],
		["no_random_events", Kind.BOOL],
		["computer_alliances", Kind.BOOL],
		["public_scores", Kind.BOOL],
		["galaxy_clumping", Kind.BOOL],
		["tutorial", Kind.BOOL],
		["victory", Kind.JSON],
		["ruleset_hash", Kind.STRING],
		["mods", Kind.JSON],
	]
