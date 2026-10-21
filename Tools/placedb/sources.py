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
# The UK Government's greenhouse-gas conversion factors, 2025 release. Published as an
# immutable asset URL, so the digest is pinned like Natural Earth's (Q-16).
DESNZ_FACTORS_URL = (
    "https://assets.publishing.service.gov.uk/media/6846b6ea57f3515d9611f0dd/"
    "ghg-conversion-factors-2025-flat-format.xlsx"
)
DESNZ_FACTORS_YEAR = 2025

# TerraClimate's 1991-2020 monthly climatologies, served by the University of Idaho's
# THREDDS server. Read through OPeNDAP as every sixth cell of the 1/24° grid — a 0.25°
# grid, about 28 km — in DAP2's binary form, which the standard library can read; the
# full files are compressed NetCDF-4 that it cannot. Each request is fixed, so its bytes
# are too, and the digest is pinned.
TERRACLIMATE_DODS = (
    "http://thredds.northwestknowledge.net:8080/thredds/dodsC/TERRACLIMATE_ALL/climatology/"
    "TerraClimate_19912020_{var}.nc.dods?{var}%5B0:1:11%5D%5B3:6:4319%5D%5B3:6:8639%5D"
)

# The elevation TerraClimate's grid is built on, sampled at the same cells, so a place
# higher or lower than its cell can be corrected by the standard lapse rate.
TERRACLIMATE_DEM_DODS = (
    "http://thredds.northwestknowledge.net:8080/thredds/dodsC/TERRACLIMATE_ALL/layers/"
    "terraclim_dem.nc.dods?elevation%5B3:6:4319%5D%5B3:6:8639%5D"
)

# The Wikidata Query Service blocks clients that do not identify themselves, and asks
# for a contact route in the User-Agent.
# https://www.mediawiki.org/wiki/Wikidata_Query_Service/User_Manual
USER_AGENT = (
    "AntipodesPlaceDB/0.3 (https://github.com/leeyenkai/Antipodes; place database pipeline)"
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
    used_for=(
        "Country list, ISO codes, continents and sovereignty classification; "
        "the railway, road and ferry networks surface legs are measured along"
    ),
    files=(
        RemoteFile(
            "ne_110m_admin_0_countries.geojson",
            f"{NATURAL_EARTH_BASE}/ne_110m_admin_0_countries.geojson",
            sha256="6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f",
        ),
        RemoteFile(
            "ne_10m_railroads.geojson",
            f"{NATURAL_EARTH_BASE}/ne_10m_railroads.geojson",
            sha256="a0962d7866060ae3e24df255f6d662389ac9ba7e0df40cf329c2281190b861e6",
        ),
        RemoteFile(
            "ne_10m_roads.geojson",
            f"{NATURAL_EARTH_BASE}/ne_10m_roads.geojson",
            sha256="66a0c7b438e92fd124822cc5921cfa11042f48c294ade5e0f03f2c6640fd0248",
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
    used_for="Landmark facts, UNESCO status, UN membership, city transit stations and lines",
    # Written by fetch_sources.py from the queries in `queries/`, not downloaded
    # directly, so they carry no URL of their own.
    files=(
        RemoteFile("un_members.csv", WIKIDATA_SPARQL),
        RemoteFile("landmarks.json", WIKIDATA_SPARQL),
        RemoteFile("transit.json", WIKIDATA_SPARQL),
    ),
)

#: Carbon factors for the journey stats (R-CO2-1 to R-CO2-3). Crown copyright under the
#: Open Government Licence v3.0, whose §"Your obligations" asks for this exact statement
#: wherever the information is used — so it is a required credit, rendered in Settings.
DESNZ = Source(
    id="desnz",
    name="UK Government GHG Conversion Factors 2025 (DESNZ)",
    url="https://www.gov.uk/government/publications/greenhouse-gas-reporting-conversion-factors-2025",
    licence="Open Government Licence v3.0",
    licence_url="https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/",
    attribution="Contains public sector information licensed under the Open Government "
    "Licence v3.0.",
    used_for="Carbon estimates per passenger-km and vehicle-km",
    files=(
        RemoteFile(
            "ghg-conversion-factors-2025-flat-format.xlsx",
            DESNZ_FACTORS_URL,
            sha256="8bfdb45b81ec4a88e3bdf4584637330f62e6bd09ce1940e654c5d7b7f736de94",
        ),
    ),
)

#: Monthly climate normals, 1991-2020, for the temperature in the month visited
#: (R-CALC-2, R-DATE-3) and the climate zone of every place (§7). Abatzoglou et al.
#: (2018); the University of Idaho releases TerraClimate under CC0.
TERRACLIMATE = Source(
    id="terraclimate",
    name="TerraClimate",
    url="https://www.climatologylab.org/terraclimate.html",
    licence="CC0 1.0",
    licence_url="https://creativecommons.org/publicdomain/zero/1.0/",
    # CC0 asks for nothing; the authors ask to be cited, and are, in Settings.
    attribution=None,
    used_for="Monthly temperature normals 1991-2020, Köppen climate zones and the "
    "elevation they are corrected by",
    files=(
        RemoteFile(
            "tmax_1991_2020_p25.dods",
            TERRACLIMATE_DODS.format(var="tmax"),
            sha256="f49e6230c71428581e8980ebfcf4c9cb63fe7f58086017f058d0728416d8b63a",
        ),
        RemoteFile(
            "tmin_1991_2020_p25.dods",
            TERRACLIMATE_DODS.format(var="tmin"),
            sha256="13a7ec5d34c5f592419fdaa29e8b7b579cbd4313d40d7d6645cbe6e8bf850f56",
        ),
        RemoteFile(
            "ppt_1991_2020_p25.dods",
            TERRACLIMATE_DODS.format(var="ppt"),
            sha256="9fb415b07dfb4face6476545b0d79ff45f76dd57910495fa3524c605df80508e",
        ),
        RemoteFile(
            "dem_p25.dods",
            TERRACLIMATE_DEM_DODS,
            sha256="f00b502ac4d0d50bb497721651acc5c96f279a89c46e3d935dc43b829a970336",
        ),
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
    used_for="Landmark selection, theme tags, famous routes, collections, achievements",
    files=(),
)


def all_sources(cities_dataset: str = DEFAULT_CITIES_DATASET) -> tuple[Source, ...]:
    """Every source, in a fixed order so the `data_source` table is deterministic."""
    return tuple(
        sorted(
            (
                NATURAL_EARTH,
                DESNZ,
                geonames_source(cities_dataset),
                OURAIRPORTS,
                TERRACLIMATE,
                WIKIDATA,
                CURATION,
            ),
            key=lambda source: source.id,
        )
    )
