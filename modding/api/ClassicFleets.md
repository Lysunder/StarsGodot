# ClassicFleets

`core/ai/classic/classic_fleets.gd`, extends `RefCounted`

How the classic personalities move their fleets (spec S22 "Classic fleets"): what a fleet is,
new orders (`AI_AddWaypoint` and its callers), merging and splitting, safe speeds in
minefields, warships' targets (`AI_DirectWarship`) and colony ships' (`AI_RateColonyTargets`).

## Constants

- `const COMBAT := "ai_hull_class.combat"`
- `const ESCORT := "ai_hull_class.escort"`
- `const MULTIROLE := "ai_hull_class.multirole"`
- `const FREIGHTER := "ai_hull_class.freighter"`
- `const CARGO_MORPH := "ai_hull_class.cargo_morph"`
- `const COLONY := "ai_hull_class.colony"`
- `const CARGO_SHIP_ROOM := 500`: Cargo room (kT) that makes a multirole ship a freighter.
- `const WARP_HOME := 4`: Speeds the toolkit's orders go at (the minefield pass sets most fleets' speeds afterwards).
- `const WARP_JOIN := 6`
- `const DESIGN_SLOTS := 16`
- `const MERGE_LIST := 32`: AI_MergeFleetsByHull keeps at most this many fleets to merge into per pass.
- `const SPLIT_LIMIT := 501`: No fleet is split once the player has this many.
- `const CHASE_RANGE2 := 32400`: A warship's prey within this distance squared is chased; beyond it, planets.
- `const MINE_WARP_HEAVY := 6`: Minefield safe speeds (`AI_SetMinefieldSafeWarp`).
- `const MINE_WARP_STANDARD := 4`
- `const MINE_WARP_SPEED_BUMP := 5`
- `const WORMHOLE_TURN := 120`: Colony ships look through wormholes only before this turn.
- `const NEAR_START := 10000000`
- `const UNSEEN := 0x10`: Planet_info byte 15 for a planet the player's turn file doesn't hold (not Robotoids or Macinti).
- `const WARSHIP := "ai_hull_class.warship"`: Hull class of `AI_HasWarshipHull` (scout to dreadnought).
- `const INFO_TARGET := 10`: planet_info byte rating a planet as a target (`AI_ScoreColonyTarget`), and its "a warship heads there" bit.
- `const HEADED := 0x80`
- `const WORMHOLE_PCT := 5`: `AI_ChooseColonyTarget` looks for a wormhole on a draw of this many in 100.
- `const UNCLAIMED_TURN := 60`: AI_HasNearbyUnclaimedPlanet's turn and distances (light years).
- `const UNCLAIMED_NEAR := 250`
- `const UNCLAIMED_MID := 300`
- `const UNCLAIMED_FAR := 350`
- `const STARTER_ENGINE := "ai_starter_engine"`: Engines that make a stranded colony ship not worth bringing home (Turindrones).
- `const WARSHIP_START := 1000000`

## Functions

### `hulls_of()`

```gdscript
static func hulls_of(w: ClassicWorld, class_id: String) -> Array
```

### `stacks_of()`

```gdscript
static func stacks_of(fleet: Fleet) -> Array[ShipStack]
```

The fleet's ships by design slot (count > 0), slot order.

### `ships()`

```gdscript
static func ships(fleet: Fleet) -> int
```

### `has_slot()`

```gdscript
static func has_slot(fleet: Fleet, slot: int) -> bool
```

### `is_combat()`

```gdscript
static func is_combat(w: ClassicWorld, fleet: Fleet) -> bool
```

`AI_IsCombatFleet`, design slots in order: warship hulls make a combat fleet; the first escort
hull decides by its rating (above 0); a multirole hull with less than CARGO_SHIP_ROOM of cargo
and a rating counts.

### `is_freighter()`

```gdscript
static func is_freighter(w: ClassicWorld, fleet: Fleet) -> bool
```

`AI_IsFreighterFleet`: a freighter hull, or a cargo morph with CARGO_SHIP_ROOM of cargo and a
rating.

### `planet_waypoint()`

