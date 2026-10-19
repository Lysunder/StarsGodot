extends RefCounted
## Fast Growth: replaces the population growth formula (`economy.pop_growth`) with one that
## doubles every gain the Standard formula gives; losses stay as they are.


func _mod_init(api: ModApi) -> void:
	api.formulas.replace(PlanetEconomy.POP_GROWTH, growth)


## The colonists a year adds (or takes): the Standard change, gains doubled.
func growth(planet: Planet, race: Race, content: ContentRegistry) -> int:
	var change := PlanetEconomy.standard_growth(planet, race, content)
	return change * 2 if change > 0 else change
