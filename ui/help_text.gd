class_name HelpText
extends RefCounted
## The help topics (content strings `help.index`, `help.<topic>.title`, `help.<topic>.body`, made
## by tools/gen_help.py; a cosmetic mod or a translation can replace them) and their markup as
## BBCode for a RichTextLabel: blank lines between paragraphs, "## " headings, "- " bullets (wrapped
## lines indented), **bold**, [[topic]] and [[topic|text]] links (the topic id as the link's meta),
## {key:action} for the player's key for a KeyBindings action and {keys} for the list of them all.

const HEADING_SIZE := 1.25


## The topic ids in order.
static func topics(content: ContentRegistry) -> PackedStringArray:
	return content.string_for("help.index").split(" ", false)


static func title(content: ContentRegistry, topic: String) -> String:
	return content.string_for("help.%s.title" % topic)


## The topic's body as BBCode, with `font_size` for the headings' size.
static func bbcode(content: ContentRegistry, topic: String, font_size: int) -> String:
	var key := "help.%s.body" % topic
	var body := content.string_for(key)
	if body == key:
		return ""
	return markup(content, body, font_size)


## Text in the help's markup as BBCode (the tutorial's steps use it too).
static func markup(content: ContentRegistry, body: String, font_size: int) -> String:
	var out: PackedStringArray = []
	for block in body.split("\n\n", false):
		var lines := block.strip_edges(false, true).split("\n")
		if lines[0].begins_with("## "):
			var size := int(font_size * HEADING_SIZE)
			out.append(
				"[font_size=%d][b]%s[/b][/font_size]" % [size, _inline(content, lines[0].substr(3))]
			)
			lines.remove_at(0)
			if lines.is_empty():
				continue
		if lines[0].begins_with("- "):
			out.append(_bullets(content, lines))
		else:
			out.append(_inline(content, " ".join(_trimmed(lines))))
	return "\n\n".join(out)


## Bullets: each "- " starts one; indented lines go on with the one before.
static func _bullets(content: ContentRegistry, lines: PackedStringArray) -> String:
	var items: PackedStringArray = []
	for line in lines:
		if line.begins_with("- "):
			items.append(line.substr(2).strip_edges())
		elif not items.is_empty():
			items[items.size() - 1] += " " + line.strip_edges()
	var out: PackedStringArray = []
	for item in items:
		out.append("[indent]• %s[/indent]" % _inline(content, item))
	return "\n".join(out)


static func _trimmed(lines: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for line in lines:
		out.append(line.strip_edges())
	return out


## Links, keys and bold in one line of text; everything else is escaped.
static func _inline(content: ContentRegistry, text: String) -> String:
	var out := ""
	var at := 0
	var token := RegEx.create_from_string(
		"\\[\\[([a-z_]+)(?:\\|([^\\]]+))?\\]\\]|\\{key:([a-z_]+)\\}|\\{keys\\}"
	)
	for m in token.search_all(text):
		out += _plain(text.substr(at, m.get_start() - at))
		if m.get_string(0) == "{keys}":
			out += _key_list()
		elif not m.get_string(3).is_empty():
			out += "[b]%s[/b]" % _escape(KeyBindings.text(KeyBindings.key(m.get_string(3))))
		else:
			var topic := m.get_string(1)
			var label := m.get_string(2)
			if label.is_empty():
				label = title(content, topic)
			out += "[url=%s]%s[/url]" % [topic, _escape(label)]
		at = m.get_end()
	return out + _plain(text.substr(at))


## Plain text with **bold**.
static func _plain(text: String) -> String:
	var parts := _escape(text).split("**")
	var out := ""
	for i in parts.size():
		out += ("[b]%s[/b]" if i % 2 == 1 else "%s") % parts[i]
	return out


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


## Every rebindable action with its key, one bullet each.
static func _key_list() -> String:
	var out: PackedStringArray = []
	for a: Array in KeyBindings.ACTIONS:
		var code := KeyBindings.key(a[0])
		var key := KeyBindings.text(code) if code != 0 else "(none)"
		out.append("[indent]• [b]%s[/b]: %s[/indent]" % [_escape(key), _escape(a[1])])
	return "\n".join(out)