```gdscript
static func planet_waypoint(w: ClassicWorld, id: int, warp: int, task: String = "none") -> Waypoint
```

### `empty_task_data()`

```gdscript
static func empty_task_data(task: String) -> Dictionary
```

The task data an order carries for `task` when nothing is set: none without a task, five zero
words for the tasks other than transport (as the original stores its waypoints).

### `fleet_waypoint()`

```gdscript
static func fleet_waypoint(target: Fleet, warp: int) -> Waypoint
```

### `go()`

```gdscript
static func go(w: ClassicWorld, fleet: Fleet, wp: Waypoint) -> bool
```

New orders (`AI_AddWaypoint`): a waypoint where the fleet is replaces its orders; elsewhere it
follows the fleet's current place. Given as waypoint orders; false when refused.

### `stop()`

```gdscript
static func stop(w: ClassicWorld, fleet: Fleet) -> void
```

Drops the fleet's waypoints beyond where it is (the original's waypoint count set to 1).

### `change()`

```gdscript
static func change(w: ClassicWorld, fleet: Fleet, index: int, wp: Waypoint) -> void
```

Changes the fleet's waypoint `index` (given as an order).

### `clear_task()`

```gdscript
static func clear_task(w: ClassicWorld, fleet: Fleet) -> void
```

`AI_ClearTask`: no task at the fleet's current place.

### `set_task()`

```gdscript
static func set_task(w: ClassicWorld, fleet: Fleet, task: String, data: Dictionary = {}) -> void
```

Gives waypoint 0 a task (the original's in-place edit of the current waypoint), and with
`data` its task data (else the data stays).

### `send_to_colonize()`

```gdscript
static func send_to_colonize(w: ClassicWorld, fleet: Fleet, planet_id: int) -> bool
```

`AI_SendToPlanet`: to colonize a planet at the fleet's top speed (no easing).

### `send_to_wormhole()`

```gdscript
static func send_to_wormhole(w: ClassicWorld, fleet: Fleet, hole: Wormhole) -> bool
```

`AI_SendToPoint`: into a wormhole at the fleet's top speed (no easing).

### `nearest_home()`

```gdscript
static func nearest_home(w: ClassicWorld, fleet: Fleet, peopled: bool) -> int
```

`AI_NearestHomePlanet`: the nearest of the player's planets with a starbase (with more than
250 hundred people when `peopled`) to where the fleet is; -1 for none.

### `return_home()`

```gdscript
static func return_home(w: ClassicWorld, fleet: Fleet, peopled: bool) -> bool
```

`AI_ReturnHome`: to the nearest home planet at WARP_HOME; false when there is none.

### `send_to_nearest_enemy()`

```gdscript
static func send_to_nearest_enemy(w: ClassicWorld, fleet: Fleet, reach: int) -> void
```

`AI_SendToNearestObject`: to the nearest planet of another player within `reach` at
WARP_HOME, unless the fleet is there.

### `d2()`

```gdscript
static func d2(x1: int, y1: int, x2: int, y2: int) -> int
```

### `nearest_planet()`

```gdscript
static func nearest_planet(w: ClassicWorld, from_id: int, accept: Callable) -> Planet
```

`AI_FindNearestPlanet`: the nearest planet to planet `from_id` that `accept` takes (asked only
of planets nearer than the best so far); null for none.

### `has_nearby_unclaimed()`

```gdscript
static func has_nearby_unclaimed(w: ClassicWorld, planet: Planet) -> bool
```

`AI_HasNearbyUnclaimedPlanet`: before turn UNCLAIMED_TURN always; later by the distance from
`planet` to the nearest planet planet_info byte 13 leaves clear: within UNCLAIMED_NEAR light
years yes, beyond UNCLAIMED_FAR no, between on draws of 1 in 2 (one past UNCLAIMED_MID, another
past UNCLAIMED_NEAR).

### `best_planet()`

```gdscript
static func best_planet(w: ClassicWorld, from_id: int, score: Callable) -> Planet
```

