# AGENTS.md

Working agreement for AI coding agents (and humans) in this repository.
Read this before touching code. The product requirements live in
[docs/SPECIFICATION.md](docs/SPECIFICATION.md); this file is about *how we build it*.

---

## 1. What this project is

**Antipodes** — a free, privacy-first iPhone/iPad/Mac app for logging every place and
journey you have travelled, then turning that log into deep statistics.

Three constraints shape nearly every decision:

1. **Privacy is a hard requirement, not a feature.** Target App Store label:
   *Data Not Collected*. No account, no server, no analytics, no third-party SDK that
   phones home. Any network request the app makes must be identical for every user
   (database and pack downloads only). If a change would make a request depend on the
   user's own data, it is wrong.
2. **Offline first.** Search, stats, distances and geocoding must work in airplane
   mode. Nothing in the logging path may require a network call.
3. **The numbers must be right, and must say what they are.** Stats are the product.
   Every stat reports how much of its input it could use and what it excluded. No
   silently dropped records, no guessed attributes.

---

## 2. Repository layout

```
AntipodesKit/            Swift package — all logic and UI. This is where you work.
  Sources/
    AntipodesCore/       Value types, flexible dates, visit types, travel modes,
                         great-circle maths, counting rules. No dependencies at all.
    AntipodesPlaces/     Read-only place database: thin SQLite3 wrapper, FTS5 search.
    AntipodesStats/      Every stat family, achievements, collections, Year in
                         Review. Pure functions over Core types.
    AntipodesExport/     CSV and JSON export of the user's whole log.
    AntipodesImport/     Flight-log CSV readers and photo clustering. Pure.
    AntipodesStore/      SwiftData models, CloudKit container, mapping to/from Core.
    AntipodesGlobe/      Globe geometry: orthographic projection, limb clipping,
                         bundled border decoding, replay timeline. Pure.
    AntipodesUI/         SwiftUI screens.
  Tests/                 One suite per pure module. Runs with no network, no simulator.
App/Antipodes/           Xcode app shell: @main entry, Info.plist, assets, resources.
App/AntipodesWidgets/    WidgetKit extension. Imports AntipodesCore only (D-19).
Antipodes.xcodeproj      Thin app project; depends on the local AntipodesKit package.
Tools/placedb/           Python pipeline that builds the read-only places.sqlite
                         from open data. curation/ is tracked; vendor/ and out/ are not.
docs/                    SPECIFICATION.md and any design notes.
scripts/                 Repo-level build, test and lint helpers.
```

### The dependency rule

```
AntipodesCore   ← depends on nothing
AntipodesPlaces ← Core
AntipodesStats  ← Core
AntipodesExport ← Core
AntipodesImport ← Core
AntipodesStore  ← Core            (SwiftData lives here and nowhere else)
AntipodesGlobe  ← Core            (globe geometry; no SwiftUI, no MapKit)
AntipodesUI     ← all of the above
```

**Never invert an arrow.** In particular: `AntipodesStats` must not import SwiftData
or `AntipodesStore`, `AntipodesGlobe` must not import SwiftUI or MapKit, and
`AntipodesCore` must not import anything but the standard library and `Foundation`. This is what lets the whole stats engine be tested from the
command line in milliseconds. If you find yourself wanting to reach backwards, add a
value type to Core instead.

---

## 3. Commands

| Task | Command |
|---|---|
| Build the package | `scripts/build.sh` |
| Run all tests | `scripts/test.sh` |
| Lint and format | `scripts/lint.sh` |
| Fetch the place-database sources | `scripts/fetch-placedb-sources.sh` |
| Build the place database | `scripts/build-placedb.sh` |
| Fetch the globe's borders | `scripts/fetch-borders.sh` |
| Build the globe's borders | `scripts/build-borders.sh` |
| Fetch and scale the satellite picture | `scripts/fetch-imagery.sh` |
| Build the iOS app | `scripts/build-app.sh` |
| Build the Mac app | `scripts/build-app.sh "generic/platform=macOS"` |
| Everything CI runs | `scripts/check.sh` (`ANTIPODES_SKIP_APP=1` skips the app builds) |
| Render the app icon | `Tools/icon/render.sh` |

Underneath, those are just:

```bash
swift build  --package-path AntipodesKit
swift test   --package-path AntipodesKit
python3 -I Tools/placedb/build_placedb.py --out <path>      # no network; reads vendor/
xcodebuild -project Antipodes.xcodeproj -scheme Antipodes \
           -destination 'generic/platform=iOS Simulator' build
```

