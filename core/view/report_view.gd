class_name ReportView
extends RefCounted
## The report tables (M11 step 7; the original's `REPORTDLG@10f8:0000`): one row per own planet,
## own fleet, other player's fleet or battle, with the values each column shows, and the
## original's sort (`Report_SortRows@10f8:3bb2` and its comparator): by one column, forward or
## reverse, then by the column sorted before it; the order also sets the Command pane's Prev /
## Next order.
##
## A sort is {column, sub, forward}. `sub` picks one mineral (or colonists) in a column of three
## (or four) numbers. Forward sorts names A to Z and numbers smallest first; equal rows keep the
## natural order (planet id, fleet number).

const PLANETS := "planets"
const FLEETS := "fleets"
const OTHERS := "others"
const BATTLES := "battles"
const REPORTS := [PLANETS, FLEETS, OTHERS, BATTLES]
const COLUMNS := {
	PLANETS:
	[
		"name",
		"starbase",
		"population",
		"cap",
		"value",
		"production",
		"mines",
		"factories",
		"defenses",
		"minerals",
		"mining",
		"concentration",
		"resources",
		"driver",
		"route",
	],
	FLEETS:
	[
		"name",
		"id",
		"location",
		"destination",
		"eta",
		"task",
		"fuel",
		"cargo",
		"composition",
		"cloak",
		"battle_plan",
		"mass",
	],
	OTHERS:
	[
		"name",
		"id",
		"location",
		"warp",
		"mass",
		"composition",
		"ships",
		"unarmed",
		"scout",
		"warship",
		"bomber",
		"utility",
	],
	BATTLES:
	[
		"location",
		"starbase",
		"sides",
		"units",
		"ours",
		"theirs",
		"unarmed",
		"scout",
		"warship",
		"bomber",
		"utility",
		"our_dead",
		"their_dead",
		"ours_left",
		"theirs_left",
	],
}
## Columns of several numbers: how many.
const PARTS := {"minerals": 3, "mining": 3, "concentration": 3, "cargo": 4}
## An ETA for a fleet with no next waypoint sorts after every real one.
const NO_ETA := 32000


## The rows of `report`, in natural order.
static func rows(view: PlayerView, report: String) -> Array[Dictionary]:
	match report:
		PLANETS:
			return _planet_rows(view)
		FLEETS:
			return _fleet_rows(view)
	# other players' fleets need visibility (M8) and battles need combat (M9)
	return []


## `rows` sorted by `primary`, then `secondary` (either {} for none), then natural order.
static func sorted(
	rows: Array[Dictionary], report: String, primary: Dictionary, secondary: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in rows.size():
		var r := rows[i].duplicate()
		r["_order"] = i
		out.append(r)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			for s: Dictionary in [primary, secondary]:
				if s.is_empty():
					continue
				var c := _compare(report, s, a, b)
				if c != 0:
					return c < 0
			return a["_order"] < b["_order"]
	)
	return out


## The planet ids or fleet numbers of `report` in the order `primary` / `secondary` give.
static func order(
	view: PlayerView, report: String, primary: Dictionary, secondary: Dictionary
) -> Array[int]:
	var out: Array[int] = []
	var key := "id" if report == PLANETS else "number"
	for r in sorted(rows(view, report), report, primary, secondary):
		out.append(r[key])
	return out


## The value a row sorts by in `column` (part `sub` of a several-number column).
static func key(report: String, column: String, sub: int, row: Dictionary) -> Variant:
	match column:
		"name", "starbase", "location", "destination", "driver", "route", "battle_plan", "task":
			return str(row.get(column, "")).to_lower()
		"production":
			var p: Dictionary = row["production"]
			return p.get("name", "").to_lower()
		"composition":
			return row["composition"].get("name", "").to_lower()
		"minerals", "mining", "concentration", "cargo":
			return row[column][sub]
		"id":
			return row["number"]
		"resources":
			return row["resources_available"]
	if report == FLEETS and column == "eta":
		return row["eta"] if row["eta"] >= 0 else NO_ETA
	return row.get(column, 0)


