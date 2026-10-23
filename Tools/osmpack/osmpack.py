"""Pure pieces of the route pack build (D-36): reading Overpass answers, joining a
route's ways into lines, merging a line's stops into stations, and the numbering that
keeps OpenStreetMap's identifiers apart from Wikidata's.

`build_osmpack.py` reads the cache and calls these; `test_osmpack.py` tests them alone.
"""

from __future__ import annotations

import math
import re
import unicodedata
from array import array
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass, field

Point = tuple[float, float]  # (latitude, longitude)
Line = list[Point]

#: OpenStreetMap ids are moved into ranges of their own, far above any Wikidata
#: Q-number, so a line or a stop from either source is one 64-bit id in the app and a
#: ride logged against one can never be mistaken for the other.
LINE_BASE = 1_000_000_000_000
STOP_BASE = 2_000_000_000_000
SYSTEM_BASE = 3_000_000_000_000

#: Two ends of consecutive ways are the same point within this distance.
JOIN_M = 30.0
#: Stops of one line with the same name within this distance are one station: a
#: platform each way, or a stop either side of the road.
STATION_M = 400.0

STOP_ROLES = ("stop", "stop_entry_only", "stop_exit_only")
PLATFORM_ROLES = ("platform", "platform_entry_only", "platform_exit_only")

MODE_KIND = {
    "subway": "metro",
    "light_rail": "light rail",
    "tram": "tram",
    "monorail": "monorail",
    "bus": "bus",
    "trolleybus": "trolleybus",
}


def distance_m(a: Point, b: Point) -> float:
    phi1, phi2 = math.radians(a[0]), math.radians(b[0])
    d_phi = phi2 - phi1
    d_lambda = math.radians(b[1] - a[1])
    h = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * 6_371_008.8 * math.asin(min(1.0, math.sqrt(h)))


def length_m(line: Line) -> float:
    return sum(distance_m(a, b) for a, b in zip(line, line[1:]))


@dataclass
class Answer:
    """One or more Overpass answers, indexed by element type and id."""

    relations: dict[int, dict] = field(default_factory=dict)
    ways: dict[int, Line] = field(default_factory=dict)
    nodes: dict[int, dict] = field(default_factory=dict)

    def add(self, document: dict) -> None:
        for element in document.get("elements", []):
            kind = element.get("type")
            if kind == "relation":
                self.relations[element["id"]] = element
            elif kind == "way":
                geometry = element.get("geometry") or []
                line = [(g["lat"], g["lon"]) for g in geometry if g]
                if len(line) > 1:
                    # A way cut to a tile can come back as several pieces with nulls
                    # between them; the longest is enough to route on.
                    known = self.ways.get(element["id"])
                    if known is None or len(line) > len(known):
                        self.ways[element["id"]] = line
                else:
                    self.ways.setdefault(element["id"], [])
            elif kind == "node":
                self.nodes[element["id"]] = element


def chain(ways: Iterable[Line], join_m: float = JOIN_M) -> list[Line]:
    """Joins ways given in route order into as few lines as their ends allow.

    Members of a route relation are listed in travel order but each way points
    whichever way it was drawn, so each is turned to meet the one before; where none
    meets, a new line starts.
    """
    parts: list[Line] = []
    current: Line = []
    first_alone = False
    for way in ways:
        if len(way) < 2:
            continue
        if not current:
            current = list(way)
            first_alone = True
            continue
        end = current[-1]
        if distance_m(end, way[0]) <= join_m:
            current.extend(way[1:])
        elif distance_m(end, way[-1]) <= join_m:
            current.extend(reversed(way[:-1]))
        elif first_alone and distance_m(current[0], way[0]) <= join_m:
            # The first way was drawn the other way round; turn it and carry on.
            current.reverse()
            current.extend(way[1:])
        elif first_alone and distance_m(current[0], way[-1]) <= join_m:
            current.reverse()
            current.extend(reversed(way[:-1]))
        else:
            parts.append(current)
            current = list(way)
            first_alone = True
            continue
        first_alone = False
    if current:
        parts.append(current)
    return parts


def route_lines(relation: dict, answer: Answer) -> list[Line]:
    """A route's ways, joined; platforms and stops are not part of its line."""
    ways = [
        answer.ways.get(member["ref"], [])
        for member in relation.get("members", [])
        if member.get("type") == "way" and not member.get("role", "").startswith("platform")
    ]
    return chain(ways)


def normalised(name: str) -> str:
    """A stop name compared loosely: case, accents and punctuation aside."""
    folded = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", " ", folded.lower()).strip() or name.strip().lower()


