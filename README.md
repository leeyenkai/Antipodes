# Antipodes

A free, privacy-first travel logger for iPhone, iPad and Mac. Log every place and
journey you have travelled, and get unusually deep statistics out of it.

Flight loggers cover one mode deeply. Country-checklist apps cover everywhere
shallowly. Antipodes covers **every mode** — places, flights, rail, road, sea,
trails — with flight-logger depth, and keeps all of it on your own devices.

> **Status: pre-release.** The v1 feature set is built and tested; nothing is
> released yet. What is still blocked, and why, is in §13.1 of the
> [specification](docs/SPECIFICATION.md#131-v1-status).

---

## What it does

- **Log fast.** Search a database bundled inside the app and tap. No typing out
  coordinates, no looking up airport codes.
- **Every mode of travel.** Flights, intercity and regional rail, city transit,
  coaches, ferries and cruises, road trips, hikes and trails, cable cars and
  funiculars — each with its own detail, multi-leg journeys with connection times, and
  famous routes such as the Glacier Express ready to ride.
- **Statistics nobody else offers.** Not just countries counted: the average age of
  the landmarks you have seen, flight hours and punctuality, days away per year, the
  longest gap since you last saw a country, an estimate of your carbon and what going
  overland saved, and a rule-based "travel personality" that always shows its working.
- **Collections and badges.** The New 7 Wonders, the Nordic capitals, every US national
  park; a wishlist that ticks itself off; badges for the Arctic Circle and the Equator.
- **Bring your history with you.** Import flights from Flighty, myFlightradar24 or
  OpenFlights, and find past trips in the dates and places of your photos — on the
  device, with nothing stored about any photo.
- **Share it.** Cards for a stat, a trip or a year, a Year in Review, and Home and
  Lock Screen widgets.
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
    AntipodesStats/    Every statistic, badge and collection (pure, no persistence)
    AntipodesExport/   CSV and JSON export
    AntipodesImport/   Flight-log and photo import (pure)
    AntipodesStore/    SwiftData models and CloudKit sync
    AntipodesGlobe/    Globe geometry and replay (pure, no SwiftUI or MapKit)
    AntipodesUI/       SwiftUI screens
  Tests/               One suite per pure module
App/Antipodes/       App shell: entry point, Info.plist, assets, bundled resources
App/AntipodesWidgets/ Home and Lock Screen widgets
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
scripts/check.sh            # data, package, tests, lint, and the iOS and Mac app builds
```

Individually:

| | |
|---|---|
| `scripts/build.sh` | Build the `AntipodesKit` package |
| `scripts/test.sh` | Run the full test suite (no simulator, no network) |
| `scripts/lint.sh` | SwiftFormat + SwiftLint |
| `scripts/build-placedb.sh` | Build `places.sqlite` from the cached open data (fetches it first if missing) |
| `scripts/build-app.sh` | Build the app with `xcodebuild`; pass `"generic/platform=macOS"` for the Mac |
| `scripts/check.sh` | Everything above, including the iOS and Mac app builds (`ANTIPODES_SKIP_APP=1` leaves those out) |

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

The place database is built from open data: Natural Earth, GeoNames, OurAirports,
Wikidata and the UK Government's carbon conversion factors. Every source's licence and
what it obliges is recorded in [Tools/placedb/SOURCES.md](Tools/placedb/SOURCES.md), and
the required credits are shown in the app under Settings.

## Contributing

This is a solo project for now. [AGENTS.md](AGENTS.md) is the working agreement for
both humans and AI coding agents; read it before making changes. Release notes go in
[CHANGELOG.md](CHANGELOG.md).

## Licence

Not yet chosen. All rights reserved until a licence is added.
