#!/usr/bin/env python3
"""Tests for tracks.py: lines, repair, junctions, edges, simplification and encoding."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import tracks  # noqa: E402


def feature(*points: tuple[float, float], kind: str = "Railroad") -> dict:
    """A GeoJSON LineString from (longitude, latitude) pairs."""
    return {
        "type": "Feature",
        "properties": {"featurecla": kind},
        "geometry": {"type": "LineString", "coordinates": [list(p) for p in points]},
    }


def railways(*features: dict) -> list[tracks.Line]:
    return tracks.lines_of(features, lambda p: p.get("featurecla") == "Railroad")


class NetworkTests(unittest.TestCase):
    def test_a_line_with_no_branch_is_one_edge(self) -> None:
        # Along the equator, 0.01° of longitude is 1,111.95 m.
        network = tracks.build_network(railways(feature((0, 0), (0.01, 0), (0.02, 0))))
        self.assertEqual(network.nodes, [(0.0, 0.0), (0.0, 0.02)])
        self.assertEqual(len(network.edges), 1)
        edge = network.edges[0]
        self.assertEqual((edge.a, edge.b), (1, 2))
        self.assertEqual(edge.length_m, 2224)
        # The middle vertex is on the straight line, so simplification drops it.
        self.assertEqual(edge.points, [(0.0, 0.0), (0.0, 0.02)])

    def test_lines_meeting_at_a_vertex_make_a_junction(self) -> None:
        network = tracks.build_network(
            railways(
                feature((-0.01, 0), (0, 0), (0.01, 0)),
                feature((0, -0.01), (0, 0), (0, 0.01)),
            )
        )
        self.assertEqual(len(network.nodes), 5)
        centre = network.nodes.index((0.0, 0.0)) + 1
        self.assertEqual(len(network.edges), 4)
        self.assertTrue(all(centre in (edge.a, edge.b) for edge in network.edges))

    def test_vertices_closer_than_the_precision_are_one(self) -> None:
        # The second line starts 2 m from where the first ends: they join.
        network = tracks.build_network(
            railways(feature((0, 0), (0.01, 0)), feature((0.010002, 0), (0.02, 0)))
        )
        self.assertEqual(len(network.edges), 1)
        self.assertEqual(network.nodes, [(0.0, 0.0), (0.0, 0.02)])

    def test_other_kinds_and_junctionless_rings_are_left_out(self) -> None:
        ring = feature((1, 1), (1.01, 1), (1.01, 1.01), (1, 1.01), (1, 1))
        lines = railways(feature((0, 0), (0.01, 0), kind="Railroad ferry"), ring)
        self.assertEqual(len(lines), 1)
        network = tracks.build_network(lines)
        self.assertEqual(network.edges, [])
        self.assertEqual(network.loops_dropped, 1)

    def test_simplifying_keeps_a_bend(self) -> None:
        # A 1 km detour north in the middle of a 2 km line is far beyond 150 m.
        points = [(0.0, 0.0), (0.009, 0.01), (0.0, 0.02)]
        self.assertEqual(tracks.simplify(points, 150.0), points)
        # 100 m is within it.
        gentle = [(0.0, 0.0), (0.0009, 0.01), (0.0, 0.02)]
        self.assertEqual(tracks.simplify(gentle, 150.0), [(0.0, 0.0), (0.0, 0.02)])


class RepairTests(unittest.TestCase):
    def test_lines_that_cross_meet_where_they_cross(self) -> None:
        # Two roads crossing at (0.005, 0.005) with no vertex there.
        lines = [[(0.0, 0.0), (0.01, 0.01)], [(0.0, 0.01), (0.01, 0.0)]]
        network = tracks.build_network(tracks.repair(lines))
        self.assertIn((0.005, 0.005), network.nodes)
        self.assertEqual(len(network.edges), 4)

    def test_a_loose_end_is_linked_to_the_road_it_stops_short_of(self) -> None:
        # A road ending 0.005° (556 m) south of an east-west road: linked to the
        # point on it straight north, which becomes a junction.
        lines = [[(0.0, 0.0), (0.0, 0.02)], [(-0.01, 0.01), (-0.005, 0.01)]]
        network = tracks.build_network(tracks.repair(lines))
        self.assertIn((0.0, 0.01), network.nodes)
        links = [edge for edge in network.edges if edge.points[-1] == (0.0, 0.01) or edge.points[0] == (0.0, 0.01)]
        self.assertEqual(len(links), 3)
        # 0.02° (2.2 km) short is too far: left alone.
        apart = [[(0.0, 0.0), (0.0, 0.02)], [(-0.04, 0.01), (-0.02, 0.01)]]
        self.assertEqual(tracks.repair(apart), apart)


class EncodingTests(unittest.TestCase):
    def test_points_survive_encoding_as_steps(self) -> None:
        points = [(59.91087, 10.75245), (59.9, 10.8), (59.91, 10.79)]
        blob = tracks.encode_points(points)
        # 8 bytes for the first point, 4 for each step.
        self.assertEqual(len(blob), 16)
        self.assertEqual(tracks.decode_points(blob), points)

    def test_long_segments_are_split_so_each_step_fits(self) -> None:
        # 1° is 100,000 units, more than a 16-bit step: split into four.
        network = tracks.build_network([[(0.0, 0.0), (0.0, 1.0)]])
        points = network.edges[0].points
        self.assertEqual(len(points), 5)
        self.assertEqual(tracks.decode_points(tracks.encode_points(points)), points)


if __name__ == "__main__":
    unittest.main()