`AI_FindNearestPlanet2`: the planet `score` rates highest (every planet is rated, in order;
at least 1), the nearer of equals; null for none.

### `nearest_fleet()`

```gdscript
static func nearest_fleet(w: ClassicWorld, from: Fleet, accept: Callable) -> Fleet
```

`AI_FindNearestFleet`: the nearest fleet (in fleet order) that `accept` takes (asked only of
fleets nearer than the best so far); null for none.

### `random_planet()`

```gdscript
static func random_planet(w: ClassicWorld, x: int, y: int, reach: int, avoid_starbases: bool) -> int
```

`AI_PickRandomTarget`: one of the planets within `reach` of (x, y), each as likely (one draw
per planet in reach); with `avoid_starbases` drawn again up to twice while the pick has a
starbase. -1 for none.

### `join_nearest()`

```gdscript
static func join_nearest(w: ClassicWorld, fleet: Fleet, low: int, high: int, near: int, far: int) -> bool
```

`AI_Explore`: the nearest of the player's fleets before this one (fleet order) with ships in
slots `low`..`high`; when within `near` (or `far`, on a draw of 1 in 2) the fleet clears its
task and joins it at WARP_JOIN. False when it does not.

### `merge_by_slots()`

```gdscript
static func merge_by_slots(w: ClassicWorld, slots: Array) -> void
```

`AI_MergeFleetsByHull`: the player's fleets with ships in the design slots of `slots` merge
with the first such fleet at the same place, in fleet order (all its ships move over as a ship
move, S11, so cargo and damage follow as for one); up to MERGE_LIST fleets are kept
to merge into, then another pass starts where the list ran out. A merged fleet leaves the
fleet list, so the fleet after it is passed over.

### `split_slots()`

```gdscript
static func split_slots(w: ClassicWorld, slots: Array) -> void
```

`AI_SplitFleets`: while the player has fewer than SPLIT_LIMIT fleets, the first fleet (fleet
order) with ships both in the slots of `slots` and in others splits them off into a new fleet
(cargo and fuel following the ships, S11).

### `avoid_minefields()`

```gdscript
static func avoid_minefields(w: ClassicWorld) -> void
```

`AI_AvoidMinefieldsAll`: every fleet of the player with somewhere to go gets its next speed:
inside a known minefield of another player (not a speed bump), heavy fields MINE_WARP_HEAVY,
standard MINE_WARP_STANDARD or on a draw (6 in 10) MINE_WARP_SPEED_BUMP, one more with
`minefield.speed_bonus`; elsewhere the default warp (WaypointWarp, as a computer player).

### `direct_warship()`

```gdscript
static func direct_warship(w: ClassicWorld, fleet: Fleet, own: Array[Fleet], enemies: Array[Fleet], spare_computers: bool) -> int
```

`AI_DirectWarship`: a warship's target. Among `enemies` (other players' fleets, in the order
given; with `spare_computers` not computer players') the nearest one is chosen, passing over
(on a draw of 1 in 3) one that `own` fleets already chase, and (on a draw of 14 in 15) keeping
one they chase with more than a fifth of this fleet's ships. Within CHASE_RANGE2 the fleet
chases it. With none at all and `spare_computers`, computer players' fleets count after all.
Otherwise, low on fuel (under half) it goes home; failing that, to the planet nearest the prey
that none of `own` heads for; failing that, the nearest planet of another player; failing
that, the nearest planet planet_info byte 9 does not mark (any planet, drawn, if none). A fleet
already heading for a planet keeps going (-1); otherwise the new orders go at WARP_HOME
(0, or -1 when refused).

### `colony_target()`

```gdscript
static func colony_target(w: ClassicWorld, fleet: Fleet, wormholes := true) -> Dictionary
```

