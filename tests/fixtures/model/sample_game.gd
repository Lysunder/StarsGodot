extends RefCounted
## A small hand-built game that is valid against the core content: two players, three planets,
## fleets, every kind of space object, and mod data. Load with preload() in tests.

const FLEET_LIMIT := 512
const OBJECT_LIMIT := 512


static func build() -> GameState:
	var state := GameState.new()
	state.turn = 7
	state.rng = RngStreams.new(1234567890, true)
	state.rng.get_stream("classic").random(100)
	state.rng.get_stream("fixes").next_raw()
	state.settings.universe_width = 800
	state.settings.density = "dense"
	state.settings.slow_tech = true
	state.settings.mods = [{"id": "core", "version": "0.1.0"}]
	for i in 2:
		state.players.append(_player(i))
	for i in 3:
		state.planets.append(_planet(i))
	var f := state.add_fleet(1, FLEET_LIMIT)
	f.add_ships(3, 2)
	f.x = 1010
	f.y = 1100
	f.planet = 1
	f.cargo[Fleet.CARGO_FUEL] = 50
	f.waypoints.append(Waypoint.new(1010, 1100))
	var wp := Waypoint.new(1020, 1100)
	wp.target = "planet"
	wp.target_id = 2
	wp.warp = 5
	f.waypoints.append(wp)
	var g := state.add_fleet(0, FLEET_LIMIT)
	g.add_ships(3, 1)
	g.x = 1000
	g.y = 1100
	var chase := Waypoint.new(1000, 1100)
	g.waypoints.append(chase)
	var follow := Waypoint.new(1010, 1100)
	follow.target = "fleet"
	follow.target_owner = 1
	follow.target_id = 0
	follow.warp = 6
	g.waypoints.append(follow)
	var field := state.add_minefield(0, OBJECT_LIMIT)
	field.x = 1200
	field.y = 1200
	field.mines = 2500
	field.seen_by.assign([0, 1])
	state.add_packet(1, true, OBJECT_LIMIT).minerals.assign([5, 0, 7])
	state.add_wormhole(OBJECT_LIMIT).other_end = 1
	state.add_wormhole(OBJECT_LIMIT).other_end = 0
	state.mod_data = {"extra_hulls": {"b": 2, "a": [1, "x", true, null]}}
	return state


static func _player(i: int) -> Player:
	var p := Player.new()
	p.index = i
	p.race.name = "Race %d" % i
	p.race.plural_name = "Races %d" % i
	p.race.primary_trait = "trait.prt.JoaT"
	p.race.lesser_traits.assign(["trait.lrt.IFE", "trait.lrt.RS"])
	if i == 1:
		p.race.hab_low.assign([-1, 20, 15])
		p.race.hab_center.assign([-1, 50, 40])
		p.race.hab_high.assign([-1, 80, 65])
	p.relations.assign(["neutral", "enemy"] if i == 0 else ["enemy", "neutral"])
	p.homeworld = i
	p.tech_levels.assign([3, 3, 3, 3, 3, 3])
	var d := Design.new()
	d.slot = 3
	d.name = "Scout"
	d.hull = "hull.scout"
	d.picture = 17
	var parts: Array[DesignSlot] = [
		DesignSlot.new("part.engine.quick_jump_5", 1),
		DesignSlot.new("part.scanner.bat_scanner", 1),
		DesignSlot.new(),
	]
	d.parts = parts
	p.set_design(d, false)
	var base := Design.new()
	base.slot = 0
	base.name = "Station"
	base.hull = "hull.space_station"
	base.picture = 136
	for n in 12:
		base.parts.append(DesignSlot.new())
	p.set_design(base, true)
	return p


static func _planet(i: int) -> Planet:
	var pl := Planet.new()
	pl.id = i
	pl.name = "Planet %d" % i
	pl.x = 1000 + 10 * i
	pl.y = 1100
	pl.owner = i if i < 2 else -1
	pl.population = 250 * (i + 1) if i < 2 else 0
	pl.surface.assign([100, 200, 300])
	pl.concentration.assign([40, 60, 80])
	if i < 2:
		pl.starbase = Starbase.new()
		pl.homeworld = true
		pl.mines = 10
		pl.factories = 10
	return pl
