class_name MessageText
extends RefCounted
## A turn message (S21) as text for the Messages pane: the type's wording from the language file
## with each `{n}` replaced by parameter n written out by its kind.

const CARGO := ["Ironium", "Boranium", "Germanium", "colonists", "fuel"]
const AXES := ["gravity", "temperature", "radiation"]
const COLONISTS := 3
const FUEL := 4
## A fleet as a transport "where": this plus its `fleet` value (S21).
const FLEET_OBJECT := 32768
## The `fleet` and `fleet_designs` packings (S21).
const OWNER_SHIFT := 512
const DESIGNS_MANY := 8192
const DESIGN_SHIFT := 32
## The first word of a "where" that names an object rather than a position (-1 as a word).
const NOT_A_POSITION := 65535


## The text of a message `m` received by `player`.
static func format(view: PlayerView, player: int, m: Dictionary) -> String:
	var content := view.content
	var type: String = m["type"]
	if not content.has_def(type):
		return "(message %s)" % type
	var kinds: Array = content.get_def("message", type)["params"]
	var params: Array = m["params"]
	var cargo := -1
	for i in mini(kinds.size(), params.size()):
		if kinds[i] == "cargo":
			cargo = int(params[i])
	var text := content.string_for(type + ".text")
	for i in mini(kinds.size(), params.size()):
		var value := _value(view, player, type, kinds[i], params[i], cargo)
		# a "where" whose first word isn't -1 is a position: x, then y
		if kinds[i] == "object" and i > 0 and kinds[i - 1] == "object_kind":
			var x := int(params[i - 1])
			if x != -1 and x != NOT_A_POSITION:
				value = "Space (%d, %d)" % [x, int(params[i])]
		text = text.replace("{%d}" % i, value)
	return text


static func _value(
	view: PlayerView, player: int, type: String, kind: String, v: Variant, cargo: int
) -> String:
	var content := view.content
	match kind:
		"number":
			return thousands(int(v))
		"amount":
			if cargo == COLONISTS:
				return thousands(int(v) * 100)
			if cargo == FUEL:
				return "%smg" % thousands(int(v))
			if cargo >= 0:
				return "%skT" % thousands(int(v))
			return thousands(int(v))
		"population":
			return thousands(int(v) * 100)
		"planet":
			var pl := view.state.planet(int(v))
			return pl.name if pl != null else "planet %d" % int(v)
		"fleet":
			return _fleet(view, int(v) / OWNER_SHIFT, int(v) % OWNER_SHIFT)
		"fleet_designs":
			var number := int(v) % OWNER_SHIFT
			var slot := (int(v) % DESIGNS_MANY) / OWNER_SHIFT
			var d := view.state.player(player).ship_design(slot)
			var name := d.name if d != null else "Fleet"
			return "%s #%d" % [name, number + 1]
		"design":
			var owner := view.state.player(int(v) / DESIGN_SHIFT)
			var d := owner.ship_design(int(v) % DESIGN_SHIFT) if owner != null else null
			return d.name if d != null else "a design"
		"minefield":
			return "minefield #%d" % (int(v) % OWNER_SHIFT + 1)
		"minefield_type":
			return ["standard", "heavy", "speed bump"][clampi(int(v), 0, 2)]
		"own_design":
			var mine := view.state.player(player).ship_design(int(v))
			return mine.name if mine != null else "a design"
		"player":
			var p := view.state.player(int(v))
			return p.race.plural_name if p != null else "player %d" % (int(v) + 1)
		"cargo":
			return CARGO[clampi(int(v), 0, CARGO.size() - 1)]
		"field":
			for id in content.ids("tech_field"):
				if int(content.tech_field(id)["order"]) == int(v):
					return content.display_name(id)
			return "?"
		"item":
			return content.display_name(str(v))
		"flag":
			return content.string_for("%s.flag.%d" % [type, int(v)])
		"axis":
			return AXES[clampi(int(v), 0, 2)]
		"axis_value":
			return EnvironmentUnits.format(int(v) / 256, int(v) % 256)
		"object":
			if int(v) >= FLEET_OBJECT:
				var word := int(v) - FLEET_OBJECT
				return _fleet(view, word / OWNER_SHIFT, word % OWNER_SHIFT)
			var pl := view.state.planet(int(v))
			return pl.name if pl != null else "deep space"
	return ""


static func _fleet(view: PlayerView, owner: int, number: int) -> String:
	var f := view.state.fleet(owner, number)
	if f != null:
		return view.fleet_name(f)
	return "Fleet #%d" % (number + 1)


## 28700 -> "28,700" (as the panes write numbers).
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(-3)
	return ("-" if n < 0 else "") + digits + out
