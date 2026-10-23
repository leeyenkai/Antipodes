#!/usr/bin/env python3
"""Download the OpenStreetMap data the route pack is built from (D-36).

OpenStreetMap is licensed under the ODbL, whose share-alike terms would reach any
database it is mixed into, so none of it goes near ``places.sqlite`` (D-8). It is
fetched here, into ``vendor/osm/``, and built by ``build_osmpack.py`` into a separate
file, ``routes-osm.sqlite``, that the app bundles beside the place database.

This is the only part of the pack pipeline that touches the network. Everything comes
from the Overpass API, one query at a time, with the project's user agent and a pause
between queries, as its usage policy asks. Each answer is written as it arrives and
recorded in ``vendor/osm/manifest.json`` with its query, size, digest and the day it
was retrieved, so an interrupted fetch picks up where it stopped and a build can say
which snapshot it rests on. OpenStreetMap changes by the minute; the manifest is the
only record of which day's map a pack holds.

What is fetched, all named in ``curation/``:

* **transit** — the metro, tram, light-rail and monorail lines of each city in
  ``cities.csv``, with their stops, the ways that draw them and the route masters that
  carry a line's Wikidata identity; and, for the cities with a bus radius, their bus and
  trolleybus lines the same way.
* **lifts** — every passenger aerial lift in the world (cable cars, gondolas, chair
  lifts), with its stations.
* **routes** — the relations in ``routes.csv`` that draw the catalogue routes.
* **trails** — the signed hiking and cycling route relations in the regions of
  ``regions.csv``, with the ways that draw them, tile by tile.

The public server answers a small query in about half a minute and lets one client run
two at once, so a fetch takes hours. Run two parts side by side to use both::

    python3 -I fetch_osm.py --only routes --only lifts --only transit &
    python3 -I fetch_osm.py --only trails

Usage::

    python3 -I fetch_osm.py                  # fill any gaps in the cache
    python3 -I fetch_osm.py --only transit   # one part: transit, lifts, routes, trails
    python3 -I fetch_osm.py --refresh        # ask everything again
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).parent
CURATION = HERE / "curation"
VENDOR = HERE / "vendor" / "osm"
MANIFEST = VENDOR / "manifest.json"

ENDPOINT = "https://overpass-api.de/api/interpreter"
USER_AGENT = (
    "Antipodes-osmpack/1.0 (+https://github.com/leeyenkai/Antipodes; "
    "builds an offline route pack for a travel logger)"
)
LICENCE = "ODbL-1.0"

#: Seconds between queries, and the base of the back-off after a refusal.
PAUSE_SECONDS = 3.0
ATTEMPTS = 8
#: Gateway timeouts in a row after which a tile is asked in quarters instead.
TIMEOUTS_BEFORE_SPLIT = 2
#: What each query declares it needs. Overpass admits a query only once this much time
#: and memory are free, so asking for more than the defaults only waits longer; a tile
#: that needs more is split instead.
TIMEOUT = 300
#: How many times a tile Overpass cannot answer is split in four before giving up.
MAX_SPLITS = 3

RAIL_MODES = "subway|light_rail|tram|monorail"
BUS_MODES = "bus|trolleybus"
LIFT_KINDS = "cable_car|gondola|chair_lift|mixed_lift"
HIKING = "hiking|foot"
CYCLING = "bicycle|mtb"
#: Local networks are left out of the trail networks: they are every village path.
LOCAL_NETWORKS = "lwn|lcn"


class FetchError(Exception):
    """A query failed in a way that should stop the fetch."""


class TooBig(Exception):
    """Overpass ran out of time or memory: the area should be asked in smaller pieces."""


# ------------------------------------------------------------------------- curation


def rows(name: str) -> list[dict[str, str]]:
    path = CURATION / name
    lines = [
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    return list(csv.DictReader(lines))


@dataclass(frozen=True)
class Box:
    south: float
    west: float
    north: float
    east: float

    def overpass(self) -> str:
        return f"{self.south:.4f},{self.west:.4f},{self.north:.4f},{self.east:.4f}"

    def name(self) -> str:
        return f"{self.south:+08.3f}_{self.west:+09.3f}_{self.north:+08.3f}_{self.east:+09.3f}"

    def quarters(self) -> list[Box]:
        mid_lat = (self.south + self.north) / 2
        mid_lon = (self.west + self.east) / 2
        return [
            Box(self.south, self.west, mid_lat, mid_lon),
            Box(self.south, mid_lon, mid_lat, self.east),
            Box(mid_lat, self.west, self.north, mid_lon),
            Box(mid_lat, mid_lon, self.north, self.east),
        ]


def circle(latitude: float, longitude: float, radius_km: float) -> Box:
    """The box around a city's circle; Overpass filters by box, not by distance."""
    dlat = radius_km / 111.32
    dlon = radius_km / (111.32 * max(math.cos(math.radians(latitude)), 0.01))
    return Box(latitude - dlat, longitude - dlon, latitude + dlat, longitude + dlon)


