-- Antipodes place database, schema version 3.
--
-- Read-only at runtime (R-DB-4). Built by build_placedb.py from the open-data sources
-- registered in `data_source`, and shipped in the app bundle, kept entirely separate
-- from the user's own SwiftData store (R-MODEL-5).
--
-- Every entity table carries a `source` column naming a row in `data_source`.
-- Attribution is a licence obligation for GeoNames, not a nicety, so the obligation
-- travels inside the artefact rather than living only in a markdown file
-- (R-DB-7, Tools/placedb/SOURCES.md).
--
-- There is deliberately **no geometry** here. Country border polygons live in their own
-- `.antborders` file built by build_borders.py, because the globe needs every visible
-- polygon per frame rather than a query (decision D-5).
--
-- **Row ids are permanent.** A user's log stores `(kind, id)` for every place it
-- references, and the database is replaced wholesale by updates (R-DB-5), so an id
-- must name the same place in every future build. Each kind takes its id from an
-- upstream identifier that is itself stable — GeoNames ids for cities and regions, the
-- Wikidata QID number for landmarks, OurAirports' own row id for airports, a curated
-- id for routes, and the ISO letters for countries. Schema version 2 numbered rows by
-- their position in a sorted list, so adding one landmark renumbered every landmark
-- after it; version 3 fixes that before anything ships.
--
-- `place_index` is a denormalised view of everything searchable, and `place_fts` is an
-- external-content FTS5 index over it. One search field covers every place type
-- (R-LOG-1), so one index is simpler and faster than five.

PRAGMA journal_mode = DELETE;

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Where the data came from and what it obliges us to do. The app reads this to render
-- the attribution in Settings, so a new source cannot ship without its credit
-- appearing (R-DB-7).
CREATE TABLE data_source (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    licence     TEXT NOT NULL,
    licence_url TEXT,
    -- The exact credit line the licence requires, or NULL where none is required.
    -- Rendered verbatim in Settings; do not paraphrase it at the call site.
    attribution TEXT,
    -- What we actually used it for, in one phrase, for the Settings list.
    used_for    TEXT NOT NULL,
    -- Digest and retrieval date of the file this build read, so an artefact can say
    -- precisely which upstream snapshot it rests on. Natural Earth is pinned to a
    -- release tag; GeoNames and OurAirports are rolling feeds, so for those this is
    -- the only record of which day's data a database holds.
    sha256      TEXT,
    retrieved   TEXT
);

CREATE TABLE country (
    id            INTEGER PRIMARY KEY,
    iso2          TEXT NOT NULL UNIQUE,
    iso3          TEXT,
    iso_numeric   TEXT,
    name          TEXT NOT NULL,
    continent     TEXT NOT NULL,
    capital       TEXT,
    population    INTEGER,
    area_km2      REAL,
    latitude      REAL,
    longitude     REAL,
    currency_code TEXT,
    languages     TEXT,
    -- Natural Earth's own classification: 'sovereign', 'dependency', 'disputed' or
    -- 'other'. NULL for the small territories Natural Earth's 1:110m layer omits —
    -- unknown rather than guessed, as everywhere else. The country *lists* the app
    -- offers are built from the two UN flags and the row count instead, so a missing
    -- status never moves a denominator (Q-4, decision D-6).
    status        TEXT,
    is_un_member   INTEGER NOT NULL DEFAULT 0,
    is_un_observer INTEGER NOT NULL DEFAULT 0,
    wikidata_qid  TEXT,
    source        TEXT NOT NULL REFERENCES data_source (id)
);

-- First-level administrative divisions, as GeoNames defines them.
--
-- `code` is GeoNames' own admin1 code ("IT.07" for Lazio), *not* ISO 3166-2. The two
-- are not the same level everywhere — Natural Earth's admin-1 layer gives Italy its
-- 110 provinces while GeoNames gives its 20 regions — and matching them up would be
-- guesswork. Using GeoNames' code throughout means a city's own admin1 code joins
-- here exactly, with nothing inferred.
CREATE TABLE region (
    id           INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    country_iso2 TEXT NOT NULL REFERENCES country (iso2),
    latitude     REAL,
    longitude    REAL,
    geonames_id  INTEGER,
    source       TEXT NOT NULL REFERENCES data_source (id)
);

