extends GdUnitTestSuite
## Pictures from mods (ArtRegistry; spec S26 "Mod hooks") where the interface shows them: ship and
## planet pictures in the tiles, part pictures in the designer, race logos by player names; and what
## the map shows besides planets and the player's fleets (MapObjects). The art mod here is made by
## the test from solid colours.

const SETTINGS := "user://test_art_settings.cfg"
const MODS := "user://test_art_mods"


func before_test() -> void:
	ModSettings.path = SETTINGS
	ModSettings.mods_dir = MODS
	var dir := MODS.path_join("test_art")
	DirAccess.make_dir_recursive_absolute(dir.path_join("art"))
	var f := FileAccess.open(dir.path_join("mod.json"), FileAccess.WRITE)
	var manifest := {
		"id": "test_art",
		"name": "Test Art",
		"version": "1.0.0",
		"api_version": 1,
		"kind": "cosmetic"
	}
	f.store_string(JSON.stringify(manifest))
	f.close()
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.ORANGE)
	image.save_png(dir.path_join("art/solid.png"))
	var index := {}
	for hull_id in GameSession.content.ids("hull"):
		for k in 4:
			index["art.%s.%d" % [hull_id, k]] = {"file": "solid.png"}
	for p in 28:
		index["art.planet.%d" % p] = {"file": "solid.png", "rect": [0, 0, 32, 32]}
	for logo in 32:
		index["art.race_logo.%d.small" % logo] = {"file": "solid.png", "rect": [0, 0, 16, 16]}
	index["art.part.beam.laser"] = {"file": "solid.png"}
	for object_id in ["minefield.0", "minefield.1", "minefield.2", "packet", "salvage", "wormhole"]:
		index["art.object." + object_id] = {"file": "solid.png", "rect": [0, 0, 16, 16]}
	index["art.title"] = {"file": "solid.png"}
	f = FileAccess.open(dir.path_join("art/index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(index))
	f.close()
	ModSettings.save(PackedStringArray(["test_art"]), {})
	GameSession.reload_content()


func after_test() -> void:
	ClassicImporter._remove_tree(MODS)
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)
	ModSettings.path = UiSettings.PATH
	ModSettings.mods_dir = ModSettings.USER_MODS
	GameSession.reload_content()


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 12
	options.opponents = [{"ai": "turindrones", "level": 1, "personality": {}}]
	GameSession.new_game(options)


func test_tiles_and_the_designer_show_mod_pictures() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var home := GameSession.view.me().homeworld
	screen._command.command("planet", home)
	screen._command._rebuild()
	var icons := screen._command.find_children("*", "FleetIcon", true, false)
	assert_bool(icons.is_empty()).is_false()
	var planet_icon: FleetIcon = icons[0]
	assert_str(planet_icon.art_id).is_equal(ArtRegistry.planet_id(home))
	assert_vector(ArtRegistry.texture(planet_icon.art_id).get_size()).is_equal(Vector2(32, 32))
	var fleet := GameSession.view.fleets()[0]
	screen._command.command("fleet", fleet.number)
	screen._command._rebuild()
	var fleet_icon: FleetIcon = screen._command.find_children("*", "FleetIcon", true, false)[0]
	assert_str(fleet_icon.art_id).starts_with("art.hull.")
	assert_object(ArtRegistry.texture(fleet_icon.art_id)).is_not_null()
	# the designer shows a part's picture once picked
	var designer := screen._designer
	designer.open()
	var at := designer._part_ids.find("part.beam.laser")
	if at >= 0:
		designer._on_part_picked(at)
		assert_bool(designer._part_picture.visible).is_true()
	designer.hide()
	# the relations list puts logos by names
	screen._relations.open()
	assert_object(screen._relations._list.get_item_icon(0)).is_not_null()
	screen._relations.hide()
	screen.queue_free()
	await get_tree().process_frame


func test_without_a_picture_the_game_draws_its_own() -> void:
	assert_object(ArtRegistry.texture("art.part.beam.phaser_bazooka")).is_null()
	assert_object(ArtRegistry.texture("")).is_null()


func test_the_map_shows_minefields_packets_and_rivals() -> void:
	var path := "res://tests/fixtures/golden/mine1/t040.json"
	var s := SaveFile.decode(FileAccess.get_file_as_string(path), GameSession.content).state
	var view := PlayerView.new(s, GameSession.content, 0)
	var fields := MapObjects.minefields(view)
	for m in fields:
		assert_bool(m.owner == 0 or m.known_by.has(0)).is_true()
	assert_int(fields.size()).is_greater(0)
	for f in MapObjects.seen_fleets(view):
		assert_int(f.owner).is_not_equal(0)
	for k in MapObjects.packets(view):
		(
			assert_bool(
				k.owner == 0 or (s.views[0]["packets"] as Array).has("%d/%d" % [k.owner, k.number])
			)
			. is_true()
		)


## Minefields and the other map objects can be selected; the summary shows their picture, and the
## main menu the title picture.
func test_map_objects_are_selectable_with_their_pictures() -> void:
	var path := "res://tests/fixtures/golden/mine1/t040.json"
	GameSession._start(
		SaveFile.decode(FileAccess.get_file_as_string(path), GameSession.content).state
	)
	var view := GameSession.view
	var field: Minefield = MapObjects.minefields(view)[0]
	var key := MapObjects.object_key(field)
	var hits := view.objects_at(field.x, field.y, 1.0)
	assert_bool(hits.has({"kind": "minefield", "id": key})).is_true()
	var here := view.objects_here(field.x, field.y, 1.0).filter(
		func(o: Dictionary) -> bool: return o["kind"] == "minefield"
	)
	assert_bool(here.is_empty()).is_false()
	assert_str(here[0]["name"]).contains("Minefield")
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen._map.select("minefield", key)
	var summary := screen._summary
	assert_str(summary._title.text).contains("Minefield")
	assert_str(summary._icon.art_id).is_equal(ArtRegistry.object_id("minefield", field))
	assert_object(ArtRegistry.texture(summary._icon.art_id)).is_not_null()
	screen._map.queue_redraw()
	await get_tree().process_frame
	screen.queue_free()
	var menu := MainMenu.new()
	add_child(menu)
	assert_object(menu._title_art.texture).is_not_null()
	menu.queue_free()
	await get_tree().process_frame