`AI_RateColonyTargets`: the nearest planet free to settle, and for a fleet at one of the
player's planets before WORMHOLE_TURN perhaps a wormhole instead (`pick_wormhole`). Planet_info
byte 15 marks each planet: 0 free (Robotoids and Macinti: any unowned planet; others: unowned
planets they could make habitable, else 8), 1 the player's, 2 another's, 4 claimed by another
of the player's fleets heading there (Robotoids and Macinti: to colonize); the others mark the
planets their turn file doesn't hold UNSEEN. Returns
{planet: id or -1, wormhole: Wormhole or null}; with a wormhole the planet is -1. Without
`wormholes` none is looked for (the original's call without a wormhole to fill in).

### `terraformed_hab()`

```gdscript
static func terraformed_hab(w: ClassicWorld, p: Planet) -> int
```

A planet's habitability once the player terraforms it as far as it can toward its ideal
(`Planet_HabValueTerraformed`).

### `info_set()`

```gdscript
static func info_set(w: ClassicWorld, planet_id: int, byte: int, value: int) -> void
```

### `pick_wormhole()`

```gdscript
static func pick_wormhole(w: ClassicWorld, x: int, y: int, planet_d2: int) -> Wormhole
```

`AI_PickWeighted`: a wormhole worth trying from (x, y), when the nearest free planet is
`planet_d2` away: wormholes within twice that distance (the original squares the distance in 16
bits, so a wormhole whose square wraps past 32767 is always in reach), scored 50 (unseen,
farther than the planet), 90 (unseen, nearer) or 70 less 10 per percent of jump chance (seen);
the best (the nearer of equals) is taken when a draw of 100 falls under its score.

### `has_warship_hull()`

```gdscript
static func has_warship_hull(w: ClassicWorld, fleet: Fleet) -> bool
```

`AI_HasWarshipHull`: ships on a hull of WARSHIP (scout to dreadnought).

### `is_armed()`

```gdscript
static func is_armed(w: ClassicWorld, fleet: Fleet) -> bool
```

`Fleet_HasArmedShips`: ships of an armed design (S16 `Design_IsArmed`).

### `go_after()`

```gdscript
static func go_after(w: ClassicWorld, fleet: Fleet, wp: Waypoint) -> bool
```

`AI_AddWaypoint` appending: the waypoint follows the fleet's last one, or takes its place when
it is there. False when refused.

### `target_score()`

```gdscript
static func target_score(w: ClassicWorld, from: Planet, p: Planet, spare_computers: bool) -> int
```

`AI_ScoreColonyTarget` (`spare_computers`) and `AI_ScoreColonyTarget2`: planet_info byte
INFO_TARGET of `p` (0 for `from` itself, and with `spare_computers` for computer players'
planets), more when near `from`; one marked HEADED counts only on a draw of 1 in 4.

### `choose_colony_target()`

```gdscript
static func choose_colony_target(w: ClassicWorld, fleet: Fleet, wormholes: bool) -> Dictionary
```

`AI_ChooseColonyTarget`: the nearest planet marked UNSEEN (rating the colony targets first
when that wasn't done this turn, without wormholes); with `wormholes`, a fleet at a planet
looks for a wormhole on a draw of WORMHOLE_PCT in 100 (`pick_wormhole`), which replaces the
planet. Returns {planet: id or -1, wormhole: Wormhole or null}.

### `direct_fleet()`

```gdscript
static func direct_fleet(w: ClassicWorld, fleet: Fleet, own: Array[Fleet], enemies: Array[Fleet], spare_computers: bool, wormholes: bool) -> int
```

`AI_DirectFleet` (Turindrones, Automitrons, Rototills): an armed fleet hunts the nearest of
`enemies` (with `spare_computers` not computer players' fleets; one that `own` fleets already
chase is passed over on a draw of 1 in 3) within CHASE_RANGE2; farther off, low on fuel (under
half) it goes home, else to the planet nearest the prey that none of `own` heads for; with no
prey at all and `spare_computers`, computer players' fleets count after all. Otherwise, and
for an unarmed fleet, it explores (`choose_colony_target`), failing that goes to the planet
`AI_ScoreColonyTarget2` rates best from the homeworld, else to any planet, drawn. A fleet
already heading for a planet keeps going (-1); a planet chosen is marked claimed (planet_info
byte 15 = 4); the orders go at the fleet's top warp, no easing (0, or -1 when refused).

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/ai/classic/classic_fleets.gd`.*