def tiles(region: dict[str, str]) -> list[Box]:
    step = float(region["tile_deg"])
    south, west = float(region["south"]), float(region["west"])
    north, east = float(region["north"]), float(region["east"])
    boxes = []
    lat = south
    while lat < north:
        lon = west
        while lon < east:
            boxes.append(Box(lat, lon, min(lat + step, north), min(lon + step, east)))
            lon += step
        lat += step
    return boxes


# -------------------------------------------------------------------------- queries


def transit_query(box: Box, modes: str) -> str:
    """Lines with their members, the route masters above them, their ways and stops."""
    return f"""[out:json][timeout:{TIMEOUT}][maxsize:536870912];
rel[type=route][route~"^({modes})$"]({box.overpass()})->.lines;
.lines out body qt;
rel(br.lines)[type=route_master];
out body qt;
way(r.lines);
out skel geom qt;
node(r.lines);
out body qt;
"""


def lifts_query() -> str:
    return f"""[out:json][timeout:{TIMEOUT}][maxsize:536870912];
way[aerialway~"^({LIFT_KINDS})$"]->.lifts;
.lifts out tags geom qt;
node(w.lifts)[aerialway=station];
out body qt;
"""


def route_query(relation: int) -> str:
    return f"""[out:json][timeout:{TIMEOUT}][maxsize:536870912];
rel(id:{relation})->.routes;
.routes out body qt;
way(r.routes);
out skel geom qt;
node(r.routes);
out body qt;
"""


def trails_query(box: Box) -> str:
    """Signed, non-local hiking and cycling routes, and their ways within the tile.

    The relations come with their members, so the build can tell a hiking way from a
    cycling one; the ways are cut to the tile, and a way on a tile's edge, fetched with
    both tiles, is kept once.
    """
    return f"""[out:json][timeout:{TIMEOUT}][maxsize:536870912];
rel[type=route][route~"^({HIKING}|{CYCLING})$"][network!~"^({LOCAL_NETWORKS})$"]({box.overpass()})->.routes;
.routes out body qt;
way(r.routes)({box.overpass()});
out skel geom qt;
"""


# ---------------------------------------------------------------------------- fetch


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            sha.update(block)
    return sha.hexdigest()


def today() -> str:
    return dt.datetime.now(dt.UTC).date().isoformat()


def overpass(query: str, *, splittable: bool = False) -> bytes:
    """Runs a query, backing off on refusals and raising `TooBig` on a timeout."""
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    last: Exception | None = None
    timeouts = 0
    for attempt in range(ATTEMPTS):
        request = urllib.request.Request(
            ENDPOINT, data=body, headers={"User-Agent": USER_AGENT}
        )
        try:
            with urllib.request.urlopen(request, timeout=1000) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            last = error
            # The gateway gives up on long queries before Overpass does, with a 504 or
            # a 502; twice in a row means the area is too big rather than the server
            # too busy.
            timeouts = timeouts + 1 if error.code in (502, 504) else 0
            if timeouts >= TIMEOUTS_BEFORE_SPLIT and splittable:
                raise TooBig(f"gateway timeout {timeouts} times") from error
            if error.code in (429, 502, 503, 504):
                wait = PAUSE_SECONDS * 10 * (attempt + 1)
                print(f"      Overpass answered {error.code}; waiting {wait:.0f}s", flush=True)
                time.sleep(wait)
                continue
            raise FetchError(f"Overpass refused the query: {error}") from error
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            last = error
            wait = PAUSE_SECONDS * 10 * (attempt + 1)
            print(f"      connection failed ({error}); waiting {wait:.0f}s", flush=True)
            time.sleep(wait)
            continue
        # Overpass reports a query it gave up on inside a 200 answer.
        head = raw[:4000].decode("utf-8", "replace") + raw[-4000:].decode("utf-8", "replace")
        if '"remark"' in head and ("timed out" in head or "out of memory" in head):
            raise TooBig(head[head.find('"remark"'):][:200])
        return raw
    raise FetchError(f"Overpass failed after {ATTEMPTS} attempts: {last}")


