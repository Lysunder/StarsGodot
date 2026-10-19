class_name BattleReplay
extends RefCounted
## A battle record (S16 "The recording") as the battle viewer plays it back (M11 step 8; the
## original's `VCR_SeekTo@10e0:053e`, `VCR_TokenStatus@10e0:0f74`), plus the Battle Summary
## report's counts (`Battle_CountShips@10e0:02aa`, `Battle_CountLosses@10e0:03b8`).
##
## Step -1 is the board as the battle started; step k shows event k: its token has moved (or
## stayed, to fire) and its hits have landed. Going on to the next round first regenerates the
## shields of tokens that regenerate them. A hit takes away the ships it killed, sets the target's
## damage word, and takes the shield damage off its shields per ship (all of them when it is at
## least what the remaining ships had).

## The report's ship filters (`Battle_CountShips`): whose tokens, whether starbases count, and
## which hull classes.
const OURS := 1
const THEIRS := 2
const STARBASES := 4
const UNARMED := 8
const SCOUT := 0x10
const WARSHIP := 0x20
const BOMBER := 0x40
const UTILITY := 0x80
const ALL_CLASSES := 0xF8
const KIND_STARBASE := 1
## The square of a token that has left the battle.
const GONE := 255
const BOARD := 10
const SHIELDS_REGENERATE := 8
const HIT_ABSORBED := 0x40

var view: PlayerView
var battle: Dictionary
## The step shown, -1 (the start) to `last`.
var step: int = -1
## The last step.
var last: int = -1
## The last round any event happens in.
var last_round: int = 0
## Each token now: {square, count, damage, shields}.
var tokens: Array[Dictionary] = []

var _round: int = 0
## The armor each target of the current event had before it (token -> armor).
var _armor_before := {}


func _init(p_view: PlayerView, p_battle: Dictionary) -> void:
	view = p_view
	battle = p_battle
	var events: Array = battle.get("events", [])
	last = events.size() - 1
	for e: Dictionary in events:
		last_round = maxi(last_round, int(e["round"]))
	seek(-1)


