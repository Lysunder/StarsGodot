"""Turn messages in the original's files (spec S21; harness only): block 12 ("events") of a player's
turn file (.m) holds that player's messages. Each record: a word with the message number (low 9 bits)
and one bit per parameter from bit 9 up (set: the parameter is a word, else a byte), a word naming the
object the message's Goto shows, then the parameters. How many parameters a message number takes is
PARAM_COUNTS below (the original's table read through code segment 1028, offset 0xe74).
"""

import struct

import starsfile

TYPE_EVENTS = 12
# Parameters per message number 0..447.
PARAM_COUNTS = [
    4, 5, 3, 4, 4, 2, 2, 4, 2, 3, 1, 1, 2, 1, 4, 3,
    3, 3, 2, 2, 4, 4, 3, 3, 4, 4, 4, 3, 3, 3, 3, 4,
    4, 3, 3, 1, 1, 5, 3, 1, 2, 2, 1, 6, 6, 6, 6, 2,
    3, 3, 4, 3, 4, 1, 2, 1, 2, 1, 2, 4, 5, 5, 1, 1,
    1, 1, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 1, 2,
    3, 1, 3, 2, 3, 2, 2, 1, 1, 4, 4, 2, 6, 6, 3, 3,
    3, 2, 3, 4, 4, 4, 4, 4, 5, 5, 3, 3, 3, 3, 4, 4,
    4, 4, 5, 5, 2, 2, 2, 1, 3, 5, 5, 4, 3, 6, 2, 0,
    0, 0, 0, 1, 1, 1, 1, 2, 3, 4, 4, 2, 2, 5, 5, 2,
    2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 6, 4, 4, 5, 5, 7,
    5, 5, 6, 6, 4, 5, 5, 6, 7, 1, 2, 2, 2, 1, 2, 1,
    1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 3, 1, 0, 2, 6, 1,
    1, 3, 7, 3, 3, 5, 6, 7, 6, 4, 5, 6, 5, 2, 3, 2,
    3, 1, 1, 2, 2, 4, 5, 6, 5, 6, 2, 4, 2, 4, 3, 1,
    2, 1, 4, 3, 4, 4, 3, 3, 4, 4, 4, 5, 4, 4, 6, 5,
    5, 5, 1, 2, 7, 1, 1, 2, 1, 1, 3, 2, 1, 2, 2, 2,
    0, 1, 1, 0, 1, 2, 2, 3, 1, 2, 2, 1, 1, 1, 1, 1,
    1, 1, 1, 5, 5, 6, 6, 0, 1, 5, 1, 1, 2, 2, 2, 2,
    2, 6, 6, 2, 5, 5, 3, 3, 3, 1, 1, 1, 4, 3, 3, 1,
    1, 4, 4, 4, 4, 2, 3, 1, 1, 4, 2, 2, 4, 5, 6, 7,
    4, 4, 6, 6, 5, 3, 4, 3, 1, 1, 2, 1, 1, 2, 2, 2,
    1, 2, 1, 0, 1, 1, 2, 3, 4, 2, 4, 3, 2, 2, 2, 5,
    6, 7, 4, 5, 6, 1, 3, 2, 3, 4, 4, 4, 4, 4, 5, 5,
    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 3, 3, 2, 2, 1, 1,
    2, 32, 101, 111, 116, 97, 115, 110, 105, 114, 108, 100, 104, 92, 117, 99,
    112, 102, 121, 98, 109, 46, 103, 118, 119, 107, 44, 89, 84, 48, 39, 65,
    122, 80, 77, 88, 83, 120, 70, 79, 106, 73, 37, 86, 76, 45, 67, 85,
    68, 33, 71, 113, 72, 42, 69, 78, 87, 40, 41, 50, 53, 58, 82, 49,
]


def decode(data):
    """The messages of one block's data: [(number, goto, [params])]."""
    out = []
    pos = 0
    while pos + 4 <= len(data):
        word, goto = struct.unpack_from("<HH", data, pos)
        pos += 4
        number = word & 0x1FF
        flags = word >> 9
        params = []
        for i in range(PARAM_COUNTS[number]):
            if flags & (1 << i):
                params.append(struct.unpack_from("<H", data, pos)[0])
                pos += 2
            else:
                params.append(data[pos])
                pos += 1
        out.append((number, goto, params))
    return out


def read(path):
    """All messages in a player's turn file, in file order."""
    out = []
    for block in starsfile.StarsFile.read(path).blocks:
        if block.type == TYPE_EVENTS:
            out.extend(decode(block.data))
    return out
