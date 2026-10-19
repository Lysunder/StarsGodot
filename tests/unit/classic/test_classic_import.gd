extends GdUnitTestSuite
## Spec S26, the classic look's import, on a synthetic executable built here (tiny generated
## bitmaps under the resource ids the importer reads, in a valid NE resource table): never the
## original's files. The reader, the import, and the art registry that shows the result.

const DIR := "user://test_classic_install"
const OUT := "user://test_classic_mod"
const SETTINGS := "user://test_classic_settings.cfg"
const MODS := "user://test_classic_mods"
## Resource table alignment: offsets and lengths in 16-byte units.
const SHIFT := 4

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	_content = r.registry


func after_test() -> void:
	for d in [DIR, OUT, MODS]:
		ClassicImporter._remove_tree(d)
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)
	ModSettings.path = UiSettings.PATH
	ModSettings.mods_dir = ModSettings.USER_MODS
	ArtRegistry.reload()


## An 8x8 24-bit packed DIB, all one colour.
static func _dib(colour: Color) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(40)
	b.encode_u32(0, 40)
	b.encode_s32(4, 8)
	b.encode_s32(8, 8)
	b.encode_u16(12, 1)
	b.encode_u16(14, 24)
	for i in 64:
		b.append(colour.b8)
		b.append(colour.g8)
		b.append(colour.r8)
	return b


## A minimal NE executable holding `bitmaps` (id -> DIB) and one named bitmap.
static func _exe(bitmaps: Dictionary) -> PackedByteArray:
	var ids: Array = bitmaps.keys()
	ids.sort()
	var entries := ids.size() + 1
	var table := 0x80
	var names_at := 2 + 8 + entries * 12 + 2
	var name := "TESTBMP"
	var data_at := table + names_at + 1 + name.length()
	data_at = (data_at + (1 << SHIFT) - 1) >> SHIFT << SHIFT
	var b := PackedByteArray()
	b.resize(data_at)
	b[0] = 0x4D
	b[1] = 0x5A
	b.encode_u16(0x3C, 0x40)
	b[0x40] = 0x4E
	b[0x41] = 0x45
	b.encode_u16(0x40 + 0x24, table - 0x40)
	b.encode_u16(table, SHIFT)
	b.encode_u16(table + 2, 0x8000 | NeResources.BITMAP)
	b.encode_u16(table + 4, entries)
	var at := table + 10
	var blobs: Array = []
	for id: int in ids:
		blobs.append([0x8000 | id, bitmaps[id]])
	blobs.append([names_at, _dib(Color.WHITE)])
	for blob: Array in blobs:
		var bytes: PackedByteArray = blob[1]
		var padded := (bytes.size() + (1 << SHIFT) - 1) >> SHIFT << SHIFT
		b.encode_u16(at, b.size() >> SHIFT)
		b.encode_u16(at + 2, padded >> SHIFT)
		b.encode_u16(at + 6, blob[0])
		at += 12
		var start := b.size()
		b.append_array(bytes)
		b.resize(start + padded)
	b[table + names_at] = name.length()
	for i in name.length():
		b[table + names_at + 1 + i] = name.unicode_at(i)
	return b


func _sheet_ids() -> PackedInt32Array:
	var ids: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ClassicImporter.IDS_PATH))
	return ClassicImporter._sheet_ids(ids)


func _install(bitmaps: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR.path_join("STARS26I.EXE"), FileAccess.WRITE)
	f.store_buffer(_exe(bitmaps))
	f.close()


func test_the_reader_finds_numbered_and_named_bitmaps() -> void:
	var exe := NeResources.read(_exe({552: _dib(Color.RED)}))
	assert_bool(exe.ok()).override_failure_message(exe.error).is_true()
	# lengths are stored in alignment units: the bitmap comes back padded
	assert_int(exe.get_resource(NeResources.BITMAP, 552).size()).is_equal(240)
	assert_bool(exe.get_resource(NeResources.BITMAP, "TESTBMP").is_empty()).is_false()
	var image := NeResources.bitmap_image(exe.get_resource(NeResources.BITMAP, 552))
	assert_int(image.get_width()).is_equal(8)
	assert_bool(image.get_pixel(3, 3).is_equal_approx(Color.RED)).is_true()
	assert_bool(NeResources.read(PackedByteArray([1, 2, 3])).ok()).is_false()


func test_an_import_writes_a_cosmetic_mod_the_art_registry_shows() -> void:
	var bitmaps := {}
	for id in _sheet_ids():
		bitmaps[id] = _dib(Color(0.2, 0.4, 0.6))
	_install(bitmaps)
	var r := ClassicImporter.run(DIR, _content, OUT)
	assert_bool(r.ok()).override_failure_message("\n".join(r.errors)).is_true()
	assert_bool(FileAccess.file_exists(OUT.path_join("mod.json"))).is_true()
	var index: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(OUT.path_join("art/index.json"))
	)
	# a scout's first picture: its hull's picture number in the ship sheets
	var n: int = _content.hull("hull.scout")["pictures"]
	(
		assert_array(
			(index["art.hull.scout.0"]["rect"] as Array).map(func(v: float) -> int: return int(v))
		)
		. is_equal([(n / 4) % 8 * 64, n % 4 * 64, 64, 64])
	)
	assert_bool(index.has("art.part.beam.laser")).is_true()
	assert_bool(index.has("art.planet.27")).is_true()
	# the mod loads as a cosmetic mod, and turned on, the registry serves its pictures
	ModSettings.path = SETTINGS
	ModSettings.mods_dir = MODS
	DirAccess.make_dir_recursive_absolute(MODS)
	DirAccess.rename_absolute(OUT, MODS.path_join(ClassicImporter.MOD_ID))
	var loaded := ModLoader.new().load_mods(ModSettings.sources(), ["classic"])
	assert_bool(loaded.ok()).override_failure_message(loaded.error_text()).is_true()
	assert_str(loaded.registry.ruleset_hash).is_equal(_content.ruleset_hash)
	ModSettings.save(PackedStringArray(["classic"]), {})
	ArtRegistry.reload()
	var tex := ArtRegistry.texture("art.hull.scout.0")
	assert_object(tex).is_not_null()
	assert_vector(tex.get_size()).is_equal(Vector2(64, 64))
	assert_object(ArtRegistry.texture("art.no.such")).is_null()


func test_a_copy_without_the_pictures_is_refused() -> void:
	_install({552: _dib(Color.RED)})
	var r := ClassicImporter.run(DIR, _content, OUT)
	assert_bool(r.ok()).is_false()
	assert_str(r.errors[0]).contains("missing pictures")
	assert_bool(FileAccess.file_exists(OUT.path_join("mod.json"))).is_false()
