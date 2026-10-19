class_name ModSettings
extends RefCounted
## The player's mod choices (plan M14), kept with the interface settings in `user://settings.cfg`
## under [mods]: the mods turned on, in the player's order ("enabled"), and the script mods the
## player trusts, each with the hash of the scripts trusted ("trusted", ModLoader.script_hash).
## Mods are found in `res://content` (the base game) and `user://mods` (the player's).

const SECTION := "mods"
const USER_MODS := "user://mods"
const BASE_MODS := "res://content"

## The settings file and the player's mods folder (tests point them elsewhere).
static var path := UiSettings.PATH
static var mods_dir := USER_MODS


static func _config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg


static func enabled() -> PackedStringArray:
	return PackedStringArray(_config().get_value(SECTION, "enabled", []))


static func trusted() -> Dictionary:
	var value: Variant = _config().get_value(SECTION, "trusted", {})
	return value if value is Dictionary else {}


static func save(p_enabled: PackedStringArray, p_trusted: Dictionary) -> void:
	var cfg := _config()
	cfg.set_value(SECTION, "enabled", Array(p_enabled))
	cfg.set_value(SECTION, "trusted", p_trusted)
	cfg.save(path)


## Every mod folder the game can load: the base game's, then the player's.
static func sources() -> Array[ModSource]:
	var out: Array[ModSource] = FolderModSource.discover(BASE_MODS)
	out.append_array(FolderModSource.discover(mods_dir))
	return out
