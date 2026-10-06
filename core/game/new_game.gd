class_name NewGame
extends RefCounted
## Creates a single-player game for the UI (spec S07 through UniverseGenerator): one human
## player with the given race in a universe of the given size, density and player spacing.

const SIZES := ["tiny", "small", "medium", "large", "huge"]
const WIDTH_STEP := 400


class Options:
	extends RefCounted
	## Index into SIZES.
	var size: int = 1
	var density: String = "normal"
	var positions: String = "moderate"
	var race: Race = null
	var seed: int = 1
	## GameSettings flags to turn on (max_minerals, slow_tech, accelerated_start,
	## no_random_events, galaxy_clumping, ...).
	var flags: Array[String] = []


static func create(content: ContentRegistry, options: Options) -> GameState:
	var settings := GameSettings.new()
	settings.universe_width = (options.size + 1) * WIDTH_STEP
	settings.density = options.density
	settings.player_positions = options.positions
	for flag in options.flags:
		settings.set(flag, true)
	var player := Player.new()
	player.index = 0
	player.race = options.race.copy() as Race if options.race != null else Race.new()
	if player.race.name.is_empty():
		player.race.name = "Humanoids"
		player.race.plural_name = "Humanoids"
	var players: Array[Player] = [player]
	var state := UniverseGenerator.new(content, settings, players, options.seed).generate()
	SaveFile.stamp(state, content)
	return state
