class_name UiSettings
extends RefCounted
## The player's interface settings (M11 step 10), kept in `user://settings.cfg` under [ui]: the
## font (an index into ClassicTheme.FONTS), its size (one of the font's sizes) and the interface
## scale (0 follows the window, else a percent). `apply` puts them into effect at once.

const PATH := "user://settings.cfg"
## The interface scale choices besides following the window, in percent.
const SCALES := [75, 100, 125, 150, 175, 200, 250, 300]
## The UI is laid out for this window size; with the automatic scale larger or smaller windows
## scale it, in steps that keep the pixel fonts as even as possible.
const BASE_SIZE := Vector2(1280, 720)
const SCALE_STEP := 0.25
const SCALE_MIN := 0.5
const SCALE_MAX := 4.0


static func _config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func font() -> int:
	var index := int(_config().get_value("ui", "font", ClassicTheme.DEFAULT_FONT))
	return clampi(index, 0, ClassicTheme.FONTS.size() - 1)


## The saved size when the font offers it, else the font's usual size.
static func font_size(font_index: int) -> int:
	return size_for(font_index, int(_config().get_value("ui", "font_size", 0)))


## `wanted` when font `font_index` offers that size, else the font's usual size.
static func size_for(font_index: int, wanted: int) -> int:
	var spec: Dictionary = ClassicTheme.FONTS[font_index]
	return wanted if (spec["sizes"] as Array).has(wanted) else int(spec["size"])


static func scale() -> int:
	var percent := int(_config().get_value("ui", "scale", 0))
	return percent if SCALES.has(percent) else 0


static func save(font_index: int, size: int, scale_percent: int) -> void:
	var cfg := _config()
	cfg.set_value("ui", "font", font_index)
	cfg.set_value("ui", "font_size", size)
	cfg.set_value("ui", "scale", scale_percent)
	cfg.save(PATH)


## The content scale for a window of `window` pixels: the saved percent, or with the automatic
## scale the smaller ratio of the window to BASE_SIZE, snapped to SCALE_STEP.
static func scale_factor(window: Vector2) -> float:
	return factor_for(window, scale())


## The content scale for a window of `window` pixels at `percent` (0: follow the window).
static func factor_for(window: Vector2, percent: int) -> float:
	if percent > 0:
		return percent / 100.0
	var ratio := minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y)
	return clampf(snappedf(ratio, SCALE_STEP), SCALE_MIN, SCALE_MAX)


## Puts the saved settings into effect: the theme and the interface scale.
static func apply(tree: SceneTree) -> void:
	var index := font()
	tree.root.theme = ClassicTheme.build(index, font_size(index))
	rescale(tree)


static func rescale(tree: SceneTree) -> void:
	var root := tree.root
	var factor := scale_factor(Vector2(root.size))
	if not is_equal_approx(root.content_scale_factor, factor):
		root.content_scale_factor = factor