class Cache:
    def __init__(self, refresh: bool) -> None:
        self.refresh = refresh
        self.manifest = (
            json.loads(MANIFEST.read_text(encoding="utf-8"))
            if MANIFEST.exists()
            else {"endpoint": ENDPOINT, "licence": LICENCE, "files": {}}
        )

    def has(self, relative: str) -> bool:
        return not self.refresh and (VENDOR / relative).exists()

    def store(self, relative: str, query: str, raw: bytes) -> None:
        path = VENDOR / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_suffix(path.suffix + ".partial")
        partial.write_bytes(raw)
        partial.replace(path)
        self.manifest["files"][relative] = {
            "query_sha256": hashlib.sha256(query.encode("utf-8")).hexdigest(),
            "sha256": digest(path),
            "bytes": path.stat().st_size,
            "retrieved": today(),
        }
        self.save()

    def save(self) -> None:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(
            json.dumps(self.manifest, sort_keys=True, indent=1) + "\n", encoding="utf-8"
        )

    def fetch(self, relative: str, query: str, *, splittable: bool = False) -> bool:
        """True if it asked Overpass, False if the cache already held the answer."""
        if self.has(relative):
            return False
        raw = overpass(query, splittable=splittable)
        self.store(relative, query, raw)
        print(f"      {relative}: {len(raw) / 1e6:.1f} MB", flush=True)
        time.sleep(PAUSE_SECONDS)
        return True


def fetch_box(cache: Cache, folder: str, box: Box, make_query, depth: int = 0) -> None:
    """Fetches one tile, splitting it in four while Overpass cannot answer it whole."""
    relative = f"{folder}/{box.name()}.json"
    if cache.has(relative):
        return
    # A tile that was split is recorded by its quarters; skip it if they are all there.
    if all(cache.has(f"{folder}/{q.name()}.json") for q in box.quarters()):
        return
    try:
        cache.fetch(relative, make_query(box), splittable=depth < MAX_SPLITS)
    except TooBig as reason:
        if depth >= MAX_SPLITS:
            raise FetchError(f"{relative} is still too big after {depth} splits: {reason}")
        print(f"      {relative} too big; splitting", flush=True)
        for quarter in box.quarters():
            fetch_box(cache, folder, quarter, make_query, depth + 1)


def fetch_transit(cache: Cache) -> None:
    cities = rows("cities.csv")
    for index, city in enumerate(cities, 1):
        latitude, longitude = float(city["latitude"]), float(city["longitude"])
        print(f"    [{index}/{len(cities)}] {city['name']}", flush=True)
        rail = circle(latitude, longitude, float(city["radius_km"]))
        fetch_box(cache, f"transit/rail/{city['slug']}", rail, lambda b: transit_query(b, RAIL_MODES))
        if city["bus_radius_km"]:
            bus = circle(latitude, longitude, float(city["bus_radius_km"]))
            fetch_box(cache, f"transit/bus/{city['slug']}", bus, lambda b: transit_query(b, BUS_MODES))


def fetch_lifts(cache: Cache) -> None:
    print("    the world's passenger lifts", flush=True)
    cache.fetch("lifts/world.json", lifts_query())


def fetch_routes(cache: Cache) -> None:
    relations = sorted(
        {int(r) for row in rows("routes.csv") for r in row["relations"].split()}
    )
    print(f"    {len(relations)} catalogue relations", flush=True)
    for relation in relations:
        cache.fetch(f"routes/{relation}.json", route_query(relation))


def fetch_trails(cache: Cache) -> None:
    for region in rows("regions.csv"):
        boxes = tiles(region)
        print(f"    {region['name']}: {len(boxes)} tiles", flush=True)
        for index, box in enumerate(boxes, 1):
            if index % 10 == 0:
                print(f"      {index}/{len(boxes)}", flush=True)
            fetch_box(cache, f"trails/{region['id']}", box, trails_query)


PARTS = {
    "routes": fetch_routes,
    "lifts": fetch_lifts,
    "transit": fetch_transit,
    "trails": fetch_trails,
}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Ask everything again.")
    parser.add_argument(
        "--only",
        action="append",
        choices=sorted(PARTS),
        help="Fetch just this part; repeatable.",
    )
    arguments = parser.parse_args(argv)
    cache = Cache(arguments.refresh)
    try:
        for name, fetch in PARTS.items():
            if arguments.only and name not in arguments.only:
                continue
            print(f"==> OpenStreetMap {name} ({LICENCE})", flush=True)
            fetch(cache)
    except FetchError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        cache.save()
    total = sum(entry["bytes"] for entry in cache.manifest["files"].values())
    print(f"\n==> Cache ready in {VENDOR}: {len(cache.manifest['files'])} files, {total / 1e9:.2f} GB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
