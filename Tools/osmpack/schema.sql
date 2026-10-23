-- routes-osm.sqlite: the OpenStreetMap route pack (D-36).
--
-- Contains information from OpenStreetMap, which is made available here under the Open
-- Database License (ODbL) 1.0, https://opendatacommons.org/licenses/odbl/1-0/.
-- © OpenStreetMap contributors.
--
-- This file is a separate database from places.sqlite and shares no table with it, so
-- the share-alike terms of the ODbL reach this file and nothing else (D-8,
-- SOURCES.md §2). It is the whole derivative database; the pipeline that makes it is
-- Tools/osmpack/ in the Antipodes repository.
--
-- Every line is stored as `points`: the first point as two little-endian int32,
-- latitude then longitude in 1/100,000 of a degree, then each later point as two int16
-- steps from the one before — the same encoding as places.sqlite's track_edge.

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

-- Signed hiking and cycling routes, as routable networks: `hiking/alps`,
-- `cycling/new-zealand` and so on (R-PATH-2). The same shape as places.sqlite's
-- track_edge, so the app routes on them with the same code.
CREATE TABLE track_edge (
    network  TEXT NOT NULL,
    id       INTEGER NOT NULL,
    node_a   INTEGER NOT NULL,
    node_b   INTEGER NOT NULL,
    length_m INTEGER NOT NULL,
    points   BLOB NOT NULL,
    PRIMARY KEY (network, id)
) WITHOUT ROWID;

-- Where each network lies, so the app loads only the one a leg is in.
CREATE TABLE track_region (
    network TEXT PRIMARY KEY,
    kind    TEXT NOT NULL,
    region  TEXT NOT NULL,
    name    TEXT NOT NULL,
    south   REAL NOT NULL,
    west    REAL NOT NULL,
    north   REAL NOT NULL,
    east    REAL NOT NULL
) WITHOUT ROWID;

-- The real shape of each catalogue route (R-JLOG-3, R-PATH-1), keyed by its id in
-- places.sqlite's `route` table; `part` orders the pieces where the map has gaps.
CREATE TABLE route_shape (
    route_id INTEGER NOT NULL,
    part     INTEGER NOT NULL,
    length_m INTEGER NOT NULL,
    points   BLOB NOT NULL,
    PRIMARY KEY (route_id, part)
) WITHOUT ROWID;

-- Passenger aerial lifts: cable cars, gondolas and chair lifts, station to station.
CREATE TABLE aerialway (
    id         INTEGER PRIMARY KEY,
    kind       TEXT NOT NULL,
    name       TEXT,
    start_name TEXT,
    end_name   TEXT,
    start_lat  REAL NOT NULL,
    start_lon  REAL NOT NULL,
    end_lat    REAL NOT NULL,
    end_lon    REAL NOT NULL,
    length_m   INTEGER NOT NULL,
    points     BLOB NOT NULL
);
CREATE INDEX idx_aerialway_start ON aerialway (start_lat);
CREATE INDEX idx_aerialway_end ON aerialway (end_lat);

-- City transit (R-TRAN-1 to R-TRAN-6), the same shape as places.sqlite's tables, so the
-- app reads both alike. Systems, lines and stops from OpenStreetMap have ids in ranges
-- of their own (osmpack.py); a line Wikidata already has keeps its Wikidata id and
-- appears here only in transit_shape.
CREATE TABLE transit_system (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    kind            TEXT NOT NULL,
    city_name       TEXT NOT NULL,
    country_iso2    TEXT NOT NULL,
    network_version TEXT NOT NULL
);

CREATE TABLE transit_line (
    id            INTEGER PRIMARY KEY,
    system_id     INTEGER NOT NULL REFERENCES transit_system (id),
    name          TEXT NOT NULL,
    short_name    TEXT,
    colour        TEXT,
    segment_count INTEGER NOT NULL
);
CREATE INDEX idx_transit_line_system ON transit_line (system_id);

CREATE TABLE transit_stop (
    id        INTEGER PRIMARY KEY,
    name      TEXT NOT NULL,
    latitude  REAL NOT NULL,
    longitude REAL NOT NULL
);

CREATE TABLE transit_segment (
    line_id INTEGER NOT NULL,
    stop_a  INTEGER NOT NULL,
    stop_b  INTEGER NOT NULL,
    PRIMARY KEY (line_id, stop_a, stop_b)
) WITHOUT ROWID;

-- The drawn shape of a line, for lines from either source: one part per direction or
-- branch that runs somewhere the others do not.
CREATE TABLE transit_shape (
    line_id INTEGER NOT NULL,
    part    INTEGER NOT NULL,
    points  BLOB NOT NULL,
    PRIMARY KEY (line_id, part)
) WITHOUT ROWID;
