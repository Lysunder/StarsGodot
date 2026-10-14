class_name ScoreWindow
extends AcceptDialog
## The score report (M11 step 7; D15, the original's `SCOREXDLG@10f8:0a66` arrangement), F10: three
## views the Switch button goes round. Player Scores: a column per player (planets, starbases,
## ships by class, tech levels, resources, score and rank; the best of each row in bold blue).
## Victory Conditions: the conditions switched on for the game and who meets them this turn.
## Score History: one figure over the years (ScoreGraph). Only the score records the player may
## see are shown (S20 "What a player sees").

const VIEWS := ["Player Scores", "Victory Conditions", "Score History"]
const ROW_LABELS := {
	"planets": "Planets",
	"starbases": "Starbases",
	"unarmed": "Unarmed ships",
	"escorts": "Escort ships",
	"capitals": "Capital ships",
	"tech": "Tech levels",
	"resources": "Resources",
	"score": "Score",
	"rank": "Rank",
}
const BEST := Color("0000a0")
const OFF := Color("808080")
const MET := "✓"

var view_index: int = 0

var _pages: Array[Control] = []
var _table: GridContainer
var _victory: GridContainer
var _victory_note: Label
var _graph: ScoreGraph


func _ready() -> void:
	ok_button_text = "Done"
	add_button("Switch", false, "switch")
	custom_action.connect(func(_a: StringName) -> void: show_view((view_index + 1) % VIEWS.size()))
	var stack := VBoxContainer.new()
	add_child(stack)
	_table = GridContainer.new()
	_table.add_theme_constant_override("h_separation", 16)
	stack.add_child(_table)
	var victory := VBoxContainer.new()
	_victory = GridContainer.new()
	_victory.add_theme_constant_override("h_separation", 16)
	victory.add_child(_victory)
	_victory_note = Label.new()
	victory.add_child(_victory_note)
	stack.add_child(victory)
	_graph = ScoreGraph.new()
	_graph.field_picked.connect(
		func(f: String) -> void:
			_graph.field = f
			_fill_graph()
	)
	stack.add_child(_graph)
	_pages = [_table, victory, _graph]


func open() -> void:
	show_view(view_index)
	popup_centered()


func show_view(index: int) -> void:
	view_index = index
	title = VIEWS[index]
	for i in _pages.size():
		_pages[i].visible = i == index
	match index:
		0:
			_fill_table()
		1:
			_fill_victory()
		2:
			_fill_graph()
	reset_size()


func _label(text: String, colour: Color = ClassicTheme.TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	if bold:
		l.add_theme_font_override("font", ClassicTheme.bold_font(_table))
	return l


func _clear(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


## The header row: an empty corner, then each player's name (grey when eliminated or unknown).
func _header(grid: GridContainer, players: Array) -> void:
	grid.add_child(_label(""))
	for info: Dictionary in players:
		var colour := ClassicTheme.TEXT
		if info["eliminated"]:
			colour = OFF
		var l := _label(info["name"], colour, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)


func _fill_table() -> void:
	_clear(_table)
	var t := ScoreView.table(GameSession.view)
	var players: Array = t["players"]
	_table.columns = players.size() + 1
	_header(_table, players)
	for row: Dictionary in t["rows"]:
		_table.add_child(_label(ROW_LABELS[row["field"]] + ":", ClassicTheme.TEXT, true))
		var values: Array = row["values"]
		# the best stands out only when the values shown differ
		var shown := values.filter(func(v: int) -> bool: return v >= 0)
		var differ := shown.any(func(v: int) -> bool: return v != shown[0])
		for v: int in values:
			var best: bool = differ and v == row["best"]
			var l := _label(
				"" if v < 0 else CommandPane.thousands(v), BEST if best else ClassicTheme.TEXT, best
			)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_table.add_child(l)


func _fill_victory() -> void:
	_clear(_victory)
	var view := GameSession.view
	var t := ScoreView.table(view)
	var players: Array = t["players"]
	_victory.columns = players.size() + 1
	_header(_victory, players)
	var criteria := 0
	var min_years := 0
	for c: Dictionary in ScoreView.conditions(view):
		match c["id"]:
			"criteria":
				criteria = c["value"]
				continue
			"min_years":
				min_years = c["value"]
				continue
		var on: bool = c["on"]
		_victory.add_child(_label(_condition_text(view, c), ClassicTheme.TEXT if on else OFF))
		for m: Variant in c["met"]:
			var l := _label(MET if m == true else "", ClassicTheme.TEXT if on else OFF, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_victory.add_child(l)
	var lines: Array[String] = [
		"A winner must meet %d of the conditions switched on." % criteria,
		"No winner can be declared before %d years have passed." % min_years,
	]
	var winners := ScoreView.winners(view)
	if not winners.is_empty():
		var names: Array[String] = []
		for p in winners:
			names.append(view.state.player(p).race.plural_name)
		lines.append("Won by: " + ", ".join(names) + ".")
	_victory_note.text = "\n".join(lines)


## A condition in our words, with the value set for the game.
static func _condition_text(view: PlayerView, c: Dictionary) -> String:
	var v: int = c["value"]
	match c["id"]:
		"owns_planets":
			var planets := view.state.planets.size()
			return "Own %d%% of the planets (%d of %d)" % [v, (planets * v + 50) / 100, planets]
		"tech_level":
			return "Reach tech level %d in %d fields" % [v, c.get("fields", 0)]
		"score":
			return "Reach a score of %s" % CommandPane.thousands(v)
		"exceeds_second":
			return "Lead the next best score by %d%%" % v
		"production":
			return "Produce %d thousand resources a year" % v
		"capital_ships":
			return "Own %d capital ships" % v
		"highest_score":
			return "Have the best score after %d years" % v
	return c["id"]


func _fill_graph() -> void:
	var view := GameSession.view
	_graph.me = view.player
	_graph.names.clear()
	for player in view.state.players:
		_graph.names.append(player.race.plural_name)
	_graph.lines = ScoreView.series(view, _graph.field)
	_graph.queue_redraw()
