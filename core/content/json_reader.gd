class_name JsonReader
extends RefCounted
## Strict JSON reader for content files.
##
## Unlike Godot's JSON class it keeps integers and floats apart (gameplay content must be integers),
## records the line of every value (for error messages), rejects duplicate keys, and keeps object
## keys in file order. Parse with JsonReader.parse(text); check `ok` on the result.


class Result:
	extends RefCounted
	var ok: bool = false
	var value: Variant = null
	## JSON pointer ("" for the root, "/a/0/b" below it) -> 1-based line where that value starts.
	var lines: Dictionary = {}
	var error: String = ""
	var error_line: int = 0


const _MAX_INT_DIGITS := 18

var _text: String
var _pos: int = 0
var _line: int = 1
var _result: Result


static func parse(text: String) -> Result:
	var reader := JsonReader.new()
	return reader._parse(text)


## Escapes one key for use in a JSON pointer (RFC 6901).
static func pointer_escape(key: String) -> String:
	return key.replace("~", "~0").replace("/", "~1")


func _parse(text: String) -> Result:
	_text = text
	_pos = 0
	_line = 1
	_result = Result.new()
	_skip_ws()
	var value: Variant = _value("")
	if _result.error.is_empty():
		_skip_ws()
		if _pos < _text.length():
			_fail("unexpected text after the JSON value")
	if _result.error.is_empty():
		_result.ok = true
		_result.value = value
	return _result


func _fail(message: String, line: int = 0) -> void:
	if _result.error.is_empty():
		_result.error = message
		_result.error_line = line if line > 0 else _line


func _peek() -> int:
	return _text.unicode_at(_pos) if _pos < _text.length() else -1


func _skip_ws() -> void:
	while _pos < _text.length():
		var c := _text.unicode_at(_pos)
		if c == 10:
			_line += 1
		elif c != 32 and c != 9 and c != 13:
			return
		_pos += 1


func _value(pointer: String) -> Variant:
	_skip_ws()
	_result.lines[pointer] = _line
	var c := _peek()
	if c == 123:  # {
		return _object(pointer)
	if c == 91:  # [
		return _array(pointer)
	if c == 34:  # "
		return _string()
	if c == 45 or (c >= 48 and c <= 57):  # - or digit
		return _number()
	if _text.substr(_pos, 4) == "true":
		_pos += 4
		return true
	if _text.substr(_pos, 5) == "false":
		_pos += 5
		return false
	if _text.substr(_pos, 4) == "null":
		_pos += 4
		return null
	_fail("expected a JSON value" if c >= 0 else "unexpected end of file")
	return null


func _object(pointer: String) -> Dictionary:
	var obj := {}
	_pos += 1
	_skip_ws()
	if _peek() == 125:  # }
		_pos += 1
		return obj
	while _result.error.is_empty():
		_skip_ws()
		if _peek() != 34:
			_fail("expected a string key")
			break
		var key_line := _line
		var key := _string()
		if obj.has(key):
			_fail('duplicate key "%s"' % key, key_line)
			break
		_skip_ws()
		if _peek() != 58:  # :
			_fail('expected ":" after a key')
			break
		_pos += 1
		obj[key] = _value(pointer + "/" + pointer_escape(key))
		_skip_ws()
		var c := _peek()
		if c == 44:  # ,
			_pos += 1
		elif c == 125:
			_pos += 1
			break
		else:
			_fail('expected "," or "}" in an object')
	return obj


func _array(pointer: String) -> Array:
	var arr := []
	_pos += 1
	_skip_ws()
	if _peek() == 93:  # ]
		_pos += 1
		return arr
	while _result.error.is_empty():
		arr.append(_value(pointer + "/" + str(arr.size())))
		_skip_ws()
		var c := _peek()
		if c == 44:
			_pos += 1
		elif c == 93:
			_pos += 1
			break
		else:
			_fail('expected "," or "]" in an array')
	return arr


func _string() -> String:
	_pos += 1
	var out := ""
	var start := _pos
	while _pos < _text.length():
		var c := _text.unicode_at(_pos)
		if c == 34:
			out += _text.substr(start, _pos - start)
			_pos += 1
			return out
		if c == 10 or c < 32:
			_fail("control character or line break inside a string")
			return out
		if c == 92:  # backslash
			out += _text.substr(start, _pos - start)
			_pos += 1
			out += _escape()
			start = _pos
			continue
		_pos += 1
	_fail("unterminated string")
	return out


func _escape() -> String:
	var c := _peek()
	_pos += 1
	match c:
		34:
			return '"'
		92:
			return "\\"
		47:
			return "/"
		98:
			return char(8)
		102:
			return char(12)
		110:
			return "\n"
		114:
			return "\r"
		116:
			return "\t"
		117:
			var code := _hex4()
			if code >= 0xD800 and code <= 0xDBFF and _text.substr(_pos, 2) == "\\u":
				_pos += 2
				var low := _hex4()
				if low >= 0xDC00 and low <= 0xDFFF:
					return char(0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00))
				_fail("invalid surrogate pair")
			return char(code)
	_fail("invalid escape sequence")
	return ""


func _hex4() -> int:
	var digits := _text.substr(_pos, 4)
	if digits.length() < 4 or not digits.is_valid_hex_number():
		_fail("invalid \\u escape")
		return 0
	_pos += 4
	return digits.hex_to_int()


func _number() -> Variant:
	var start := _pos
	var is_float := false
	if _peek() == 45:
		_pos += 1
	if _peek() == 48:
		_pos += 1
	elif _peek() >= 49 and _peek() <= 57:
		while _peek() >= 48 and _peek() <= 57:
			_pos += 1
	else:
		_fail("invalid number")
		return 0
	if _peek() == 46:  # .
		is_float = true
		_pos += 1
		if not (_peek() >= 48 and _peek() <= 57):
			_fail("invalid number: digits expected after the decimal point")
			return 0
		while _peek() >= 48 and _peek() <= 57:
			_pos += 1
	if _peek() == 101 or _peek() == 69:  # e E
		is_float = true
		_pos += 1
		if _peek() == 43 or _peek() == 45:
			_pos += 1
		if not (_peek() >= 48 and _peek() <= 57):
			_fail("invalid number: digits expected in the exponent")
			return 0
		while _peek() >= 48 and _peek() <= 57:
			_pos += 1
	var literal := _text.substr(start, _pos - start)
	if is_float:
		return literal.to_float()
	if literal.lstrip("-").length() > _MAX_INT_DIGITS:
		_fail("integer out of range")
		return 0
	return literal.to_int()
