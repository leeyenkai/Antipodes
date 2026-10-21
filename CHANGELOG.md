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

The V1 scope is built (decision D-18). §13.1 of the spec records what is done and what
is blocked.

### Added

- **Journeys in all eight modes** (R-LOG-6, §5): flights, rail, city transit, coach,
  ferry, road trips, on foot or by bike, and cable cars and mountain railways. A journey
  is one or more legs; each new leg starts where the last ended, the connection time
  shows between legs, and a connection can be marked missed (R-JLOG-4). Leg details —
  service number, scheduled and actual times, class, vehicle, seat, operator,
  registration, rating — stay collapsed until asked for (R-LEG-2, R-JLOG-2). Times are
  read in each end's own time zone, so flight and connection times are right across
  zones (D-13).
- **Catalogue routes** (R-JLOG-3): fourteen named journeys such as the Bergen Line and
  the Glacier Express, ridden end to end with their published length, or in part.
- **The full statistics dashboard** (§7): place attributes (landmark age, elevation,
  city population, languages, currencies, time zones), time and patterns (days away,
  trips per year, busiest month, seasonality, repeat visits, longest gaps, on this day),
  culture and themes with the travel personality (R-PERS-1 to R-PERS-3, D-15), flight
  and rail detail, punctuality, and carbon estimates with the overland saving
  (R-CO2-1 to R-CO2-3, D-14). Every number drills down to the records behind it, and
  every stat says what it could not use.
- **Achievements, wishlist and collections** (§8): 36 badges defined in the database,
  tiered where it makes sense (R-ACH-1 to R-ACH-3); a wishlist pinned on the globe in its
  own style that ticks itself off when a visit is logged (R-WISH-1, R-WISH-4); and five
  curated collections with progress — New 7 Wonders, Nordic capitals, European capitals,
  US national parks and famous rail journeys (R-WISH-2, R-WISH-3).
- **Import** (`AntipodesImport`): flight histories from Flighty, myFlightradar24,
  OpenFlights or any CSV with a date and two airport columns, matched by code with a
  review step for anything unmatched (R-LOG-8, R-JLOG-7, D-16); and visit suggestions
  from the dates and locations of photos, read on the device, opt-in, and limited to the
  photos the user allows (R-LOG-7, R-PRIV-4). Nothing about a photo is stored (D-17).
- **Sharing**: share cards for a stat, the globe, a trip, a journey or a year, in square
  and story sizes (R-SHARE-1); Year in Review as a set of cards per year, shareable as
  images (R-SHARE-3).
- **Home and Lock Screen widgets** (R-SHARE-2): countries and share of the world, the
  globe, on this day, and progress on a chosen collection. Widgets read a snapshot the
  app writes into the shared app group and never open the log or the database (D-19).
- **Mac and iPad**: a sidebar on iPad and Mac (R-NAV-1), an *All records* table for
  editing the type, date or trip of many visits at once (R-PLAT-3, R-NAV-2), and menu
  commands with keyboard shortcuts for logging.
- **The globe beside the lists on iPad and Mac** (R-NAV-1, R-PLAT-2, D-22): Trips and
  Collections keep the globe in view beside the list and every page opened from it.
  The globe frames whatever is open — a trip on its own, a visit, a journey, a country,
  a collection's members — and a tap on a pin or an arc opens that record in the list.
  On the Globe tab, what is tapped opens in an inspector beside the globe instead of a
  sheet. iPhone is unchanged.
- **Drag-and-drop import on the Mac** (R-NAV-2, R-PLAT-3): drop a flight-log CSV or an
  Antipodes JSON backup anywhere on the window. A flight log opens the same review as
  Settings ▸ Import; a backup says how many trips, places, journeys and wishlist
  entries it would add, and how many are already in the log, before anything is
  written.
- **Year in Review as a video** (R-SHARE-3): every card of the year drawn as a 1080 × 1920
  still and made into a 20-second H.264 film with cross-fades, on the device, nothing
  uploaded. The same stills can be shared as a set of images, or the year as one card.
