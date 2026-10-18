#!/usr/bin/env python3
"""The register of upstream sources, their licences and what each one obliges.

This module is the single definition shared by ``fetch_sources.py`` (which downloads)
and ``build_placedb.py`` (which reads the cache and writes the `data_source` table).
[SOURCES.md](SOURCES.md) is the prose version of the same facts and the place the
licence reasoning lives; if the two ever disagree, this file is what actually ships,
so fix it here first.

Nothing enters the pipeline without a `Source` here (R-DB-7). The `attribution` field
is rendered verbatim in the app's Settings screen, so it is the licence text's words
rather than a paraphrase.

**Why no OpenStreetMap.** ODbL 1.0 §4.4(b) makes extracting a substantial part of the
contents into a new database a Derivative Database, and §4.4(a) requires one that is
publicly used to be licensed under ODbL. Shipping OSM geometry inside `places.sqlite`
would therefore put share-alike on the whole file. §4.5(a) keeps a *separate*,
self-contained ODbL database out of that scope, so OSM-derived geometry, if it is ever
wanted, ships as its own pack rather than mixed in here. Trainline's stations dataset
is also ODbL and falls under exactly the same analysis.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# Natural Earth is read from a tagged release rather than `master`, so the same tag
# always yields the same geometry and classification. The globe pipeline
# (`build_borders.py`, decision D-5) pins the same tag and the same digest for the same
# file; keep them in step.
NATURAL_EARTH_TAG = "v5.1.2"
NATURAL_EARTH_BASE = (
    f"https://raw.githubusercontent.com/nvkelso/natural-earth-vector/{NATURAL_EARTH_TAG}/geojson"
)

GEONAMES_BASE = "https://download.geonames.org/export/dump"
OURAIRPORTS_BASE = "https://davidmegginson.github.io/ourairports-data"
WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"

# The Wikidata Query Service blocks clients that do not identify themselves, and asks
# for a contact route in the User-Agent.
# https://www.mediawiki.org/wiki/Wikidata_Query_Service/User_Manual
USER_AGENT = (
    "AntipodesPlaceDB/0.2 (https://github.com/leeyenkai/Antipodes; place database pipeline)"
)


@dataclass(frozen=True)
class RemoteFile:
    """One file to download into the cache."""

    name: str
    url: str
    # Set only where the upstream is pinned to an immutable release, in which case a
    # mismatch fails the fetch. Rolling feeds (GeoNames, OurAirports) leave this None
    # and have their digest recorded in the manifest after the fact instead.
    sha256: str | None = None
    # Extracted member to read out of a .zip, if the download is one.
    zip_member: str | None = None


@dataclass(frozen=True)
class Source:
    id: str
    name: str
    url: str
    licence: str
    licence_url: str | None
    # The credit the licence requires, verbatim, or None where none is required.
    attribution: str | None
    used_for: str
    files: tuple[RemoteFile, ...] = field(default_factory=tuple)


#: Which GeoNames populated-place extract to bundle, resolved by Q-5 (decision D-7).
#:
#: `cities5000` — every place above 5,000 people plus the seats of first-level
#: divisions — is the bundled set: 69,822 cities and a 30 MB database, inside the 48 MB
#: budget. `cities1000` more than doubles the file to 68 MB for a hundred thousand
#: hamlets, and `cities15000` saves 13 MB but loses places people genuinely travel to
#: (Zermatt has 6,629 residents). `--cities` switches between them.
CITIES_DATASET_ROWS = {
    "cities500": "places above 500 people (~200,000 rows)",
    "cities1000": "places above 1,000 people (171,329 rows, 68 MB)",
    "cities5000": "places above 5,000 people (69,822 rows, 30 MB)",
    "cities15000": "places above 15,000 people (34,167 rows, 17 MB)",
}
DEFAULT_CITIES_DATASET = "cities5000"

#: The size budget for the bundled database (Q-5, decision D-7). The build does not
#: enforce it — a hard failure on a byte count would be hostile — but
#: `scripts/build-placedb.sh` prints the size, and anything approaching this should go
#: through the R-DB-5 update channel as a pack instead of into the bundle.
SIZE_BUDGET_MB = 48


def geonames_source(cities_dataset: str = DEFAULT_CITIES_DATASET) -> Source:
    """GeoNames: the only source in the database that obliges us to do anything."""
    if cities_dataset not in CITIES_DATASET_ROWS:
        raise ValueError(
            f"unknown cities dataset {cities_dataset!r}; "
            f"choose from {', '.join(sorted(CITIES_DATASET_ROWS))}"
        )
    return Source(
        id="geonames",
        name="GeoNames",
        url="https://www.geonames.org/",
        licence="CC BY 4.0",
        licence_url="https://creativecommons.org/licenses/by/4.0/",
        # CC BY 4.0 §3(a) wants the creator credited, the licence identified and
        # modification indicated. We filter and reshape the extracts, so the
        # "modified" clause is not optional for us.
        attribution="Contains data from GeoNames (geonames.org), modified, "
        "licensed under CC BY 4.0.",
        used_for="Cities, regions, elevations, time zones, country facts",
        files=(
            RemoteFile("countryInfo.txt", f"{GEONAMES_BASE}/countryInfo.txt"),
            RemoteFile("admin1CodesASCII.txt", f"{GEONAMES_BASE}/admin1CodesASCII.txt"),
            RemoteFile(
                f"{cities_dataset}.zip",
                f"{GEONAMES_BASE}/{cities_dataset}.zip",
                zip_member=f"{cities_dataset}.txt",
            ),
        ),
    )


NATURAL_EARTH = Source(
    id="naturalearth",
    name="Natural Earth",
    url="https://www.naturalearthdata.com/",
    licence="Public domain",
    licence_url="https://www.naturalearthdata.com/about/terms-of-use/",
    # "No permission is needed to use Natural Earth. Crediting the authors is
    # unnecessary." Credited anyway, because a user looking at the Settings screen
    # deserves to know where their country list came from.
    attribution=None,
    used_for="Country list, ISO codes, continents and sovereignty classification",
    files=(
        RemoteFile(
            "ne_110m_admin_0_countries.geojson",
            f"{NATURAL_EARTH_BASE}/ne_110m_admin_0_countries.geojson",
            sha256="6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f",
        ),
    ),
)

OURAIRPORTS = Source(
    id="ourairports",
    name="OurAirports",
    url="https://ourairports.com/data/",
    licence="Public domain",
    licence_url="https://ourairports.com/data/",
    attribution=None,
    used_for="Airports, IATA and ICAO codes, elevations",
    files=(RemoteFile("airports.csv", f"{OURAIRPORTS_BASE}/airports.csv"),),
)

WIKIDATA = Source(
    id="wikidata",
    name="Wikidata",
    url="https://www.wikidata.org/",
    licence="CC0 1.0",
    licence_url="https://creativecommons.org/publicdomain/zero/1.0/",
    attribution=None,
    used_for="Landmark facts, UNESCO status, UN membership",
    # Written by fetch_sources.py from the queries in `queries/`, not downloaded
    # directly, so they carry no URL of their own.
    files=(
        RemoteFile("un_members.csv", WIKIDATA_SPARQL),
        RemoteFile("landmarks.json", WIKIDATA_SPARQL),
    ),
)

#: Deliberate human input: which landmarks and routes exist, the theme taxonomy, and
#: the two reconciliations the upstream data cannot express. §6 of the specification
#: calls for landmarks and famous routes to be curated, and R-DB-1 requires a theme
#: tag that no source supplies.
CURATION = Source(
    id="antipodes-curation",
    name="Antipodes curation",
    url="https://github.com/leeyenkai/Antipodes/tree/main/Tools/placedb/curation",
    licence="CC0 1.0 (part of this repository)",
    licence_url=None,
    attribution=None,
    used_for="Landmark selection, theme tags, famous routes",
    files=(),
)


def all_sources(cities_dataset: str = DEFAULT_CITIES_DATASET) -> tuple[Source, ...]:
    """Every source, in a fixed order so the `data_source` table is deterministic."""
    return tuple(
        sorted(
            (
                NATURAL_EARTH,
                geonames_source(cities_dataset),
                OURAIRPORTS,
                WIKIDATA,
                CURATION,
            ),
            key=lambda source: source.id,
        )
    )
