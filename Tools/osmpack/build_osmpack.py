#!/usr/bin/env python3
"""Build routes-osm.sqlite, the OpenStreetMap route pack (D-36), from the cache.

This reads only ``vendor/osm/`` (filled by ``fetch_osm.py``) and the curation, never
the network, so a rebuild is offline and repeatable — the same split as the place
database (D-9). It also reads, never writes, the place database's catalogue routes and
transit lines, to know which route ids to draw and which Wikidata lines to give a shape.

What it writes, all under the ODbL with the notice in ``meta``:

* ``track_edge``/``track_region`` — signed hiking and cycling routes in each region of
  ``curation/regions.csv``, as routable networks named ``hiking/<region>`` and
  ``cycling/<region>`` (R-PATH-2).
* ``route_shape`` — the catalogue routes' real shapes (R-JLOG-3, R-PATH-1).
* ``aerialway`` — passenger lifts with their stations.
* ``transit_*`` — metro, tram, light-rail, monorail and bus lines with their stops and
  shapes (R-TRAN-1, R-TRAN-5, R-TRAN-6), and shapes for the place database's own lines.

Usage::

    python3 -I build_osmpack.py [--places PATH] [--out PATH]
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "Tools" / "placedb"))

import osmpack  # noqa: E402 - must follow the sys.path lines above
import tracks  # noqa: E402

VENDOR = HERE / "vendor" / "osm"
CURATION = HERE / "curation"
DEFAULT_OUT = HERE / "out" / "routes-osm.sqlite"
DEFAULT_PLACES = REPO / "App" / "Antipodes" / "Resources" / "places.sqlite"

SCHEMA_VERSION = 1
#: The pack's size limit (D-36). The build fails above it rather than ship a surprise.
SIZE_BUDGET_MB = 120
#: How closely each kind of line is drawn. Lengths are measured before simplifying.
TRAIL_SIMPLIFY_M = 25.0
TRANSIT_SIMPLIFY_M = 8.0
ROUTE_SIMPLIFY_M = 40.0
LIFT_SIMPLIFY_M = 5.0
#: Shorter lifts are tows and nursery lifts, not rides anyone logs.
MIN_LIFT_M = 150.0
LIFT_KINDS = {"cable_car", "gondola", "chair_lift", "mixed_lift"}
#: A bus route longer than this is a coach — Flixbus, National Express — not city
#: transit, and is logged as a coach journey instead.
MAX_BUS_ROUTE_KM = 120
LICENCE = "ODbL-1.0"
ATTRIBUTION = "© OpenStreetMap contributors, available under the Open Database License (ODbL)"


class BuildError(Exception):
    pass


def rows(name: str) -> list[dict[str, str]]:
    lines = [
        line
        for line in (CURATION / name).read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    return list(csv.DictReader(lines))


def load(paths) -> osmpack.Answer:
    answer = osmpack.Answer()
    for path in sorted(paths):
        answer.add(json.loads(path.read_text(encoding="utf-8")))
    return answer


def encode(line: osmpack.Line, simplify_m: float) -> bytes:
    return tracks.encode_points(tracks._within_steps(tracks.simplify(line, simplify_m)))


# ---------------------------------------------------------------------------- trails


def build_trails(connection: sqlite3.Connection, report: list[str]) -> None:
    for region in rows("regions.csv"):
        files = sorted((VENDOR / "trails" / region["id"]).glob("*.json"))
        if not files:
            report.append(f"trails {region['id']}: not fetched, left out")
            continue
        ways = osmpack.TrailWays()
        for path in files:
            ways.add(json.loads(path.read_text(encoding="utf-8")))
        for kind, bit in (("hiking", ways.HIKING), ("cycling", ways.CYCLING)):
            name = f"{kind}/{region['id']}"
            junctions: dict[int, int] = {}
            edges = []
            for first, last, points in ways.pieces(bit):
                if first == last and len(points) < 3:
                    continue
                a = junctions.setdefault(first, len(junctions) + 1)
                b = junctions.setdefault(last, len(junctions) + 1)
                edges.append(
                    (
                        name,
                        len(edges) + 1,
                        a,
                        b,
                        round(osmpack.length_m(points)),
                        encode(points, TRAIL_SIMPLIFY_M),
                    )
                )
            if not edges:
                continue
            connection.executemany("INSERT INTO track_edge VALUES (?, ?, ?, ?, ?, ?)", edges)
            connection.execute(
                "INSERT INTO track_region VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    name,
                    kind,
                    region["id"],
                    region["name"],
                    float(region["south"]),
                    float(region["west"]),
                    float(region["north"]),
                    float(region["east"]),
                ),
            )
            km = sum(edge[4] for edge in edges) / 1000
            report.append(f"{name}: {len(edges):,} edges, {len(junctions):,} junctions, {km:,.0f} km")
        del ways


# ---------------------------------------------------------------------------- routes


def build_routes(connection: sqlite3.Connection, places: sqlite3.Connection, report: list[str]) -> None:
    known = {row[0] for row in places.execute("SELECT id FROM route")}
    for row in rows("routes.csv"):
        route_id = int(row["route_id"])
        if route_id not in known:
            raise BuildError(f"routes.csv names route {route_id}, which places.sqlite does not have")
        ways: list[osmpack.Line] = []
        missing = []
        for relation_id in row["relations"].split():
            path = VENDOR / "routes" / f"{relation_id}.json"
            if not path.exists():
                missing.append(relation_id)
                continue
            answer = load([path])
            relation = answer.relations.get(int(relation_id))
            if relation is None:
                missing.append(relation_id)
                continue
            ways.extend(
                answer.ways.get(member["ref"], [])
                for member in relation.get("members", [])
                if member.get("type") == "way" and not member.get("role", "").startswith("platform")
            )
        if missing:
            report.append(f"route {route_id} ({row['note']}): relations {', '.join(missing)} not fetched")
        parts = [part for part in osmpack.chain(ways) if osmpack.length_m(part) > 200]
        for index, part in enumerate(parts):
            connection.execute(
                "INSERT INTO route_shape VALUES (?, ?, ?, ?)",
                (route_id, index, round(osmpack.length_m(part)), encode(part, ROUTE_SIMPLIFY_M)),
            )
        if parts:
            km = sum(osmpack.length_m(p) for p in parts) / 1000
            report.append(f"route {route_id} ({row['note']}): {len(parts)} parts, {km:,.0f} km")


# ----------------------------------------------------------------------------- lifts


def build_lifts(connection: sqlite3.Connection, report: list[str]) -> None:
    path = VENDOR / "lifts" / "world.json"
    if not path.exists():
        report.append("lifts: not fetched, left out")
        return
    document = json.loads(path.read_text(encoding="utf-8"))
    stations: dict[tuple[float, float], str] = {}
    for element in document["elements"]:
        if element["type"] == "node":
            name = osmpack.lift_name(element.get("tags") or {})
            if name:
                stations[(round(element["lat"], 6), round(element["lon"], 6))] = name
    count = 0
    for element in document["elements"]:
        if element["type"] != "way":
            continue
        tags = element.get("tags") or {}
        if tags.get("aerialway") not in LIFT_KINDS:
            continue
        line = [(g["lat"], g["lon"]) for g in element.get("geometry") or [] if g]
        if len(line) < 2 or osmpack.length_m(line) < MIN_LIFT_M:
            continue
        start, end = line[0], line[-1]
        connection.execute(
            "INSERT INTO aerialway VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                element["id"],
                tags["aerialway"],
                osmpack.lift_name(tags),
                stations.get((round(start[0], 6), round(start[1], 6))),
                stations.get((round(end[0], 6), round(end[1], 6))),
                start[0],
                start[1],
                end[0],
                end[1],
                round(osmpack.length_m(line)),
                encode(line, LIFT_SIMPLIFY_M),
            ),
        )
        count += 1
    report.append(f"lifts: {count:,}")


# --------------------------------------------------------------------------- transit


class Transit:
    """Lines gathered from every city, written once at the end."""

    def __init__(self, places: sqlite3.Connection, version: str) -> None:
        self.version = version
        # The place database's lines, by Wikidata number, and its systems.
        self.wikidata_lines = {row[0]: row[1] for row in places.execute("SELECT id, system_id FROM transit_line")}
        self.wikidata_line_names: dict[int, list[tuple[int, str, str | None]]] = defaultdict(list)
        for line_id, system_id, name, short in places.execute(
            "SELECT id, system_id, name, short_name FROM transit_line"
        ):
            self.wikidata_line_names[system_id].append(
                (line_id, osmpack.normalised(name), osmpack.normalised(short) if short else None)
            )
        self.wikidata_systems = {
            row[0]: (row[1], row[2])
            for row in places.execute(
                "SELECT s.id, s.name, c.name FROM transit_system AS s LEFT JOIN city AS c ON c.id = s.city_id"
            )
        }
        self.systems: dict[tuple[str, str], dict] = {}
        self.lines: dict[int, dict] = {}
        self.shapes: dict[int, list[osmpack.Line]] = defaultdict(list)
        self.stops: dict[int, osmpack.Stop] = {}
        self.seen_relations: set[int] = set()
        self.matched_relations = 0

    def wikidata_system_in(self, city: str) -> set[int]:
        return {sid for sid, (_, city_name) in self.wikidata_systems.items() if city_name == city}

    def add_city(self, city: dict, answer: osmpack.Answer) -> None:
        masters: dict[int, dict] = {}
        for relation in answer.relations.values():
            tags = relation.get("tags") or {}
            if tags.get("type") == "route_master":
                for member in relation.get("members", []):
                    if member.get("type") == "relation":
                        masters[member["ref"]] = relation
        city_systems = self.wikidata_system_in(city["name"])
        for relation in answer.relations.values():
            tags = relation.get("tags") or {}
            if tags.get("type") != "route" or tags.get("route") not in osmpack.MODE_KIND:
                continue
            if relation["id"] in self.seen_relations:
                continue
            self.seen_relations.add(relation["id"])
            master = masters.get(relation["id"])
            master_tags = (master or {}).get("tags") or {}
            self.add_route(city, relation, tags, master, master_tags, answer, city_systems)

    def add_route(self, city, relation, tags, master, master_tags, answer, city_systems) -> None:
        mode = tags["route"]
        lines = [line for line in osmpack.route_lines(relation, answer) if osmpack.length_m(line) > 50]
        # A line the place database already has keeps its identity and gains a shape.
        wikidata = osmpack.qid_number(master_tags.get("wikidata")) or osmpack.qid_number(tags.get("wikidata"))
        if wikidata in self.wikidata_lines:
            self.shapes[wikidata].extend(lines)
            self.matched_relations += 1
            return
        # A metro whose system the place database has, but whose line is not tagged
        # with its Wikidata identity, is matched by its number or name instead, and
        # left alone if neither fits, rather than listed twice.
        network_qid = osmpack.qid_number(tags.get("network:wikidata") or master_tags.get("network:wikidata"))
        if network_qid in city_systems or (mode == "subway" and city_systems):
            systems = [network_qid] if network_qid in city_systems else sorted(city_systems)
            match = self.match_line(systems, tags, master_tags)
            if match is not None:
                self.shapes[match].extend(lines)
                self.matched_relations += 1
            return

        stops = osmpack.route_stops(relation, answer)
        if len(stops) < 2:
            return
        kind = osmpack.MODE_KIND[mode]
        if kind in ("bus", "trolleybus"):
            if sum(osmpack.length_m(line) for line in lines) > MAX_BUS_ROUTE_KM * 1000:
                return
            # A city's buses are one system, whoever runs each route: a rider knows the
            # number on the front, not the operator behind it.
            kind = "bus"
            network = f"{city['name']} buses"
        else:
            network = tags.get("network") or master_tags.get("network") or tags.get("operator") or city["name"]
        key = (city["slug"], f"{network}|{kind}")
        system = self.systems.get(key)
        if system is None:
            system = {
                "id": osmpack.SYSTEM_BASE + len(self.systems) + 1,
                "name": network,
                "kind": kind,
                "city": city["name"],
                "country": city["country"],
            }
            self.systems[key] = system
        # One line per route master; routes without one are grouped by their number.
        line_key = master["id"] if master else (key, tags.get("ref") or tags.get("name"))
        line_id = osmpack.LINE_BASE + (master["id"] if master else relation["id"])
        line = self.lines.get(line_key)
        if line is None:
            ref = master_tags.get("ref") or tags.get("ref")
            name = master_tags.get("name") or tags.get("name") or (f"Line {ref}" if ref else "Line")
            line = {
                "id": line_id,
                "system": system["id"],
                "name": name,
                "short": ref,
                "colour": osmpack.colour(master_tags.get("colour") or tags.get("colour")),
                "routes": [],
            }
            self.lines[line_key] = line
        line["routes"].append(stops)
        self.shapes[line["id"]].extend(lines)
        for stop in stops:
            self.stops[stop.id] = stop

    def match_line(self, systems: list[int], tags: dict, master_tags: dict) -> int | None:
        """The place database's line an untagged route is, by number or by name."""
        ref = osmpack.normalised(master_tags.get("ref") or tags.get("ref") or "")
        names = {
            osmpack.normalised(text.split(":")[0])
            for text in (master_tags.get("name"), tags.get("name"), master_tags.get("name:en"), tags.get("name:en"))
            if text
        }
        found = set()
        for system in systems:
            for line_id, name, short in self.wikidata_line_names.get(system, []):
                if ref and (short == ref or name.split()[-1:] == [ref] or name == ref):
                    found.add(line_id)
                elif name in names:
                    found.add(line_id)
        # Two lines with the same number in one city (a metro 1 and a tram 1) is no match.
        return found.pop() if len(found) == 1 else None

    def write(self, connection: sqlite3.Connection, report: list[str]) -> None:
        station = osmpack.merge_stations(self.stops.values())
        used_stops: set[int] = set()
        written_lines = 0
        # A network running more than one kind in a city — a metro and a tram under one
        # name — is told apart by its kind.
        names = defaultdict(int)
        for system in self.systems.values():
            names[(system["city"], system["name"])] += 1
        for system in self.systems.values():
            if names[(system["city"], system["name"])] > 1:
                system["name"] = f"{system['name']} ({system['kind']})"
        for system in self.systems.values():
            connection.execute(
                "INSERT INTO transit_system VALUES (?, ?, ?, ?, ?, ?)",
                (system["id"], system["name"], system["kind"], system["city"], system["country"], self.version),
            )
        for line in self.lines.values():
            segments: set[tuple[int, int]] = set()
            for stops in line["routes"]:
                ids = [station[s.id].id for s in stops]
                for a, b in zip(ids, ids[1:]):
                    if a != b:
                        segments.add((min(a, b), max(a, b)))
            if not segments:
                continue
            used_stops.update(i for pair in segments for i in pair)
            connection.execute(
                "INSERT INTO transit_line VALUES (?, ?, ?, ?, ?, ?)",
                (line["id"], line["system"], line["name"], line["short"], line["colour"], len(segments)),
            )
            connection.executemany(
                "INSERT INTO transit_segment VALUES (?, ?, ?)",
                [(line["id"], a, b) for a, b in sorted(segments)],
            )
            written_lines += 1
        for stop_id in sorted(used_stops):
            stop = self.stops[stop_id]
            connection.execute(
                "INSERT INTO transit_stop VALUES (?, ?, ?, ?)",
                (stop.id, stop.name, stop.point[0], stop.point[1]),
            )
        shape_parts = 0
        for line_id, parts in self.shapes.items():
            for index, part in enumerate(distinct(parts)):
                connection.execute(
                    "INSERT INTO transit_shape VALUES (?, ?, ?)",
                    (line_id, index, encode(part, TRANSIT_SIMPLIFY_M)),
                )
                shape_parts += 1
        connection.execute(
            "DELETE FROM transit_system WHERE id NOT IN (SELECT DISTINCT system_id FROM transit_line)"
        )
        wikidata_shaped = sum(1 for line_id in self.shapes if line_id in self.wikidata_lines)
        report.append(
            f"transit: {len(self.systems):,} systems, {written_lines:,} lines, {len(used_stops):,} stations; "
            f"{shape_parts:,} shape parts; {wikidata_shaped} Wikidata lines given a shape"
        )