@dataclass
class Stop:
    id: int
    name: str
    point: Point


def route_stops(relation: dict, answer: Answer) -> list[Stop]:
    """A route's stops in order: its stop positions, or its platforms where it has none."""

    def collect(roles: tuple[str, ...]) -> list[Stop]:
        stops: list[Stop] = []
        for member in relation.get("members", []):
            if member.get("type") != "node" or member.get("role") not in roles:
                continue
            node = answer.nodes.get(member["ref"])
            if node is None or "lat" not in node:
                continue
            tags = node.get("tags") or {}
            name = tags.get("name") or tags.get("name:en")
            if not name:
                continue
            stops.append(Stop(STOP_BASE + node["id"], name, (node["lat"], node["lon"])))
        return stops

    return collect(STOP_ROLES) or collect(PLATFORM_ROLES)


def merge_stations(stops: Iterable[Stop], station_m: float = STATION_M) -> dict[int, Stop]:
    """Maps each stop to its station: the stop with the lowest id among those of the
    same name within `station_m`, so a platform each way is one place to board."""
    by_name: dict[str, list[Stop]] = {}
    for stop in sorted({s.id: s for s in stops}.values(), key=lambda s: s.id):
        by_name.setdefault(normalised(stop.name), []).append(stop)
    station_of: dict[int, Stop] = {}
    for group in by_name.values():
        stations: list[Stop] = []
        for stop in group:
            home = next((s for s in stations if distance_m(s.point, stop.point) <= station_m), None)
            if home is None:
                stations.append(stop)
                home = stop
            station_of[stop.id] = home
    return station_of


def qid_number(text: str | None) -> int | None:
    """`Q1234` as 1234, or `None` for anything that is not a Q-number."""
    if not text:
        return None
    match = re.fullmatch(r"Q(\d+)", text.strip())
    return int(match.group(1)) if match else None


def colour(text: str | None) -> str | None:
    """Six hex digits, upper case, from `#e32017` or `E32017`; `None` for a name."""
    if not text:
        return None
    match = re.fullmatch(r"#?([0-9a-fA-F]{6})", text.strip())
    return match.group(1).upper() if match else None


def lift_name(tags: dict) -> str | None:
    return tags.get("name:en") or tags.get("name")


# ---------------------------------------------------------------------------- trails


class TrailWays:
    """The ways of one region's signed routes, kept compact while the tiles are read.

    A region's tiles hold tens of millions of points; as Python tuples they would not
    fit in memory, so each way is two flat integer arrays — its node ids, and its points
    in 1/100,000 of a degree — and a bitmask of the networks it belongs to.
    """

    HIKING = 1
    CYCLING = 2

    def __init__(self) -> None:
        self.nodes: dict[int, array] = {}
        self.points: dict[int, array] = {}
        self.networks: dict[int, int] = defaultdict(int)

    def add(self, document: dict) -> None:
        for element in document.get("elements", []):
            kind = element.get("type")
            if kind == "relation":
                route = (element.get("tags") or {}).get("route")
                bit = self.HIKING if route in ("hiking", "foot") else self.CYCLING
                for member in element.get("members", []):
                    if member.get("type") == "way":
                        self.networks[member["ref"]] |= bit
            elif kind == "way" and element["id"] not in self.nodes:
                ids = element.get("nodes") or []
                geometry = element.get("geometry") or []
                if len(ids) < 2 or len(ids) != len(geometry) or any(g is None for g in geometry):
                    continue
                self.nodes[element["id"]] = array("q", ids)
                flat = array("i")
                for g in geometry:
                    flat.append(round(g["lat"] * 100_000))
                    flat.append(round(g["lon"] * 100_000))
                self.points[element["id"]] = flat

    def pieces(self, bit: int):
        """Each way of the network split at its junctions — a node two or more of its
        ways share, or a way's end — as (first junction, last junction, points)."""
        ways = [way for way, mask in self.networks.items() if mask & bit and way in self.nodes]
        uses: dict[int, int] = defaultdict(int)
        for way in ways:
            ids = self.nodes[way]
            uses[ids[0]] += 2
            uses[ids[-1]] += 2
            for node in ids[1:-1]:
                uses[node] += 1
        for way in sorted(ways):
            ids = self.nodes[way]
            flat = self.points[way]
            start = 0
            for index in range(1, len(ids)):
                if uses[ids[index]] >= 2 or index == len(ids) - 1:
                    points = [
                        (flat[2 * i] / 100_000, flat[2 * i + 1] / 100_000) for i in range(start, index + 1)
                    ]
                    yield ids[start], ids[index], points
                    start = index

