"""Tests for the harness file reader and importer (specs S23, S03). They build synthetic files with
a small writer, so no file from the original game is needed (or committed).

Run: python -m unittest discover -s tools/harness -p "test_*.py"
"""

import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stars_import  # noqa: E402
import starsfile  # noqa: E402


def header_bytes(game_id=1234567, turn=0, player=31, salt=0x2A5, kind=2, flag=0):
    return (
        b"J3J3"
        + struct.pack("<IHHH", game_id, 0x2A2A, turn, player | salt << 5)
        + bytes([kind, flag << 4])
    )


def write_file(blocks, planet_data=b"", **header):
    """blocks: list of (type, data). Encrypts like the original (S23)."""
    head = header_bytes(**header)
    gen = starsfile.Header(head).cipher()
    out = struct.pack("<H", 8 << 10 | 16) + head
    for type_id, data in blocks:
        enc = data if type_id == 0 else starsfile.decrypt(gen, data)
        out += struct.pack("<H", type_id << 10 | len(data)) + enc
        if type_id == 7:
            out += planet_data
    return out


class TestCipherAndContainer(unittest.TestCase):
    def test_seed_table(self):
        table = starsfile.SEED_TABLE
        self.assertEqual(len(table), 128)
        self.assertEqual((table[0], table[54], table[55], table[56], table[127]), (3, 263, 279, 271, 727))

    def test_keystream_is_plain_difference(self):
        gen = starsfile.Generator(3, 5)
        # s1 = 120042, s2 = 203460: the difference is negative and wraps to 32 bits
        self.assertEqual(gen.next_key(), (120042 - 203460) & 0xFFFFFFFF)

    def test_round_trip_and_registration_block_dropped(self):
        blocks = [(6, bytes(range(10))), (9, b"\x01\x02\x03\x04\x05"), (13, b"abcdefg"), (0, b"\x00\x00")]
        f = starsfile.StarsFile(write_file(blocks, salt=0x7FF, flag=1))
        self.assertEqual([b.type for b in f.blocks], [6, 13, 0])
        self.assertEqual(f.blocks[0].data, bytes(range(10)))
        self.assertEqual(f.blocks[1].data, b"abcdefg")
        self.assertEqual(f.header.salt, 0x7FF)
        self.assertEqual(f.header.cipher_flag, 1)

    def test_encryption_changes_the_bytes(self):
        raw = write_file([(6, bytes(8))])
        self.assertNotEqual(raw[-8:], bytes(8))

    def test_planet_data_after_settings(self):
        settings = struct.pack("<IHHHHH", 1234567, 0, 1, 1, 2, 1) + bytes(52)
        planets = struct.pack("<II", 16 | 1370 << 10 | 932 << 22, 4 | 1049 << 10 | 5 << 22)
        f = starsfile.StarsFile(write_file([(7, settings), (0, b"\x00\x00")], planets, kind=0))
        self.assertEqual(f.planet_data, planets)
        _, players, _, positions = stars_import.read_settings(f)
        self.assertEqual(players, 1)
        self.assertEqual(positions, [(1016, 1370, 932), (1020, 1049, 5)])

    def test_rejects_bad_files(self):
        with self.assertRaises(ValueError):
            starsfile.StarsFile(struct.pack("<H", 6 << 10 | 2) + b"xx")
        with self.assertRaises(ValueError):
            starsfile.StarsFile(write_file([(6, bytes(4))]) + b"\x01")

    def test_multi_turn_file(self):
        one = write_file([(6, bytes(4)), (0, b"\x00\x00")], turn=1)
        two = write_file([(6, bytes(4)), (0, b"\x00\x00")], turn=2)
        f = starsfile.StarsFile(one + two)
        self.assertEqual([h.turn for h, _ in f.turns], [1, 2])


class TestPackedText(unittest.TestCase):
    def test_examples_from_spec(self):
        self.assertEqual(starsfile.decode_text(bytes([0x12, 0x3F])), "aeh")
        self.assertEqual(starsfile.decode_text(bytes([0xB0])), "A")
        self.assertEqual(starsfile.decode_text(bytes([0xDA])), "k")

    def test_round_trip(self):
        for text in ["", "Humanoid", "Scout #2", "Zz 09 +-,!.?:;'*%$", "Café"]:
            self.assertEqual(starsfile.decode_text(starsfile.encode_text(text)), text)

    def test_read_string(self):
        packed = starsfile.encode_text("Long Range")
        data = bytes([len(packed)]) + packed + b"\x00plain\x00rest"
        text, pos = starsfile.read_string(data, 0)
        self.assertEqual(text, "Long Range")
        self.assertEqual(starsfile.read_string(data, pos), ("plain", pos + 7))

    def test_read_sized(self):
        data = bytes([7, 0x34, 0x12, 1, 2, 3, 4])
        self.assertEqual(starsfile.read_sized(data, 0, 0), (0, 0))
        self.assertEqual(starsfile.read_sized(data, 0, 1), (7, 1))
        self.assertEqual(starsfile.read_sized(data, 1, 2), (0x1234, 3))
        self.assertEqual(starsfile.read_sized(data, 3, 3), (0x04030201, 7))


