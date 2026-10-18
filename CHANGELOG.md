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

- The data in `Tools/placedb/seed/` is a small hand-entered development seed, not the
  real dataset. The real pipeline (Natural Earth, GeoNames, OurAirports, Wikidata) is
  not built yet and its licence review is outstanding (R-DB-7).
- No release has been made. Version numbers begin at the first tagged build.
