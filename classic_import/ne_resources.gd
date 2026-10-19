class_name NeResources
extends RefCounted
## The resources of a 16-bit Windows (NE) executable (spec S26 "NE resource table"): read from the
## player's own copy of the original at import time, never stored in the repository.
##
## The MZ header's word at 0x3C points to the NE header; the NE header's word at 0x24 points to the
## resource table (relative to the NE header). The table starts with an alignment shift (offsets and
## lengths are in units of 2^shift bytes), then type entries until a zero type word: type id, count,
## 4 reserved bytes, then 12 bytes per resource (offset, length, flags, id, 4 reserved). An id
## with bit 15 set is a number (the low 15 bits); otherwise it is the offset, from the table's
## start, of a length-prefixed name.

const BITMAP := 2
const ICON := 3
const CURSOR := 1
const MZ_POINTER := 0x3C
const NE_RESOURCE_TABLE := 0x24
const NUMERIC := 0x8000
const ENTRY_SIZE := 12

## Problems found reading the file ("" when none).
var error := ""
## The whole file, for its code segments (segment).
var bytes := PackedByteArray()
## Per type id, per resource id (int, or String for a named one): the resource's bytes.
var resources := {}


static func read(p_bytes: PackedByteArray) -> NeResources:
	var out := NeResources.new()
	out.bytes = p_bytes
	out._parse(p_bytes)
	return out


## Code or data segment `index` (counting from 1): the NE header's segment table (its word at 0x22,
## 8 bytes an entry: offset and length in the units its word at 0x32 gives as a shift; length 0
## means 64 KB). Empty when it isn't there.
func segment(index: int) -> PackedByteArray:
	if not ok() or index < 1:
		return PackedByteArray()
	var ne := bytes.decode_u16(MZ_POINTER)
	var table := ne + bytes.decode_u16(ne + 0x22)
	var shift := bytes.decode_u16(ne + 0x32)
	var entry := table + (index - 1) * 8
	if entry + 8 > bytes.size():
		return PackedByteArray()
	var offset := bytes.decode_u16(entry) << shift
	var length := bytes.decode_u16(entry + 2)
	if length == 0:
		length = 0x10000
	return bytes.slice(offset, mini(offset + length, bytes.size()))


func ok() -> bool:
	return error.is_empty()


## The bytes of resource `id` of type `type`, or an empty array.
func get_resource(type: int, id: Variant) -> PackedByteArray:
	return resources.get(type, {}).get(id, PackedByteArray())


func _parse(b: PackedByteArray) -> void:
	if b.size() < 0x40 or b[0] != 0x4D or b[1] != 0x5A:
		error = "not a Windows executable"
		return
	var ne := b.decode_u16(MZ_POINTER)
	if ne + 0x40 > b.size() or b[ne] != 0x4E or b[ne + 1] != 0x45:
		error = "not a 16-bit (NE) Windows executable"
		return
	var table := ne + b.decode_u16(ne + NE_RESOURCE_TABLE)
	if table + 2 > b.size():
		error = "the resource table is outside the file"
		return
	var shift := b.decode_u16(table)
	var at := table + 2
	while at + 8 <= b.size():
		var type := b.decode_u16(at)
		if type == 0:
			return
		var count := b.decode_u16(at + 2)
		at += 8
		var key: Variant = type & ~NUMERIC if type & NUMERIC else _name(b, table + type)
		var of_type: Dictionary = resources.get(key, {})
		for i in count:
			if at + ENTRY_SIZE > b.size():
				error = "the resource table is cut short"
				return
			var offset := b.decode_u16(at) << shift
			var length := b.decode_u16(at + 2) << shift
			var id := b.decode_u16(at + 6)
			var res_id: Variant = id & ~NUMERIC if id & NUMERIC else _name(b, table + id)
			if offset + length <= b.size():
				of_type[res_id] = b.slice(offset, offset + length)
			at += ENTRY_SIZE
		resources[key] = of_type
	error = "the resource table has no end"


static func _name(b: PackedByteArray, at: int) -> String:
	if at >= b.size():
		return ""
	var n := b[at]
	return b.slice(at + 1, at + 1 + n).get_string_from_ascii()


## A packed device-independent bitmap (a BITMAP resource: header, colour table, pixels, no file
## header) as an Image: the 14-byte file header is put in front and Godot's BMP loader decodes it.
static func bitmap_image(dib: PackedByteArray) -> Image:
	if dib.size() < 40:
		return null
	var header_size := dib.decode_u32(0)
	var bits := dib.decode_u16(14)
	var used := dib.decode_u32(32)
	var colours := used if used > 0 else (1 << bits if bits <= 8 else 0)
	var file := PackedByteArray()
	file.resize(14)
	file[0] = 0x42
	file[1] = 0x4D
	file.encode_u32(2, 14 + dib.size())
	file.encode_u32(10, 14 + header_size + 4 * colours)
	file.append_array(dib)
	var image := Image.new()
	if image.load_bmp_from_buffer(file) != OK:
		return null
	return image