CREATE TABLE city (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    ascii_name   TEXT,
    country_iso2 TEXT NOT NULL REFERENCES country (iso2),
    region_code  TEXT REFERENCES region (code),
    latitude     REAL NOT NULL,
    longitude    REAL NOT NULL,
    population   INTEGER,
    elevation_m  INTEGER,
    timezone     TEXT,
    is_capital   INTEGER NOT NULL DEFAULT 0,
    -- GeoNames feature code (PPLC, PPLA, PPL…). Kept because it is the only honest
    -- signal of what kind of populated place a row is.
    feature_code TEXT,
    geonames_id  INTEGER UNIQUE,
    source       TEXT NOT NULL REFERENCES data_source (id)
);

CREATE TABLE landmark (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    kind         TEXT,
    city_id      INTEGER REFERENCES city (id),
    country_iso2 TEXT NOT NULL REFERENCES country (iso2),
    region_code  TEXT REFERENCES region (code),
    latitude     REAL NOT NULL,
    longitude    REAL NOT NULL,
    -- Year built, negative for BC. NULL where only an era is known (R-DB-3).
    year_built   INTEGER,
    era          TEXT,
    height_m     REAL,
    unesco       INTEGER NOT NULL DEFAULT 0,
    -- Comma-separated theme tags from the taxonomy in curation/themes.csv (R-DB-1).
    -- The final taxonomy is still open (Q-6), so this stays text rather than a
    -- foreign key for now.
    themes       TEXT,
    wikidata_qid TEXT UNIQUE,
    -- Wikipedia language-edition count, used as the fame signal for search ranking.
    -- A measured number rather than a hand-assigned score.
    sitelinks    INTEGER,
    source       TEXT NOT NULL REFERENCES data_source (id)
);

CREATE TABLE airport (
    id           INTEGER PRIMARY KEY,
    iata         TEXT,
    icao         TEXT,
    name         TEXT NOT NULL,
    city_id      INTEGER REFERENCES city (id),
    city_name    TEXT,
    country_iso2 TEXT NOT NULL REFERENCES country (iso2),
    region_code  TEXT REFERENCES region (code),
    latitude     REAL NOT NULL,
    longitude    REAL NOT NULL,
    elevation_m  INTEGER,
    -- IANA time zone, taken from the linked city, or else from the bundled cities of
    -- the same country where they all share one zone. NULL where neither settles it:
    -- a time zone near a zone boundary is not something to guess (R-DB-2).
    timezone     TEXT,
    -- OurAirports' size class: large_airport, medium_airport, small_airport.
    kind              TEXT,
    scheduled_service INTEGER NOT NULL DEFAULT 0,
    source            TEXT NOT NULL REFERENCES data_source (id)
);

CREATE TABLE route (
    id                       INTEGER PRIMARY KEY,
    name                     TEXT NOT NULL,
    mode                     TEXT NOT NULL,
    start_name               TEXT,
    end_name                 TEXT,
    -- Where the route begins and ends, as bundled places, so logging a ride can fill
    -- in both ends (R-JLOG-3). NULL where the end of the line is too small to be in
    -- the bundled city set.
    start_kind               TEXT,
    start_ref_id             INTEGER,
    end_kind                 TEXT,
    end_ref_id               INTEGER,
    country_codes            TEXT,
    length_km                REAL,
    typical_duration_minutes INTEGER,
    highest_point_m          REAL,
    source                   TEXT NOT NULL REFERENCES data_source (id)
);

-- The landmark theme taxonomy (R-DB-1, Q-6), with the label the app shows.
CREATE TABLE theme (
    id          TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    description TEXT,
    sort_order  INTEGER NOT NULL
);

-- Curated collections to work through (R-WISH-2) and their members, resolved to
-- bundled places at build time so a member can never point at nothing.
CREATE TABLE collection (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    symbol      TEXT,
    sort_order  INTEGER NOT NULL
);

CREATE TABLE collection_member (
    collection_id TEXT NOT NULL REFERENCES collection (id),
    place_kind    TEXT NOT NULL,
    ref_id        INTEGER NOT NULL,
    sort_order    INTEGER NOT NULL,
    PRIMARY KEY (collection_id, place_kind, ref_id)
);

