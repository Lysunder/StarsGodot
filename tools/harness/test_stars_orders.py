"""Tests for the order file converter (specs S11, S23), on synthetic .x files.

Run: python -m unittest discover -s tools/harness -p "test_*.py"
"""

import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stars_orders  # noqa: E402
from test_starsfile import write_file  # noqa: E402


class TestOrders(unittest.TestCase):
    def x_file(self, blocks, kind=1):
        return write_file(blocks + [(0, b"")], player=1, turn=3, kind=kind)

    def test_converts_queue_research_and_planet_changes(self):
        queue = struct.pack("<H", 10) + struct.pack("<HHHH", 7 << 10 | 5, 2 | 40 << 4, 17 << 10 | 1, 4)
        planet = struct.pack("<HI", 10, 1 | (12 + 1) << 1 | 3 << 11 | (5 + 1) << 15)
        raw = self.x_file([(29, queue), (34, bytes([20, 0x60])), (35, planet)])
        out = stars_orders.convert(raw)
        self.assertEqual((out["format"], out["player"], out["turn"]), ("starsgodot-orders", 1, 3))
        self.assertEqual(
            out["orders"],
            [
                {
                    "type": "production_queue",
                    "planet": 10,
                    "items": [
                        {"item": "production_item.factories", "design": -1, "starbase": False,
                         "count": 5, "progress": 40},
                        {"item": "", "design": 1, "starbase": True, "count": 1, "progress": 0},
                    ],
                },
                {"type": "research", "percent": 20, "field": 0, "next": 6},
                {"type": "planet_settings", "planet": 10, "leftover_to_research": True,
                 "mass_driver_target": 12, "mass_driver_warp": 7, "route": 5},
            ],
        )

    def test_converts_fleet_orders(self):
        a, b = 3 | 1 << 9, 7 | 1 << 9
        move = struct.pack("<HHBHhh", a, b, 0x11, 0b101, 2, -1)
        name = struct.pack("<HH", a, 0) + bytes([0]) + b"Scouts\0"
        raw = self.x_file([
            (24, struct.pack("<H", a)), (23, move), (37, struct.pack("<HHH", a, b, 9 | 1 << 9)),
            (37, struct.pack("<H", a)), (10, struct.pack("<HH", a, 1)), (42, struct.pack("<HH", a, 2)),
            (44, name),
        ])
        out = stars_orders.convert(raw)["orders"]
        ref = {"fleet": 3, "owner": 1}
        self.assertEqual(out, [
            dict(ref, type="fleet_split"),
            dict(ref, type="fleet_move_ships", other=7,
                 ships=[{"design": 0, "count": 2}, {"design": 2, "count": -1}]),
            dict(ref, type="fleet_merge", fleets=[7, 9]),
            dict(ref, type="fleet_merge", fleets=[]),
            dict(ref, type="fleet_repeat", repeat=True),
            dict(ref, type="fleet_battle_plan", plan=2),
            dict(ref, type="fleet_rename", name=""),
        ])
        kept = stars_orders.convert(self.x_file([(44, name)]), keep_names=True)["orders"]
        self.assertEqual(kept[0]["name"], "Scouts")

    def test_converts_player_defaults(self):
        words = struct.pack("<HH", 1 | 0x3FF << 6, 8 | 5 << 6)
        out = stars_orders.convert(self.x_file([(46, bytes([1, 2]) + words)]))["orders"]
        self.assertEqual(out, [{
            "type": "player_defaults",
            "leftover_to_research": True,
            "queue": [
                {"item": "production_item.auto_factories", "design": -1, "starbase": False,
                 "count": 1023, "progress": 0},
                {"item": "production_item.mines", "design": -1, "starbase": False,
                 "count": 5, "progress": 0},
            ],
        }])

    def test_unknown_blocks_and_wrong_files_stop(self):
        with self.assertRaises(stars_orders.StarsOrdersError):
            stars_orders.convert(self.x_file([(27, b"\0" * 8)]))
        with self.assertRaises(stars_orders.StarsOrdersError):
            stars_orders.convert(self.x_file([], kind=2))


if __name__ == "__main__":
    unittest.main()
