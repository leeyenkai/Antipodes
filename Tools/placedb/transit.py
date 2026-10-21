#!/usr/bin/env python3
"""City transit systems, lines, stops and segments from the Wikidata cache (R-TRAN-1..5).

`fetch_sources.py` caches each curated system's station-to-station links; this module
turns them into the tables the app reads. Everything here is pure: no database, no
network, so it is tested on its own (`test_transit.py`), and `build_placedb.py` only
writes what it returns.

Three judgements, each made the same way every build:

* **A segment is a link between two adjacent stops on one line** (R-TRAN-2), stored
  once with the lower station id first, whichever direction Wikidata recorded it in.
* **A station further than `MAX_DISTANCE_KM` from its system's city is not part of it.**
  Wikidata links a line's stations to through-running services far out of town; those
  would put a Tokyo subway segment in Yokohama and inflate every percentage.
* **A line belongs to the system if Wikidata says so**, where the system records its
  lines at all: London's stations are also linked along the West Coast Main Line, which
  is not the Underground. A system that records membership only on its stations keeps
  every line its stations' links name.
* **A few lines are corrected by hand** (`curation/transit_line_fixes.csv`): a closed
  line Wikidata still files under its system is dropped, and a construction phase or a
  branch recorded as a line of its own is merged into the line that runs over it.
* **A line needs at least one segment.** Lines are kept even when their links leave
  gaps, and the coverage report says how many lines are in pieces, because a ride across
  a gap cannot be routed and is counted from its two ends only.
"""

from __future__ import annotations

import math
import re
import unicodedata
from dataclasses import dataclass, field

#: How far a system's stations can lie from its city. The longest metros in the launch
#: set reach about 60 km from their centres (Seoul, Beijing, Shanghai).
MAX_DISTANCE_KM = 90.0

_SYSTEM_WORDS = (
    r"metro|métro|metrô|subway|subte|u-bahn|underground|mrt|lrt|line|station|railway"
)
# A trailing parenthetical says which system or city a station is in, which the app
# shows anyway: "Sol (Madrid Metro)", "Civil Lines metro station (Delhi)".
_PARENTHETICAL = re.compile(r"\s*\([^)]*\)\s*$")
# "… metro station", optionally followed by the town: "Sikanderpur metro station, Gurugram".
# A bare capitalised "Station" is handled by `_STATION`, which knows the city.
_SUFFIX = re.compile(
    r"\s+(?:(?i:tube|underground|metro|métro|subway|u-bahn|mrt|lrt|light rail|railway|train)"
    r"\s+(?i:station)|station)(?:,?\s+[A-Z][\w-]*)?$",
)
# Wikidata names Japanese stations by operator, to tell them from the railways' own
# stations of the same name: "Tokyo Metro Kanda", "Tokyu Railways and Tokyo Metro Shibuya".
_OPERATOR = re.compile(
    r"^(?:Tokyu Railways(?:,| and)\s+)?(?:Tokyo Metro|Toei Subway|Osaka Metro)"
    r"(?:,? and Toei Subway)?\s+(?=\S)"
)


# English labels of East Asian stations end in a capitalised "Station": "Asakusa Station".
_STATION = re.compile(r"\s+Station$")


