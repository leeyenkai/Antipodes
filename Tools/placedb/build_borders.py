#!/usr/bin/env python3
"""Build the bundled country-border file the globe screen draws (R-GLOBE-2).

Reads a Natural Earth *Admin 0 – Countries* GeoJSON and writes a compact binary
``.antborders`` file. Natural Earth is public domain, which is why it is the source
here: the ODbL share-alike question for a shipped derived database is still unresolved
(R-DB-7), so OpenStreetMap geometry is not cleared for release and must not end up in
the bundle. See [SOURCES.md](SOURCES.md).

The borders are deliberately *not* a table in ``places.sqlite``. The globe needs every
visible polygon on every frame rather than a query, and keeping the geometry in its own
file lets the pure ``AntipodesGlobe`` module decode it without depending on
``AntipodesPlaces`` (decision D-5).

Same two properties as the place-database pipeline, and for the same reasons:

* **Deterministic.** Same input, byte-identical output. Countries are sorted, rings keep
  their source order, and coordinates are rounded with a fixed rule.
* **Nothing guessed.** A feature whose ISO 3166-1 alpha-2 code cannot be resolved is
  written *unkeyed*: it is still drawn, so the coastline is right, but nothing can ever
  shade it, because no visit can refer to it. The count of those is in the header so the
  app can report what it could not key rather than quietly dropping land.

Usage::

    python3 build_borders.py --geojson vendor/naturalearth/ne_110m_admin_0_countries.geojson \\
        --scale 110 --out out/borders-110m.antborders
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

FORMAT_VERSION = 1
MAGIC = b"ANTB"

# Coordinates are stored as signed micro-degrees: 1e-6 degrees is about 11 cm, far
# finer than any Natural Earth scale, so the quantisation is lossless in practice and
# an integer encoding keeps the file byte-identical across rebuilds.
COORDINATE_SCALE = 1_000_000

RING_OUTER = 0
RING_HOLE = 1

# Natural Earth's continent names mapped to the app's `Continent` cases. Written as the
# enum's raw value rather than an index, so reordering the Swift enum cannot silently
# move every country to another continent.
CONTINENTS = {
    "Africa": "africa",
    "Antarctica": "antarctica",
    "Asia": "asia",
    "Europe": "europe",
    "North America": "northAmerica",
    "Oceania": "oceania",
    "South America": "southAmerica",
    # Natural Earth files the scattered ocean possessions (Bouvet Island, the French
    # Southern Territories) under this. There is no seventh-continent answer for them,
    # and guessing one would corrupt the continent coverage stat, so they stay unknown.
    "Seven seas (open ocean)": "",
}

# Natural Earth writes -99 where it has no ISO code for a feature.
NO_ISO = {None, "", "-99"}


class BuildError(Exception):
    """A problem in the input data. Fails the build rather than writing bad geometry."""


@dataclass(frozen=True)
class Ring:
    role: int
    points: tuple[tuple[int, int], ...]  # (latitude, longitude) in micro-degrees

    @property
    def bounding_box(self) -> tuple[int, int, int, int]:
        latitudes = [point[0] for point in self.points]
        longitudes = [point[1] for point in self.points]
        return (min(latitudes), min(longitudes), max(latitudes), max(longitudes))


@dataclass(frozen=True)
class Country:
    key: str  # ISO 3166-1 alpha-2, or "" when Natural Earth has no code for it
    name: str
    continent: str
    rings: tuple[Ring, ...]

    @property
    def bounding_box(self) -> tuple[int, int, int, int]:
        boxes = [ring.bounding_box for ring in self.rings]
        return (
            min(box[0] for box in boxes),
            min(box[1] for box in boxes),
            max(box[2] for box in boxes),
            max(box[3] for box in boxes),
        )


def micro(degrees: float) -> int:
    """Degrees to micro-degrees, rounded the same way every time."""
    if not isinstance(degrees, (int, float)):
        raise BuildError(f"coordinate is not a number: {degrees!r}")
    value = round(degrees * COORDINATE_SCALE)
    return int(value)


def iso_code(properties: dict) -> str:
    """The feature's ISO 3166-1 alpha-2 code, or "" if it genuinely has none.

    Natural Earth puts -99 in ``ISO_A2`` for a handful of countries whose code is
    disputed or administratively odd (Norway and France among them), and sometimes a
    value that is not an alpha-2 code at all — it files Taiwan as ``CN-TW``. The usable
    code is in ``ISO_A2_EH``, so each field is taken only when it is a well-formed
    alpha-2 code and skipped otherwise.

    What survives this is unkeyed: at 1:50m that is Northern Cyprus, Somaliland and the
    Siachen Glacier. Which of those should count as a country is exactly what Q-4 is
    about, and the answer is not this script's to invent. Kosovo keeps ``XK``, which is
    user-assigned rather than official ISO 3166-1, for the same reason: it is the code
    the rest of the pipeline uses, and whether it counts is Q-4's call.
    """
    for field in ("ISO_A2", "ISO_A2_EH"):
        candidate = properties.get(field)
        if candidate in NO_ISO:
            continue
        code = str(candidate).strip().upper()
        if len(code) == 2 and code.isascii() and code.isalpha():
            return code
    return ""


def continent_of(properties: dict, name: str) -> str:
    raw = properties.get("CONTINENT")
    if raw not in CONTINENTS:
        raise BuildError(f"{name}: unknown Natural Earth continent {raw!r}")
    return CONTINENTS[raw]


def rings_of(geometry: dict, name: str) -> tuple[Ring, ...]:
    kind = geometry.get("type")
    if kind == "Polygon":
        polygons = [geometry["coordinates"]]
    elif kind == "MultiPolygon":
        polygons = geometry["coordinates"]
    else:
        raise BuildError(f"{name}: unsupported geometry type {kind!r}")

    rings: list[Ring] = []
    for polygon in polygons:
        for index, ring in enumerate(polygon):
            if len(ring) < 4:
                raise BuildError(f"{name}: ring with only {len(ring)} points")
            points = tuple((micro(point[1]), micro(point[0])) for point in ring)
            for latitude, longitude in points:
                if not -90 * COORDINATE_SCALE <= latitude <= 90 * COORDINATE_SCALE:
                    raise BuildError(f"{name}: latitude out of range: {latitude}")
                if not -180 * COORDINATE_SCALE <= longitude <= 180 * COORDINATE_SCALE:
                    raise BuildError(f"{name}: longitude out of range: {longitude}")
            # The first ring of a GeoJSON polygon is its outline; the rest are holes,
            # which is how South Africa gets a Lesotho-shaped gap in it.
            rings.append(Ring(RING_OUTER if index == 0 else RING_HOLE, points))
    return tuple(rings)


def read_countries(path: Path) -> list[Country]:
    try:
        with path.open(encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot read {path}: {error}") from error

    features = document.get("features")
    if not isinstance(features, list) or not features:
        raise BuildError(f"{path} has no features")

    countries: list[Country] = []
    for feature in features:
        properties = feature.get("properties") or {}
        name = str(properties.get("ADMIN") or properties.get("NAME") or "").strip()
        if not name:
            raise BuildError("a feature has no ADMIN or NAME")
        countries.append(
            Country(
                key=iso_code(properties),
                name=name,
                continent=continent_of(properties, name),
                rings=rings_of(feature.get("geometry") or {}, name),
            )
        )

    # Sorted so the output never depends on the order the source happens to use. Two
    # features can share an ISO code — at 1:50m, Australia's Indian Ocean Territories
    # and Ashmore and Cartier Islands both resolve to AU — so the name breaks the tie
    # and keeps the sort total. Shading matches on the key, so all of a country's
    # records shade together.
    countries.sort(key=lambda country: (country.key, country.name))
    return countries


def encode(countries: list[Country], scale: int) -> bytes:
    total_points = sum(len(ring.points) for country in countries for ring in country.rings)
    unkeyed = sum(1 for country in countries if not country.key)

    out = bytearray()
    out += MAGIC
    out += struct.pack(
        "<HHIIII",
        FORMAT_VERSION,
        scale,
        len(countries),
        unkeyed,
        total_points,
        0,  # reserved
    )

    for country in countries:
        name = country.name.encode("utf-8")
        continent = country.continent.encode("ascii")
        if len(name) > 255:
            raise BuildError(f"name too long to encode: {country.name}")
        key = country.key.encode("ascii") if country.key else b"\0\0"
        out += key
        out += struct.pack("<B", len(continent))
        out += continent
        out += struct.pack("<B", len(name))
        out += name
        out += struct.pack("<H", len(country.rings))
        out += struct.pack("<iiii", *country.bounding_box)
        for ring in country.rings:
            out += struct.pack("<BI", ring.role, len(ring.points))
            out += struct.pack("<iiii", *ring.bounding_box)
            for latitude, longitude in ring.points:
                out += struct.pack("<ii", latitude, longitude)

    return bytes(out)


@dataclass(frozen=True)
class Counts:
    countries: int
    unkeyed: int
    rings: int
    points: int

    def summary(self) -> str:
        return (
            f"{self.countries} countries ({self.unkeyed} with no ISO code), "
            f"{self.rings} rings, {self.points} points"
        )


def build(geojson: Path, out: Path, scale: int) -> Counts:
    countries = read_countries(geojson)
    payload = encode(countries, scale)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(payload)
    return Counts(
        countries=len(countries),
        unkeyed=sum(1 for country in countries if not country.key),
        rings=sum(len(country.rings) for country in countries),
        points=sum(len(ring.points) for country in countries for ring in country.rings),
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--geojson", type=Path, required=True)
    parser.add_argument(
        "--scale",
        type=int,
        required=True,
        help="Natural Earth scale denominator in millions: 110 or 50.",
    )
    parser.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args(argv)

    if arguments.scale not in (110, 50):
        print(f"error: unsupported scale {arguments.scale}", file=sys.stderr)
        return 1

    try:
        counts = build(arguments.geojson, arguments.out, arguments.scale)
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    digest = hashlib.sha256(arguments.out.read_bytes()).hexdigest()[:16]
    size_kb = arguments.out.stat().st_size / 1024
    print(f"Built {arguments.out}")
    print(f"  {counts.summary()}")
    print(f"  {size_kb:.1f} KB, sha256:{digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