- **Share any card** (R-SHARE-1, §9): every stat card and row on the Stats screen offers
  "Share…" in its context menu; the Globe tab, trips, journeys and the countries,
  places, distance and carbon lists have a Share button. Every share opens one sheet
  with square and story sizes and a preview that is exactly the image shared — drawn
  once, at a fixed text size, so the reader's text size cannot reflow it.
- **Wishlist from anywhere** (R-WISH-1): swipe a search result, or touch and hold it, to
  add it to the wishlist, with a star on the places already there; a dropped pin — from
  the add sheet or a long press on the globe — can be saved to the wishlist instead of
  logged. Wishlisting a route no longer marks its first station as wishlisted. Return
  in a search field picks the top result.
- **Widgets open the app where they point** (R-SHARE-2, D-25): Countries opens Stats,
  Globe the globe, a collection its own page, and each "On this day" memory the visit
  or journey it remembers, through `antipodes://` links handled on the device. "On
  this day" now carries the next two weeks, so it stays right on days the app is not
  opened; it had gone blank the morning after. Widgets have accessibility labels, and
  the extension has its own privacy manifest. The app writes the widgets' snapshot a
  moment after a burst of edits settles, and only when something changed.
- **The app icon** (D-24): "Great circle" — one great circle on a glass Earth, carrying a
  place on its near side and its antipode on the far side. A layered Icon Composer
  document generated from geometry by `Tools/icon/build_icons.py`, so iPhone, iPad and
  Mac draw it with Liquid Glass in every appearance (default, dark, clear and tinted).
  `Tools/icon/render.sh` renders it with Xcode's `ictool`, beside the two concepts it was
  chosen from. It replaces a flattened PNG with an alpha channel, which App Store Connect
  rejects, and hand-made Mac sizes.
- The icon's Earth carries real continents, projected from Natural Earth so the near
  point is Madrid and the far point, seen through the glass, its true antipode off New
  Zealand. A deeper sky, a two-tone ocean, sage land, and tinted and clear renditions
  that keep land and sea apart.
- A vector version of the same mark signs share cards and Year in Review instead of a
  generic globe symbol.
- Spec 0.6.0: D-26 (satellite globe), D-27 (journey lists), and §13.1 brought up to
  date, naming what still waits for data — climate zones, mountain passes, a nightlife
  theme and eras for undated landmarks.
- **Stats can be filtered** by year, trip, mode and purpose (§5.7). A banner says what
  slice is showing; a mode or purpose keeps journeys only, since places have neither,
  and asking for commutes counts them whatever the counting rule.
- **Road and sea** (§5.7): distance driven, ferries taken, the longest sea crossing and
  the ships sailed on. Rail adds the classes and train types travelled in.
- **Punctuality by mode and by operator** (§5.7): every operator's average delay, each
  mode's, and the worst delay's route; time travelling breaks down by mode.
- **Every figure opens what it rests on** (§7): landmark age, elevation and city size
  open their places ranked; time zones, main languages and currencies open the places
  and countries under each; the busiest day opens that day's legs, punctuality its timed
  arrivals, night trains, overland and connections their own legs; each theme in the
  personality opens its landmarks.
- **Share a personality, a badge or a collection** (R-SHARE-1, §9 "share any card"):
  each has its card, square or story, with its symbol where other cards have a globe;
  share from the personality screen, a badge's sheet, a collection, or the hero's menu.
- **Rail logs and any journey list import** (R-JLOG-7, R-LOG-8, D-27): the importer
  reads a mode column, rail-log columns and stated distances, and JSON lists as well as
  CSV. Stations and towns are matched by name to bundled places, airports by code, and
  a list with no mode column is read as whatever the user says it is. Dropping a JSON
  journey list on the Mac window opens the same review.
- "On this day" on the Lock Screen (R-SHARE-2): a rectangular size with the day's first
  memory, in the system's monochrome.
