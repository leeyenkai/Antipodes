# Place database pipeline

Builds the read-only SQLite file the app bundles and searches (R-DB-4).

```bash
python3 build_placedb.py --seed seed --out out/places.sqlite
```

Or from the repository root, which also copies the result into the app bundle:

```bash
scripts/build-placedb.sh
```

## Files

| | |
|---|---|
| `schema.sql` | Schema version 1, including the `place_index` table and the FTS5 index over it |
| `build_placedb.py` | The pipeline: reads the seed CSVs, validates, writes the database |
| `seed/` | Hand-entered development data — see [SOURCES.md](SOURCES.md) |
| `SOURCES.md` | Every source, its licence and what it obliges us to do |
| `out/` | Build output, not committed |

## Two properties it must keep

**Deterministic.** The same input produces a byte-identical file. Everything is sorted
and nothing depends on dict or filesystem ordering, so if a rebuild changes the file,
the data changed. `--built-at` defaults to a fixed string for this reason; pass a real
date only for a release build.

```bash
python3 build_placedb.py --out out/a.sqlite && python3 build_placedb.py --out out/b.sqlite
cmp out/a.sqlite out/b.sqlite && echo identical
```

**Nothing guessed.** A missing attribute is written as NULL and the app reports its
coverage (R-DB-2). The build fails rather than inventing a value, and it also fails on a
landmark with no theme tag (R-DB-1), an unknown country code, a coordinate out of
range, or a duplicate IATA code.

## Adding data

Seed CSVs are plain UTF-8 with a header row. Landmarks and airports link to a city by
`city_name` within the same country, and the build fails if that city is not in
`cities.csv`. A landmark outside any city (the Grand Canyon) leaves `city_name` empty
and still counts its country.

Raise `SCHEMA_VERSION` in `build_placedb.py` and
`PlaceDatabase.expectedSchemaVersion` in Swift together whenever the schema changes —
the app refuses a database whose schema version it does not recognise, rather than
running the wrong query.
