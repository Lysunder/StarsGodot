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

    def test_unknown_blocks_and_wrong_files_stop(self):
        with self.assertRaises(stars_orders.StarsOrdersError):
            stars_orders.convert(self.x_file([(4, b"\0" * 8)]))
        with self.assertRaises(stars_orders.StarsOrdersError):
            stars_orders.convert(self.x_file([], kind=2))


if __name__ == "__main__":
    unittest.main()