def distinct(parts: list[osmpack.Line]) -> list[osmpack.Line]:
    """Leaves out a part that runs over one already kept — the other direction of a
    line, usually — so each stretch of track is stored once or twice, not per route."""
    kept: list[osmpack.Line] = []
    for part in sorted(parts, key=osmpack.length_m, reverse=True):
        ends = (part[0], part[-1])
        if any(
            osmpack.distance_m(ends[0], other[-1]) < 300 and osmpack.distance_m(ends[1], other[0]) < 300
            or osmpack.distance_m(ends[0], other[0]) < 300 and osmpack.distance_m(ends[1], other[-1]) < 300
            for other in kept
        ):
            continue
        kept.append(part)
    return kept


def build_transit(connection: sqlite3.Connection, places: sqlite3.Connection, version: str, report: list[str]) -> None:
    transit = Transit(places, version)
    fetched = 0
    for city in rows("cities.csv"):
        for group in ("rail", "bus"):
            files = list((VENDOR / "transit" / group / city["slug"]).glob("*.json"))
            if files:
                fetched += 1
                transit.add_city(city, load(files))
    if not fetched:
        report.append("transit: not fetched, left out")
        return
    transit.write(connection, report)


# ------------------------------------------------------------------------------ main


def snapshot() -> tuple[str, str]:
    manifest = json.loads((VENDOR / "manifest.json").read_text(encoding="utf-8"))
    days = sorted(entry["retrieved"] for entry in manifest["files"].values())
    if not days:
        raise BuildError("The cache is empty. Run fetch_osm.py first.")
    return days[0], days[-1]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--places", type=Path, default=DEFAULT_PLACES)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    arguments = parser.parse_args(argv)
    try:
        if not arguments.places.exists():
            raise BuildError(f"Missing {arguments.places}. Run scripts/build-placedb.sh first.")
        first, last = snapshot()
        version = f"osm-{last}"
        out: Path = arguments.out
        out.parent.mkdir(parents=True, exist_ok=True)
        partial = out.with_suffix(".partial")
        partial.unlink(missing_ok=True)
        places = sqlite3.connect(f"file:{arguments.places}?mode=ro", uri=True)
        connection = sqlite3.connect(partial)
        connection.executescript((HERE / "schema.sql").read_text(encoding="utf-8"))
        report: list[str] = []
        build_routes(connection, places, report)
        build_lifts(connection, report)
        build_transit(connection, places, version, report)
        build_trails(connection, report)
        meta = {
            "schema_version": str(SCHEMA_VERSION),
            "built": dt.datetime.now(dt.UTC).date().isoformat(),
            "licence": LICENCE,
            "attribution": ATTRIBUTION,
            "osm_snapshot": first if first == last else f"{first} to {last}",
            "network_version": version,
        }
        connection.executemany("INSERT INTO meta VALUES (?, ?)", sorted(meta.items()))
        connection.commit()
        connection.execute("VACUUM")
        sizes = connection.execute(
            "SELECT name, SUM(pgsize) FROM dbstat GROUP BY name ORDER BY 2 DESC"
        ).fetchall()
        connection.close()
        places.close()
        megabytes = partial.stat().st_size / (1024 * 1024)
        for line in report:
            print(f"    {line}")
        print("    sizes: " + ", ".join(f"{name} {size / 1048576:.1f} MB" for name, size in sizes[:8]))
        print(f"==> {out.name}: {megabytes:.1f} MB of {SIZE_BUDGET_MB} MB")
        if megabytes > SIZE_BUDGET_MB:
            raise BuildError(f"{out.name} is {megabytes:.1f} MB, over its {SIZE_BUDGET_MB} MB budget")
        partial.replace(out)
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