## The battles the player took part in this year, in the order fought.
static func battles(p_view: PlayerView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in p_view.state.battles:
		if (b.get("players", []) as Array).has(p_view.player):
			out.append(b)
	return out


static func find(p_view: PlayerView, id: int) -> Dictionary:
	for b in battles(p_view):
		if int(b["id"]) == id:
			return b
	return {}


## Where the battle was: the planet's name, or the point in space.
static func location(p_view: PlayerView, b: Dictionary) -> String:
	var planet := int(b.get("planet", -1))
	if planet >= 0:
		return p_view.state.planet(planet).name
	return "Space (%d, %d)" % [int(b["x"]), int(b["y"])]


## Ships at the start of the battle that pass `mask` (whose; starbases; hull classes), counting
## each token's ships. Without STARBASES only ship tokens count; with every class bit set the
## class doesn't matter.
static func count_ships(p_view: PlayerView, b: Dictionary, mask: int) -> int:
	var n := 0
	for t: Dictionary in b.get("tokens", []):
		var side := OURS if int(t["owner"]) == p_view.player else THEIRS
		if mask & side == 0:
			continue
		var starbase := int(t["kind"]) == KIND_STARBASE
		if starbase:
			if mask & STARBASES:
				n += int(t["count"])
			continue
		if mask & ALL_CLASSES == ALL_CLASSES or mask & class_bit(p_view, t):
			n += int(t["count"])
	return n


## The report column a ship token's hull class falls in: classes 2 (scout), 3 (warship),
## 5 (bomber), 4 (utility), every other class unarmed.
static func class_bit(p_view: PlayerView, t: Dictionary) -> int:
	var token_design := p_view.state.player(int(t["owner"])).ship_design(int(t["design"]))
	if token_design == null:
		return UNARMED
	match int(p_view.content.hull(token_design.hull).get("class", 0)):
		2:
			return SCOUT
		3:
			return WARSHIP
		4:
			return UTILITY
		5:
			return BOMBER
	return UNARMED


## Ships the player (`ours`) or everyone else lost in the battle.
static func losses(p_view: PlayerView, b: Dictionary, ours: bool) -> int:
	var board: Array = b.get("tokens", [])
	var n := 0
	for e: Dictionary in b.get("events", []):
		for h: Dictionary in e["hits"]:
			var mine := int(board[int(h["target"])]["owner"]) == p_view.player
			if mine == ours:
				n += int(h["killed"])
	return n


## The Battle Summary report row.
static func summary_row(p_view: PlayerView, b: Dictionary) -> Dictionary:
	var everyone := OURS | THEIRS
	var ours := count_ships(p_view, b, 0xFF & ~THEIRS)
	var theirs := count_ships(p_view, b, 0xFF & ~OURS)
	var our_dead := losses(p_view, b, true)
	var their_dead := losses(p_view, b, false)
	var sb := ""
	if count_ships(p_view, b, OURS | STARBASES) > 0:
		sb = "O"
	elif count_ships(p_view, b, THEIRS | STARBASES) > 0:
		sb = "T"
	return {
		"id": int(b["id"]),
		"location": location(p_view, b),
		"x": int(b["x"]),
		"y": int(b["y"]),
		"planet": int(b.get("planet", -1)),
		"starbase": sb,
		"sides": int(b["sides"]),
		"units": count_ships(p_view, b, 0xFF),
		"ours": ours,
		"theirs": theirs,
		"unarmed": count_ships(p_view, b, everyone | UNARMED),
		"scout": count_ships(p_view, b, everyone | SCOUT),
		"warship": count_ships(p_view, b, everyone | WARSHIP),
		"bomber": count_ships(p_view, b, everyone | BOMBER),
		"utility": count_ships(p_view, b, everyone | UTILITY),
		"our_dead": our_dead,
		"their_dead": their_dead,
		"ours_left": ours - our_dead,
		"theirs_left": theirs - their_dead,
	}


## Shows step `to` (clamped to -1..last).
func seek(to: int) -> void:
	to = clampi(to, -1, last)
	if to < step or tokens.is_empty():
		_reset()
	var events: Array = battle["events"]
	while step < to:
		step += 1
		var e: Dictionary = events[step]
		if int(e["round"]) > _round:
			_round = int(e["round"])
			_regenerate()
		tokens[int(e["token"])]["square"] = int(e["square"])
		_armor_before.clear()
		for h: Dictionary in e["hits"]:
			var target := int(h["target"])
			if not _armor_before.has(target):
				_armor_before[target] = _armor_now(target)
			_land(h)


func _reset() -> void:
	tokens.clear()
	for t: Dictionary in battle["tokens"]:
		(
			tokens
			. append(
				{
					"square": int(t["square"]),
					"count": int(t["count"]),
					"damage": int(t["damage"]),
					"shields": int(t["shields"]),
				}
			)
		)
	step = -1
	_round = 0
	_armor_before.clear()


func _land(h: Dictionary) -> void:
	var t := tokens[int(h["target"])]
	t["count"] = maxi(int(t["count"]) - int(h["killed"]), 0)
	t["damage"] = int(h["damage"])
	var hit := BattleEngine.unpack(int(h["shield_damage"]))
	if int(t["shields"]) != 0 and hit != 0:
		if int(t["shields"]) * int(t["count"]) <= hit:
			t["shields"] = 0
		else:
			t["shields"] = int(t["shields"]) - hit / int(t["count"])


func _regenerate() -> void:
	for i in tokens.size():
		var rec: Dictionary = battle["tokens"][i]
		if int(rec["state"]) & SHIELDS_REGENERATE == 0:
			continue
		var full := PartRules.shields(design(i), view.content, _owner(i).race)
		tokens[i]["shields"] = mini(int(tokens[i]["shields"]) + full / 10, full)


func _owner(i: int) -> Player:
	return view.state.player(int(battle["tokens"][i]["owner"]))


## The token's design.
func design(i: int) -> Design:
	var rec: Dictionary = battle["tokens"][i]
	if int(rec["kind"]) == KIND_STARBASE:
		return _owner(i).starbase_design(int(rec["design"]) - 16)
	return _owner(i).ship_design(int(rec["design"]))


## The current event ({} at the start).
func event() -> Dictionary:
	return {} if step < 0 else battle["events"][step]


## The round of the current event (0 at the start).
func current_round() -> int:
	return _round


## The tokens on a square (alive, still in the battle), in board order.
func tokens_at(square: int) -> Array[int]:
	var out: Array[int] = []
	for i in tokens.size():
		if int(tokens[i]["square"]) == square and int(tokens[i]["count"]) > 0:
			out.append(i)
	return out


func _armor_now(i: int) -> int:
	return armor_left(i) if int(tokens[i]["count"]) > 0 else 0


## The armor the token's ships have left (`Token_RemainingArmor@10e0:046a`): the full armor of
## each ship less, for the damaged share of them, the damage each carries.
func armor_left(i: int) -> int:
	var t := tokens[i]
	var count := int(t["count"])
	var armor := PartRules.armor(design(i), view.content, _owner(i).race)
	var left := count * armor
	var damage := int(t["damage"])
	if damage != 0 and count > 0:
		var damaged := maxi(count * (damage & 0x7F) / 100, 1)
		left += _tdiv(_tdiv(-(damage >> 7) * armor, 10) * damaged, 50)
	return left


## How the selected token stands, for the viewer's selection panel.
func status(i: int) -> Dictionary:
	var rec: Dictionary = battle["tokens"][i]
	var t := tokens[i]
	var d := design(i)
	var count := int(t["count"])
	var damage := int(t["damage"])
	var starbase := int(rec["kind"]) == KIND_STARBASE
	var out := {
		"owner": int(rec["owner"]),
		"name": d.name if d != null else "",
		"count": count,
		"starbase": starbase,
		"alive": count > 0,
		"gone": int(t["square"]) == GONE,
		"initiative": 0 if int(rec["initiative_low"]) == 255 else int(rec["initiative_low"]),
		# moves a round, in quarters: (rating + 2) / 4; a starbase never moves
		"movement_quarters": -1 if starbase else (int(rec["movement"]) & 15) + 2,
		"armor": armor_left(i) if count > 0 else 0,
		"damaged": 0,
		"damage_pct": 0,
		"shields": int(t["shields"]) * count,
		"jamming": int(rec["torpedo_jamming"]),
		"tactic": int(rec["tactic"]) & 15,
		"countdown": _countdown(i),
		"primary_target": int(rec["targets"]) & 15,
		"secondary_target": int(rec["targets"]) >> 4,
	}
	if damage != 0 and count > 0:
		out["damaged"] = maxi(count * (damage & 0x7F) / 100, 1)
		out["damage_pct"] = maxi((damage / 5) >> 7, 1)
	return out


## The disengage countdown as of the token's last event (the record's at the start).
func _countdown(i: int) -> int:
	var events: Array = battle["events"]
	for k in range(step, -1, -1):
		if int(events[k]["token"]) == i:
			return int(events[k]["countdown"])
	return (int(battle["tokens"][i]["state"]) >> 5) & 15


## What the current event did, for the viewer's action panel: {token, square, target (the first
## one hit, -1 for none), target_square, shield_damage, armor_damage, killed (over every target),
## no_damage (the first hit was absorbed and nothing got through)}.
func action() -> Dictionary:
	var e := event()
	if e.is_empty():
		return {}
	var out := {
		"token": int(e["token"]),
		"square": int(e["square"]),
		"target": -1,
		"target_square": -1,
		"shield_damage": 0,
		"armor_damage": 0,
		"killed": 0,
		"no_damage": false,
	}
	var hits: Array = e["hits"]
	if hits.is_empty():
		return out
	var first := int(hits[0]["target"])
	out["target"] = first
	out["target_square"] = int(tokens[first]["square"])
	for h: Dictionary in hits:
		out["killed"] += int(h["killed"])
		out["shield_damage"] += BattleEngine.unpack(int(h["shield_damage"]))
	for target: int in _armor_before:
		out["armor_damage"] += int(_armor_before[target]) - _armor_now(target)
	out["no_damage"] = (
		int(hits[0]["kind"]) & HIT_ABSORBED != 0
		and out["shield_damage"] == 0
		and out["armor_damage"] == 0
	)
	return out


## Integer division truncating toward zero, like the original's C.
static func _tdiv(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if (a < 0) == (b < 0) else -q
