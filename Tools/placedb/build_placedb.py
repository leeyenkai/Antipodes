#!/usr/bin/env python3
"""Build the read-only Antipodes place database from the cached open-data sources.

Reads the files ``fetch_sources.py`` put in ``vendor/`` plus the deliberate human input
in ``curation/``, and writes a SQLite file with FTS5 search indexes (R-DB-4).

* Countries, ISO codes and the sovereignty classification — Natural Earth (public domain)
* Country facts, regions, cities, elevations, time zones — GeoNames (CC BY 4.0)
* Airports and their codes — OurAirports (public domain)
* Landmark facts, UNESCO status, UN membership — Wikidata (CC0)
* Which landmarks and routes exist, and their theme tags — ``curation/``

No network access: everything comes from the cache, so a rebuild is offline and
reproducible from a known set of inputs. Run ``fetch_sources.py`` first.

Two properties matter and are tested:

* **Deterministic.** Same cache, byte-identical output. Everything is sorted and no
  step depends on dict or filesystem ordering, so a rebuild that changes the file means
  the inputs changed. ``--built-at`` defaults to a fixed string for the same reason.
* **Nothing guessed.** A missing attribute is written as NULL and the app reports
  coverage rather than showing an invented number (R-DB-2). The build fails rather than
  writing a wrong row: on an unknown country code, an out-of-range coordinate, a
  duplicate IATA code, a landmark with no theme tag (R-DB-1), a theme outside the
  taxonomy, a curated landmark whose Wikidata label or country does not match what the
  curation file says, or a UN member total that is not 193.

Usage::

    python3 build_placedb.py --out out/places.sqlite
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sqlite3
import sys
import unicodedata
import zipfile
from dataclasses import dataclass, field as dataclass_field
from pathlib import Path

HERE = Path(__file__).parent

# Run under `python3 -I`, which keeps a module planted in the working directory from
# being imported — worth having in a pipeline whose job is reading downloaded files.
# Isolated mode also drops the script's own directory, so `sources` needs this.
sys.path.insert(0, str(HERE))

import sources as registry  # noqa: E402 - must follow the sys.path line above

SCHEMA_VERSION = 2

#: The UN has 193 member states. Wikidata's own modelling yields 192 ISO 3166-1 codes
#: and `curation/un_membership.csv` reconciles the difference, so asserting the total
#: here is what stops an upstream change quietly moving the "% of the world"
#: denominator (Q-4).
EXPECTED_UN_MEMBERS = 193

# Search ranking has two parts, and the split matters (R-LOG-1).
#
# `kind_rank` breaks ties between rows that match the query *exactly*: "Singapore"
# should offer the country before the city, and "Oslo" the city before the region,
# because that is what someone logging travel almost always means.
#
# `prominence` orders everything else, and is deliberately on **one scale across
# kinds** rather than a per-kind tier. An earlier version multiplied the kind rank by
# a billion, which made every country outrank every city — so typing "par" offered
# Paraguay before Paris. A single scale lets a famous city beat an obscure country,
# which is what a traveller means.
#
# The numbers below are "how likely is someone searching for this", not raw size:
#
# * A **country** sits near 1,000,000 — above a mid-sized city, below a famous one —
#   with population only as a tiebreak between countries. Searching travel, a country
#   is not a thousand times more likely to be meant than its capital.
# * A **city** uses population directly, which is the one honest popularity signal in
#   the data, nudged for capitals.
# * A **landmark** uses its Wikipedia language-edition count, a measured fame signal.
# * An **airport** uses OurAirports' size class; no cleared source carries traffic.
KIND_RANK = {
    "country": 6,
    "city": 5,
    "region": 4,
    "airport": 3,
    "landmark": 2,
    "route": 1,
}

COUNTRY_BASE_PROMINENCE = 1_000_000
CAPITAL_PROMINENCE_BONUS = 250_000
# A region has no population of its own in GeoNames' admin1 file, so its
# prominence is the summed population of the cities this database bundles inside
# it. That is an aggregate of sourced figures rather than an invented one, and it
# is used only for search ranking, never shown as a statistic.
#
# A flat value was tried first and was wrong in both directions: high enough to
# clear the exact-match floor, an obscure Montenegrin municipality called Bar
# outranked Barcelona; low enough to stay below it, Oslo the county fell behind
# Oslo Airport. The real aggregate puts each region where it belongs.
#
# It is then divided by ten, because a region is a less likely search target than
# a city of the same population. Undamped, the Brazilian states of Paraná, Pará
# and Paraíba — eleven, eight and four million between their cities — all pushed
# Paris off the top of a search for "par".
REGION_PROMINENCE_DAMPING = 10
ROUTE_PROMINENCE = 40_000
LANDMARK_BASE_PROMINENCE = 20_000
LANDMARK_PROMINENCE_PER_SITELINK = 8_000
LANDMARK_UNESCO_BONUS = 40_000
AIRPORT_PROMINENCE = {
    "large_airport": 900_000,
    "medium_airport": 250_000,
    "small_airport": 70_000,
}
AIRPORT_SCHEDULED_BONUS = 100_000


# GeoNames' one-or-two-letter continent code to the app's `Continent` cases. GeoNames
# assigns one to every territory in countryInfo.txt, which Natural Earth's 1:110m layer
# does not, so this is the source for the column.
CONTINENTS = {
    "AF": "africa",
    "AN": "antarctica",
    "AS": "asia",
    "EU": "europe",
    "NA": "northAmerica",
    "OC": "oceania",
    "SA": "southAmerica",
}

# Natural Earth's TYPE field, narrowed to the four values the app cares about.
COUNTRY_STATUS = {
    "Sovereign country": "sovereign",
    "Country": "sovereign",
    "Dependency": "dependency",
    "Disputed": "disputed",
    "Indeterminate": "disputed",
    "Lease": "other",
    "Sovereignty": "other",
}

# Natural Earth writes -99 where it has no ISO code for a feature.
NO_ISO = {None, "", "-99"}

# OurAirports rows worth offering a traveller: the ones with a size class a scheduled
# flight could use, plus anything carrying an IATA code. Heliports, seaplane bases,
# balloonports and the 13,574 closed fields are left out — 9,763 rows instead of 86,258,
# which is most of the Q-5 size budget saved on places nobody logs a trip through.
AIRPORT_KINDS = {"large_airport", "medium_airport"}

FEET_TO_METRES = 0.3048


class BuildError(Exception):
    """A problem in the input data. Fails the build rather than writing bad rows."""


@dataclass
class Counts:
    countries: int = 0
    regions: int = 0
    cities: int = 0
    landmarks: int = 0
    airports: int = 0
    routes: int = 0
    indexed: int = 0

    def summary(self) -> str:
        return (
            f"{self.countries} countries, {self.regions} regions, {self.cities} cities, "
            f"{self.landmarks} landmarks, {self.airports} airports, "
            f"{self.routes} routes, {self.indexed} searchable rows"
        )


@dataclass
class Coverage:
    """What the build could not fill in, so the report can say so out loud.

    AGENTS.md §7: no stat may silently skip records. The same goes for the pipeline that
    feeds them — a column that is mostly NULL is something to know before shipping.
    """

    notes: list[str] = dataclass_field(default_factory=list)

    def record(self, label: str, present: int, total: int) -> None:
        if total == 0:
            return
        percent = 100.0 * present / total
        self.notes.append(f"{label}: {present}/{total} ({percent:.1f}%)")


# --------------------------------------------------------------------------- helpers


def text(value: str | None) -> str | None:
    """Empty and whitespace-only become NULL, never the empty string.

    One representation of "unknown" keeps the app's coverage reporting honest.
    """
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def integer(value: str | None, *, field: str, row: str) -> int | None:
    stripped = text(value)
    if stripped is None:
        return None
    try:
        return int(stripped)
    except ValueError as error:
        raise BuildError(f"{row}: {field} is not a whole number: {stripped!r}") from error


def real(value: str | None, *, field: str, row: str) -> float | None:
    stripped = text(value)
    if stripped is None:
        return None
    try:
        return float(stripped)
    except ValueError as error:
        raise BuildError(f"{row}: {field} is not a number: {stripped!r}") from error


def required_real(value: str | None, *, field: str, row: str) -> float:
    result = real(value, field=field, row=row)
    if result is None:
        raise BuildError(f"{row}: {field} is required")
    return result


def check_coordinate(latitude: float, longitude: float, *, row: str) -> None:
    if not -90 <= latitude <= 90:
        raise BuildError(f"{row}: latitude {latitude} is out of range")
    if not -180 <= longitude <= 180:
        raise BuildError(f"{row}: longitude {longitude} is out of range")


def read_curation(name: str) -> list[dict[str, str]]:
    """Reads a curation CSV, skipping the `#` prose at the top."""
    path = HERE / "curation" / name
    if not path.exists():
        raise BuildError(f"Missing curation file: {path}")
    lines = [
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    rows = list(csv.DictReader(lines))
    if not rows:
        raise BuildError(f"Curation file has no rows: {path}")
    return rows


def read_vendor_tsv(source: str, name: str, *, columns: int) -> list[list[str]]:
    """Reads one of GeoNames' tab-separated dumps."""
    path = HERE / "vendor" / source / name
    if not path.exists():
        raise BuildError(f"Missing cached source file: {path}. Run fetch_sources.py.")
    rows: list[list[str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < columns:
            raise BuildError(f"{path}: expected {columns} columns, got {len(fields)}")
        rows.append(fields)
    if not rows:
        raise BuildError(f"Cached source file has no rows: {path}")
    return rows


def read_vendor_zip_tsv(source: str, archive: str, member: str, *, columns: int) -> list[list[str]]:
    path = HERE / "vendor" / source / archive
    if not path.exists():
        raise BuildError(f"Missing cached source file: {path}. Run fetch_sources.py.")
    rows: list[list[str]] = []
    with zipfile.ZipFile(path) as bundle:
        with bundle.open(member) as handle:
            for raw in handle.read().decode("utf-8").splitlines():
                if not raw:
                    continue
                fields = raw.split("\t")
                if len(fields) < columns:
                    raise BuildError(f"{member}: expected {columns} columns, got {len(fields)}")
                rows.append(fields)
    if not rows:
        raise BuildError(f"{archive}:{member} has no rows")
    return rows


def search_terms(*values: str | None) -> str:
    """Builds the text FTS5 indexes for a row.

    Includes an unaccented copy of every term so "Tromso" finds "Tromsø" even where the
    tokeniser's own folding falls short, and de-duplicates while keeping order so the
    output stays deterministic.
    """
    terms: list[str] = []
    for value in values:
        if not value:
            continue
        for part in str(value).replace(",", " ").split():
            for candidate in (part, strip_accents(part)):
                lowered = candidate.lower()
                if lowered and lowered not in terms:
                    terms.append(lowered)
    return " ".join(terms)


# Letters that NFKD does not decompose, so neither Python nor FTS5's
# `remove_diacritics` turns them into the ASCII a user actually types. Without these,
# "Tromso" never finds "Tromsø".
TRANSLITERATIONS = {
    "ø": "o",   # ø
    "æ": "ae",  # æ
    "å": "a",   # å
    "ß": "ss",  # ß
    "đ": "d",   # đ
    "ð": "d",   # ð
    "þ": "th",  # þ
    "ł": "l",   # ł
    "ı": "i",   # ı
    "ħ": "h",   # ħ
    "ö": "o",   # ö — decomposes, but listed so the table reads completely
    "ä": "a",   # ä
    "ü": "u",   # ü
}


def strip_accents(value: str) -> str:
    """ASCII-folds a term for the search index.

    Two steps, because they catch different things: transliteration handles letters
    that are their own Unicode character (ø, æ, ß), and NFKD handles combining marks
    (é, ã, ů).
    """
    lowered = value.lower()
    for source, replacement in TRANSLITERATIONS.items():
        lowered = lowered.replace(source, replacement)
    decomposed = unicodedata.normalize("NFKD", lowered)
    return "".join(char for char in decomposed if not unicodedata.combining(char))


def wikidata_year(timestamp: str | None) -> int | None:
    """Pulls the year out of a Wikidata time literal, keeping BC years negative.

    Wikidata writes ``+0080-01-01T00:00:00Z`` and ``-0500-01-01T00:00:00Z``. Only the
    year is kept: the month and day on an ancient inception date are padding, not
    knowledge, and R-DB-3 asks for a year.
    """
    if not timestamp:
        return None
    sign = -1 if timestamp.startswith("-") else 1
    body = timestamp.lstrip("+-")
    year_text = body.split("-", 1)[0]
    if not year_text.isdigit():
        return None
    year = int(year_text)
    return sign * year if year else None


def haversine_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    """Great-circle distance, used only to disambiguate same-named cities."""
    radius = 6371.0088
    phi1, phi2 = math.radians(a_lat), math.radians(b_lat)
    d_phi = phi2 - phi1
    d_lambda = math.radians(b_lon - a_lon)
    h = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(h))


# ------------------------------------------------------------------------- the build


def build(out_path: Path, cities_dataset: str, data_version: str, built_at: str) -> tuple[Counts, Coverage]:
    schema_path = HERE / "schema.sql"
    if not schema_path.exists():
        raise BuildError(f"Missing schema: {schema_path}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    connection = sqlite3.connect(out_path)
    try:
        connection.executescript(schema_path.read_text(encoding="utf-8"))
        counts = Counts()
        coverage = Coverage()

        manifest = write_data_sources(connection, cities_dataset)
        countries = insert_countries(connection, counts, coverage)
        regions = insert_regions(connection, countries, counts)
        by_name = insert_cities(
            connection, cities_dataset, countries, regions, counts, coverage
        )
        insert_landmarks(connection, countries, by_name, counts, coverage)
        insert_airports(connection, countries, by_name, counts, coverage)
        insert_routes(connection, counts)

        counts.indexed = build_search_index(connection)
        write_meta(connection, data_version, built_at, counts, coverage, manifest, cities_dataset)

        connection.commit()
        connection.execute("VACUUM")
        connection.commit()
        return counts, coverage
    finally:
        connection.close()


def write_data_sources(connection: sqlite3.Connection, cities_dataset: str) -> dict:
    """Writes the licence register into the artefact itself (R-DB-7).

    The app renders this in Settings, so a source cannot ship without its credit
    appearing there. Digests come from the fetch manifest, which is what lets a built
    database say which upstream snapshot it holds.
    """
    manifest_path = HERE / "vendor" / "manifest.json"
    if not manifest_path.exists():
        raise BuildError(
            f"Missing {manifest_path}. Run fetch_sources.py before building."
        )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    files: dict[str, dict] = manifest.get("files", {})

    cached = manifest.get("cities_dataset")
    if cached and cached != cities_dataset:
        raise BuildError(
            f"the cache holds {cached} but the build asked for {cities_dataset}; "
            f"run fetch_sources.py --cities {cities_dataset}"
        )

    for source in registry.all_sources(cities_dataset):
        # One digest per source: the files are fetched together and a single combined
        # digest over them, in sorted order, is what identifies the snapshot.
        digests = sorted(
            (name, entry)
            for name, entry in files.items()
            if name.startswith(f"{source.id}/")
        )
        combined: str | None = None
        retrieved: str | None = None
        if digests:
            sha = hashlib.sha256()
            for name, entry in digests:
                sha.update(f"{name}:{entry.get('sha256', '')}".encode())
            combined = sha.hexdigest()
            retrieved = max(entry.get("retrieved", "") for _, entry in digests) or None

        connection.execute(
            """
            INSERT INTO data_source (id, name, url, licence, licence_url, attribution,
                                     used_for, sha256, retrieved)
            VALUES (:id, :name, :url, :licence, :licence_url, :attribution,
                    :used_for, :sha256, :retrieved)
            """,
            {
                "id": source.id,
                "name": source.name,
                "url": source.url,
                "licence": source.licence,
                "licence_url": source.licence_url,
                "attribution": source.attribution,
                "used_for": source.used_for,
                "sha256": combined,
                "retrieved": retrieved,
            },
        )
    return manifest


def natural_earth_countries() -> dict[str, dict[str, str]]:
    """ISO2 -> Natural Earth classification, for the countries its 1:110m layer has."""
    path = HERE / "vendor" / "naturalearth" / "ne_110m_admin_0_countries.geojson"
    if not path.exists():
        raise BuildError(f"Missing cached source file: {path}. Run fetch_sources.py.")
    payload = json.loads(path.read_text(encoding="utf-8"))

    found: dict[str, dict[str, str]] = {}
    for feature in payload.get("features", []):
        properties = feature.get("properties", {})
        # ISO_A2 is -99 for Norway and France — a known Natural Earth quirk — while
        # ISO_A2_EH carries the right code, so that is read first.
        iso2 = None
        for key in ("ISO_A2_EH", "ISO_A2", "ADM0_ISO"):
            candidate = properties.get(key)
            if candidate not in NO_ISO and len(str(candidate)) == 2:
                iso2 = str(candidate)
                break
        if iso2 is None:
            # Northern Cyprus and Somaliland genuinely have no ISO 3166-1 code. They
            # are not countries the app can key a visit to, so they are skipped here
            # rather than given an invented code.
            continue
        found[iso2] = {
            "status": COUNTRY_STATUS.get(str(properties.get("TYPE")), "other"),
            "wikidata_qid": text(properties.get("WIKIDATAID")),
        }
    return found


def un_membership() -> tuple[set[str], set[str]]:
    """Current UN member and observer ISO2 codes, reconciled and then checked."""
    path = HERE / "vendor" / "wikidata" / "un_members.csv"
    if not path.exists():
        raise BuildError(f"Missing cached source file: {path}. Run fetch_sources.py.")
    members = {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()[1:]
        if line.strip()
    }
    observers: set[str] = set()

    for row in read_curation("un_membership.csv"):
        iso2 = text(row["iso2"])
        role = text(row["role"])
        if not iso2 or role not in {"member", "observer"}:
            raise BuildError(f"un_membership.csv: {row} needs an iso2 and a role")
        if not text(row.get("reason")):
            raise BuildError(f"un_membership.csv {iso2}: a reason is required")
        (members if role == "member" else observers).add(iso2)

    # Observers are not members; the lists must not overlap or "% of the world" counts
    # a state twice.
    overlap = members & observers
    if overlap:
        raise BuildError(
            f"un_membership.csv lists {', '.join(sorted(overlap))} as both member and observer"
        )
    if len(members) != EXPECTED_UN_MEMBERS:
        raise BuildError(
            f"expected {EXPECTED_UN_MEMBERS} UN member states, got {len(members)}. "
            "Wikidata's membership statements or ISO codes have changed; check "
            "queries/un_members.rq and curation/un_membership.csv before shipping, "
            "because this number is the '% of the world' denominator (Q-4)."
        )
    return members, observers


def insert_countries(
    connection: sqlite3.Connection, counts: Counts, coverage: Coverage
) -> dict[str, dict[str, object]]:
    """Countries and territories: GeoNames' ISO 3166-1 list, classified by Natural Earth.

    GeoNames' `countryInfo.txt` is the list because it covers every assigned ISO 3166-1
    code, including the small territories Natural Earth's 1:110m layer leaves out. The
    classification and Wikidata id come from Natural Earth where it has the code, and
    are NULL where it does not.
    """
    classification = natural_earth_countries()
    members, observers = un_membership()
    rows = read_vendor_tsv("geonames", "countryInfo.txt", columns=17)
    countries: dict[str, dict[str, object]] = {}

    with_status = 0
    for index, fields in enumerate(sorted(rows, key=lambda r: r[0]), start=1):
        iso2 = text(fields[0])
        label = f"countryInfo.txt {iso2 or '?'}"
        if not iso2 or len(iso2) != 2:
            raise BuildError(f"{label}: iso2 must be two characters")
        if iso2 in countries:
            raise BuildError(f"{label}: duplicate iso2")

        continent_code = text(fields[8])
        continent = CONTINENTS.get(continent_code or "")
        if continent is None:
            raise BuildError(f"{label}: unknown continent code {continent_code!r}")

        name = text(fields[4])
        if not name:
            raise BuildError(f"{label}: name is required")

        extra = classification.get(iso2, {})
        if extra.get("status"):
            with_status += 1

        record = {
            "id": index,
            "iso2": iso2,
            "iso3": text(fields[1]),
            "iso_numeric": text(fields[2]),
            "name": name,
            "continent": continent,
            "capital": text(fields[5]),
            "population": integer(fields[7], field="population", row=label),
            "area_km2": real(fields[6], field="area_km2", row=label),
            # GeoNames' countryInfo.txt carries no representative point, and inventing
            # one from a bounding box would be a guess. The globe's Natural Earth
            # border file is where country geometry lives (decision D-5).
            "latitude": None,
            "longitude": None,
            "currency_code": text(fields[10]),
            "languages": text(fields[15]),
            "status": extra.get("status"),
            "is_un_member": 1 if iso2 in members else 0,
            "is_un_observer": 1 if iso2 in observers else 0,
            "wikidata_qid": extra.get("wikidata_qid"),
            "source": "geonames",
        }
        countries[iso2] = record
        connection.execute(
            """
            INSERT INTO country (id, iso2, iso3, iso_numeric, name, continent, capital,
                                 population, area_km2, latitude, longitude,
                                 currency_code, languages, status, is_un_member,
                                 is_un_observer, wikidata_qid, source)
            VALUES (:id, :iso2, :iso3, :iso_numeric, :name, :continent, :capital,
                    :population, :area_km2, :latitude, :longitude, :currency_code,
                    :languages, :status, :is_un_member, :is_un_observer, :wikidata_qid,
                    :source)
            """,
            record,
        )
        counts.countries += 1

    unknown_members = sorted(members - set(countries))
    if unknown_members:
        raise BuildError(
            "UN member codes with no country row: " + ", ".join(unknown_members)
        )

    coverage.record("country sovereignty classification", with_status, counts.countries)
    return countries


def insert_regions(
    connection: sqlite3.Connection,
    countries: dict[str, dict[str, object]],
    counts: Counts,
) -> dict[str, dict[str, object]]:
    """First-level divisions from GeoNames, keyed by its own admin1 code.

    See the note on `region.code` in schema.sql for why this is GeoNames' code and not
    ISO 3166-2.
    """
    rows = read_vendor_tsv("geonames", "admin1CodesASCII.txt", columns=4)
    regions: dict[str, dict[str, object]] = {}

    for index, fields in enumerate(sorted(rows, key=lambda r: r[0]), start=1):
        code = text(fields[0])
        label = f"admin1CodesASCII.txt {code or '?'}"
        if not code or "." not in code:
            raise BuildError(f"{label}: code must look like 'IT.07'")
        if code in regions:
            raise BuildError(f"{label}: duplicate code")

        country_iso2 = code.split(".", 1)[0]
        if country_iso2 not in countries:
            # GeoNames keeps admin1 codes for a few territories its own countryInfo.txt
            # does not list. A region with no country cannot be keyed to a visit, so it
            # is skipped rather than given one.
            continue

        name = text(fields[1])
        if not name:
            raise BuildError(f"{label}: name is required")

        record = {
            "id": index,
            "code": code,
            "name": name,
            "country_iso2": country_iso2,
            # admin1CodesASCII.txt has no coordinates. The region's extent is in the
            # globe's border file, not here.
            "latitude": None,
            "longitude": None,
            "geonames_id": integer(fields[3], field="geonames_id", row=label),
            "source": "geonames",
        }
        regions[code] = record
        connection.execute(
            """
            INSERT INTO region (id, code, name, country_iso2, latitude, longitude,
                                geonames_id, source)
            VALUES (:id, :code, :name, :country_iso2, :latitude, :longitude,
                    :geonames_id, :source)
            """,
            record,
        )
        counts.regions += 1

    return regions


def insert_cities(
    connection: sqlite3.Connection,
    cities_dataset: str,
    countries: dict[str, dict[str, object]],
    regions: dict[str, dict[str, object]],
    counts: Counts,
    coverage: Coverage,
) -> dict[tuple[str, str], list[dict[str, object]]]:
    """Populated places from GeoNames.

    Returns an index from (country, folded name) to every city with that name, which is
    how landmarks and airports find their city without guessing between two places of
    the same name.
    """
    rows = read_vendor_zip_tsv(
        "geonames", f"{cities_dataset}.zip", f"{cities_dataset}.txt", columns=19
    )
    by_name: dict[tuple[str, str], list[dict[str, object]]] = {}

    with_elevation = 0
    with_timezone = 0
    with_region = 0
    with_population = 0

    # Sorted by GeoNames id, which is stable upstream, so row ids do not shuffle when a
    # place is renamed or its population revised.
    ordered = sorted(rows, key=lambda r: int(r[0]))
    for index, fields in enumerate(ordered, start=1):
        geonames_id = integer(fields[0], field="geonames_id", row="cities")
        name = text(fields[1])
        country_iso2 = text(fields[8])
        label = f"{cities_dataset} {geonames_id} {name or '?'}"
        if not name:
            raise BuildError(f"{label}: name is required")
        if country_iso2 not in countries:
            # A populated place in a territory countryInfo.txt does not list cannot be
            # keyed to a country, so it is left out rather than mis-filed.
            continue

        latitude = required_real(fields[4], field="latitude", row=label)
        longitude = required_real(fields[5], field="longitude", row=label)
        check_coordinate(latitude, longitude, row=label)

        admin1 = text(fields[10])
        region_code = f"{country_iso2}.{admin1}" if admin1 else None
        if region_code and region_code not in regions:
            # GeoNames carries admin1 codes it has no name for. Unknown, not invented.
            region_code = None

        # `elevation` is a recorded figure and `dem` a modelled one from SRTM/GTOPO30.
        # Preferring the recorded value and falling back to the model is still a
        # sourced number either way — but it is two methods in one column, which is
        # why the build reports its coverage rather than leaving it implied.
        elevation = integer(fields[15], field="elevation_m", row=label)
        if elevation is None:
            elevation = integer(fields[16], field="dem", row=label)

        population = integer(fields[14], field="population", row=label)
        timezone = text(fields[17])
        feature_code = text(fields[7])

        record = {
            "id": index,
            "name": name,
            "ascii_name": text(fields[2]),
            "country_iso2": country_iso2,
            "region_code": region_code,
            "latitude": latitude,
            "longitude": longitude,
            "population": population,
            "elevation_m": elevation,
            "timezone": timezone,
            "is_capital": 1 if feature_code == "PPLC" else 0,
            "feature_code": feature_code,
            "geonames_id": geonames_id,
            "source": "geonames",
        }
        # Indexed under both the local name and GeoNames' ASCII form, because the two
        # fold differently: Xi'an is "Xi’an" with a typographic apostrophe in `name`
        # and "Xi'an" with a plain one in `asciiname`, and only the latter is what
        # anyone types.
        for spelling in {strip_accents(name), strip_accents(record["ascii_name"] or name)}:
            by_name.setdefault((country_iso2, spelling), []).append(record)

        with_elevation += 1 if elevation is not None else 0
        with_timezone += 1 if timezone else 0
        with_region += 1 if region_code else 0
        with_population += 1 if population else 0

        connection.execute(
            """
            INSERT INTO city (id, name, ascii_name, country_iso2, region_code, latitude,
                              longitude, population, elevation_m, timezone, is_capital,
                              feature_code, geonames_id, source)
            VALUES (:id, :name, :ascii_name, :country_iso2, :region_code, :latitude,
                    :longitude, :population, :elevation_m, :timezone, :is_capital,
                    :feature_code, :geonames_id, :source)
            """,
            record,
        )
        counts.cities += 1

    coverage.record("city elevation", with_elevation, counts.cities)
    coverage.record("city time zone", with_timezone, counts.cities)
    coverage.record("city region", with_region, counts.cities)
    coverage.record("city population above zero", with_population, counts.cities)
    return by_name


def nearest_city(
    candidates: list[dict[str, object]], latitude: float, longitude: float
) -> dict[str, object]:
    """Picks between cities of the same name by distance to a known coordinate.

    Two hundred places share the name "Springfield". Choosing the most populous would
    be a guess about which one a landmark or airport belongs to; choosing the closest to
    its own coordinate uses a fact. Ties break on GeoNames id so the result is stable.
    """
    return min(
        candidates,
        key=lambda city: (
            round(
                haversine_km(
                    latitude, longitude, float(city["latitude"]), float(city["longitude"])
                ),
                6,
            ),
            int(city["geonames_id"]),  # type: ignore[arg-type]
        ),
    )


def theme_taxonomy() -> set[str]:
    themes = set()
    for row in read_curation("theme_taxonomy.csv"):
        theme = text(row["theme"])
        if not theme:
            raise BuildError("theme_taxonomy.csv: a row has no theme tag")
        themes.add(theme)
    return themes


def landmark_kinds() -> dict[str, tuple[int, str]]:
    """Wikidata class QID -> (priority, kind label)."""
    mapping: dict[str, tuple[int, str]] = {}
    for row in read_curation("landmark_kinds.csv"):
        class_qid = text(row["class_qid"])
        kind = text(row["kind"])
        if not class_qid or not kind:
            raise BuildError(f"landmark_kinds.csv: {row} needs a class_qid and a kind")
        mapping[class_qid] = (
            integer(row["priority"], field="priority", row=class_qid) or 0,
            kind,
        )
    return mapping


def insert_landmarks(
    connection: sqlite3.Connection,
    countries: dict[str, dict[str, object]],
    by_name: dict[tuple[str, str], list[dict[str, object]]],
    counts: Counts,
    coverage: Coverage,
) -> None:
    """Curated landmarks, with every fact taken from Wikidata.

    `curation/landmarks.csv` says which landmarks exist and what themes they carry
    (R-DB-1); the name, coordinate, year built, height and UNESCO status come from the
    cached Wikidata answer. The curated name and country are *expectations*: a mismatch
    fails the build, which is what stops a mistyped QID shipping the wrong place.
    """
    facts_path = HERE / "vendor" / "wikidata" / "landmarks.json"
    if not facts_path.exists():
        raise BuildError(f"Missing cached source file: {facts_path}. Run fetch_sources.py.")
    facts = {
        record["qid"]: record
        for record in json.loads(facts_path.read_text(encoding="utf-8"))
    }

    taxonomy = theme_taxonomy()
    kinds = landmark_kinds()
    curated = read_curation("landmarks.csv")

    # Curation mistakes are collected rather than raised one at a time: finding all
    # thirty bad rows in one run beats thirty runs, and every one of them has to be
    # fixed by hand anyway.
    problems: list[str] = []

    with_year = 0
    with_height = 0
    with_city = 0
    with_kind = 0
    unesco_count = 0

    ordered = sorted(curated, key=lambda r: (r["country_iso2"], r["name"], r["qid"]))
    for index, row in enumerate(ordered, start=1):
        qid = text(row["qid"])
        expected_name = text(row["name"])
        expected_country = text(row["country_iso2"])
        label = f"landmarks.csv {qid or '?'} {expected_name or '?'}"
        if not qid or not expected_name or not expected_country:
            raise BuildError(f"{label}: qid, name and country_iso2 are all required")

        record = facts.get(qid)
        if record is None:
            problems.append(
                f"{label}: no Wikidata facts cached. Run fetch_sources.py --only wikidata."
            )
            continue

        if record["label"] != expected_name:
            problems.append(
                f"{label}: Wikidata calls {qid} {record['label']!r}. Either the QID is "
                "wrong or the label changed upstream — check it rather than renaming."
            )
            continue

        city_name = text(row.get("city_name"))
        # Wikidata gives a list, because a landmark can sit in two countries at once:
        # Niagara Falls, the Matterhorn and Iguaçu Falls all do. The curation says
        # which side it is filed under, and the build only insists that Wikidata agrees
        # it is one of them.
        wikidata_countries = [code for code in record.get("country_codes", []) if code]
        if wikidata_countries and expected_country not in wikidata_countries:
            problems.append(
                f"{label}: Wikidata puts {qid} in {', '.join(wikidata_countries)}, "
                f"the curation says {expected_country}"
            )
            continue
        if not wikidata_countries and not city_name:
            # Wikidata has no country for a few items (the Amsterdam museums). The
            # curated city's own GeoNames country is a sound substitute, and requiring
            # the city means nothing is assumed.
            problems.append(
                f"{label}: Wikidata has no country for {qid}, so the curation must "
                "give a city_name to take one from"
            )
            continue
        country_iso2 = expected_country
        if country_iso2 not in countries:
            problems.append(f"{label}: unknown country {country_iso2!r}")
            continue

        if record.get("latitude") is None or record.get("longitude") is None:
            raise BuildError(f"{label}: Wikidata has no coordinate for {qid}")
        latitude = float(record["latitude"])
        longitude = float(record["longitude"])
        check_coordinate(latitude, longitude, row=label)

        themes = sorted(
            {theme.strip() for theme in (row.get("themes") or "").split(",") if theme.strip()}
        )
        if not themes:
            # R-DB-1: every landmark needs at least one theme or the personality stats
            # quietly under-count.
            raise BuildError(f"{label}: at least one theme tag is required")
        unknown = [theme for theme in themes if theme not in taxonomy]
        if unknown:
            problems.append(
                f"{label}: theme(s) {', '.join(unknown)} are not in "
                "curation/theme_taxonomy.csv"
            )
            continue

        # A landmark outside any city (the Grand Canyon) keeps a NULL city and still
        # counts its country and region (R-MODEL-6).
        city: dict[str, object] | None = None
        if city_name:
            candidates = by_name.get((country_iso2, strip_accents(city_name)))
            if not candidates:
                problems.append(
                    f"{label}: city {city_name!r} is not in the {country_iso2} city set"
                )
                continue
            city = nearest_city(candidates, latitude, longitude)

        mapped = sorted(
            (kinds[class_qid][0], kinds[class_qid][1], class_qid)
            for class_qid in record.get("classes", {})
            if class_qid in kinds
        )
        kind = mapped[0][1] if mapped else None

        year_built = wikidata_year(record.get("inception"))
        height = record.get("height_m")
        unesco = 1 if record.get("unesco") else 0

        with_year += 1 if year_built is not None else 0
        with_height += 1 if height is not None else 0
        with_city += 1 if city else 0
        with_kind += 1 if kind else 0
        unesco_count += unesco

        connection.execute(
            """
            INSERT INTO landmark (id, name, kind, city_id, country_iso2, region_code,
                                  latitude, longitude, year_built, era, height_m,
                                  unesco, themes, wikidata_qid, sitelinks, source)
            VALUES (:id, :name, :kind, :city_id, :country_iso2, :region_code,
                    :latitude, :longitude, :year_built, :era, :height_m,
                    :unesco, :themes, :wikidata_qid, :sitelinks, :source)
            """,
            {
                "id": index,
                "name": record["label"],
                "kind": kind,
                "city_id": city["id"] if city else None,
                "country_iso2": country_iso2,
                "region_code": city["region_code"] if city else None,
                "latitude": latitude,
                "longitude": longitude,
                "year_built": year_built,
                # Only the inception date is fetched, so an era is never derived.
                # R-DB-3 wants a year where known and an era where not; the era half
                # waits for a source that carries one.
                "era": None,
                "height_m": height,
                "unesco": unesco,
                "themes": ",".join(themes),
                "wikidata_qid": qid,
                "sitelinks": record.get("sitelinks"),
                "source": "wikidata",
            },
        )
        counts.landmarks += 1

    if problems:
        raise BuildError(
            f"{len(problems)} landmark(s) in curation/landmarks.csv need attention:\n  "
            + "\n  ".join(problems)
        )

    coverage.record("landmark year built", with_year, counts.landmarks)
    coverage.record("landmark height", with_height, counts.landmarks)
    coverage.record("landmark city", with_city, counts.landmarks)
    coverage.record("landmark kind", with_kind, counts.landmarks)
    coverage.record("landmark UNESCO listed", unesco_count, counts.landmarks)


def insert_airports(
    connection: sqlite3.Connection,
    countries: dict[str, dict[str, object]],
    by_name: dict[tuple[str, str], list[dict[str, object]]],
    counts: Counts,
    coverage: Coverage,
) -> None:
    """Airports from OurAirports, narrowed to the ones a traveller could fly through."""
    path = HERE / "vendor" / "ourairports" / "airports.csv"
    if not path.exists():
        raise BuildError(f"Missing cached source file: {path}. Run fetch_sources.py.")

    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise BuildError(f"{path} has no rows")

    kept = [
        row
        for row in rows
        if row["type"] != "closed"
        and (row["type"] in AIRPORT_KINDS or text(row.get("iata_code")))
    ]

    seen_iata: set[str] = set()
    with_iata = 0
    with_icao = 0
    with_city = 0
    with_elevation = 0

    # Sorted by OurAirports' own `ident`, which is unique and stable.
    ordered = sorted(kept, key=lambda r: r["ident"])
    for index, row in enumerate(ordered, start=1):
        name = text(row["name"])
        country_iso2 = text(row["iso_country"])
        iata = text(row.get("iata_code"))
        label = f"airports.csv {row['ident']} {iata or name or '?'}"
        if not name:
            raise BuildError(f"{label}: name is required")
        if country_iso2 not in countries:
            # OurAirports uses a handful of codes ISO 3166-1 does not assign. An airport
            # with no country cannot count towards coverage, so it is left out.
            continue
        if iata:
            if len(iata) != 3:
                raise BuildError(f"{label}: IATA code must be three letters")
            if iata in seen_iata:
                raise BuildError(f"{label}: duplicate IATA code")
            seen_iata.add(iata)

        latitude = required_real(row["latitude_deg"], field="latitude", row=label)
        longitude = required_real(row["longitude_deg"], field="longitude", row=label)
        check_coordinate(latitude, longitude, row=label)

        city_name = text(row.get("municipality"))
        city: dict[str, object] | None = None
        if city_name:
            candidates = by_name.get((country_iso2, strip_accents(city_name)))
            if candidates:
                city = nearest_city(candidates, latitude, longitude)
            # No match is common and fine: plenty of airports serve a town too small
            # for the bundled city set. The name is kept as text, the link is NULL, and
            # the coverage line below says how often that happens.

        elevation_ft = real(row.get("elevation_ft"), field="elevation_ft", row=label)
        elevation = round(elevation_ft * FEET_TO_METRES) if elevation_ft is not None else None
        icao = text(row.get("icao_code"))
        scheduled = 1 if text(row.get("scheduled_service")) == "yes" else 0

        with_iata += 1 if iata else 0
        with_icao += 1 if icao else 0
        with_city += 1 if city else 0
        with_elevation += 1 if elevation is not None else 0

        connection.execute(
            """
            INSERT INTO airport (id, iata, icao, name, city_id, city_name, country_iso2,
                                 region_code, latitude, longitude, elevation_m, kind,
                                 scheduled_service, source)
            VALUES (:id, :iata, :icao, :name, :city_id, :city_name, :country_iso2,
                    :region_code, :latitude, :longitude, :elevation_m, :kind,
                    :scheduled_service, :source)
            """,
            {
                "id": index,
                "iata": iata,
                "icao": icao,
                "name": name,
                "city_id": city["id"] if city else None,
                "city_name": city_name,
                "country_iso2": country_iso2,
                # OurAirports' own `iso_region` is ISO 3166-2, a different code space
                # from the GeoNames admin1 codes in `region`, so it is not written
                # here. The region comes from the linked city or stays unknown.
                "region_code": city["region_code"] if city else None,
                "latitude": latitude,
                "longitude": longitude,
                "elevation_m": elevation,
                "kind": text(row.get("type")),
                "scheduled_service": scheduled,
                "source": "ourairports",
            },
        )
        counts.airports += 1

    coverage.record("airport IATA code", with_iata, counts.airports)
    coverage.record("airport ICAO code", with_icao, counts.airports)
    coverage.record("airport city link", with_city, counts.airports)
    coverage.record("airport elevation", with_elevation, counts.airports)


def insert_routes(connection: sqlite3.Connection, counts: Counts) -> None:
    rows = read_curation("routes.csv")
    for index, row in enumerate(sorted(rows, key=lambda r: r["name"]), start=1):
        name = text(row["name"])
        label = f"routes.csv {name or '?'}"
        if not name:
            raise BuildError(f"{label}: name is required")

        connection.execute(
            """
            INSERT INTO route (id, name, mode, start_name, end_name, country_codes,
                               length_km, typical_duration_minutes, highest_point_m, source)
            VALUES (:id, :name, :mode, :start_name, :end_name, :country_codes,
                    :length_km, :typical_duration_minutes, :highest_point_m, :source)
            """,
            {
                "id": index,
                "name": name,
                "mode": text(row["mode"]),
                "start_name": text(row.get("start_name")),
                "end_name": text(row.get("end_name")),
                "country_codes": text(row.get("country_codes")),
                "length_km": real(row.get("length_km"), field="length_km", row=label),
                "typical_duration_minutes": integer(
                    row.get("typical_duration_minutes"),
                    field="typical_duration_minutes",
                    row=label,
                ),
                "highest_point_m": real(
                    row.get("highest_point_m"), field="highest_point_m", row=label
                ),
                "source": "antipodes-curation",
            },
        )
        counts.routes += 1


def build_search_index(connection: sqlite3.Connection) -> int:
    """Fills ``place_index`` and the FTS5 index over it.

    ``prominence`` decides ties in search, which is what makes "par" offer Paris before
    Parma (R-LOG-1). Scales differ per kind deliberately: a country outranks a city of
    the same name, and a famous landmark outranks an obscure one.
    """
    rows: list[tuple] = []

    for row in connection.execute(
        """
        SELECT id, iso2, iso3, name, continent, capital, population
        FROM country ORDER BY iso2
        """
    ):
        (cid, iso2, iso3, name, continent, _capital, population) = row
        rows.append(
            (
                "country", cid, name, strip_accents(name),
                continent_label(continent), iso2,
                # The capital is deliberately not indexed here: searching "Paris"
                # should offer Paris, not France.
                search_terms(name, iso2, iso3),
                iso2, name, continent, None, None, None, None, None, None,
                KIND_RANK["country"],
                COUNTRY_BASE_PROMINENCE + (population or 0) // 1000,
            )
        )

    for row in connection.execute(
        """
        SELECT r.id, r.code, r.name, r.latitude, r.longitude,
               c.iso2, c.name, c.continent,
               (SELECT COALESCE(SUM(ci.population), 0)
                  FROM city AS ci WHERE ci.region_code = r.code) AS city_population
        FROM region AS r JOIN country AS c ON c.iso2 = r.country_iso2
        ORDER BY r.code
        """
    ):
        (rid, code, name, lat, lon, iso2, country_name, continent, city_population) = row
        rows.append(
            (
                "region", rid, name, strip_accents(name), country_name, code,
                search_terms(name, code, country_name),
                iso2, country_name, continent, code, name, None, None, lat, lon,
                KIND_RANK["region"],
                (city_population or 0) // REGION_PROMINENCE_DAMPING,
            )
        )

    for row in connection.execute(
        """
        SELECT ci.id, ci.name, ci.ascii_name, ci.latitude, ci.longitude, ci.population,
               ci.is_capital, ci.region_code, r.name, co.iso2, co.name, co.continent
        FROM city AS ci
        JOIN country AS co ON co.iso2 = ci.country_iso2
        LEFT JOIN region AS r ON r.code = ci.region_code
        ORDER BY ci.id
        """
    ):
        (cid, name, ascii_name, lat, lon, population, is_capital, region_code,
         region_name, iso2, country_name, continent) = row
        subtitle = ", ".join(part for part in (region_name, country_name) if part)
        rows.append(
            (
                "city", cid, name, strip_accents(name), subtitle, None,
                # The country and region are indexed so "paris france" and
                # "springfield illinois" narrow the way a user expects.
                search_terms(name, ascii_name, country_name, region_name, iso2),
                iso2, country_name, continent, region_code, region_name, cid, name,
                lat, lon,
                KIND_RANK["city"],
                # Capitals get a nudge, so a capital outranks a larger non-capital
                # whose name merely starts the same way.
                (population or 0) + (CAPITAL_PROMINENCE_BONUS if is_capital else 0),
            )
        )

    for row in connection.execute(
        """
        SELECT l.id, l.name, l.kind, l.latitude, l.longitude, l.unesco, l.sitelinks,
               l.city_id, ci.name, l.region_code, r.name, co.iso2, co.name, co.continent
        FROM landmark AS l
        JOIN country AS co ON co.iso2 = l.country_iso2
        LEFT JOIN city AS ci ON ci.id = l.city_id
        LEFT JOIN region AS r ON r.code = l.region_code
        ORDER BY l.id
        """
    ):
        (lid, name, kind, lat, lon, unesco, sitelinks, city_id, city_name,
         region_code, region_name, iso2, country_name, continent) = row
        subtitle = ", ".join(part for part in (city_name, country_name) if part)
        rows.append(
            (
                "landmark", lid, name, strip_accents(name), subtitle, None,
                # Themes are not indexed as search terms: "parks" would otherwise
                # match every national park while the user is typing "Parma".
                search_terms(name, kind, city_name, country_name),
                iso2, country_name, continent, region_code, region_name,
                city_id, city_name, lat, lon,
                KIND_RANK["landmark"],
                # Wikipedia language editions, a measured fame signal, with a nudge for
                # a UNESCO listing.
                LANDMARK_BASE_PROMINENCE
                + (sitelinks or 0) * LANDMARK_PROMINENCE_PER_SITELINK
                + (LANDMARK_UNESCO_BONUS if unesco else 0),
            )
        )

    for row in connection.execute(
        """
        SELECT a.id, a.iata, a.icao, a.name, a.latitude, a.longitude, a.city_id,
               a.city_name, a.region_code, r.name, co.iso2, co.name, co.continent,
               a.kind, a.scheduled_service
        FROM airport AS a
        JOIN country AS co ON co.iso2 = a.country_iso2
        LEFT JOIN region AS r ON r.code = a.region_code
        ORDER BY a.id
        """
    ):
        (aid, iata, icao, name, lat, lon, city_id, city_name, region_code,
         region_name, iso2, country_name, continent, kind, scheduled) = row
        subtitle = ", ".join(part for part in (city_name, country_name) if part)
        rows.append(
            (
                "airport", aid, name, strip_accents(name), subtitle, iata,
                search_terms(name, iata, icao, city_name, country_name),
                iso2, country_name, continent, region_code, region_name,
                city_id, city_name, lat, lon,
                KIND_RANK["airport"],
                AIRPORT_PROMINENCE.get(kind or "", 0)
                + (AIRPORT_SCHEDULED_BONUS if scheduled else 0),
            )
        )

    for row in connection.execute(
        """
        SELECT id, name, mode, start_name, end_name, country_codes
        FROM route ORDER BY id
        """
    ):
        (rid, name, mode, start_name, end_name, country_codes) = row
        rows.append(
            (
                "route", rid, name, strip_accents(name),
                " – ".join(part for part in (start_name, end_name) if part), None,
                search_terms(name, mode, start_name, end_name, country_codes),
                None, None, None, None, None, None, None, None, None,
                KIND_RANK["route"], ROUTE_PROMINENCE,
            )
        )

    connection.executemany(
        """
        INSERT INTO place_index (kind, ref_id, name, name_folded, subtitle, code,
                                 search_text, country_iso2, country_name, continent,
                                 region_code, region_name, city_id, city_name,
                                 latitude, longitude, kind_rank, prominence)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )

    # Rebuilding from the content table is how an external-content FTS5 index is
    # populated; inserting into it directly would double-store every row.
    connection.execute("INSERT INTO place_fts(place_fts) VALUES ('rebuild')")
    connection.execute("INSERT INTO place_fts(place_fts) VALUES ('optimize')")
    return len(rows)


def continent_label(continent: str) -> str:
    labels = {
        "africa": "Africa",
        "antarctica": "Antarctica",
        "asia": "Asia",
        "europe": "Europe",
        "northAmerica": "North America",
        "oceania": "Oceania",
        "southAmerica": "South America",
    }
    return labels.get(continent, continent)


def write_meta(
    connection: sqlite3.Connection,
    data_version: str,
    built_at: str,
    counts: Counts,
    coverage: Coverage,
    manifest: dict,
    cities_dataset: str,
) -> None:
    """Writes the facts the app needs about the database itself.

    The three country counts are here rather than compiled into Swift because which
    places count as a country is a choice the user gets to make (Q-4, decision D-6):
    the app offers the lists, and the denominators come from the data.
    """

    def scalar(sql: str) -> int:
        return int(connection.execute(sql).fetchone()[0])

    attribution = "; ".join(
        row[0]
        for row in connection.execute(
            "SELECT attribution FROM data_source WHERE attribution IS NOT NULL ORDER BY id"
        )
    )

    entries = {
        "schema_version": str(SCHEMA_VERSION),
        "data_version": data_version,
        "built_at": built_at,
        "row_summary": counts.summary(),
        "coverage": "; ".join(coverage.notes),
        "cities_dataset": cities_dataset,
        # Shown in Settings so a user can see what the data rests on (R-DB-7). The
        # per-source detail is in `data_source`; this is the one-line form.
        "attribution": attribution,
        "country_count_un_members": str(scalar("SELECT COUNT(*) FROM country WHERE is_un_member = 1")),
        "country_count_un_members_and_observers": str(
            scalar("SELECT COUNT(*) FROM country WHERE is_un_member = 1 OR is_un_observer = 1")
        ),
        "country_count_all": str(scalar("SELECT COUNT(*) FROM country")),
    }
    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        sorted(entries.items()),
    )


# ------------------------------------------------------------------------------ main


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=HERE / "out/places.sqlite")
    parser.add_argument(
        "--cities",
        default=registry.DEFAULT_CITIES_DATASET,
        choices=sorted(registry.CITIES_DATASET_ROWS),
        help="Which cached GeoNames populated-place extract to build from (Q-5).",
    )
    parser.add_argument(
        "--data-version",
        default="0.2.0",
        help="Written into meta.data_version and shown in the app's Settings screen.",
    )
    parser.add_argument(
        "--built-at",
        default="unversioned",
        help=(
            "Written into meta.built_at. A fixed string by default so rebuilds are "
            "byte-identical; pass a date for a release build."
        ),
    )
    arguments = parser.parse_args(argv)

    try:
        counts, coverage = build(
            arguments.out, arguments.cities, arguments.data_version, arguments.built_at
        )
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    digest = hashlib.sha256(arguments.out.read_bytes()).hexdigest()[:16]
    size_mb = arguments.out.stat().st_size / (1024 * 1024)
    print(f"Built {arguments.out}")
    print(f"  {counts.summary()}")
    print(f"  {size_mb:.1f} MB, sha256:{digest}")
    if size_mb > registry.SIZE_BUDGET_MB:
        # Not a failure: a byte count is a judgement, not a correctness property.
        # But the bundle budget was a decision (Q-5, D-7), and quietly blowing
        # through it is how an app ends up far larger than anyone intended.
        print(
            f"  warning: over the {registry.SIZE_BUDGET_MB} MB bundle budget "
            "(Q-5, decision D-7) — use a smaller --cities set, or ship the extra "
            "as an R-DB-5 pack rather than in the app"
        )
    for note in coverage.notes:
        print(f"  coverage — {note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
