"""Tests for the pure parts of the route pack build (osmpack.py)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "placedb"))

import build_osmpack  # noqa: E402
import osmpack  # noqa: E402


class ChainTests(unittest.TestCase):
    def test_ways_drawn_either_way_join_into_one_line(self):
        a = [(0.0, 0.0), (0.0, 0.01)]
        b = [(0.0, 0.02), (0.0, 0.01)]  # drawn backwards
        c = [(0.0, 0.02), (0.0, 0.03)]
        self.assertEqual(osmpack.chain([a, b, c]), [[(0.0, 0.0), (0.0, 0.01), (0.0, 0.02), (0.0, 0.03)]])

    def test_a_first_way_drawn_backwards_is_turned(self):
        a = [(0.0, 0.01), (0.0, 0.0)]
        b = [(0.0, 0.01), (0.0, 0.02)]
        self.assertEqual(osmpack.chain([a, b]), [[(0.0, 0.0), (0.0, 0.01), (0.0, 0.02)]])

    def test_a_gap_starts_a_new_part(self):
        a = [(0.0, 0.0), (0.0, 0.01)]
        b = [(1.0, 1.0), (1.0, 1.01)]
        self.assertEqual(len(osmpack.chain([a, b])), 2)


class StationTests(unittest.TestCase):
    def test_a_platform_each_way_is_one_station(self):
        north = osmpack.Stop(10, "Oxford Circus", (51.5152, -0.1418))
        south = osmpack.Stop(11, "Oxford Circus", (51.5150, -0.1416))
        elsewhere = osmpack.Stop(12, "Oxford Circus", (53.0, -1.0))
        station = osmpack.merge_stations([north, south, elsewhere])
        self.assertEqual(station[11].id, 10)
        self.assertEqual(station[12].id, 12)

    def test_names_compare_loosely(self):
        self.assertEqual(osmpack.normalised("Saint-Lazare"), osmpack.normalised("saint lazare"))
        self.assertEqual(osmpack.normalised("Châtelet"), "chatelet")


class TagTests(unittest.TestCase):
    def test_ids_and_colours(self):
        self.assertEqual(osmpack.qid_number("Q2944"), 2944)
        self.assertIsNone(osmpack.qid_number("Line A"))
        self.assertEqual(osmpack.colour("#e32017"), "E32017")
        self.assertIsNone(osmpack.colour("red"))

    def test_osm_ids_never_meet_wikidata_ids(self):
        self.assertGreater(osmpack.LINE_BASE, 10**10)
        self.assertGreater(osmpack.STOP_BASE - osmpack.LINE_BASE, 10**11)


class DistinctTests(unittest.TestCase):
    def test_the_other_direction_is_stored_once(self):
        there = [(0.0, 0.0), (0.0, 0.05)]
        back = [(0.0, 0.05), (0.0, 0.0)]
        branch = [(0.0, 0.0), (0.05, 0.0)]
        self.assertEqual(len(build_osmpack.distinct([there, back, branch])), 2)


if __name__ == "__main__":
    unittest.main()


class TrailTests(unittest.TestCase):
    def test_ways_split_at_shared_nodes_and_keep_their_network(self):
        document = {
            "elements": [
                {"type": "relation", "id": 1, "tags": {"route": "hiking"},
                 "members": [{"type": "way", "ref": 10}, {"type": "way", "ref": 11}]},
                {"type": "relation", "id": 2, "tags": {"route": "bicycle"},
                 "members": [{"type": "way", "ref": 12}]},
                {"type": "way", "id": 10, "nodes": [1, 2, 3],
                 "geometry": [{"lat": 0, "lon": 0}, {"lat": 0, "lon": 0.01}, {"lat": 0, "lon": 0.02}]},
                {"type": "way", "id": 11, "nodes": [2, 4],
                 "geometry": [{"lat": 0, "lon": 0.01}, {"lat": 0.01, "lon": 0.01}]},
                {"type": "way", "id": 12, "nodes": [5, 6],
                 "geometry": [{"lat": 1, "lon": 1}, {"lat": 1, "lon": 1.01}]},
            ]
        }
        ways = osmpack.TrailWays()
        ways.add(document)
        hiking = list(ways.pieces(ways.HIKING))
        # Way 10 splits at node 2, where way 11 joins it.
        self.assertEqual(sorted((a, b) for a, b, _ in hiking), [(1, 2), (2, 3), (2, 4)])
        self.assertEqual([(a, b) for a, b, _ in ways.pieces(ways.CYCLING)], [(5, 6)])
