class_name UiLocale
extends RefCounted
## The interface language (M11 step 10). A translation is a cosmetic mod with lang/<locale>.json:
## content names and help under their usual keys, and the interface's own text as "ui.<English
## text>" (modding/translation_template.json lists every key). The chosen locale is kept in
## settings.cfg (ui/locale); English fills any gaps.
##
## Text set on controls is translated by Godot as it is drawn; text the game puts together itself
## goes through tr() where it is made.

const DEFAULT := "en"
const UI_PREFIX := "ui."

## The translation this class registered last, removed again when the language changes.
static var _translation: Translation = null


## The locales the loaded mods have strings for, English first.
static func locales(content: ContentRegistry) -> PackedStringArray:
	var out := PackedStringArray([DEFAULT])
	var others: Array = content.strings.keys()
	others.sort()
	for loc: String in others:
		if loc != DEFAULT:
			out.append(loc)
	return out


## The locale's name in its own language, as Godot knows it ("Deutsch"), else its code.
static func display_name(locale: String) -> String:
	var name_text := TranslationServer.get_locale_name(locale)
	return name_text if not name_text.is_empty() else locale


## The player's language, if the mods still provide it.
static func chosen(content: ContentRegistry) -> String:
	var cfg := ConfigFile.new()
	cfg.load(UiSettings.PATH)
	var locale := str(cfg.get_value("ui", "locale", DEFAULT))
	return locale if locales(content).has(locale) else DEFAULT


static func save(locale: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(UiSettings.PATH)
	cfg.set_value("ui", "locale", locale)
	cfg.save(UiSettings.PATH)


## Uses `locale` (the player's choice when empty) for the content's strings and the interface.
static func apply(content: ContentRegistry, locale: String = "") -> void:
	if locale.is_empty():
		locale = chosen(content)
	content.locale = locale
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	if locale != DEFAULT:
		_translation = Translation.new()
		_translation.locale = locale
		var table: Dictionary = content.strings.get(locale, {})
		for key: String in table:
			if key.begins_with(UI_PREFIX):
				_translation.add_message(key.substr(UI_PREFIX.length()), table[key])
		TranslationServer.add_translation(_translation)
	TranslationServer.set_locale(locale)
