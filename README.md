# Antipodes

A free, privacy-first travel logger for iPhone, iPad and Mac. Log every place and
journey you have travelled, and get unusually deep statistics out of it.

Flight loggers cover one mode deeply. Country-checklist apps cover everywhere
shallowly. Antipodes covers **every mode** — places, flights, rail, road, sea,
trails — with flight-logger depth, and keeps all of it on your own devices.

> **Status: pre-alpha.** The first internal milestone (M1) is under construction.
> Nothing is released yet and the data pipeline ships with a small development seed
> rather than the real dataset.

---

## What it does

- **Log fast.** Search a database bundled inside the app and tap. No typing out
  coordinates, no looking up airport codes.
- **Every mode of travel.** Flights, intercity and regional rail, city transit,
  coaches, ferries and cruises, road trips, hikes and trails, cable cars and
  funiculars — each with its own detail and its own real path on the map.
- **Statistics nobody else offers.** Not just countries counted: average age of the
  landmarks you have seen, the temperature in the month you visited, percentage of a
  country's rail network you have ridden, and a rule-based "travel personality" that
  always shows its working.
- **A globe, not a list.** The home screen is a 3D globe with your countries shaded,
  your pins placed and your journeys drawn as arcs.
- **Private by design.** No account. No server. No analytics. Your travel history
  lives on your device and in your own iCloud, and the developer never sees it. The
  target App Store privacy label is *Data Not Collected*.

Full requirements: [docs/SPECIFICATION.md](docs/SPECIFICATION.md).

## What it deliberately does not do

No social feed, no friends or following. No live flight tracking — this app logs
journeys, it does not follow them in real time. No booking, no recommendations, no
itinerary planning. No Android or web version.

---

## Repository layout

```
AntipodesKit/        Swift package: all logic and UI
  Sources/
    AntipodesCore/     Value types, flexible dates, great-circle maths, counting rules
    AntipodesPlaces/   Read-only place database (SQLite + FTS5 search)
    AntipodesStats/    Coverage and distance statistics (pure, no persistence)
    AntipodesExport/   CSV and JSON export
    AntipodesStore/    SwiftData models and CloudKit sync
    AntipodesUI/       SwiftUI screens
  Tests/               One suite per pure module
App/Antipodes/       App shell: entry point, Info.plist, assets, bundled resources
Antipodes.xcodeproj  Thin app project depending on the local package
Tools/placedb/       Python pipeline that builds the read-only place database
docs/                Specification and design notes
scripts/             Build, test and lint helpers
```

## Building

**Requirements:** macOS with Xcode 27 or later (Swift 6.4), and `python3` for the data
pipeline. There are no third-party Swift dependencies, so no package resolution and no
network access are needed to build.

```bash
git clone https://github.com/leeyenkai/Antipodes.git
cd Antipodes
scripts/check.sh            # build the package, run the tests, build the place database
```

Individually:

| | |
|---|---|
| `scripts/build.sh` | Build the `AntipodesKit` package |
| `scripts/test.sh` | Run the full test suite (no simulator, no network) |
| `scripts/lint.sh` | SwiftFormat + SwiftLint |
| `scripts/build-placedb.sh` | Build `places.sqlite` from the seed data |
| `scripts/build-app.sh` | Build the iOS app with `xcodebuild` |
| `scripts/check.sh` | Everything above except the app build |

To run the app, open `Antipodes.xcodeproj` in Xcode and run the `Antipodes` scheme on
an iPhone simulator, an iPad simulator or My Mac.

> Run `scripts/build-placedb.sh` before the first app build — the app bundles
> `App/Antipodes/Resources/places.sqlite`, which is a build product and is not
> committed.

## Architecture in one paragraph

Everything lives in a local Swift package so the whole test suite runs from the command
line in milliseconds, with no simulator. `AntipodesCore` holds the value types and the
maths and depends on nothing. `AntipodesStats` is a set of pure functions over those
types — it never touches SwiftData, which is what makes the statistics (the substance
of the product) cheap to test exhaustively. `AntipodesStore` owns the SwiftData models
and CloudKit mirroring and maps between the two worlds. `AntipodesPlaces` reads a
read-only SQLite file built offline by `Tools/placedb/`, searched with FTS5. The Xcode
project is a thin shell that hosts the `@main` entry point and bundles resources.

See [AGENTS.md](AGENTS.md) for the conventions, the module dependency rule and the
project-specific traps.

## Data and attribution

The place database is built from open data. Sources, licences and attribution
obligations are tracked in [Tools/placedb/SOURCES.md](Tools/placedb/SOURCES.md), and
the licence review is not yet complete — see R-DB-7 in the specification. The data
currently in `Tools/placedb/seed/` is a small hand-entered development seed, not the
real dataset.

## Contributing

This is a solo project for now. [AGENTS.md](AGENTS.md) is the working agreement for
both humans and AI coding agents; read it before making changes. Release notes go in
[CHANGELOG.md](CHANGELOG.md).

## Licence

Not yet chosen. All rights reserved until a licence is added.
