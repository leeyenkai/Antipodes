# Changelog

All notable changes to Antipodes are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Entries cite requirement IDs from [docs/SPECIFICATION.md](docs/SPECIFICATION.md) where
they apply.

**How to update this file:** add your change under `[Unreleased]` as part of the same
commit. On release, rename that heading to the new version with a date and start a
fresh `[Unreleased]` block. Sections used: Added, Changed, Deprecated, Removed, Fixed,
Security, Data (place-database changes).

## [Unreleased]

### Added

- Repository scaffolding: `README.md`, `.gitignore`, `AGENTS.md` (working agreement for
  humans and AI agents), `CLAUDE.md` (pointer to `AGENTS.md`), and this changelog.
- `docs/SPECIFICATION.md` — the requirements for the app, transcribed from the
  2026-10-15 draft spec sheet, with stable requirement IDs (`R-…`), milestone tags,
  M1 acceptance criteria and a register of open questions (`Q-…`).
- `AntipodesKit` Swift package with the module layout and dependency rule described in
  §12.2 of the specification.
- `AntipodesCore`: `FlexibleDate` (exact day, range, month, year, unknown — R-DATE-1),
  `VisitType` with default coverage rules (R-CALC-1), `TravelMode` for all eight modes
  (§5.1), `Coordinate` and `GreatCircle` distance and interpolation (R-PATH-4),
  `CountingRules`, and the `Trip`/`Visit`/`Journey`/`JourneyLeg` value types.
- `AntipodesPlaces`: a dependency-free wrapper over the system SQLite3 C API and a
  read-only `PlaceDatabase` with FTS5 search across countries, cities, landmarks and
  airports, ranked by prefix match then prominence (R-LOG-1).
- `AntipodesStats`: coverage statistics (countries, % of the world, continents,
  regions, cities — R-CALC-1, R-CALC-3) and distance statistics (total km by mode,
  times round the Earth, longest leg — §5.7). Every result reports the records it used
  and excluded, with reasons (R-CALC-5).
- `AntipodesExport`: full CSV and JSON export of trips, visits, journeys and legs
  (R-LOG-9, R-PRIV-6).
- `AntipodesStore`: SwiftData models with CloudKit-compatible definitions, and mapping
  to and from the `AntipodesCore` value types (R-PRIV-2).
- `AntipodesUI`: first pass at the globe, trips, add, stats and settings screens
  (§9), with the add sheet built around search-and-tap (R-LOG-1).
- `Tools/placedb/`: deterministic Python pipeline that builds the read-only
  `places.sqlite` with FTS5 indexes from seed CSVs (R-DB-4), plus `SOURCES.md`
  recording every source and its licence obligations (R-DB-7).
- `scripts/`: `build.sh`, `test.sh`, `lint.sh`, `build-placedb.sh`, `build-app.sh` and
  `check.sh`.
- `Antipodes.xcodeproj`: multiplatform app shell for iOS, iPadOS and macOS, targeting
  iOS 26 / macOS 26 (D-4).

- `.swiftformat` and `.swiftlint.yml`, tuned to this codebase. `scripts/lint.sh` is
  idempotent and reports no warnings.

### Data

- **The place database is now built from real open data.** The hand-entered development
  seed in `Tools/placedb/seed/` is gone, replaced by a pipeline over Natural Earth
  (country list, ISO codes, sovereignty), GeoNames (regions, cities, elevations, time
  zones, country facts), OurAirports (airports and codes) and Wikidata (landmark facts,
  UNESCO status, UN membership). The database goes from 60 countries, 86 cities, 35
  landmarks and 85 airports to **252 countries, 3,865 regions, 69,822 cities, 236
  landmarks and 9,763 airports** — 31 MB, 83,946 searchable rows (R-DB-4).
- **Completed the licence review that blocked release (R-DB-7).** Every candidate source
  in [`Tools/placedb/SOURCES.md`](Tools/placedb/SOURCES.md) is reviewed against its own
  licence text, with the obligation recorded and met:
  - GeoNames is **CC BY 4.0** and is the only source in the database that obliges
    anything. Its required credit, including the "modified" indication CC BY 4.0 §3(a)
    calls for, is written into the database and rendered verbatim in Settings.
  - Natural Earth and OurAirports are public domain; Wikidata is CC0. All three are
    credited anyway.
  - **OpenStreetMap is excluded, and that is now settled rather than open** (decision
    D-8). ODbL §4.4 would put share-alike on the whole bundled file. If route geometry
    is ever wanted it ships as a separate ODbL pack under the §4.5(a) collective-database
    exemption. **Trainline's stations dataset is ODbL too** and is excluded on the same
    ground — it is not a way around OSM.
  - **UNESCO's own World Heritage List is excluded**: republishing it needs prior
    written authorisation. UNESCO status comes from Wikidata's `P1435` instead.