static func _compare(report: String, s: Dictionary, a: Dictionary, b: Dictionary) -> int:
	var column: String = s["column"]
	var sub: int = s.get("sub", 0)
	var c := 0
	if report == PLANETS and column == "starbase":
		# planets with a starbase come first, then by its design's name
		var has_a: bool = a["starbase"] != ""
		var has_b: bool = b["starbase"] != ""
		if has_a != has_b:
			c = -1 if has_a else 1
	if c == 0:
		var ka: Variant = key(report, column, sub, a)
		var kb: Variant = key(report, column, sub, b)
		if ka is String:
			c = (ka as String).naturalnocasecmp_to(kb)
		else:
			c = signi(int(ka) - int(kb))
	return c if s.get("forward", true) else -c


static func _planet_rows(view: PlayerView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var race := view.me().race
	for pl in view.state.planets:
		if pl.owner != view.player:
			continue
		var info := view.planet_info(pl.id)
		var sb: Dictionary = info.get("starbase_info", {})
		var queue: Array = info["queue"]
		var max_pop: int = info["max_population"]
		var row := {
			"id": pl.id,
			"name": pl.name,
			"starbase": info["starbase"],
			# the dots by the name: a starbase that can build ships (dock), one that can't, a
			# mass driver, a stargate
			"dock": sb.get("dock", 0) != 0,
			"no_dock": not sb.is_empty() and sb.get("dock", 0) == 0,
			"driver_dot": sb.get("driver_warp", 0) > 0,
			"gate": _has_gate(view, pl),
			"population": pl.population * 100,
			"max_population": max_pop * 100,
			"cap": pl.population * 100 / max_pop if max_pop > 0 else 0,
			"value": info["habitability"],
			"value_terraformed": Habitability.value(info["terraform_best"], race),
			"production": queue[0] if not queue.is_empty() else {},
			"mines": pl.mines,
			"max_mines": info["max_mines"],
			"factories": pl.factories,
			"max_factories": info["max_factories"],
			"defenses": pl.defenses,
			"max_defenses": info["max_defenses"],
			"minerals": info["surface"],
			"mining": info["mined_next_year"],
			"concentration": info["concentration"],
			"resources": info["resources"],
			"resources_available": info["resources_production"],
			"driver": _planet_name(view, pl.mass_driver_target),
			"route": _planet_name(view, pl.route),
		}
		out.append(row)
	return out


static func _fleet_rows(view: PlayerView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var owner := view.me()
	for f in view.fleets():
		var info := view.fleet_info(f.number)
		var wps: Array = info["waypoints"]
		var next: Dictionary = wps[1] if wps.size() > 1 else {}
		var main := FleetOrders.main_design(f, owner, view.content)
		var design := owner.ship_design(main[0])
		var damaged := false
		for s: Dictionary in info["ships"]:
			damaged = damaged or s["damage"] > 0
		var plans: Array = owner.battle_plans
		var row := {
			"number": f.number,
			"name": info["name"],
			"location":
			(
				view.state.planet(f.planet).name
				if f.planet >= 0
				else "Space (%d, %d)" % [roundi(f.x), roundi(f.y)]
			),
			"destination": next.get("label", ""),
			"eta": next.get("years", -1),
			"short_of_fuel": next.get("short_of_fuel", false),
			"task": (next if not next.is_empty() else wps[0])["task"] if not wps.is_empty() else "",
			"fuel": f.cargo[Fleet.CARGO_FUEL],
			"cargo": f.cargo.slice(0, 4),
			"composition":
			{
				"name": design.name if design != null else "",
				"count": f.stack_for(main[0]).count if design != null else 0,
				"multi": main[1] > 1,
				"damaged": damaged,
			},
			# cloaking comes with visibility (M8, S15)
			"cloak": 0,
			"battle_plan": plans[f.battle_plan]["name"] if f.battle_plan < plans.size() else "",
			"mass": info["mass"],
		}
		out.append(row)
	return out


static func _planet_name(view: PlayerView, id: int) -> String:
	var pl := view.state.planet(id) if id >= 0 else null
	return pl.name if pl != null else ""


static func _has_gate(view: PlayerView, pl: Planet) -> bool:
	if pl.starbase == null:
		return false
	var d := view.me().starbase_design(pl.starbase.design)
	if d == null:
		return false
	for s in d.parts:
		if s.count > 0 and not s.part.is_empty():
			if view.content.part(s.part).get("stats", {}).has("gate_mass"):
				return true
	return false