# --- A minimal synthetic game -------------------------------------------------------------------


def player_block(index, prt=9, lrt_bits=0x2001, designs=1, starbases=1):
    rec = bytearray(0x70)
    rec[0] = index
    rec[1] = designs
    rec[5] = starbases << 4
    rec[6] = 7
    rec[7] = 0x01
    struct.pack_into("<h", rec, 8, 0)
    rec[0x10:0x19] = bytes([50, 50, 50, 15, 15, 15, 85, 85, 85])
    rec[0x19] = 15
    rec[0x1A:0x20] = bytes([3, 3, 3, 3, 3, 3])
    struct.pack_into("<6I", rec, 0x20, 1, 2, 3, 4, 5, 6)
    rec[0x38] = 15
    rec[0x39] = 0x62
    rec[0x3E:0x45] = bytes([10, 10, 10, 10, 10, 5, 10])
    rec[0x45] = 3
    rec[0x46:0x4C] = bytes([1, 1, 0, 2, 1, 1])
    rec[0x4C] = prt
    struct.pack_into("<I", rec, 0x4E, lrt_bits | 1 << 29)
    name = starsfile.encode_text("Testers")
    return bytes(rec) + bytes([1, 0]) + bytes([len(name)]) + name + bytes([0, 0])


def planet_block(pid, owner):
    flags = 0x07 | 0x80 | 0x2000 | 0x800 | 0x200 | 0x4000
    out = struct.pack("<HH", pid | owner << 11, flags)
    out += bytes([0b000001, 99]) + bytes([40, 60, 80]) + bytes([50, 51, 52]) + b"\x00\x00"
    out += bytes([0b10_01_10_11]) + struct.pack("<I", 70000) + struct.pack("<H", 500) + bytes([7])
    out += struct.pack("<H", 250)
    out += bytes([12, 0x2C, 0x21, 0x03, 40, 0x31, 0x80, 0])
    out += struct.pack("<HH", 2 | 100 << 4, (1 + 1) | 3 << 10)
    out += struct.pack("<H", 0 + 1)
    return out


def design_block(slot, starbase, hull, parts):
    out = bytes([7, 1 | slot << 2 | (0x40 if starbase else 0), hull, 4])
    out += struct.pack("<HB", 100, len(parts)) + struct.pack("<HII", 0, 1, 1)
    for kind, item, count in parts:
        out += struct.pack("<HBB", kind, item, count)
    name = starsfile.encode_text("D")
    return out + bytes([len(name)]) + name


def fleet_block(owner, number):
    out = struct.pack("<HhBB", number | owner << 9, owner, 7, 8)
    out += struct.pack("<hHHH", 0, 1016, 1370, 1 << 3) + bytes([2])
    out += struct.pack("<H", 3 << 8) + struct.pack("<I", 100)
    out += struct.pack("<H", 1 << 3) + struct.pack("<H", 20 << 7 | 50)
    return out + bytes([0, 2])


def waypoint_short(x, y, target_id, kind):
    return struct.pack("<HHH", x, y, target_id) + bytes([0, kind])


def waypoint_full(x, y, target_id, kind, warp, task):
    return struct.pack("<HHH", x, y, target_id) + bytes([warp << 4 | task, kind]) + bytes(10)


