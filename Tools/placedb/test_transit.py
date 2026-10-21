#!/usr/bin/env python3
"""Tests for transit.py: names, membership, distance and segments."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import transit  # noqa: E402


class NameTests(unittest.TestCase):
    def test_station_names_lose_the_words_that_say_station(self) -> None:
        self.assertEqual(transit.station_name("Baker Street tube station"), "Baker Street")
        self.assertEqual(transit.station_name("Sol (Madrid Metro)"), "Sol")
        self.assertEqual(transit.station_name("Alexanderplatz U-Bahn station"), "Alexanderplatz")
        self.assertEqual(transit.station_name("Bastille"), "Bastille")
        self.assertEqual(transit.station_name("Civil Lines metro station (Delhi)"), "Civil Lines")
        self.assertEqual(transit.station_name("Sikanderpur metro station, Gurugram"), "Sikanderpur")
        self.assertEqual(transit.station_name("Tokyo Metro Kanda"), "Kanda")
        self.assertEqual(transit.station_name("Tokyu Railways and Tokyo Metro Shibuya"), "Shibuya")
        self.assertEqual(
            transit.station_name("Tokyu Railways, Tokyo Metro and Toei Subway Meguro"), "Meguro"
        )
        self.assertEqual(transit.station_name("Osaka Metro Shin-Osaka"), "Shin-Osaka")
        # Not every "and" is an operator.
        self.assertEqual(transit.station_name("Totteridge and Whetstone"), "Totteridge and Whetstone")
        # East Asian labels end in "Station", which is dropped unless it is the name.
        self.assertEqual(transit.station_name("Asakusa Station", "Tokyo"), "Asakusa")
        self.assertEqual(transit.station_name("Seoul Station", "Seoul"), "Seoul Station")
        self.assertEqual(transit.station_name("Ōsaka Station", "Osaka"), "Ōsaka Station")
        self.assertEqual(transit.station_name("Taipei Main Station", "Taipei"), "Taipei Main Station")
        # A name that is nothing but the word keeps it.
        self.assertEqual(transit.station_name("Station"), "Station")

    def test_line_names_lose_their_system(self) -> None:
        self.assertEqual(transit.line_name("Paris Métro Line 1", "Paris Métro"), "Line 1")
        self.assertEqual(transit.line_name("Central line", "London Underground"), "Central line")


def cached(links, *, members=("Q100",), far=()):
    """A system of stations Q1..Q5 at the city centre (Q9 90+ km away), on line Q100
    (a member of the system) and Q200 (not)."""
    stations = {f"Q{n}": {"label": f"S{n} station", "latitude": 51.5, "longitude": -0.1} for n in range(1, 6)}
    stations["Q9"] = {"label": "Far", "latitude": 52.5, "longitude": -0.1}  # ~111 km north
    lines = {
        "Q100": {"label": "Test Metro Red", "colour": "#dc241f", "short": "R", "member": "Q100" in members},
        "Q200": {"label": "Main Line", "colour": None, "short": None, "member": "Q200" in members},
    }
    return {"qid": "Q42", "stations": stations, "lines": lines, "links": links}


CURATED = {"qid": "Q42", "name": "Test Metro", "country_iso2": "GB", "city_name": "London", "kind": "metro"}


class SystemTests(unittest.TestCase):
    def test_segments_are_stored_once_whichever_way_they_were_recorded(self) -> None:
        # Q1–Q2 recorded both ways is one segment; Q2–Q3 one way is another.
        system = transit.build_system(
            CURATED,
            cached([["Q1", "Q2", "Q100"], ["Q2", "Q1", "Q100"], ["Q3", "Q2", "Q100"]]),
            (51.5, -0.1),
        )
        self.assertEqual(len(system.lines), 1)
        line = system.lines[0]
        self.assertEqual(line.segments, {(1, 2), (2, 3)})
        self.assertEqual(line.name, "Red")
        self.assertEqual(line.colour, "DC241F")
        self.assertEqual(sorted(system.stops), [1, 2, 3])
        self.assertEqual(system.stops[1].name, "S1")

    def test_lines_outside_the_system_are_left_out_where_membership_is_recorded(self) -> None:
        links = [["Q1", "Q2", "Q100"], ["Q2", "Q3", "Q200"]]
        system = transit.build_system(CURATED, cached(links), (51.5, -0.1))
        self.assertEqual([line.id for line in system.lines], [100])
        # With no line recorded as a member, every line the stations name is kept.
        everything = transit.build_system(CURATED, cached(links, members=()), (51.5, -0.1))
        self.assertEqual([line.id for line in everything.lines], [100, 200])

    def test_stations_far_from_the_city_are_not_part_of_it(self) -> None:
        system = transit.build_system(
            CURATED,
            cached([["Q1", "Q2", "Q100"], ["Q2", "Q9", "Q100"]]),
            (51.5, -0.1),
        )
        self.assertEqual(system.lines[0].segments, {(1, 2)})
        self.assertEqual(system.dropped_far, 1)

    def test_lines_are_dropped_or_merged_by_hand(self) -> None:
        links = [["Q1", "Q2", "Q100"], ["Q2", "Q3", "Q200"], ["Q3", "Q4", "Q300"]]
        answer = cached(links, members=("Q100", "Q200", "Q300"))
        answer["lines"]["Q300"] = {"label": "Branch", "colour": None, "short": None, "member": True}
        fixes = {
            "Q200": transit.LineFix.parse({"line_qid": "Q200", "action": "drop", "into": ""}),
            "Q300": transit.LineFix.parse({"line_qid": "Q300", "action": "merge", "into": "Q100"}),
        }
        system = transit.build_system(CURATED, answer, (51.5, -0.1), fixes)
        self.assertEqual([line.id for line in system.lines], [100])
        self.assertEqual(system.lines[0].segments, {(1, 2), (3, 4)})
        self.assertEqual(sorted(system.stops), [1, 2, 3, 4])
        with self.assertRaises(ValueError):
            transit.LineFix.parse({"line_qid": "Q1", "action": "merge", "into": ""})

    def test_a_line_with_a_gap_is_two_pieces(self) -> None:
        line = transit.Line(id=1, system_id=42, name="L", short_name=None, colour=None)
        line.segments = {(1, 2), (2, 3), (4, 5)}
        self.assertEqual(line.components(), 2)
        line.segments.add((3, 4))
        self.assertEqual(line.components(), 1)


if __name__ == "__main__":
    unittest.main()