- Wishlisted routes on the globe (R-WISH-1): a catalogue route on the wishlist is drawn
  dashed between its two ends in the wishlist colour, outside every count.
- **Ride again in one tap** (R-JLOG-6): the journey sheet lists the last few rides to
  log again for today, and any leg of a longer journey can be ridden again.
- **Satellite globe** (D-26, R-GLOBE-1): the globe can be drawn from NASA's Blue Marble
  instead of the vector map — from the globe's toolbar or Settings. One picture of the
  whole Earth ships in the app and is wrapped round the sphere on the device, so it
  works offline and turning it asks nothing of any server. Country outlines draw over
  it, visited ones washed in the visited colour.
- **Replay plays** (§9, R-GLOBE-6): the replay is a play button beside the scrubber now,
  stepping trip by trip through the whole log in about fifteen seconds, and stopping
  when the scrubber is touched. It had only parked the scrubber at the end.
- Surface legs are dashed on the globe, since the great circle drawn is not the road or
  track they took (R-PATH-3).
- Onboarding: what the app does, what it never does with your data, and where home is.
- Settings: appearance, home, counting rules, units, a JSON backup that can be restored,
  CSV export, imports, a plain-language account of how things are counted, and the data
  sources with their credits.
- `-seedSampleData` launch argument, debug builds only, for screenshots and manual
  testing.

### Added (M1)

- The v1 globe screen: a 3D globe drawn by the app rather than fetched, with visited
  countries shaded, pins for places, great-circle arcs for journeys, filtering by year,
  trip and mode, tap-to-open on any pin or arc, and a timeline that replays the log
  (§9.1, R-GLOBE-1 to R-GLOBE-7). Resolves [Q-3](docs/SPECIFICATION.md#15-open-questions)
  as decision D-5: MapKit cannot render without fetching map content, and what it
  fetches follows wherever the user's own travel puts the camera, which R-PRIV-7 does
  not allow. The globe renders with no network access at all.
- `AntipodesGlobe`: a pure module holding the orthographic projection, limb clipping of
  arcs and filled country rings, bounding-box culling, hit testing, the `.antborders`
  decoder, scene building from the log and the replay timeline. 71 tests, no SwiftUI
  and no MapKit.
- `Tools/placedb/build_borders.py` plus `scripts/fetch-borders.sh` and
  `scripts/build-borders.sh`: build the bundled country outlines from public-domain
  Natural Earth, 96 KB at 1:110m and 821 KB at 1:50m, deterministically. Land the
  source has no ISO code for (Northern Cyprus, Somaliland, the Siachen Glacier) is
  drawn but never shaded, and the count is in the file header rather than silently
  dropped — which of those counts as a country is
  [Q-4](docs/SPECIFICATION.md#15-open-questions)'s business, not the pipeline's.
- Wishlist pins have a seam but no feature: `GlobeSceneBuilder` takes wishlist places
  and styles them distinctly (R-GLOBE-4, `[V1]`), so adding the wishlist later is a
  matter of passing a non-empty array.

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

- **Schema version 3.** Row ids are now the upstream identities — GeoNames id, Wikidata
  QID number, OurAirports id, and a number derived from the ISO code for countries — so
  a logged place survives any rebuild of the database (D-12).
- Every place carries an IANA time zone where it can be known: cities from GeoNames,
  airports and landmarks from the bundled cities within 75 km when they agree, or a
  single-zone country. 85% of airports and 90% of landmarks get one; the rest stay empty
  rather than guessed (D-13, R-DB-2).
- New tables for routes with resolved start and end places, themes, collections and
  their members, achievements, and carbon factors. Achievements and collections ride in
  the database so updates can add them without an app release (R-ACH-1, R-DB-6).
- Carbon factors from the UK Government's 2025 GHG conversion factors (DESNZ, Open
  Government Licence v3), read from the published file; the curation sheet names only
  which factor each mode and class uses (D-14). Credited in Settings.
- 60 US national parks added to the landmarks, for the collection of the same name: 296
  landmarks in all.
- GeoNames' "no data" elevation of −9,999 m is stored as unknown. It had made Tromsø
  the lowest place anyone had visited.
- The satellite globe's picture: NASA Blue Marble Next Generation (August 2004, with
  topography and bathymetry), public domain, fetched once by `scripts/fetch-imagery.sh`,
  digest-verified and scaled to 4096 × 2048. Recorded in `Tools/placedb/SOURCES.md` and
  credited in Settings (D-26).

