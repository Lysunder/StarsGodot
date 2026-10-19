extends GdUnitTestSuite
## Spec S26 "Packed string tables": the nibble-packed table reader, on a table packed here from our
## own words, and the conversion of backslash codes to our placeholders with the kind check.

const CODES := {
	"p": ["planet"],
	"s": ["fleet", "object"],
	"n": ["object_kind+object"],
	"i": ["number", "colonists"],
}


## Packs `strings` (ASCII) into a segment: character table, group words, length bytes, stream.
static func _pack(strings: Array) -> Array:
	var chars := PackedByteArray([0])
	var stream := PackedInt32Array()  # nibbles
	var lens := PackedByteArray()
	for s: String in strings:
		var start := stream.size()
		for i in s.length():
			var code := s.unicode_at(i)
			var at := chars.find(code)
			if at < 0:
				chars.append(code)
				at = chars.size() - 1
			while at >= 15:
				stream.append(15)
				at -= 15
			stream.append(at)
		lens.append(stream.size() - start)
	while lens.size() < 64:
		lens.append(0)
	var seg := PackedByteArray()
	var table := {"chars": 0, "groups": 256, "lens": 258, "stream": 258 + 64}
	seg.resize(table["stream"])
	for i in chars.size():
		seg[i] = chars[i]
	seg.encode_u16(table["groups"], 0)
	for i in lens.size():
		seg[table["lens"] + i] = lens[i]
	for i in range(0, stream.size(), 2):
		var low := stream[i + 1] if i + 1 < stream.size() else 0
		seg.append(stream[i] << 4 | low)
	return [seg, table]


func test_the_reader_unpacks_strings() -> void:
	var words := ["Hello there", "", "A planet {cut} away", "zzz"]
	var packed := _pack(words)
	for i in words.size():
		assert_str(ClassicText.get_text(packed[0], packed[1], i)).is_equal(words[i])


func test_codes_become_placeholders_of_the_right_kind() -> void:
	var t := "\\s reached \\p with \\i colonists."
	assert_str(ClassicText.convert_template(t, ["fleet", "planet", "colonists"], CODES)).is_equal(
		"{0} reached {1} with {2} colonists."
	)
	# a location code stands for two parameters and is written as the second
	(
		assert_str(ClassicText.convert_template("Battle at \\n.", ["object_kind", "object"], CODES))
		. is_equal("Battle at {1}.")
	)
	# a kind the code can't stand for, an unknown code, or a literal brace: kept as ours
	assert_str(ClassicText.convert_template("\\p", ["fleet"], CODES)).is_empty()
	assert_str(ClassicText.convert_template("\\G", [], CODES)).is_empty()
	assert_str(ClassicText.convert_template("{x}", [], CODES)).is_empty()
