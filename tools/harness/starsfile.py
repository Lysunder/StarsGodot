"""Reads the container format of the original game's files (spec S23): block framing, the
cipher, the file header and packed text. Dev harness only; the game never reads these files.

Registration data is out of scope (S23): block type 9 is skipped, never decoded.
"""

import struct

M1, A1 = 2147483563, 40014
M2, A2 = 2147483399, 40692

TYPE_FOOTER = 0
TYPE_SETTINGS = 7
TYPE_HEADER = 8
TYPE_REGISTRATION = 9


def seed_table():
    """The S01 seed table: the 128 smallest odd primes, except entry 55 is 279."""
    out = []
    n = 3
    while len(out) < 128:
        if all(n % p for p in out if p * p <= n):
            out.append(n)
        n += 2
    out[55] = 279
    return out


SEED_TABLE = seed_table()


class Generator:
    """The cipher's keystream: the two S01 component generators, combined as a plain 32-bit
    difference (s1 - s2) mod 2^32, without the correction random() applies (S23)."""

    def __init__(self, s1, s2):
        self.s1, self.s2 = s1, s2

    def next_key(self):
        self.s1 = A1 * self.s1 % M1
        self.s2 = A2 * self.s2 % M2
        return (self.s1 - self.s2) & 0xFFFFFFFF


class Header:
    """The 16-byte file header (block type 8)."""

    def __init__(self, data):
        if len(data) != 16 or data[:4] != b"J3J3":
            raise ValueError("not a Stars! file header")
        self.game_id, self.version, self.turn, word12 = struct.unpack_from("<IHHH", data, 4)
        self.player = word12 & 31
        self.salt = word12 >> 5
        self.file_kind = data[14]
        self.cipher_flag = (data[15] >> 4) & 1

    def cipher(self):
        i, j = self.salt & 31, (self.salt >> 5) & 31
        if self.salt & 0x400:
            i += 32
        else:
            j += 32
        gen = Generator(SEED_TABLE[i], SEED_TABLE[j])
        burn = ((self.game_id & 3) + 1) * ((self.turn & 3) + 1) * ((self.player & 3) + 1)
        for _ in range(burn + self.cipher_flag):
            gen.next_key()
        return gen


def decrypt(gen, data):
    out = bytearray(data)
    whole = len(out) & ~3
    for k in range(0, whole, 4):
        v = struct.unpack_from("<I", out, k)[0] ^ gen.next_key()
        struct.pack_into("<I", out, k, v & 0xFFFFFFFF)
    if len(out) & 3:
        v = gen.next_key()
        for k in range(whole, len(out)):
            out[k] ^= v & 0xFF
            v >>= 8
    return bytes(out)


class Block:
    def __init__(self, type_id, data):
        self.type = type_id
        self.data = data

    def __repr__(self):
        return "Block(%d, %d bytes)" % (self.type, len(self.data))


class StarsFile:
    """One file: a list of turns (a .m file can hold several), each a header and its blocks.

    For .xy files, `planet_data` holds the raw 4-byte planet records that follow block 7.
    """

    def __init__(self, raw):
        self.turns = []  # list of (Header, [Block])
        self.planet_data = b""
        self._parse(raw)

    @classmethod
    def read(cls, path):
        with open(path, "rb") as f:
            return cls(f.read())

    def _parse(self, raw):
        pos = 0
        gen = None
        blocks = None
        while pos + 2 <= len(raw):
            word = struct.unpack_from("<H", raw, pos)[0]
            type_id, size = word >> 10, word & 0x3FF
            data = raw[pos + 2 : pos + 2 + size]
            if len(data) != size:
                raise ValueError("truncated block at offset %d" % pos)
            pos += 2 + size
            if type_id == TYPE_HEADER:
                header = Header(data)
                gen = header.cipher()
                blocks = []
                self.turns.append((header, blocks))
                continue
            if blocks is None:
                raise ValueError("file does not start with a header block")
            if type_id == TYPE_FOOTER:
                blocks.append(Block(type_id, data))
                continue
            data = decrypt(gen, data)
            if type_id == TYPE_REGISTRATION:
                continue  # registration data: never kept or decoded (S23)
            blocks.append(Block(type_id, data))
            if type_id == TYPE_SETTINGS:
                count = struct.unpack_from("<H", data, 10)[0]
                self.planet_data = raw[pos : pos + 4 * count]
                pos += 4 * count
        if pos != len(raw):
            raise ValueError("trailing bytes after the last block")

    @property
    def header(self):
        return self.turns[-1][0]

    @property
    def blocks(self):
        return self.turns[-1][1]


# --- Packed text ------------------------------------------------------------------------------

_ONE_NIBBLE = " aehilnorst"
_LOWER_REST = "bcdfgjkmpquvwxyz"
_PUNCT = "+-,!.?:;'*%$"


def _nibbles(data):
    for b in data:
        yield b >> 4
        yield b & 15


def decode_text(data):
    """Packed text (S23) to a string."""
    out = []
    it = iter(list(_nibbles(data)))
    for n in it:
        if n <= 10:
            out.append(_ONE_NIBBLE[n])
            continue
        second = next(it, None)
        if second is None:
            break
        if n == 15:
            third = next(it, None)
            if third is None:
                break  # padding at the end
            out.append(chr(third * 16 + second))
            continue
        k = (n - 11) * 16 + second
        if k < 26:
            out.append(chr(ord("A") + k))
        elif k < 36:
            out.append(chr(ord("0") + k - 26))
        elif k < 52:
            out.append(_LOWER_REST[k - 36])
        else:
            out.append(_PUNCT[k - 52])
    return "".join(out)


def encode_text(text):
    """A string to packed text (used by tests and, later, by order files)."""
    nibbles = []
    for ch in text:
        if ch in _ONE_NIBBLE:
            nibbles.append(_ONE_NIBBLE.index(ch))
            continue
        if "A" <= ch <= "Z":
            k = ord(ch) - ord("A")
        elif "0" <= ch <= "9":
            k = 26 + ord(ch) - ord("0")
        elif ch in _LOWER_REST:
            k = 36 + _LOWER_REST.index(ch)
        elif ch in _PUNCT:
            k = 52 + _PUNCT.index(ch)
        else:
            code = ord(ch)
            if code > 255:
                raise ValueError("character not representable: %r" % ch)
            nibbles += [15, code & 15, code >> 4]
            continue
        nibbles += [11 + k // 16, k % 16]
    if len(nibbles) % 2:
        nibbles.append(15)
    return bytes(nibbles[i] << 4 | nibbles[i + 1] for i in range(0, len(nibbles), 2))


def read_string(data, pos):
    """A length-prefixed name at pos: packed text, or a plain zero-terminated string when the
    length is 0. Returns (text, next position)."""
    length = data[pos]
    if length:
        return decode_text(data[pos + 1 : pos + 1 + length]), pos + 1 + length
    end = data.index(0, pos + 1)
    return data[pos + 1 : end].decode("latin-1"), end + 1


def read_sized(data, pos, code):
    """A value stored in 0, 1, 2 or 4 bytes (two-bit length code 0..3). Returns (value, pos)."""
    size = (0, 1, 2, 4)[code]
    return int.from_bytes(data[pos : pos + size], "little"), pos + size
