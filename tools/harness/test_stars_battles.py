"""Tests of the battle recording reader on a synthetic record (no original files needed)."""

import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stars_battles  # noqa: E402


def token(word, owner, kind, design, square, count):
    data = bytearray(stars_battles.TOKEN)
    struct.pack_into("<hBBBB", data, 0, word, owner, kind, design, square)
    struct.pack_into("<H", data, 19, count)
    return bytes(data)


def record():
    tokens = token(2 * 512 + 7, 2, 2, 3, 0x41, 5) + token(17, 0, 1, 16, 0x58, 1)
    move = struct.pack("<BBHH", 0, 0x42, 0, 0x31)
    shot = struct.pack("<BBHH", 1, 0x58, 1, 0x02)
    # 0x2005: 5 shifted left by 2
    hit = struct.pack("<BBHHH", 0, 4, 2, 0x2005, 0x0123)
    body = tokens + move + shot + hit
    size = stars_battles.HEADER + len(body)
    header = struct.pack("<HBBHHhHH", 0x501, 2, 2, 0b101, size, 17, 1200, 1300)
    return header + body


class ParseRecord(unittest.TestCase):
    def test_header_tokens_and_events(self):
        b = stars_battles.parse_record(record())
        self.assertEqual(b["id"], 0x501)
        self.assertEqual(b["players"], [0, 2])
        self.assertEqual((b["planet"], b["x"], b["y"]), (17, 1200, 1300))
        ship, base = b["tokens"]
        self.assertEqual((ship["fleet"], ship["fleet_owner"], ship["count"]), (7, 2, 5))
        self.assertEqual((base["planet"], base["design"]), (17, 16))
        move, shot = b["events"]
        self.assertEqual((move["token"], move["square"], move["round"], move["countdown"]), (0, 0x42, 1, 3))
        self.assertEqual(move["hits"], [])
        self.assertEqual(
            shot["hits"],
            [{"target": 0, "kind": 4, "killed": 2, "shield_damage": 20, "damage": 0x0123}],
        )

    def test_size_must_match(self):
        with self.assertRaises(ValueError):
            stars_battles.parse_record(record() + b"\x00")


if __name__ == "__main__":
    unittest.main()