### Data (M1)

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

- **A quieter, more refined look.** One sea-glass teal is the brand and the visited
  colour, pins are champagne, and the eight modes share a muted, evenly weighted set
  used identically on the globe, in charts and in lists. Chrome is neutral: row tiles
  and section headers no longer carry a different bright colour each. Figures are set
  in SF Pro with even digits, lighter as they grow, instead of bold rounded; display
  titles — a travel personality, a Year in Review card, onboarding, share cards — are
  in New York. Cards, rings and bars are thinner, badges are flat medallions without a
  glow, Year in Review fades in rather than bouncing, and the globe's arcs and pins are
  finer with a softer glow. The mode picker's tiles are neutral, coloured only by their
  symbol, and the globe and Stats filters open as short submenus. Widgets follow.

- **Release hygiene**:
  - Saving a share card or a Year in Review video to Photos would have ended the app:
    the photo-library add-usage string was missing. It is there now.
  - An app build fails, with instructions, when the place database or either outline
    file is missing, instead of shipping with empty search and an unshaded globe.
  - The version and build number are set once, for the app and the widgets together.
  - `scripts/check.sh` also builds the app for the iOS Simulator and the Mac, and a lint
    failure now fails the check.
- **Faster journeys** (R-JLOG-1): choosing a mode opens the search for where the leg
  started, and choosing that opens the search for where it ended — a flight is mode,
  from, to, save. A connecting leg opens straight on its destination.
- **Undo**: deleting a place, a journey, a trip or a wishlist entry shows "Undo" for a
  few seconds, and puts the records back by their own identity — a trip gets its
  places back. Swipe to delete stays one gesture; the delete buttons in forms say the
  deletion can be undone. "Ride Again" no longer logs a journey on a full swipe.
- **Every number opens what it rests on** (§7): continents, the world share, the round
  the Earth and Moon figures, flight hours, airlines, aircraft, every rail and
  punctuality row, the highest and lowest places, every place attribute, days away,
  trips, average trip, the busiest month, places returned to, and carbon by mode. A
  place visited more than once opens all its visits rather than the first.
- Year is chosen from a menu rather than a stepper, and the date's precision becomes a
  menu where five segments will not fit.
- Empty states: a search that finds nothing in Trips or All Records says so; a
  collection with nothing left says "Every one ticked off"; badges say why they are
  missing if the place list could not be read.
- **Liquid Glass**: the globe's summary and its caveat, and the replay bar with its
  warning, are each one glass container; buttons in the content layer are bordered
  rather than glass; toolbar confirm buttons take the system's own prominent style.
- **Accessibility**: VoiceOver can turn the globe east, west, north and south, zoom by
  swiping up and down, and open any of the ten places nearest the middle of the view;
  the globe says which way it faces. The replay button is a full-size target. The
  globe's summary and the theme and Year in Review tiles grow with the text size, and a
  badge's detail scrolls. Photo suggestions report whether they are selected.
- Haptics when a pin is dropped, a wishlist place toggled, and the replay steps.
- On iPad and Mac, the Trips menu and the wishlist's add button no longer show a second
  "+" beside the Log button.
- **Mac**: Settings open in their own window with ⌘, (and leave the sidebar); ⌘1 to ⌘4
  switch between Globe, Trips, Stats and Collections; ⌫ deletes the selected rows of
  All Records after asking. The menu commands live in the package (`AppCommands`).
- Units read "Kilometres and metres" or "Miles and feet" — what the app shows today.
- The SwiftData schema is versioned from the first release (`AntipodesSchemaV1` with an
  empty migration plan), so a later change that is not purely additive has somewhere
  to put its migration.
