class_name KeyBindings
extends RefCounted
## The game's keyboard shortcuts (M11 step 10): each action's key, the original's by default (its
## menus' keys, the player's guide appendix A), changeable in Settings and kept in
## `user://settings.cfg` under [keys] (a key with its modifiers, 0 for none). Keys inside lists and
## dialogs (arrows, Enter, Escape, Delete) are not rebindable.

const SECTION := "keys"
## [id, what it does, default key with modifiers], in the order Settings lists them.
const ACTIONS := [
	["help", "Help", KEY_F1],
	["save", "Save the game", KEY_MASK_CTRL | KEY_S],
	["reports", "Reports (press again for the next one)", KEY_F3],
	["ship_design", "Ship design", KEY_F4],
	["research", "Research", KEY_F5],
	["battle_plans", "Battle plans", KEY_F6],
	["relations", "Player relations", KEY_F7],
	["generate", "Generate the turn", KEY_F9],
	["score", "Score", KEY_F10],
]

## The settings file (tests point it elsewhere).
static var path := UiSettings.PATH


static func _config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg


static func default_key(id: String) -> int:
	for a: Array in ACTIONS:
		if a[0] == id:
			return a[2]
	return 0


## The action's key with its modifiers (0 for none).
static func key(id: String) -> int:
	return int(_config().get_value(SECTION, id, default_key(id)))


## Sets the action's key; another action that had the same key loses it.
static func set_key(id: String, code: int) -> void:
	var cfg := _config()
	if code != 0:
		for a: Array in ACTIONS:
			if a[0] != id and int(cfg.get_value(SECTION, a[0], a[2])) == code:
				cfg.set_value(SECTION, a[0], 0)
	cfg.set_value(SECTION, id, code)
	cfg.save(path)


static func reset() -> void:
	var cfg := _config()
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	cfg.save(path)


## "Ctrl+S", "F3", or "(none)".
static func text(code: int) -> String:
	return OS.get_keycode_string(code) if code != 0 else "(none)"


## The key with its modifiers of a key press (0 for a lone modifier key).
static func code_of(event: InputEventKey) -> int:
	if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return 0
	return event.get_keycode_with_modifiers()


## Whether a key press is the action's key.
static func matches(event: InputEvent, id: String) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and key(id) != 0 and code_of(k) == key(id)


## Whether the action's key (without its modifiers) is held now.
static func held(id: String) -> bool:
	var code := key(id) & KEY_CODE_MASK
	return code != 0 and Input.is_key_pressed(code)
