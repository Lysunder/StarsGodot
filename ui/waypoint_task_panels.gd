class_name WaypointTaskPanels
extends RefCounted
## The Waypoint Task tile's settings for the lay mines and patrol tasks, as the original shows
## them. Each change calls `change(wp, warp, task, task_data)` (the Command pane's waypoint change).


## A task's data words (S11), a copy to change.
static func _task_words(wp: Dictionary) -> Array:
	var words: Array = (wp["task_data"].get("raw", [0, 0, 0, 0, 0]) as Array).duplicate()
	while words.size() < 5:
		words.append(0)
	return words


## A label and a list in one row of tile `t`; picking an item calls `picked(index)`.
static func _choice_row(
	t: Tile, label_text: String, items: Array, at: int, picked: Callable
) -> void:
	var r := t.row()
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = "BoldLabel"
	r.add_child(l)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: String in items:
		choice.add_item(item)
	choice.select(clampi(at, 0, items.size() - 1))
	choice.item_selected.connect(picked)
	r.add_child(choice)


## The lay mines task: how many years to lay, as the original lists them (task data word 0: 0 to
## 4 for 1 to 5 years, 5 for indefinitely; S11 "Lay mines").
static func lay_mines(t: Tile, wp: Dictionary, change: Callable) -> void:
	var words := _task_words(wp)
	var items := ["1 year"]
	for n in range(2, 6):
		items.append(TranslationServer.translate("%d years") % n)
	items.append("Indefinitely")
	_choice_row(
		t,
		"Lay for",
		items,
		words[0],
		func(i: int) -> void:
			words[0] = i
			change.call(wp, wp["warp"], "lay_mines", {"raw": words})
	)


## The patrol task: the intercept range (task data word 1: 50 to 550 ly, then any enemy) and the
## intercept speed (word 0; 0 is Automatic, the fleet's default warp) (S15 "Patrol").
static func patrol(t: Tile, wp: Dictionary, change: Callable) -> void:
	var words := _task_words(wp)
	var items := []
	for n in range(1, Retargeting.ANY_ENEMY + 1):
		items.append(TranslationServer.translate("Within %d l.y.") % (n * Retargeting.RANGE_STEP))
	items.append("Any enemy")
	_choice_row(
		t,
		"Intercept",
		items,
		words[1],
		func(i: int) -> void:
			words[1] = i
			change.call(wp, wp["warp"], "patrol", {"raw": words})
	)
	var speed := t.gauge("Intercept Speed", WarpGauge.new()) as WarpGauge
	speed.zero_text = "Automatic"
	speed.set_value(int(words[0]) & 15)
	speed.value_set.connect(
		func(v: int) -> void:
			words[0] = v
			change.call(wp, wp["warp"], "patrol", {"raw": words})
	)