- Forms use the grouped style on the Mac too, where the default laid them out in
  columns; Settings in the sidebar has no Done button, since it is not a sheet there.
- **Dark appearance by default**, with Light and System in Settings, and a dark launch
  screen to match (D-20).
- The app's identifiers are `com.leeyenkai.antipodes`, with app group
  `group.com.leeyenkai.antipodes` and iCloud container `iCloud.com.leeyenkai.antipodes`.
  The Mac app is sandboxed, with access to files the user picks and to Photos (D-21).
- `scripts/build-app.sh` signs simulator builds ad hoc, so the app-group entitlement the
  widgets depend on is present; device and Mac builds stay unsigned.
- The SwiftData model gains the wishlist and the new leg fields. Every new property is
  optional or defaulted, so existing stores migrate lightweight.
- Long source files are split by concern (`JourneyLeg.swift`, `AppModel+Search.swift`,
  `AppModel+Widgets.swift` and others). A handful of single-pass algorithms carry a
  documented SwiftLint region instead of being broken up; `scripts/lint.sh --check`
  reports nothing.

### Fixed

- "Longest journey" took the longest of all journeys, so one long flight hid it; it is
  the longest journey of more than one leg, as its title says.
- A ride logged again joins the original's trip only while that trip is under way; it
  had filed today's ride under a trip from years ago.
- The Equator and Arctic and Antarctic Circle badges follow each flight's whole arc, so
  a polar flight counts though neither end is inside the circle; "UNESCO sites in one
  trip" has its earned-on date.
- Countries overland and by rail include every country a catalogue route ridden in full
  runs through, not only its two ends.
- The lists behind journey figures, and a trip's distance in the Trips list, follow the
  commute rule like the figures do.
- Every carbon figure names its factors and their year: a trip's, the carbon-by-leg list
  and a shared carbon card (R-CO2-3).
- The globe's trip filter named every trip without a name "Untitled trip"; it uses the
  trip's dates and first place, as the Trips list does.
- The place database opens as immutable, so SQLite takes no file locks on it. A file
  provider touching it — iCloud Drive syncing a checkout — could fail a read with
  "database is locked".
- **Edits no longer vanish.** Every edit form saves only on its confirm button, and now
  leaving any other way asks first: while there are unsaved changes, Back gives way to
  Cancel, Cancel asks "Discard your changes?", and a sheet cannot be swiped away. The
  globe's sheet on iPhone had two "Done" buttons, one of which threw edits away; it now
  has Close or Cancel and Save. On iPad and Mac, tapping another pin while the inspector
  holds unsaved edits asks before replacing them. A form whose save failed stays open.
- The distance on a leg accepts decimals ("2.5") and keeps an override exactly instead
  of rounding it on every save; a duration is chosen as hours and minutes instead of a
  5-minute stepper. Coordinates for a dropped pin can be typed negative on iPhone.
- "Log Another Visit Here" and a wishlist pin's "Log a Visit" did nothing on iPhone,
  because the add sheet cannot open over the globe's sheet; it now opens once that
  sheet has closed. The globe's sheet follows the app's appearance instead of always
  being dark.
- Creating a trip that fails says so instead of doing nothing.
- The replay turns the globe to the newest record by date rather than the last one read,
  after the scene has moved on, and starts again when a filter changes. A pinch that
  drifts into a drag keeps its zoom.
- A trip dated only "2019" reads "2019", not "1 Jan – 31 Dec 2019 · 365 days"; the trip
  list counts countries by the counting rules, like the trip itself.
- Narrowing an iPad window while on All Records or Settings no longer leaves a blank
  screen, and All Records is reachable on every iPhone, held either way.
- On the Mac, Year in Review and onboarding page with arrows and the arrow keys instead
  of showing as unlabelled tabs, and Year in Review opens at a sensible size.
