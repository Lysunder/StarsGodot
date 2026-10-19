class_name ClassicText
extends RefCounted
## The original's turn-message wording (spec S26 "Packed string tables"), read from the player's own
## copy at import time and turned into our language-file keys (`message.<x>.text`, S21). Nothing it
## reads is stored in the repository.
##
## A table is a character table, a word per group of 64 strings (where the group starts in the
## nibble stream), a byte per string (its length in nibbles), and the nibble stream. A nibble of 15
## means "add 15 and go on"; any other nibble ends a character, the running sum indexing the
## character table. Characters are Windows-1252.

const GROUP := 64
const CONTINUE := 15
const BACKSLASH := 0x5C


## String `sid` of the table at `table` ({chars, groups, lens, stream}: offsets in `seg`).
static func get_text(seg: PackedByteArray, table: Dictionary, sid: int) -> String:
	var group := sid / GROUP
	var at := sid % GROUP
	var lens := int(table["lens"]) + group * GROUP
	if lens + at >= seg.size():
		return ""
	var nibble := 0
	for i in at:
		nibble += seg[lens + i]
	var count := seg[lens + at]
	var p := seg.decode_u16(int(table["groups"]) + group * 2) + int(table["stream"]) + nibble / 2
	var high := nibble % 2 == 0
	var out := ""
	var sum := 0
	for i in count:
		if p >= seg.size():
			return ""
		var n: int
		if high:
			n = seg[p] >> 4
		else:
			n = seg[p] & 15
			p += 1
		high = not high
		sum += n
		if n != CONTINUE:
			out += String.chr(seg[int(table["chars"]) + sum])
			sum = 0
	return out


## A template in our placeholder form: each backslash code becomes `{i}` for the parameter it stands
## for, in order, when its kind is one the code may stand for (`codes`: letter -> kinds, "a+b" for
## two parameters written as the second). "" when the template doesn't fit `params`.
static func convert_template(template: String, params: Array, codes: Dictionary) -> String:
	var out := ""
	var next := 0
	var i := 0
	while i < template.length():
		var c := template.unicode_at(i)
		if c != BACKSLASH or i + 1 >= template.length():
			if c == 0x7B or c == 0x7D:
				return ""
			out += template[i]
			i += 1
			continue
		var letter := template[i + 1]
		i += 2
		if not codes.has(letter):
			return ""
		var placed := -1
		for kinds: String in codes[letter]:
			var parts := kinds.split("+")
			if next + parts.size() > params.size():
				continue
			var fits := true
			for k in parts.size():
				if params[next + k] != parts[k]:
					fits = false
			if fits:
				placed = next + parts.size() - 1
				next += parts.size()
				break
		if placed < 0:
			return ""
		out += "{%d}" % placed
	return out
