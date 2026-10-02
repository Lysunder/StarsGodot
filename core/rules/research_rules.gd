class_name ResearchRules
extends RefCounted
## Research costs and the yearly tech update (spec S05).
##
## Trait parameters: `research.current_field_pct` / `research.other_field_pct` (Generalized
## Research: 50 / 15; without them the current field gets everything) and `research.spy_pct`
## (Super-Stealth: 50, the share of the average points of all players).

const EXPENSIVE := 0
const CHEAP := 2
const FIELDS := 6


## Research points needed to raise `field` by one level (S05 "Cost of the next level").
static func level_cost(player: Player, field: int, content: ContentRegistry, slow: bool) -> int:
	var total := 0
	for level in player.tech_levels:
		total += level
	var next_level := player.tech_levels[field] + 1
	var c := (
		content.constant("constant.research.base_cost_%d" % next_level)
		+ content.constant("constant.research.cost_per_level_sum") * total
	)
	match player.race.research_costs[field]:
		EXPENSIVE:
			c = 2 * c - c / 4
		CHEAP:
			c = c / 2
	return 2 * c if slow else c


## The tech update (S05 "Points each year", "Gaining levels", "Super-Stealth spying").
## `spent`: each player's research resources this year (production), or empty for an update
## without new points (after tech trading).
static func update(state: GameState, content: ContentRegistry, spent: Array[int]) -> void:
	var slow := state.settings.slow_tech
	var spending := not spent.is_empty()
	var added: Array[int] = []
	added.resize(FIELDS)
	var active := 0
	for p in state.players:
		if p.active:
			active += 1
		_update_player(p, content, slow, spent[p.index] if spending else -1, added)
	if not spending or active < 2:
		return
	var spied := false
	for p in state.players:
		var pct := RaceMath.trait_param(p.race, content, "research.spy_pct", 0)
		if pct == 0:
			continue
		for f in FIELDS:
			if added[f] <= 0:
				continue
			var bonus := added[f] / active * pct / 100
			if bonus > 1:
				spied = true
				p.research_points[f] += (bonus + 1) / 2 if slow else bonus
	if spied:
		update(state, content, [])


## One player's update; `spent` < 0 means no new points. Adds the points this player put into
## each field to `added` (for spying).
static func _update_player(
	p: Player, content: ContentRegistry, slow: bool, spent: int, added: Array[int]
) -> void:
	var max_level := content.constant("constant.research.max_level")
	var current_pct := RaceMath.trait_param(p.race, content, "research.current_field_pct", 100)
	var other_pct := RaceMath.trait_param(p.race, content, "research.other_field_pct", 0)
	var split := current_pct != 100 or other_pct != 0
	var spending := spent >= 0
	var split_done := false
	var current := p.research_field
	var next := p.next_research_field
	while true:
		var again := false
		for i in FIELDS:
			var e := p.research_points[i] * (2 if slow else 1)
			if i == current and spending and not split_done:
				if not split:
					e += spent
					added[i] += spent
				else:
					split_done = true
					again = true
					var share := _share(spent, current_pct)
					e += share
					added[i] += share
					for j in FIELDS:
						if j != i:
							var v := _share(spent, other_pct)
							p.research_points[j] += v / 2 if slow else v
							added[j] += v
			var switched := false
			while true:
				# A field at the top level keeps its stored points; this year's are dropped (S05).
				if p.tech_levels[i] >= max_level:
					break
				var cost := level_cost(p, i, content, slow)
				if e < cost:
					p.research_points[i] = (e + 1) / 2 if slow else e
					break
				e -= cost
				p.tech_levels[i] += 1
				if p.tech_levels[i] == max_level and next == Player.NEXT_FIELD_SAME:
					next = Player.NEXT_FIELD_LOWEST
				if i == current and next != Player.NEXT_FIELD_SAME:
					switched = true
					break
			if switched:
				var target := _lowest_field(p) if next == Player.NEXT_FIELD_LOWEST else next
				if next != Player.NEXT_FIELD_LOWEST:
					next = Player.NEXT_FIELD_SAME
				current = target
				p.research_points[i] = 0
				p.research_points[target] += (e + 1) / 2 if slow else e
				spending = false
				again = true
		if not again:
			break
	p.research_field = current
	p.next_research_field = next


## pct percent of `spent`, rounded up.
static func _share(spent: int, pct: int) -> int:
	return (spent * pct + 99) / 100


## The field with the lowest level (the first one on ties).
static func _lowest_field(p: Player) -> int:
	var best := 0
	for f in range(1, FIELDS):
		if p.tech_levels[f] < p.tech_levels[best]:
			best = f
	return best