- Restoring a backup from Settings shows what it will add first, as dropping one on the
  Mac window does, and counts wishlist entries. A dropped link explains what can be
  imported; the result of a dropped backup no longer goes missing behind its own
  confirmation. Closing the photo import stops its scan.
- Plurals: "1 day", "1 country · 1 continent", and "Longest since" in months or days
  rather than "0 years". Requirement IDs no longer appear in Settings' text.
- Smoother: a trip's statistics are worked out off the main thread and only when the
  log changes, trip thumbnails are drawn once per change, the detailed outlines load in
  the background at launch, and a damaged outline file is tried once rather than on
  every frame. The globe no longer changes state while it is being drawn.
- Reduce Motion stops the onboarding globe turning and calms Year in Review.
- **Flight imports** (R-LOG-8, D-16):
  - Airports given by their four-letter ICAO code (`ENGM`) are matched; they had always
    needed choosing by hand.
  - A flight already logged without its number is recognised as the same flight as an
    imported SK903 on that day and route, and a flight listed twice in one file is
    imported once.
  - Flighty's cancelled flights are shown in the review but not imported; a diverted
    flight lands where it actually landed, with a note.
  - 12-hour times (`8:35 PM`), times stamped with a zone (`08:35Z`), year-first dates
    (`2024/06/12`), westbound flights that land two days later, a stated flight time,
    a quoted field after a space, and UTF-16 "Unicode text" from Excel all read
    correctly. In a name written all in capitals the code is taken from the end.
  - Import errors read as sentences, not as Swift type names.
- **Export** (R-LOG-9): text a spreadsheet would run as a formula is defused with a
  leading apostrophe; `from_code`/`to_code` hold the airport's own code, with the
  internal id in new `from_place_id`/`to_place_id` columns; the overrides, a visit's
  region name, city id and logged date are exported too. A backup from a newer version
  of the app is refused with a clear message rather than half-restored, and a backup
  whose trips are missing says how many records will arrive unfiled.
- **A trip across New Year no longer disappears.** A range such as 28 December to
  3 January had no year, so it fell out of every per-year view, the globe's year filter,
  Year in Review and carbon by year, while the Stats screen filed it under its first
  year. It now belongs to the year it began everywhere (D-23).
- **Capitals reached through a landmark count.** Logging only the Eiffel Tower counted
  Paris as a city but not as a capital, because Paris's facts were never fetched.
- **An airport no longer implies its city** (R-MODEL-6). A layover at Heathrow, with
  layovers counted, had ticked off London, "European capitals" and the capitals badges.
- Year in Review no longer calls a country new when an undated visit there might have
  come first; it says such countries may be new instead.
- Riding part of a catalogue route — Oslo to Finse on the Bergen Line — no longer
  completes the route in collections and the wishlist, or claims its highest point.
- Badges and collections show an earned or first-visited day only when the records
  behind it are dated to the day, instead of 1 January for a visit dated "2019".
