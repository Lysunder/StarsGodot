class_name ReportSettings
extends RefCounted
## Each report's sort and hidden columns (the original keeps them in Stars.ini, [Misc]
## ReportPlanSort, ReportPlanFld and so on), saved in the player's settings file. The planet and
## fleet sorts also set the order the Command pane's and Production dialog's Prev / Next follow.

const SECTION := "reports"

## The settings file (tests use their own).
static var path := ClassicTheme.SETTINGS_PATH


## The settings of `report`: {primary, secondary (sorts, {} for none), hidden (column ids)}.
static func of(report: String) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var stored: Variant = cfg.get_value(SECTION, report, {})
	var out := {"primary": {}, "secondary": {}, "hidden": []}
	if stored is Dictionary:
		for k: String in out:
			if stored.has(k) and typeof(stored[k]) == typeof(out[k]):
				out[k] = stored[k]
	return out


static func save(report: String, settings: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(SECTION, report, settings)
	cfg.save(path)


## Sorts `report` by `sort`; the sort before it becomes the second level when the column changes
## (as `Report_SortRows` does).
static func sort_by(report: String, sort: Dictionary) -> void:
	var s := of(report)
	var before: Dictionary = s["primary"]
	if not before.is_empty() and before["column"] != sort["column"]:
		s["secondary"] = before
	s["primary"] = sort
	save(report, s)


## The player's planet ids in the Planet report's order.
static func planet_order() -> Array[int]:
	return _order(ReportView.PLANETS)


## The player's fleet numbers in the Fleet report's order.
static func fleet_order() -> Array[int]:
	return _order(ReportView.FLEETS)


static func _order(report: String) -> Array[int]:
	if not GameSession.has_game():
		return []
	var s := of(report)
	return ReportView.order(GameSession.view, report, s["primary"], s["secondary"])
