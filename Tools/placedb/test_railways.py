#!/usr/bin/env python3
"""Tests for railways.py: junctions, edges, simplification and encoding."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import railways  # noqa: E402


def line(*points: tuple[float, float], kind: str = "Railroad") -> dict:
    """A GeoJSON LineString from (longitude, latitude) pairs."""
    return {
        "type": "Feature",
        "properties": {"featurecla": kind},
        "geometry": {"type": "LineString", "coordinates": [list(p) for p in points]},
    }


class NetworkTests(unittest.TestCase):
    def test_a_line_with_no_branch_is_one_edge(self) -> None:
        # Along the equator, 0.01° of longitude is 1,111.95 m.
        network = railways.build_network([line((0, 0), (0.01, 0), (0.02, 0))])
        self.assertEqual(network.nodes, [(0.0, 0.0), (0.0, 0.02)])
        self.assertEqual(len(network.edges), 1)
        edge = network.edges[0]
        self.assertEqual((edge.a, edge.b), (1, 2))
        self.assertEqual(edge.length_m, 2224)
        # The middle vertex is on the straight line, so simplification drops it.
        self.assertEqual(edge.points, [(0.0, 0.0), (0.0, 0.02)])

    def test_lines_meeting_at_a_vertex_make_a_junction(self) -> None:
        # A cross: two lines through (0, 0).
        network = railways.build_network(
            [line((-0.01, 0), (0, 0), (0.01, 0)), line((0, -0.01), (0, 0), (0, 0.01))]
        )
        self.assertEqual(len(network.nodes), 5)
        centre = network.nodes.index((0.0, 0.0)) + 1
        self.assertEqual(len(network.edges), 4)
        self.assertTrue(all(centre in (edge.a, edge.b) for edge in network.edges))

    def test_vertices_closer_than_the_precision_are_one(self) -> None:
        # The second line starts 2 m from where the first ends: they join.
        network = railways.build_network(
            [line((0, 0), (0.01, 0)), line((0.010002, 0), (0.02, 0))]
        )
        self.assertEqual(len(network.edges), 1)
        self.assertEqual(network.nodes, [(0.0, 0.0), (0.0, 0.02)])

    def test_ferries_and_junctionless_rings_are_left_out(self) -> None:
        ring = line((1, 1), (1.01, 1), (1.01, 1.01), (1, 1.01), (1, 1))
        network = railways.build_network(
            [line((0, 0), (0.01, 0), kind="Railroad ferry"), ring]
        )
        self.assertEqual(network.edges, [])
        self.assertEqual(network.loops_dropped, 1)

    def test_simplifying_keeps_a_bend(self) -> None:
        # A 1 km detour north in the middle of a 2 km line is far beyond 150 m.
        points = [(0.0, 0.0), (0.009, 0.01), (0.0, 0.02)]
        self.assertEqual(railways.simplify(points, 150.0), points)
        # 100 m is within it.
        gentle = [(0.0, 0.0), (0.0009, 0.01), (0.0, 0.02)]
        self.assertEqual(railways.simplify(gentle, 150.0), [(0.0, 0.0), (0.0, 0.02)])

    def test_points_survive_encoding(self) -> None:
        points = [(59.91087, 10.75245), (-33.86882, 151.20929)]
        blob = railways.encode_points(points)
        self.assertEqual(len(blob), 16)
        self.assertEqual(railways.decode_points(blob), points)


if __name__ == "__main__":
    unittest.main()