-- Achievement definitions (R-ACH-1). Evaluated on the device; shipped here so new ones
-- arrive with a database update (R-DB-6). See curation/achievements.csv for the rules.
CREATE TABLE achievement (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT NOT NULL,
    symbol      TEXT,
    rule        TEXT NOT NULL,
    threshold   REAL,
    parameter   TEXT,
    tier        TEXT,
    sort_order  INTEGER NOT NULL
);

-- Carbon factors per mode and class (R-CO2-1). `basis` says whether a factor is per
-- passenger-km or per vehicle-km; `year` is the factor set's own year, shown with every
-- carbon figure (R-CO2-3).
CREATE TABLE emission_factor (
    mode           TEXT NOT NULL,
    travel_class   TEXT NOT NULL DEFAULT '',
    kg_co2e_per_km REAL NOT NULL,
    basis          TEXT NOT NULL,
    label          TEXT NOT NULL,
    year           INTEGER NOT NULL,
    source         TEXT NOT NULL REFERENCES data_source (id),
    PRIMARY KEY (mode, travel_class)
);

CREATE INDEX idx_city_country ON city (country_iso2);
-- Nearest-city lookups (dropped pins, photo import) narrow by latitude band first.
CREATE INDEX idx_city_latitude ON city (latitude);
CREATE INDEX idx_city_region ON city (region_code);
CREATE INDEX idx_landmark_city ON landmark (city_id);
CREATE INDEX idx_airport_iata ON airport (iata);
CREATE INDEX idx_airport_country ON airport (country_iso2);
CREATE INDEX idx_country_un ON country (is_un_member);

-- The climate of a place: TerraClimate's 1991-2020 monthly normals at the nearest grid
-- cell with data, and the Köppen-Geiger zone they make (R-CALC-2, §7). One row per
-- city, landmark and airport that has land within reach of its coordinate; a place
-- without one has no row rather than a guessed climate (R-DB-2).
CREATE TABLE climate (
    place_kind   TEXT NOT NULL,
    ref_id       INTEGER NOT NULL,
    -- Twelve monthly mean temperatures, January first, in tenths of a degree Celsius,
    -- comma-separated: "53,59,81,…".
    tmean_tenths TEXT NOT NULL,
    koppen       TEXT NOT NULL,
    source       TEXT NOT NULL REFERENCES data_source (id),
    PRIMARY KEY (place_kind, ref_id)
) WITHOUT ROWID;

-- Everything searchable, flattened.
--
-- Two ranking columns, because they answer different questions (R-LOG-1).
-- `kind_rank` orders rows that match the query *exactly* — "Singapore" offers the
-- country before the city. `prominence` orders everything else and is on one scale
-- across kinds, so a famous city outranks an obscure country and typing "par" offers
-- Paris rather than Paraguay. See the comment on KIND_RANK in build_placedb.py.
CREATE TABLE place_index (
    rowid        INTEGER PRIMARY KEY,
    kind         TEXT NOT NULL,
    ref_id       INTEGER NOT NULL,
    name         TEXT NOT NULL,
    -- The name ASCII-folded and lowercased, by the same rule as `search_text`.
    -- Without it an accented name can never match a query *exactly*, because nobody
    -- types the accent: "malmo" would rank a hamlet in Aruba called Malmok above
    -- Malmö, and "goteborg" would not find Göteborg at all.
    name_folded  TEXT NOT NULL DEFAULT '',
    subtitle     TEXT,
    code         TEXT,
    search_text  TEXT NOT NULL,
    country_iso2 TEXT,
    country_name TEXT,
    continent    TEXT,
    region_code  TEXT,
    region_name  TEXT,
    city_id      INTEGER,
    city_name    TEXT,
    latitude     REAL,
    longitude    REAL,
    -- IANA time zone where the place has one, so a leg's times can be read in the
    -- zone they happened in (§5.2).
    timezone     TEXT,
    kind_rank    INTEGER NOT NULL DEFAULT 0,
    prominence   INTEGER NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX idx_place_index_ref ON place_index (kind, ref_id);
CREATE INDEX idx_place_index_kind ON place_index (kind);

-- `remove_diacritics 2` makes "Tromso" find "Tromsø" and "Sao Paulo" find
-- "São Paulo", which users type far more often than the accented form.
CREATE VIRTUAL TABLE place_fts USING fts5 (
    name,
    code,
    search_text,
    content = 'place_index',
    content_rowid = 'rowid',
    tokenize = "unicode61 remove_diacritics 2"
);
