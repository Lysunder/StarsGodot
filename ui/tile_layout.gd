class_name TileLayout
extends RefCounted
## Where the Command pane's tiles go (issue #11): for planets and for fleets, columns of tile keys
## from top to bottom, and which tiles are collapsed. Saved in the player's settings file, as the
## original keeps its tile order in Stars.ini (PlanetTiles, ShipTiles). The default is the
## original's: two columns.

const SECTION := "tiles"
const COLUMNS := 2
const DEFAULTS := {
	"planet":
	[
		["planet", "Minerals on Hand", "Status"],
		["Fleets in Orbit", "starbase", "Production"],
	],
	"fleet":
	[
		["fleet", "location", "Fuel & Cargo", "Fleet Composition"],
		["Fleet Waypoints", "Waypoint Task", "Other Fleets Here"],
	],
}

## A column of tiles is at least this wide (the widest tile, the Planet tile, fits).
const COLUMN_WIDTH := 232
const COLUMN_GAP := 2

## The settings file (tests use their own).
static var path := UiSettings.PATH


## The space below a column's tiles: a tile dropped there goes to the bottom of the column.
class ColumnEnd:
	extends Control

	signal dropped(from_key: String)

	func _init() -> void:
		custom_minimum_size = Vector2(0, Tile.BAR_HEIGHT)
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("tile")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		dropped.emit(data["tile"])


## Moves the tiles just made in `box` into columns as the layout places them. A tile dropped on
## another goes above it in that tile's column; one dropped below a column's tiles goes to its
## bottom: both call `on_move(key, column, before)`.
static func arrange(box: Container, kind: String, on_move: Callable) -> void:
	var made := {}
	var keys := []
	for child in box.get_children():
		if child is Tile and not child.is_queued_for_deletion():
			made[child.key] = child
			keys.append(child.key)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", COLUMN_GAP)
	box.add_child(row)
	var placed := place(kind, keys)
	for i in placed.size():
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		for key: String in placed[i]:
			var t: Tile = made[key]
			box.remove_child(t)
			column.add_child(t)
			t.tile_dropped.connect(
				func(from_key: String, to_key: String) -> void: on_move.call(from_key, i, to_key)
			)
		var end := ColumnEnd.new()
		end.dropped.connect(func(from_key: String) -> void: on_move.call(from_key, i, ""))
		column.add_child(end)


## The columns for `kind` ("planet", "fleet"), each an array of tile keys.
static func columns(kind: String) -> Array:
	var stored: Variant = _config().get_value(SECTION, kind, [])
	var out := []
	if stored is Array and (stored as Array).size() == COLUMNS:
		for column: Variant in stored:
			if not column is Array:
				return (DEFAULTS.get(kind, [[], []]) as Array).duplicate(true)
			out.append((column as Array).filter(func(k: Variant) -> bool: return k is String))
		return out
	return (DEFAULTS.get(kind, [[], []]) as Array).duplicate(true)


## Lays `keys` (the tiles being shown, in the order they were made) out in columns: each where the
## layout puts it, tiles it doesn't know at the end of the first column.
static func place(kind: String, keys: Array) -> Array:
	var layout := columns(kind)
	var out := []
	for column: Array in layout:
		out.append(column.filter(func(k: String) -> bool: return keys.has(k)))
	for k: String in keys:
		if not layout.any(func(column: Array) -> bool: return column.has(k)):
			out[0].append(k)
	return out


## Moves tile `key` into `column`, before tile `before` (at the end when "" or not there).
static func move(kind: String, key: String, column: int, before: String = "") -> void:
	var layout := columns(kind)
	for c: Array in layout:
		c.erase(key)
	var target: Array = layout[clampi(column, 0, COLUMNS - 1)]
	var at := target.find(before) if not before.is_empty() else -1
	if at < 0:
		target.append(key)
	else:
		target.insert(at, key)
	var cfg := _config()
	cfg.set_value(SECTION, kind, layout)
	cfg.save(path)


## The column holding tile `key` (-1 when the layout doesn't place it).
static func column_of(kind: String, key: String) -> int:
	var layout := columns(kind)
	for i in layout.size():
		if (layout[i] as Array).has(key):
			return i
	return -1


static func is_collapsed(key: String) -> bool:
	return (_config().get_value(SECTION, "collapsed", []) as Array).has(key)


static func set_collapsed(key: String, collapsed: bool) -> void:
	var cfg := _config()
	var keys: Array = cfg.get_value(SECTION, "collapsed", [])
	keys.erase(key)
	if collapsed:
		keys.append(key)
	cfg.set_value(SECTION, "collapsed", keys)
	cfg.save(path)


static func _config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg
