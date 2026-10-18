extends GdUnitTestSuite
## Copies hold every saved field (S03): each class's schema is filled with values unlike the
## defaults, nested objects too, and the copy must equal the original and share nothing with it.
## Planets, fleets, waypoints and ship stacks copy field by field by hand (the hot path), so a
## field added to their schema but not to their copy fails here.

var _classes: Array = [Planet, Fleet, Waypoint, ShipStack, Player, Design, Minefield, Packet]


func test_copies_hold_every_field() -> void:
	for script: GDScript in _classes:
		var original: ModelObject = script.new()
		_fill(original, 0)
		var copy := original.copy()
		(
			assert_bool(copy.equals(original))
			. override_failure_message("%s: the copy differs" % script.resource_path)
			. is_true()
		)
		assert_dict(copy.to_dict()).is_equal(original.to_dict())


func test_copies_share_nothing() -> void:
	var fleet := Fleet.new()
	_fill(fleet, 0)
	var copy := fleet.copy() as Fleet
	fleet.waypoints[0].task_data["k"].append(99)
	fleet.stacks[0].paid.append(5)
	fleet.cargo[0] += 1
	assert_bool(copy.equals(fleet)).is_false()
	var planet := Planet.new()
	_fill(planet, 0)
	var p2 := planet.copy() as Planet
	planet.queue[0].count += 1
	planet.surface[1] += 1
	assert_bool(p2.equals(planet)).is_false()


## Every schema field set to something unlike a new object's (by kind), nested objects filled
## alike, a few levels deep.
func _fill(o: ModelObject, depth: int) -> void:
	var fields: Array = o._schema()
	for i in fields.size():
		var field: Array = fields[i]
		var name: String = field[0]
		match field[1]:
			ModelObject.Kind.INT:
				o.set(name, 11 + i + depth * 100)
			ModelObject.Kind.BOOL:
				o.set(name, not o.get(name))
			ModelObject.Kind.STRING:
				o.set(name, "v%d_%d" % [depth, i])
			ModelObject.Kind.ENUM:
				o.set(name, (field[2] as Array)[-1])
			ModelObject.Kind.INT_LIST:
				var n := maxi((o.get(name) as Array).size(), 3)
				var values := []
				for k in n:
					values.append(i + k + 1)
				(o.get(name) as Array).assign(values)
			ModelObject.Kind.STRING_LIST:
				(o.get(name) as Array).assign(["a%d" % i, "b%d" % i])
			ModelObject.Kind.OBJECT, ModelObject.Kind.OBJECT_OR_NULL:
				if depth < 3:
					var child: ModelObject = (field[2] as GDScript).new()
					_fill(child, depth + 1)
					o.set(name, child)
			ModelObject.Kind.OBJECT_LIST:
				if depth < 3:
					var child: ModelObject = (field[2] as GDScript).new()
					_fill(child, depth + 1)
					(o.get(name) as Array).assign([child])
			ModelObject.Kind.JSON:
				o.set(name, {"k": [i, "x%d" % depth]})
