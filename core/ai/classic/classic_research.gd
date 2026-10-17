class_name ClassicResearch
extends RefCounted
## How the classic personalities choose research (spec S22 "Classic research",
## `AI_RunResearchPlan`): a plan of steps (a tech field and a level), followed in order.

const MAX_LEVEL := 24


## Sets the research budget to `percent` and works through `plan_id`'s steps (none for "");
## returns the index of the step being researched, or -1 when every step is done. The research
## field is that step's, and when the step is one level away the next field is the next step's.
## With every step done the lowest field is researched (the first of equals). The budget reaches
## the host only with a field change (the original sends nothing else), and is 0 once every field
## is at MAX_LEVEL.
static func follow_plan(w: ClassicWorld, plan_id: String, percent: int) -> int:
	var p := w.me()
	p.research_percent = percent
	if p.tech_levels.all(func(level: int) -> bool: return level >= MAX_LEVEL):
		p.research_percent = 0
		_send(w)
	var order := PartRules.tech_order(w.content)
	var steps: Array = []
	if not plan_id.is_empty():
		steps = w.content.get_def("ai_research_plan", plan_id)["steps"]
	for i in steps.size():
		var field: int = order[steps[i]["field"]]
		var level: int = steps[i]["level"]
		var have := p.tech_levels[field]
		if have >= level:
			continue
		p.research_field = field
		if i < steps.size() - 1 and level - have == 1:
			p.next_research_field = order[steps[i + 1]["field"]]
		_send(w)
		return i
	var lowest := 0
	for f in range(1, p.tech_levels.size()):
		if p.tech_levels[f] < p.tech_levels[lowest]:
			lowest = f
	if p.research_field != lowest:
		p.research_field = lowest
		_send(w)
	return -1


static func _send(w: ClassicWorld) -> void:
	var p := w.me()
	(
		w
		. order(
			{
				"type": "research",
				"percent": p.research_percent,
				"field": p.research_field,
				"next": p.next_research_field,
			}
		)
	)
