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
    AntipodesStats/      Coverage and distance stats. Pure functions over Core types.
    AntipodesExport/     CSV and JSON export of the user's whole log.
    AntipodesStore/      SwiftData models, CloudKit container, mapping to/from Core.
    AntipodesUI/         SwiftUI screens.
  Tests/                 One suite per pure module. Runs with no network, no simulator.
App/Antipodes/           Xcode app shell: @main entry, Info.plist, assets, resources.
Antipodes.xcodeproj      Thin app project; depends on the local AntipodesKit package.
Tools/placedb/           Python pipeline that builds the read-only places.sqlite.
docs/                    SPECIFICATION.md and any design notes.
scripts/                 Repo-level build, test and lint helpers.
```

### The dependency rule

```
AntipodesCore   ← depends on nothing
AntipodesPlaces ← Core
AntipodesStats  ← Core
AntipodesExport ← Core
AntipodesStore  ← Core            (SwiftData lives here and nowhere else)
AntipodesUI     ← all of the above
```

**Never invert an arrow.** In particular: `AntipodesStats` must not import SwiftData
or `AntipodesStore`, and `AntipodesCore` must not import anything but the standard
library and `Foundation`. This is what lets the whole stats engine be tested from the
command line in milliseconds. If you find yourself wanting to reach backwards, add a
value type to Core instead.

---

## 3. Commands

| Task | Command |
|---|---|
| Build the package | `scripts/build.sh` |
| Run all tests | `scripts/test.sh` |
| Lint and format | `scripts/lint.sh` |
| Build the place database | `scripts/build-placedb.sh` |
| Build the iOS app | `scripts/build-app.sh` |
| Everything CI runs | `scripts/check.sh` |

Underneath, those are just:

```bash
swift build  --package-path AntipodesKit
swift test   --package-path AntipodesKit
python3 Tools/placedb/build_placedb.py --seed Tools/placedb/seed --out <path>
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

| Source | Licence | Obligation |
|---|---|---|
| Wikidata | CC0 | None |
| GeoNames | CC BY | Attribution required |
| OpenStreetMap | ODbL | Share-alike on a *derived database* |
| OurAirports | Public domain | None |
| Natural Earth | Public domain | None |
| GTFS feeds | Varies per feed | Check each one individually |

**Rules:**

- Nothing enters `Tools/placedb/seed/` or the pipeline without its licence recorded in
  `Tools/placedb/SOURCES.md`.
- The ODbL share-alike question for a shipped derived database is **unresolved**
  (R-DB-7). Treat OSM-derived geometry as not-yet-cleared for release, and keep it
  behind the pipeline rather than hand-copied into source files.
- The data currently in `Tools/placedb/seed/` is a small hand-entered development
  seed — plain geographic facts, enough to exercise the app. It is **not** the real
  dataset and is not a substitute for the pipeline.

---

## 6. Working practice

**Before you start**

- Read the relevant section of [docs/SPECIFICATION.md](docs/SPECIFICATION.md) and note
  the requirement IDs you are implementing.
- Check the milestone tag. `[M1]` work is in scope now; `[V1]` and `[LATER]` are not —
  do not build them early, and do not quietly expand scope.

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

**SwiftFormat rewrites force-unwraps in tests.** The default `noForceUnwrapInTests`
rule turns `foo!` into `#require(foo)`. Inside an expression that is already wrapped in
`#require`, that produces a nested macro and a *recursive expansion of macro 'require'*
compile error. Write the two steps as separate lines rather than nesting them:

```swift
let data = try #require(files["visits.csv"])          // not  files["visits.csv"]!
let text = try #require(String(data: data, encoding: .utf8))
```