- The "Round the world" badge and "× round the Earth" now use the same circumference
  (the Equator's 40,075 km), so 1.00× and the badge arrive together.
- A flight with no distance still counts as a flight; it is left out of the kilometres
  and the average only. The trips badge ignores trips with nothing in them.
- More stats say what they left out (R-CALC-5): places per year, longest since a
  country, the busiest travel day, rail distance, the highest and lowest places, and
  days away, which now also follows the visit-type rule and says how many visits were
  at home. "% of the world" says when the country list could not be read.
- A dropped pin in Chukotka or Fiji's eastern islands resolves to its country: rings
  closed along the antimeridian are no longer turned inside out.
- A selected wishlist pin stays selected when the globe redraws.
- Date spans follow the device's day–month order.
- The antipodes badge finds the closest pair with a dot product per pair instead of a
  haversine — the same answer, a fraction of the work on a long log.
- **A record held twice is counted once.** CloudKit cannot enforce a unique identity,
  so a backup restored on two devices before they synced left every record twice:
  totals doubled and *All records* crashed. The log is now read one record per
  identity, and every edit and delete reaches all copies so they never drift apart
  (R-CALC-5, R-PRIV-6).
- A flight or photo import lands whole or not at all; a failure part-way no longer
  leaves half of it in the log. A failed save is rolled back rather than left pending.
- *Delete everything* also forgets the home place, and the widgets' globe is redrawn
  without it (R-PRIV-6).
- If the travel log cannot be opened, the app says so and offers to try again, instead
  of quietly running on an empty log in memory that would be lost at the next launch.
- A missing place database no longer tells the user to run a developer script.
- A shaded country lying just past the edge of the globe could be filled across the
  whole visible face, turning the ocean green or grey whenever the globe faced Japan.
  The edge of a clipped outline now follows the hidden part of the outline round the
  limb instead of guessing the direction from one point of it.
- Settings on the Mac did not scroll: the top and bottom of it were cut off.
- The Collections section picker showed a stray "Section" label on the Mac.
- Collections, badges and carbon could stay empty after launch until the next edit,
  when the log's place facts arrived before the database catalogue had loaded.
- The globe's summary counted every country while Stats counted only those on the
  chosen list; both now count the listed ones.
- Onboarding stuttered and could ignore taps while its globe was drawn on the main
  thread every frame.
- Picking a leg's endpoint could dismiss the whole add sheet.
- iPhone showed a stray "More" tab for destinations meant only for the sidebar.
- "On this day" could crash when the range ran into the current year.

### Changed (M1)

- `StatInputSummary` and `ExclusionReason` moved from `AntipodesStats` to
  `AntipodesCore`. The globe reports what it could not draw in the same terms a
  statistic does, and the two should not word it differently (AGENTS.md §2).
- The globe's summary bar now reports the scene it is showing rather than whole-log
  totals, so filtering or scrubbing the replay changes the numbers with the picture.
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

- `scripts/check.sh` passes: the database and borders build, the package builds clean,
  261 tests pass with no network and no simulator, and SwiftFormat and SwiftLint
  (strict) report nothing.
- The app builds for the iOS Simulator and for macOS. On an iPhone simulator:
  onboarding, logging a place, a flight leg (SIN → SYD, 6,293 km), the globe with
  shading, pins, arcs, wishlist and home markers, trips, every stats section, Year in
  Review, collections and badges; all four widgets render live data from the app's
  snapshot. On an iPad simulator the globe opens with the sidebar-adaptable tab bar.
- Not checked by eye: the Mac app's windows, the photo and flight import flows end to
  end, and anything on a physical device.

### Verified (M1)

- `scripts/check.sh` passes: the place database builds (byte-identically on a rebuild),
  the package builds clean, and 104 tests pass with no network and no simulator.
- The app builds for both the iOS Simulator and macOS, and runs on an iPhone simulator:
  searching "oslo" offline returns the city, then the region, then OSL; a visit saves
  and the stats recompute to 1 country / 0.5% of the world / 1 of 7 continents with the
  city, region and country chain counted; an OSL→JFK flight reports 5,917 km against a
  published great-circle figure of about 5,920 km, and draws as a curved arc on the
  globe (M1 acceptance criteria 1, 2, 4, 5, 6, 8, 11).

### Notes

- Blocked, and recorded as such in §13.1 of the spec: city transit lines and packs and
  path snapping (they need OpenStreetMap-derived packs, which D-8 keeps out of the
  bundled database), database updates from a host (R-DB-5 needs a host), temperature in
  the month visited (R-CALC-2 needs a licensed climate-normals source), and Year in
  Review as video.
- Owner's tasks before release: set a development team so device and Mac builds sign,
  enable the iCloud capability (the keys are in `App/Antipodes/Antipodes.entitlements`),
  and check the name (R-NAME-1).
- The hand-entered development seed is gone: the pipeline now builds from Natural
  Earth, GeoNames, OurAirports and Wikidata, and the licence review behind R-DB-7 is
  complete. See `Tools/placedb/SOURCES.md`.
- No release has been made. Version numbers begin at the first tagged build.