`swift test` is the fast loop and must stay fast and hermetic. If a change makes the
suite need a network connection, a simulator or a `ModelContainer`, that change is in
the wrong module.

---

## 4. Conventions

### Swift

- Swift 6 language mode, strict concurrency. New types are `Sendable` unless there is a
  reason not to be. UI types are `@MainActor`.
- Value types by default. Reference types only for SwiftData models and genuine
  identity.
- No third-party dependencies without a decision recorded in
  [§12.1 of the spec](docs/SPECIFICATION.md#121-implementation-decisions-taken-during-the-m1-build).
  The current answer is zero.
- Units are explicit in names: `distanceKm`, `durationMinutes`, `temperatureC`. Never a
  bare `distance`.
- Optional means "genuinely unknown", and unknown is a first-class state throughout
  this app (see `FlexibleDate`). Do not paper over it with a sentinel such as `0`,
  `-1` or `Date.distantPast`.
- `swift-format` / SwiftLint config in the repo root is authoritative. Run
  `scripts/lint.sh` before you commit.

### SwiftUI

- Small, dedicated views. If a `body` runs past roughly 60 lines, split it.
- Model-View, not MVVM: views read `@Query`/model state directly; no view-model layer
  wrapping SwiftData. Computation belongs in `AntipodesStats`, not in a view.
- Every screen must work at iPhone-SE width and at Mac window width.

### SwiftData and CloudKit

CloudKit mirroring imposes rules that are easy to break and painful to discover late:

- Every property must be optional **or** have a default value.
- No `@Attribute(.unique)` constraints.
- Every relationship must have an inverse, and must be optional or defaulted.
- Deletes propagate; check cascade rules when you add a relationship.

Changing a model that has shipped is a migration. Write the migration plan in the same
commit.

### Tests

- Swift Testing (`import Testing`, `@Test`), not XCTest, for new tests.
- Every stat gets a test with a hand-computed expected value and a comment saying where
  that value came from. A test that just re-runs the implementation proves nothing.
- Test the unknown-date and empty-log paths explicitly. They are the common crash.
- Great-circle distances are checked against published reference figures with a stated
  tolerance.

### Python (the place-database pipeline)

- Standard library only where possible. The pipeline must be runnable on a clean
  machine with `python3` and nothing else.
- The pipeline is **deterministic**: same inputs, byte-identical output. Sort
  everything; never rely on dict or filesystem ordering.
- Every output row records which source it came from. Attribution is a licence
  obligation, not a nicety (see R-DB-7).
- Never guess an attribute to fill a column. Leave it NULL; the app reports coverage.

---

## 5. Data and licensing

The place database is built from open data, and the licences differ:

| Source | Licence | Obligation | In use |
|---|---|---|---|
| Natural Earth | Public domain | None | Yes — country list, ISO codes, sovereignty |
| GeoNames | **CC BY 4.0** | **Attribution, and say it was modified** | Yes — cities, regions, elevations, time zones |
| OurAirports | Public domain | None | Yes — airports and codes |
| Wikidata | CC0 | None | Yes — landmark facts, UNESCO status, UN membership |
| TerraClimate (University of Idaho) | CC0 | None (cited anyway) | Yes — 1991–2020 monthly temperature normals and Köppen climate zones |
| NASA Blue Marble | Public domain | Credit NASA; no endorsement implied | Yes — the satellite globe's picture (bundled, not in the database) |
| OpenStreetMap / OpenRailwayMap | ODbL | Share-alike on a *derived database* | **No — excluded, see below** |
| Trainline EU stations | ODbL | Same as OSM | **No — excluded** |
| UNESCO World Heritage List | Prior written authorisation | Permission needed | **No — excluded; status comes from Wikidata** |
| GTFS feeds | Varies per feed | Check each one individually | Not yet reviewed |

**Rules:**

- Nothing enters the pipeline without a `Source` in `Tools/placedb/sources.py` **and** a
  row in `Tools/placedb/SOURCES.md`. A test fails if any row names an unregistered
  source.
- **No OpenStreetMap-derived data goes into `places.sqlite`** (decision D-8). ODbL
  §4.4 would put share-alike on the whole file, including the CC BY and CC0 material in
  it. If route geometry is wanted, it ships as a separate ODbL pack — read
  `SOURCES.md` §2 before writing any code that touches OSM. This is settled, not open.
- Where a licence requires attribution, put the licence's own words in the source's
  `attribution` field. It is written into the database and rendered verbatim in
  Settings, so a new source cannot ship uncredited.
- Fetching and building are separate: `fetch_sources.py` is the only thing that touches
  the network, and `build_placedb.py` reads only `Tools/placedb/vendor/`. Neither
  `vendor/` nor `out/` is committed; `curation/` is.
- Never hand-enter a geographic fact. The old `Tools/placedb/seed/` CSVs are gone.
  Facts come from a source; `curation/` holds only judgements — which landmarks and
  routes exist, their theme tags, and two documented reconciliations.

---

## 6. Working practice

**Before you start**

- Read the relevant section of [docs/SPECIFICATION.md](docs/SPECIFICATION.md) and note
  the requirement IDs you are implementing.
- Check the milestone tag. `[M1]` and `[V1]` work is in scope (decision D-18);
  `[LATER]` is not — do not build it early, and do not quietly expand scope. §13.1 of
  the spec says which V1 areas are blocked and why.

**While you work**

- Reference requirement IDs in commit messages: `Add coverage stats (R-CALC-1, R-CALC-3)`.
- If the spec is wrong, ambiguous or silent, say so and propose an edit to the spec in
  the same change. Do not invent a requirement and leave it undocumented in code.
- An open question (`Q-n`) that blocks you: pick a reasonable default, implement behind
  a seam you can swap, and record the decision in §12.1 of the spec. Do not stall, and
  do not pretend the question is settled.

**Before you finish**

- `scripts/check.sh` passes.
- Add a line to [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]`.
- If you changed requirements, bump the spec version and add a row to §16 of the spec.
- Report honestly what you did not do or could not verify.

**Commits**

- Conventional-ish prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`,
  `data:`.
- One logical change per commit. Keep generated artefacts out (see `.gitignore`).

---

## 7. Traps specific to this project

- **Don't compute distances from coordinates in a view.** All distance maths lives in
  `AntipodesCore.GreatCircle`, so there is exactly one implementation to get right.
- **Don't let a stat silently skip records.** Every result carries the count it used
  and the count it excluded. If you add a stat, add that bookkeeping.
- **Don't double-count places.** Averages over places count each unique place once;
  time-based stats count each visit (R-CALC-3). These two are easy to mix up.
- **Don't assume a date exists.** `FlexibleDate` has an `unknown` case and real users
  will have plenty of them.
- **Don't widen a visit's implied coverage by accident.** A landmark implies its city,
  region and country (R-MODEL-6) — that chain is deliberate, and anything beyond it is
  a bug.
- **Don't bundle the place database into the SwiftData store.** They are separate
  stores with separate lifetimes (R-MODEL-5).
- **Don't add a network call to the logging path.** Ever.
- **Don't draw the globe with a map framework.** MapKit fetches its map from Apple's
  servers, and what it fetches follows wherever the user's own travel puts the camera —
  a request shaped by their private data, which R-PRIV-7 forbids. The globe is drawn
  from bundled vector borders instead (decision D-5). The same goes for any map view
  added later.

---

## 8. Environment traps

Two that cost time once already.

**Build products must live outside the repository.** This checkout can sit in an
iCloud-synced folder (Desktop, Documents). The file provider stamps
`com.apple.FinderInfo` onto directories it syncs, and `codesign` then refuses the test
bundles with *"resource fork, Finder information, or similar detritus not allowed"*, so
every `swift test` fails. The scripts pass `--scratch-path` into `~/Library/Caches`
to avoid it. If you invoke `swift` directly, do the same, or override with
`ANTIPODES_SCRATCH`:

```bash
swift test --package-path AntipodesKit --scratch-path "$HOME/Library/Caches/Antipodes/swiftpm"
```

**iCloud leaves duplicate files behind.** When the synced folder and a local edit
race, the file provider keeps both as `Name 2.swift`. SwiftPM compiles it and the build
fails with redeclaration errors that point at code you did not touch. Delete the
` 2` copy after checking it holds nothing newer.

**Widgets need a signed simulator build.** The widget reads the app's snapshot through
the app-group container, and an unsigned build carries no entitlements, so the widget
shows its placeholder. `scripts/build-app.sh` signs simulator builds ad hoc for this
reason; a device build needs a team in Signing & Capabilities.

**SwiftFormat rewrites force-unwraps in tests.** The default `noForceUnwrapInTests`
rule turns `foo!` into `#require(foo)`. Inside an expression that is already wrapped in
`#require`, that produces a nested macro and a *recursive expansion of macro 'require'*
compile error. Write the two steps as separate lines rather than nesting them:

```swift
let data = try #require(files["visits.csv"])          // not  files["visits.csv"]!
let text = try #require(String(data: data, encoding: .utf8))
```
