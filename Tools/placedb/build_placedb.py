#!/usr/bin/env python3
"""Build the read-only Antipodes place database.

Reads the CSVs in ``seed/`` and writes a SQLite file with FTS5 search indexes
(R-DB-4). The real pipeline will read Natural Earth, GeoNames, OurAirports and
Wikidata; the shape of this script is what that pipeline grows into, and the seed CSVs
stand in until the licence review is done (R-DB-7).

Two properties matter and are tested:

* **Deterministic.** Same input, byte-identical output. Everything is sorted and no
  step depends on dict or filesystem ordering, so a rebuild that changes the file means
  the data changed.
* **Nothing guessed.** A missing attribute is written as NULL. The app reports coverage
  rather than showing an invented number (R-DB-2).

Usage::

    python3 build_placedb.py --seed seed --out out/places.sqlite
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import sqlite3
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path

SCHEMA_VERSION = 1

# Recorded against every row. When a real source replaces the seed, this becomes that
# source's name and the attribution in SOURCES.md follows it.
SEED_SOURCE = "seed/hand-entered"

# Search ranking: kind picks the tier, population or fame orders within it. A city
# beats a region of the same name ("Oslo"), and a country beats both ("Singapore"),
# because that is what someone logging travel almost always means (R-LOG-1).
KIND_TIER = {
    "country": 6,
    "city": 5,
    "region": 4,
    "airport": 3,
    "landmark": 2,
    "route": 1,
}
TIER_SCALE = 1_000_000_000


def prominence(kind: str, within_tier: int = 0) -> int:
    return KIND_TIER[kind] * TIER_SCALE + max(0, min(within_tier, TIER_SCALE - 1))


CONTINENTS = {
    "africa",
    "antarctica",
    "asia",
    "europe",
    "northAmerica",
    "oceania",
    "southAmerica",
}


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


# --------------------------------------------------------------------------- helpers


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise BuildError(f"Missing seed file: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise BuildError(f"Seed file has no rows: {path}")
    return rows


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
    "\u00f8": "o",   # ø
    "\u00e6": "ae",  # æ
    "\u00e5": "a",   # å
    "\u00df": "ss",  # ß
    "\u0111": "d",   # đ
    "\u00f0": "d",   # ð
    "\u00fe": "th",  # þ
    "\u0142": "l",   # ł
    "\u0131": "i",   # ı
    "\u0127": "h",   # ħ
    "\u00f6": "o",   # ö — decomposes, but listed so the table reads completely
    "\u00e4": "a",   # ä
    "\u00fc": "u",   # ü
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


# ------------------------------------------------------------------------- the build


def build(seed_dir: Path, out_path: Path, data_version: str, built_at: str) -> Counts:
    schema_path = Path(__file__).with_name("schema.sql")
    if not schema_path.exists():
        raise BuildError(f"Missing schema: {schema_path}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    connection = sqlite3.connect(out_path)
    try:
        connection.executescript(schema_path.read_text(encoding="utf-8"))
        counts = Counts()

        countries = insert_countries(connection, seed_dir, counts)
        regions = insert_regions(connection, seed_dir, countries, counts)
        cities = insert_cities(connection, seed_dir, countries, regions, counts)
        insert_landmarks(connection, seed_dir, countries, cities, counts)
        insert_airports(connection, seed_dir, countries, cities, counts)
        insert_routes(connection, seed_dir, counts)

        counts.indexed = build_search_index(connection)
        write_meta(connection, data_version, built_at, counts)

        connection.commit()
        connection.execute("VACUUM")
        connection.commit()
        return counts
    finally:
        connection.close()


def insert_countries(
    connection: sqlite3.Connection, seed_dir: Path, counts: Counts
) -> dict[str, dict[str, object]]:
    rows = read_csv(seed_dir / "countries.csv")
    countries: dict[str, dict[str, object]] = {}

    for index, row in enumerate(sorted(rows, key=lambda r: r["iso2"]), start=1):
        iso2 = text(row["iso2"])
        label = f"countries.csv {iso2 or '?'}"
        if not iso2 or len(iso2) != 2:
            raise BuildError(f"{label}: iso2 must be two characters")
        if iso2 in countries:
            raise BuildError(f"{label}: duplicate iso2")

        continent = text(row["continent"])
        if continent not in CONTINENTS:
            raise BuildError(f"{label}: unknown continent {continent!r}")

        name = text(row["name"])
        if not name:
            raise BuildError(f"{label}: name is required")

        record = {
            "id": index,
            "iso2": iso2,
            "iso3": text(row.get("iso3")),
            "name": name,
            "continent": continent,
            "capital": text(row.get("capital")),
            "population": integer(row.get("population"), field="population", row=label),
            "area_km2": real(row.get("area_km2"), field="area_km2", row=label),
            "latitude": real(row.get("latitude"), field="latitude", row=label),
            "longitude": real(row.get("longitude"), field="longitude", row=label),
            "currency_code": text(row.get("currency_code")),
            "languages": text(row.get("languages")),
            "is_un_member": 1 if text(row.get("is_un_member")) == "1" else 0,
            "source": SEED_SOURCE,
        }
        countries[iso2] = record
        connection.execute(
            """
            INSERT INTO country (id, iso2, iso3, name, continent, capital, population,
                                 area_km2, latitude, longitude, currency_code,
                                 languages, is_un_member, source)
            VALUES (:id, :iso2, :iso3, :name, :continent, :capital, :population,
                    :area_km2, :latitude, :longitude, :currency_code, :languages,
                    :is_un_member, :source)
            """,
            record,
        )
        counts.countries += 1

    return countries


def insert_regions(
    connection: sqlite3.Connection,
    seed_dir: Path,
    countries: dict[str, dict[str, object]],
    counts: Counts,
) -> dict[str, dict[str, object]]:
    rows = read_csv(seed_dir / "regions.csv")
    regions: dict[str, dict[str, object]] = {}

    for index, row in enumerate(sorted(rows, key=lambda r: r["code"]), start=1):
        code = text(row["code"])
        label = f"regions.csv {code or '?'}"
        if not code:
            raise BuildError(f"{label}: code is required")
        if code in regions:
            raise BuildError(f"{label}: duplicate code")

        country_iso2 = text(row["country_iso2"])
        if country_iso2 not in countries:
            raise BuildError(f"{label}: unknown country {country_iso2!r}")

        record = {
            "id": index,
            "code": code,
            "name": text(row["name"]),
            "country_iso2": country_iso2,
            "latitude": real(row.get("latitude"), field="latitude", row=label),
            "longitude": real(row.get("longitude"), field="longitude", row=label),
            "source": SEED_SOURCE,
        }
        regions[code] = record
        connection.execute(
            """
            INSERT INTO region (id, code, name, country_iso2, latitude, longitude, source)
            VALUES (:id, :code, :name, :country_iso2, :latitude, :longitude, :source)
            """,
            record,
        )
        counts.regions += 1

    return regions


def insert_cities(
    connection: sqlite3.Connection,
    seed_dir: Path,
    countries: dict[str, dict[str, object]],
    regions: dict[str, dict[str, object]],
    counts: Counts,
) -> dict[tuple[str, str], dict[str, object]]:
    rows = read_csv(seed_dir / "cities.csv")
    cities: dict[tuple[str, str], dict[str, object]] = {}

    ordered = sorted(rows, key=lambda r: (r["country_iso2"], r["name"]))
    for index, row in enumerate(ordered, start=1):
        name = text(row["name"])
        country_iso2 = text(row["country_iso2"])
        label = f"cities.csv {name or '?'}"
        if not name:
            raise BuildError(f"{label}: name is required")
        if country_iso2 not in countries:
            raise BuildError(f"{label}: unknown country {country_iso2!r}")

        region_code = text(row.get("region_code"))
        if region_code and region_code not in regions:
            raise BuildError(f"{label}: unknown region {region_code!r}")

        latitude = required_real(row["latitude"], field="latitude", row=label)
        longitude = required_real(row["longitude"], field="longitude", row=label)
        check_coordinate(latitude, longitude, row=label)

        key = (country_iso2, name)
        if key in cities:
            raise BuildError(f"{label}: duplicate city in {country_iso2}")

        record = {
            "id": index,
            "name": name,
            "country_iso2": country_iso2,
            "region_code": region_code,
            "latitude": latitude,
            "longitude": longitude,
            "population": integer(row.get("population"), field="population", row=label),
            "elevation_m": integer(row.get("elevation_m"), field="elevation_m", row=label),
            "timezone": text(row.get("timezone")),
            "is_capital": 1 if text(row.get("is_capital")) == "1" else 0,
            "source": SEED_SOURCE,
        }
        cities[key] = record
        connection.execute(
            """
            INSERT INTO city (id, name, country_iso2, region_code, latitude, longitude,
                              population, elevation_m, timezone, is_capital, source)
            VALUES (:id, :name, :country_iso2, :region_code, :latitude, :longitude,
                    :population, :elevation_m, :timezone, :is_capital, :source)
            """,
            record,
        )
        counts.cities += 1

    return cities


def insert_landmarks(
    connection: sqlite3.Connection,
    seed_dir: Path,
    countries: dict[str, dict[str, object]],
    cities: dict[tuple[str, str], dict[str, object]],
    counts: Counts,
) -> None:
    rows = read_csv(seed_dir / "landmarks.csv")
    ordered = sorted(rows, key=lambda r: (r["country_iso2"], r["name"]))

    for index, row in enumerate(ordered, start=1):
        name = text(row["name"])
        country_iso2 = text(row["country_iso2"])
        label = f"landmarks.csv {name or '?'}"
        if not name:
            raise BuildError(f"{label}: name is required")
        if country_iso2 not in countries:
            raise BuildError(f"{label}: unknown country {country_iso2!r}")

        # A landmark outside any seeded city (the Grand Canyon, the Taj Mahal) keeps a
        # NULL city and still counts its country and region (R-MODEL-6).
        city_name = text(row.get("city_name"))
        city = cities.get((country_iso2, city_name)) if city_name else None
        if city_name and city is None:
            raise BuildError(f"{label}: city {city_name!r} is not in cities.csv")

        latitude = required_real(row["latitude"], field="latitude", row=label)
        longitude = required_real(row["longitude"], field="longitude", row=label)
        check_coordinate(latitude, longitude, row=label)

        themes = text(row.get("themes"))
        if not themes:
            # R-DB-1: every landmark needs at least one theme or the personality stats
            # quietly under-count.
            raise BuildError(f"{label}: at least one theme tag is required")

        connection.execute(
            """
            INSERT INTO landmark (id, name, kind, city_id, country_iso2, region_code,
                                  latitude, longitude, year_built, era, height_m,
                                  unesco, themes, source)
            VALUES (:id, :name, :kind, :city_id, :country_iso2, :region_code,
                    :latitude, :longitude, :year_built, :era, :height_m,
                    :unesco, :themes, :source)
            """,
            {
                "id": index,
                "name": name,
                "kind": text(row.get("kind")),
                "city_id": city["id"] if city else None,
                "country_iso2": country_iso2,
                "region_code": city["region_code"] if city else None,
                "latitude": latitude,
                "longitude": longitude,
                "year_built": integer(row.get("year_built"), field="year_built", row=label),
                "era": text(row.get("era")),
                "height_m": real(row.get("height_m"), field="height_m", row=label),
                "unesco": 1 if text(row.get("unesco")) == "1" else 0,
                "themes": themes,
                "source": SEED_SOURCE,
            },
        )
        counts.landmarks += 1


def insert_airports(
    connection: sqlite3.Connection,
    seed_dir: Path,
    countries: dict[str, dict[str, object]],
    cities: dict[tuple[str, str], dict[str, object]],
    counts: Counts,
) -> None:
    rows = read_csv(seed_dir / "airports.csv")
    ordered = sorted(rows, key=lambda r: (r["iata"] or "", r["name"]))
    seen_iata: set[str] = set()

    for index, row in enumerate(ordered, start=1):
        name = text(row["name"])
        country_iso2 = text(row["country_iso2"])
        iata = text(row.get("iata"))
        label = f"airports.csv {iata or name or '?'}"
        if not name:
            raise BuildError(f"{label}: name is required")
        if country_iso2 not in countries:
            raise BuildError(f"{label}: unknown country {country_iso2!r}")
        if iata:
            if len(iata) != 3:
                raise BuildError(f"{label}: IATA code must be three letters")
            if iata in seen_iata:
                raise BuildError(f"{label}: duplicate IATA code")
            seen_iata.add(iata)

        city_name = text(row.get("city_name"))
        city = cities.get((country_iso2, city_name)) if city_name else None
        if city_name and city is None:
            raise BuildError(f"{label}: city {city_name!r} is not in cities.csv")

        latitude = required_real(row["latitude"], field="latitude", row=label)
        longitude = required_real(row["longitude"], field="longitude", row=label)
        check_coordinate(latitude, longitude, row=label)

        connection.execute(
            """
            INSERT INTO airport (id, iata, icao, name, city_id, city_name, country_iso2,
                                 region_code, latitude, longitude, elevation_m, source)
            VALUES (:id, :iata, :icao, :name, :city_id, :city_name, :country_iso2,
                    :region_code, :latitude, :longitude, :elevation_m, :source)
            """,
            {
                "id": index,
                "iata": iata,
                "icao": text(row.get("icao")),
                "name": name,
                "city_id": city["id"] if city else None,
                "city_name": city_name,
                "country_iso2": country_iso2,
                "region_code": city["region_code"] if city else None,
                "latitude": latitude,
                "longitude": longitude,
                "elevation_m": integer(row.get("elevation_m"), field="elevation_m", row=label),
                "source": SEED_SOURCE,
            },
        )
        counts.airports += 1


def insert_routes(connection: sqlite3.Connection, seed_dir: Path, counts: Counts) -> None:
    rows = read_csv(seed_dir / "routes.csv")
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
                "source": SEED_SOURCE,
            },
        )
        counts.routes += 1


def build_search_index(connection: sqlite3.Connection) -> int:
    """Fills ``place_index`` and the FTS5 index over it.

    ``prominence`` decides ties in search, which is what makes "par" offer Paris before
    Parma (R-LOG-1). Scales differ per kind deliberately: a country outranks a city of
    the same name, and a UNESCO landmark outranks a plain one.
    """
    rows: list[tuple] = []

    for row in connection.execute(
        """
        SELECT id, iso2, iso3, name, continent, capital, population, latitude, longitude
        FROM country ORDER BY iso2
        """
    ):
        (cid, iso2, iso3, name, continent, capital, population, lat, lon) = row
        rows.append(
            (
                "country", cid, name,
                continent_label(continent), iso2,
                # The capital is deliberately not indexed here: searching "Paris"
                # should offer Paris, not France.
                search_terms(name, iso2, iso3),
                iso2, name, continent, None, None, None, None, lat, lon,
                prominence("country", population or 0),
            )
        )

    for row in connection.execute(
        """
        SELECT r.id, r.code, r.name, r.latitude, r.longitude,
               c.iso2, c.name, c.continent
        FROM region AS r JOIN country AS c ON c.iso2 = r.country_iso2
        ORDER BY r.code
        """
    ):
        (rid, code, name, lat, lon, iso2, country_name, continent) = row
        rows.append(
            (
                "region", rid, name, country_name, code,
                search_terms(name, code, country_name),
                iso2, country_name, continent, code, name, None, None, lat, lon,
                prominence("region"),
            )
        )

    for row in connection.execute(
        """
        SELECT ci.id, ci.name, ci.latitude, ci.longitude, ci.population, ci.is_capital,
               ci.region_code, r.name, co.iso2, co.name, co.continent
        FROM city AS ci
        JOIN country AS co ON co.iso2 = ci.country_iso2
        LEFT JOIN region AS r ON r.code = ci.region_code
        ORDER BY ci.id
        """
    ):
        (cid, name, lat, lon, population, is_capital, region_code, region_name,
         iso2, country_name, continent) = row
        subtitle = ", ".join(part for part in (region_name, country_name) if part)
        rows.append(
            (
                "city", cid, name, subtitle, None,
                search_terms(name, country_name, region_name, iso2),
                iso2, country_name, continent, region_code, region_name, cid, name,
                lat, lon,
                # Capitals get a nudge, so a capital outranks a larger non-capital
                # whose name merely starts the same way.
                prominence("city", (population or 0) + (250_000 if is_capital else 0)),
            )
        )

    for row in connection.execute(
        """
        SELECT l.id, l.name, l.kind, l.latitude, l.longitude, l.unesco, l.themes,
               l.city_id, ci.name, l.region_code, r.name, co.iso2, co.name, co.continent
        FROM landmark AS l
        JOIN country AS co ON co.iso2 = l.country_iso2
        LEFT JOIN city AS ci ON ci.id = l.city_id
        LEFT JOIN region AS r ON r.code = l.region_code
        ORDER BY l.id
        """
    ):
        (lid, name, kind, lat, lon, unesco, themes, city_id, city_name,
         region_code, region_name, iso2, country_name, continent) = row
        subtitle = ", ".join(part for part in (city_name, country_name) if part)
        rows.append(
            (
                "landmark", lid, name, subtitle, None,
                # Themes are not indexed as search terms: "parks" would otherwise
                # match every national park while the user is typing "Parma".
                search_terms(name, kind, city_name, country_name),
                iso2, country_name, continent, region_code, region_name,
                city_id, city_name, lat, lon,
                # UNESCO status is the only fame signal the seed carries.
                prominence("landmark", 100_000 if unesco else 0),
            )
        )

    for row in connection.execute(
        """
        SELECT a.id, a.iata, a.icao, a.name, a.latitude, a.longitude,
               a.city_id, a.city_name, a.region_code, r.name, co.iso2, co.name, co.continent
        FROM airport AS a
        JOIN country AS co ON co.iso2 = a.country_iso2
        LEFT JOIN region AS r ON r.code = a.region_code
        ORDER BY a.id
        """
    ):
        (aid, iata, icao, name, lat, lon, city_id, city_name, region_code,
         region_name, iso2, country_name, continent) = row
        subtitle = ", ".join(part for part in (city_name, country_name) if part)
        rows.append(
            (
                "airport", aid, name, subtitle, iata,
                search_terms(name, iata, icao, city_name, country_name),
                iso2, country_name, continent, region_code, region_name,
                city_id, city_name, lat, lon,
                prominence("airport"),
            )
        )

    for row in connection.execute(
        """
        SELECT id, name, mode, start_name, end_name, country_codes, length_km
        FROM route ORDER BY id
        """
    ):
        (rid, name, mode, start_name, end_name, country_codes, length_km) = row
        rows.append(
            (
                "route", rid, name,
                " – ".join(part for part in (start_name, end_name) if part), None,
                search_terms(name, mode, start_name, end_name, country_codes),
                None, None, None, None, None, None, None, None, None,
                prominence("route"),
            )
        )

    connection.executemany(
        """
        INSERT INTO place_index (kind, ref_id, name, subtitle, code, search_text,
                                 country_iso2, country_name, continent, region_code,
                                 region_name, city_id, city_name, latitude, longitude,
                                 prominence)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    connection: sqlite3.Connection, data_version: str, built_at: str, counts: Counts
) -> None:
    entries = {
        "schema_version": str(SCHEMA_VERSION),
        "data_version": data_version,
        "built_at": built_at,
        "row_summary": counts.summary(),
        # Shown in Settings so a user can see what the data rests on (R-DB-7).
        "attribution": "Development seed, hand-entered. See Tools/placedb/SOURCES.md.",
    }
    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        sorted(entries.items()),
    )


# ------------------------------------------------------------------------------ main


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=Path, default=Path(__file__).parent / "seed")
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "out/places.sqlite")
    parser.add_argument(
        "--data-version",
        default="0.1.0-seed",
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
        counts = build(arguments.seed, arguments.out, arguments.data_version, arguments.built_at)
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