def _folded(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


def station_name(label: str, city: str | None = None) -> str:
    """A station's name without the words that say it is a station.

    "Baker Street tube station" is Baker Street; "Sol (Madrid Metro)" is Sol; "Asakusa
    Station" is Asakusa. "Station" stays where it is part of the name: "Seoul Station"
    in Seoul is not the city, and "Taipei Main Station" is not "Taipei Main". A label
    that would be left empty keeps its full form.
    """
    name = _PARENTHETICAL.sub("", label).strip()
    name = _SUFFIX.sub("", name).strip()
    name = _OPERATOR.sub("", name).strip()
    stem = _STATION.sub("", name).strip()
    if stem != name and stem and not stem.endswith(" Main"):
        if city is None or _folded(stem) != _folded(city):
            name = stem
    return name or label.strip()


def line_name(label: str, system: str) -> str:
    """A line's name without its system's in front: "Paris Métro Line 1" is Line 1."""
    name = label.strip()
    if name.lower().startswith(system.lower() + " ") and len(name) > len(system) + 1:
        rest = name[len(system) + 1 :].strip()
        return rest[0].upper() + rest[1:]
    return name


@dataclass
class Stop:
    id: int
    name: str
    latitude: float
    longitude: float


@dataclass
class Line:
    id: int
    system_id: int
    name: str
    short_name: str | None
    colour: str | None
    segments: set[tuple[int, int]] = field(default_factory=set)

    def components(self) -> int:
        """How many separate pieces the line's segments make."""
        neighbours: dict[int, set[int]] = {}
        for a, b in self.segments:
            neighbours.setdefault(a, set()).add(b)
            neighbours.setdefault(b, set()).add(a)
        seen: set[int] = set()
        pieces = 0
        for start in sorted(neighbours):
            if start in seen:
                continue
            pieces += 1
            frontier = [start]
            while frontier:
                stop = frontier.pop()
                if stop in seen:
                    continue
                seen.add(stop)
                frontier.extend(neighbours[stop] - seen)
        return pieces


@dataclass
class System:
    id: int
    name: str
    country_iso2: str
    city_name: str
    kind: str
    lines: list[Line]
    stops: dict[int, Stop]
    dropped_far: int = 0


def qid(text: str) -> int:
    if not text.startswith("Q") or not text[1:].isdigit():
        raise ValueError(f"{text!r} is not a Wikidata QID")
    return int(text[1:])


def distance_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    phi1, phi2 = math.radians(a_lat), math.radians(b_lat)
    d_lambda = math.radians(b_lon - a_lon)
    d_phi = phi2 - phi1
    h = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * 6371.0088 * math.asin(min(1.0, math.sqrt(h)))


@dataclass(frozen=True)
class LineFix:
    """A hand correction to a line: drop it, or merge its links into other lines."""

    action: str
    into: tuple[str, ...] = ()

    @staticmethod
    def parse(row: dict[str, str]) -> LineFix:
        action = (row.get("action") or "").strip()
        into = tuple(part.strip() for part in (row.get("into") or "").split(";") if part.strip())
        if action == "drop" and not into:
            return LineFix("drop")
        if action == "merge" and into:
            for target in into:
                qid(target)
            return LineFix("merge", into)
        raise ValueError(f"line fix for {row.get('line_qid')!r}: expected 'drop', or 'merge' with lines to merge into")


def build_system(
    curated: dict[str, str],
    cached: dict,
    centre: tuple[float, float],
    fixes: dict[str, LineFix] | None = None,
) -> System:
    """One system from its curation row, its cached Wikidata answer and its city's
    coordinate, with the hand corrections to its lines applied."""
    system_id = qid(curated["qid"])
    stations = cached.get("stations", {})
    fixes = fixes or {}

    def near(station: str) -> bool:
        record = stations.get(station)
        if record is None:
            return False
        return distance_km(centre[0], centre[1], record["latitude"], record["longitude"]) <= MAX_DISTANCE_KM

    cached_lines = cached.get("lines", {})
    records_membership = any(info.get("member") for info in cached_lines.values())

    def targets(line_qid: str) -> tuple[str, ...]:
        fix = fixes.get(line_qid)
        if fix is None:
            return (line_qid,)
        return fix.into

    lines: dict[int, Line] = {}
    used: set[str] = set()
    dropped = 0
    for station, adjacent, recorded in cached.get("links", []):
        for line_qid in targets(recorded):
            info = cached_lines.get(line_qid, {})
            if records_membership and not info.get("member"):
                continue
            if not (near(station) and near(adjacent)):
                dropped += 1
                continue
            line_id = qid(line_qid)
            line = lines.setdefault(
                line_id,
                Line(
                    id=line_id,
                    system_id=system_id,
                    name=line_name(info.get("label") or line_qid, curated["name"]),
                    short_name=(info.get("short") or None),
                    colour=_colour(info.get("colour")),
                ),
            )
            a, b = sorted((qid(station), qid(adjacent)))
            line.segments.add((a, b))
            used.update((station, adjacent))

    stops = {
        qid(station): Stop(
            id=qid(station),
            name=station_name(stations[station].get("label") or station, curated["city_name"]),
            latitude=stations[station]["latitude"],
            longitude=stations[station]["longitude"],
        )
        for station in sorted(used)
    }
    return System(
        id=system_id,
        name=curated["name"],
        country_iso2=curated["country_iso2"],
        city_name=curated["city_name"],
        kind=curated.get("kind") or "metro",
        lines=[lines[key] for key in sorted(lines) if lines[key].segments],
        stops=stops,
        dropped_far=dropped,
    )


def _colour(value: str | None) -> str | None:
    """A six-digit hex colour, upper case, or nothing."""
    if not value:
        return None
    text = value.strip().lstrip("#").upper()
    return text if re.fullmatch(r"[0-9A-F]{6}", text) else None
