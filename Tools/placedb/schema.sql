-- Antipodes place database, schema version 1.
--
-- Read-only at runtime (R-DB-4). Built by build_placedb.py and shipped in the app
-- bundle, kept entirely separate from the user's own SwiftData store (R-MODEL-5).
--
-- Every entity table carries a `source` column. Attribution is a licence obligation
-- for several of the upstream datasets, not a nicety (R-DB-7, Tools/placedb/SOURCES.md).
--
-- `place_index` is a denormalised view of everything searchable, and `place_fts` is an
-- external-content FTS5 index over it. One search field covers every place type
-- (R-LOG-1), so one index is simpler and faster than five.

PRAGMA journal_mode = DELETE;

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE country (
    id            INTEGER PRIMARY KEY,
    iso2          TEXT NOT NULL UNIQUE,
    iso3          TEXT,
    name          TEXT NOT NULL,
    continent     TEXT NOT NULL,
    capital       TEXT,
    population    INTEGER,
    area_km2      REAL,
    latitude      REAL,
    longitude     REAL,
    currency_code TEXT,
    languages     TEXT,
    is_un_member  INTEGER NOT NULL DEFAULT 0,
    source        TEXT NOT NULL
);

CREATE TABLE region (
    id           INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    country_iso2 TEXT NOT NULL REFERENCES country (iso2),
    latitude     REAL,
    longitude    REAL,
    source       TEXT NOT NULL
);

CREATE TABLE city (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    country_iso2 TEXT NOT NULL REFERENCES country (iso2),
    region_code  TEXT REFERENCES region (code),
    latitude     REAL NOT NULL,
    longitude    REAL NOT NULL,
    population   INTEGER,
    elevation_m  INTEGER,
    timezone     TEXT,
    is_capital   INTEGER NOT NULL DEFAULT 0,
    source       TEXT NOT NULL
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
    -- Comma-separated theme tags from the taxonomy (R-DB-1). The final taxonomy is
    -- open (Q-6), so this stays text rather than a foreign key for now.
    themes       TEXT,
    source       TEXT NOT NULL
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
    source       TEXT NOT NULL
);

CREATE TABLE route (
    id                       INTEGER PRIMARY KEY,
    name                     TEXT NOT NULL,
    mode                     TEXT NOT NULL,
    start_name               TEXT,
    end_name                 TEXT,
    country_codes            TEXT,
    length_km                REAL,
    typical_duration_minutes INTEGER,
    highest_point_m          REAL,
    source                   TEXT NOT NULL
);

CREATE INDEX idx_city_country ON city (country_iso2);
CREATE INDEX idx_landmark_city ON landmark (city_id);
CREATE INDEX idx_airport_iata ON airport (iata);
CREATE INDEX idx_airport_country ON airport (country_iso2);

-- Everything searchable, flattened. `prominence` is the ranking key: population for
-- cities and countries, curated fame for landmarks, traffic proxy for airports
-- (R-LOG-1).
CREATE TABLE place_index (
    rowid        INTEGER PRIMARY KEY,
    kind         TEXT NOT NULL,
    ref_id       INTEGER NOT NULL,
    name         TEXT NOT NULL,
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
