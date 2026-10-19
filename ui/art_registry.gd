class_name ArtRegistry
extends RefCounted
## Pictures by art id (MODDING.md §10; spec S26 "Mod hooks"): any mod turned on may supply them in
## `art/index.json` (art id -> {"file": path in its art folder, "rect": [x, y, w, h], optional}),
## later mods winning, as the classic look's import does. A hook asks for an id and draws our own
## placeholder when there is none. PNGs load at run time from the mod's folder, so no import step
## is needed and it works in exported games.

const INDEX := "art/index.json"
const ART_DIR := "art"

## art id -> [mod folder, entry]; the textures made so far; the sheets loaded (path -> texture).
static var _index := {}
static var _textures := {}
static var _sheets := {}
static var _built := false


## Forgets everything: the next lookup reads the mods turned on again.
static func reload() -> void:
	_index.clear()
	_textures.clear()
	_sheets.clear()
	_built = false


## The picture for `id`, or null when no mod turned on supplies one.
static func texture(id: String) -> Texture2D:
	if id.is_empty():
		return null
	if not _built:
		_build()
	if _textures.has(id):
		return _textures[id]
	var tex: Texture2D = null
	if _index.has(id):
		tex = _make(_index[id][0], _index[id][1])
	_textures[id] = tex
	return tex


## The art id of a ship design's picture: `art.<hull id>.<k>`, k the picture among the hull's four.
static func ship_id(design: Design, content: ContentRegistry, small := false) -> String:
	if design == null or not content.has_def(design.hull):
		return ""
	var base := int(content.hull(design.hull).get("pictures", design.picture))
	var k := clampi(design.picture - base, 0, 3)
	return "art.%s.%d%s" % [design.hull, k, ".small" if small else ""]


## The art id of a planet's picture (S26: picture (planet number + 8) mod 28).
static func planet_id(planet_id_number: int) -> String:
	return "art.planet.%d" % ((planet_id_number + 8) % 28)


static func _build() -> void:
	_built = true
	var on := ModSettings.enabled()
	var roots := {}
	for source in ModSettings.sources():
		var m := ModManifest.from_json(source.read_text(ModManifest.FILE), source.root())
		if m.errors.is_empty():
			roots[m.id] = source.root()
	for id in on:
		if not roots.has(id):
			continue
		var text := FileAccess.get_file_as_string(str(roots[id]).path_join(INDEX))
		var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if not data is Dictionary:
			continue
		for art_id: String in data:
			if data[art_id] is Dictionary:
				_index[art_id] = [roots[id], data[art_id]]


static func _make(root: String, entry: Dictionary) -> Texture2D:
	var path := root.path_join(ART_DIR).path_join(str(entry.get("file", "")))
	if not _sheets.has(path):
		var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		_sheets[path] = ImageTexture.create_from_image(image) if image != null else null
	var sheet: Texture2D = _sheets[path]
	if sheet == null or not entry.has("rect"):
		return sheet
	var r: Array = entry["rect"]
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(r[0], r[1], r[2], r[3])
	return atlas