class TestImporter(unittest.TestCase):
    def build(self):
        settings = struct.pack("<IHHHHH", 1234567, 0, 1, 1, 2, 1) + bytes(2) + struct.pack("<H", 0x82)
        settings += bytes(64 - len(settings))
        planets = struct.pack("<II", 16 | 1370 << 10, 4 | 1049 << 10)
        xy = starsfile.StarsFile(write_file([(7, settings), (0, b"\x00\x00")], planets, kind=0))
        scout = design_block(3, False, 4, [(1, 1, 1), (2, 0, 1), (0x3FFB, 0, 0)])
        station = design_block(0, True, 34, [(0x0A00, 0, 0)] * 12)
        unowned = struct.pack("<HH", 1 | 31 << 11, 0x07) + bytes([0]) + bytes([1, 2, 3, 4, 5, 6])
        objects = struct.pack("<H", 1)
        salvage = struct.pack("<HHHHHHHHH", 1 << 13 | 0 << 9, 1100, 1200, 0x83FF, 5, 0, 7, 2, 79)
        plan = bytes([0x00, 4, 0x13, 2]) + bytes([0]) + b"Default\x00"
        blocks = [
            (6, player_block(0)),
            (13, planet_block(0, 0)),
            (28, struct.pack("<HH", 1 | 21 << 10, 4 | 29 << 4)),
            (13, unowned),
            (26, scout),
            (16, fleet_block(0, 0)),
            (20, waypoint_short(1016, 1370, 0, 1)),
            (19, waypoint_full(1020, 1049, 1, 1, 5, 1)),
            (26, station),
            (43, objects),
            (43, salvage),
            (30, plan),
            (0, b"\x00\x00"),
        ]
        hst = starsfile.StarsFile(write_file(blocks, turn=3))
        return stars_import.Importer(xy, hst, stars_import.Legacy()).run((5, 673))

    def test_synthetic_game(self):
        save = self.build()
        s = save["state"]
        self.assertEqual(save["format"], "starsgodot-save")
        self.assertEqual(s["turn"], 3)
        self.assertTrue(s["settings"]["slow_tech"])
        self.assertTrue(s["settings"]["no_random_events"])
        self.assertEqual(s["settings"]["universe_width"], 400)
        p = s["players"][0]
        self.assertEqual(p["race"]["primary_trait"], "trait.prt.JoaT")
        self.assertEqual(p["race"]["lesser_traits"], ["trait.lrt.IFE", "trait.lrt.RS"])
        self.assertTrue(p["race"]["techs_start_at_3"])
        self.assertEqual(p["race"]["leftover_points"], "factories")
        self.assertEqual(p["race"]["name"], "Race 0")
        self.assertEqual((p["research_field"], p["next_research_field"]), (2, 6))
        self.assertEqual(p["research_points"], [1, 2, 3, 4, 5, 6])
        self.assertEqual(p["relations"], ["neutral"])
        self.assertEqual(p["ship_designs"][0]["parts"][0], {"part": "part.engine.quick_jump_5", "count": 1})
        self.assertEqual(p["ship_designs"][0]["parts"][2], {"part": "", "count": 0})
        self.assertEqual(p["starbase_designs"][0]["hull"], "hull.space_station")
        self.assertEqual(p["battle_plans"][0]["name"], "Plan 0")
        self.assertEqual(p["battle_plans"][0]["attack"], 2)
        pl = s["planets"][0]
        self.assertEqual((pl["x"], pl["y"]), (1016, 1370))
        self.assertEqual(pl["concentration_fraction"], [99, 0, 0])
        self.assertEqual(pl["environment_original"], [50, 51, 52])
        self.assertEqual(pl["surface"], [70000, 500, 7])
        self.assertEqual(pl["population"], 250)
        self.assertEqual((pl["extra_colonists"], pl["mines"], pl["factories"], pl["defenses"]), (12, 300, 50, 296))
        self.assertTrue(pl["leftover_to_research"])
        self.assertTrue(pl["has_scanner"])
        self.assertEqual(pl["starbase"], {"design": 2, "damage": 100})
        self.assertEqual((pl["mass_driver_target"], pl["mass_driver_warp"]), (1, 7))
        self.assertEqual(pl["route"], 0)
        self.assertEqual(
            pl["queue"], [{"item": "", "design": 5, "starbase": True, "count": 1, "progress": 29}]
        )
        self.assertEqual(s["planets"][1]["owner"], -1)
        f = s["fleets"][0]
        self.assertEqual(f["stacks"], [{"design": 3, "count": 2, "damaged_percent": 50, "damage": 20, "paid": [0, 0, 0, 0]}])
        self.assertEqual(f["cargo"], [0, 0, 0, 0, 100])
        self.assertEqual(len(f["waypoints"]), 2)
        self.assertEqual(f["waypoints"][1]["task"], "transport")
        self.assertEqual(f["waypoints"][1]["warp"], 5)
        self.assertEqual(f["waypoints"][1]["task_data"], {"raw": [0, 0, 0, 0, 0]})
        pk = s["packets"][0]
        self.assertEqual((pk["salvage"], pk["minerals"], pk["destination"]), (True, [5, 0, 7], -1))
        self.assertEqual(s["rng"]["streams"]["classic"], {"s1": 5, "s2": 673})


if __name__ == "__main__":
    unittest.main()