- Resolved **Q-4**: the user chooses between three named country lists — UN members
  (193), UN members and observers (195), and all countries and territories (252) — and
  the denominator for "% of the world" is read from the database rather than compiled in
  (decision D-6). `CountingRules.worldCountryCount` is now driven by `CountryList`.
- Resolved **Q-5**: a 48 MB budget for the bundled database, bundling cities above 5,000
  people (decision D-7). The 1,000 cut-off would have cost 68 MB for a hundred thousand
  hamlets; 15,000 would have dropped places people travel to, such as Zermatt.
- New `data_source` table (schema version **2**) carrying each source's licence,
  required credit, and the digest and date of the snapshot a build read. Attribution now
  travels inside the artefact, so a source cannot ship uncredited.
- Fetching is separate from building (decision D-9): `scripts/fetch-placedb-sources.sh`
  is the only step that needs a network, and `build_placedb.py` reads only the cache, so
  a rebuild is offline and still byte-identical. `vendor/manifest.json` records what each
  build read — Natural Earth is pinned to release `v5.1.2`, while GeoNames, OurAirports
  and Wikidata are rolling feeds whose digests are the only record of which snapshot is
  in a given database.
- Landmarks are curated by identity and themed by hand, with every fact from Wikidata
  (decision D-10). `curation/landmarks.csv` records the expected Wikidata label and
  country for each QID and the build fails if Wikidata disagrees, which caught
  "Persepolis" resolving to a football club and "Grand Canyon" to a university.
  236 landmarks across 70 countries, 61 of them UNESCO-designated, with a sixteen-tag
  theme taxonomy in `curation/theme_taxonomy.csv` (R-DB-1, working answer to Q-6).
- The build reports its own coverage, so a mostly-empty column is visible before
  shipping: landmark year built 67%, height 29%, city link 61%; airport IATA 93%, city
  link 61% (R-DB-2).

### Changed

- **Accented place names are now matched exactly when typed without accents.**
  `place_index` carries an ASCII-folded copy of every name, which the search compares
  the raw query against alongside the original. Before this, no accented name could
  ever be an *exact* match: "malmo" ranked *Malmok*, a hamlet in Aruba, and an airport
  above Malmö, and "zurich" ranked the canton above the city. The folding rules stay in
  the pipeline rather than being reimplemented in Swift, so there is one copy.
- **Search ranking** now uses one prominence scale across place kinds, with the kind
  only breaking ties between exact matches and an exact match promoted only above a
  prominence floor (decision D-11, R-LOG-1). The previous per-kind tiering made every
  country outrank every city, so "par" offered Paraguay before Paris; promoting every
  exact match put *Par*, a Cornish village, ahead of both. Landmark prominence is now a
  measured signal — its Wikipedia language-edition count — rather than a UNESCO flag,
  airports rank by OurAirports' size class, and a region's is the summed population of
  the cities inside it, damped. Searching "oslo" now gives the city, then the county,
  then the airport; "par" gives Paris ahead of Paraguay and the Brazilian states.
- `PlaceDatabase.approximateCountry(for:)` resolves a dropped pin through the nearest
  bundled city rather than the nearest country centroid (R-LOG-5). The database holds
  no country centroid and inventing one would be a guess, while 69,822 city coordinates
  are facts GeoNames publishes — and a pin in Trondheim is metres from a known city but
  hundreds of kilometres from Norway's middle.
- Region codes are GeoNames admin1 codes (`IT.07` for Lazio) rather than ISO 3166-2.
  The two are different levels in some countries — Natural Earth's admin-1 layer gives
  Italy its 110 provinces where GeoNames gives its 20 regions — and matching them would
  have been guesswork. `PlaceReference.qualifiedRegionCode` treats both separators as
  already country-qualified.
- Settings gains a *Where the places come from* section listing every source, its
  licence and the snapshot this build used, with the required credits shown first and
  verbatim (R-DB-7). The "countries in the world" stepper is now a named-list picker.

### Removed

- `Tools/placedb/seed/` — the hand-entered development CSVs. Approximate figures with no
  upstream source have no place in a shipped database, and `AGENTS.md` now forbids
  hand-entering a geographic fact.

### Verified

- `scripts/check.sh` passes: the place database builds (byte-identically on a rebuild),
  the package builds clean, and 104 tests pass with no network and no simulator.
- The app builds for both the iOS Simulator and macOS, and runs on an iPhone simulator:
  searching "oslo" offline returns the city, then the region, then OSL; a visit saves
  and the stats recompute to 1 country / 0.5% of the world / 1 of 7 continents with the
  city, region and country chain counted; an OSL→JFK flight reports 5,917 km against a
  published great-circle figure of about 5,920 km, and draws as a curved arc on the
  globe (M1 acceptance criteria 1, 2, 4, 5, 6, 8, 11).

### Notes

- The hand-entered development seed is gone: the pipeline now builds from Natural
  Earth, GeoNames, OurAirports and Wikidata, and the licence review behind R-DB-7 is
  complete. See `Tools/placedb/SOURCES.md`.
- No release has been made. Version numbers begin at the first tagged build.
