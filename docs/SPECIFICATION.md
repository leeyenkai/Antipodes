# Antipodes — Specification

| | |
|---|---|
| **Status** | Draft |
| **Spec version** | 0.13.0 |
| **Last updated** | 2026-10-22 |
| **Owner** | Lee Yen Kai |
| **Source** | Derived from *Antipodes — Spec Sheet (Draft v0.1)* (2026-10-15) |

This is the living requirements document for Antipodes. It will change as the app is
built. Requirements carry stable IDs (`R-<AREA>-<n>`) so commits, issues and
[CHANGELOG.md](../CHANGELOG.md) entries can point at them. Open questions live in
[§15](#15-open-questions) and are resolved into requirements as decisions are made.

**Conventions used below**

- **MUST** — required for the release it is scoped to.
- **SHOULD** — intended, but may be dropped under time pressure without changing the product's identity.
- **MAY** — optional.
- *Milestone tags*: `[M1]` first internal milestone · `[V1]` public v1 release · `[LATER]` post-v1.

---

## 1. Overview

A free, privacy-first iPhone app (with iPad and Mac versions) for logging every place
and journey you have travelled, then turning that log into unusually deep statistics.
Think Flighty's polish and data depth, applied to all travel rather than flights alone.

### 1.1 Goals

| ID | Goal |
|---|---|
| G-1 | **Fast logging.** Search a bundled database and tap, instead of typing details by hand. |
| G-2 | **Stats nobody else offers.** Place attributes (landmark age, climate in the month you visited) and a "travel personality" built from what you choose to see. |
| G-3 | **Private by design.** No account, no server, no sync; the log stays on the device (D-31). |
| G-4 | **Beautiful to look at and share.** A 3D globe as the home screen, and shareable stat cards. |

### 1.2 Non-goals for v1

- Social feed, friends or following.
- Live flight tracking (Flighty's core feature). This app logs journeys; it does not track them in real time.
- Booking, recommendations or itinerary planning.
- Android or web versions.

### 1.3 Positioning

Flight loggers cover one mode deeply; country-checklist apps cover everywhere
shallowly. Antipodes covers **every mode** (places, flights, rail, road, sea, trails)
with **flight-logger depth**, and keeps it all **private**.

### 1.4 Name

Working title **Antipodes** — points on exactly opposite sides of the globe.
Globe-centric, and doubles as a stat ("your antipode").

| ID | Requirement |
|---|---|
| R-NAME-1 | Before public release, "Antipodes" MUST be checked against the App Store and the relevant trademark registers. `[V1]` |

Candidates kept for reference: Hither, Gazetteer, Kilometre Zero, Postmark, Footnote,
Farther. See [§15](#15-open-questions).

---

## 2. Platforms and users

iPhone is the primary platform; iPad and Mac ship as the same multiplatform app with
adapted layouts.

| ID | Requirement |
|---|---|
| R-PLAT-1 | iPhone is primary. Every flow MUST be usable one-handed. `[M1]` |
| R-PLAT-2 | iPad MUST use sidebar navigation with a large globe and an inspector panel side by side. `[V1]` Built (D-22). |
| R-PLAT-3 | Mac MUST support bulk work: file import, editing dates across many visits, browsing stats on a large screen. `[V1]` Built. |
| R-PLAT-4 | Distribution is the App Store, free, with no monetisation at launch. `[V1]` |
| R-PLAT-5 | One multiplatform codebase; no per-platform forks. `[M1]` |

**Minimum OS.** Current working decision: **iOS/iPadOS 26.0 and macOS 26.0**
(latest minus one, against the iOS 27 SDK). Tracked as [Q-2](#15-open-questions).

### 2.1 Target users

- Frequent travellers who enjoy data about themselves (the Flighty, Strava and Spotify Wrapped crowd).
- Rail, aviation and road-trip enthusiasts who want to log specific journeys.
- Students on exchange, expats and digital nomads building up a long travel history.
- Privacy-conscious users who will not hand their movement history to an account-based service.

---

## 3. Core concepts and data model

A **trip** holds **visits** and **journeys**; each one points at an entry in the
read-only **place database**, which is what lets the app compute stats without asking
the user for details.

User data stays on the device (D-31). The place database ships with the app and is
identical for every user.

```
Trip ──┬── Visit  ───────> Place (country | region | city | landmark | airport | custom pin)
       └── Journey ──┬── Leg ──> From place, To place, mode, service detail
                     └── Leg ──> …
```

| ID | Requirement |
|---|---|
| R-MODEL-1 | A trip MUST group zero or more visits and zero or more journeys, and MAY be unnamed. `[M1]` |
| R-MODEL-2 | A visit MUST reference exactly one place and carry a visit type and a flexible date. `[M1]` |
| R-MODEL-3 | A visit MAY exist without a trip and be assigned to one later. `[M1]` |
| R-MODEL-4 | A journey MUST consist of one or more ordered legs. `[M1]` |
| R-MODEL-5 | User data and the place database MUST be stored separately; the place database is read-only. `[M1]` |
| R-MODEL-6 | Logging a landmark MUST imply its city, region and country. Logging a city MUST imply its region and country. `[M1]` |

### 3.1 Visit types

| Visit type | Meaning | Counts towards coverage by default |
|---|---|---|
| Stayed | At least one night there | Yes |
| Day trip | Visited without staying overnight | Yes |
| Passed through | Crossed it by road, rail or sea without stopping to visit | No |
| Layover | Changed planes or trains without leaving the station or airport | No |

| ID | Requirement |
|---|---|
| R-MODEL-7 | A global setting MUST let the user include "Passed through" and "Layover" in coverage, and every stat MUST respect it. `[M1]` |

### 3.2 Flexible dates

| ID | Requirement |
|---|---|
| R-DATE-1 | A date MUST be expressible as an exact day, a date range, a month, a year, or unknown. `[M1]` |
| R-DATE-2 | Stats that need a date MUST skip undated visits and MUST say that they did so. `[M1]` |
| R-DATE-3 | Where only a year is known, a stat MAY fall back to an annual figure, and MUST flag that it did. `[V1]` |

---

## 4. Logging and input

Searching the bundled database and picking a result is the main way in. Every other
route is optional and runs entirely on the device.

| ID | Requirement | Milestone |
|---|---|---|
| R-LOG-1 | One search field across countries, cities, landmarks, airports and routes, with type filters. MUST work offline. Results ranked by population and fame. | `[M1]` |
| R-LOG-2 | The user MUST be able to create a trip and add visits and journeys to it. | `[M1]` |
| R-LOG-3 | A visit MUST be quick-loggable on its own and assignable to a trip later. | `[M1]` |
| R-LOG-4 | Every visit MUST carry a visit type (§3.1). | `[M1]` |
| R-LOG-5 | Custom places: the user MUST be able to drop a pin for anything not in the database. It MUST be assigned a country and region automatically from bundled border data, so it still counts in coverage. | `[M1]` |
| R-LOG-6 | Journeys for all eight modes (§5.1), each made of one or more legs. | `[V1]` |
| R-LOG-7 | Photo library import, opt-in: read location and date from on-device photos, cluster into suggested trips and visits, confirm each. Nothing is uploaded, and nothing about a photo is stored (D-17). | `[V1]` |
| R-LOG-8 | Import from other apps: CSV or JSON from flight loggers and similar trackers, matched against the database, with a review screen for anything ambiguous. | `[V1]` |
| R-LOG-9 | Export everything as CSV or JSON at any time. | `[M1]` |

---

## 5. Journeys

Every journey is a chain of one or more legs, and every ground leg follows real tracks
or roads. Distances, network completion and carbon estimates all come from that same
path, so the numbers agree with what the globe shows.

### 5.1 Modes

| Mode | Examples | Picked from the database | Path drawn from |
|---|---|---|---|
| Flight | Scheduled, charter, private | Airports, airlines, aircraft types | Great-circle arc between airports |
| Long-distance and regional rail | Intercity, high-speed, regional, sleeper and night trains | Stations, operators, named services, famous routes | Railway lines from OpenStreetMap |
| City transit | Metro, tram, light rail, suburban rail, local bus, city ferry | Transit systems, lines, stops | Line shapes from transit feeds, OpenStreetMap as fallback |
| Intercity bus and coach | Scheduled coaches, airport buses, rural buses | Bus stations and stops, operators | Roads, snapped with a road router |
| Ferry and cruise | Car ferries, coastal voyages, river cruises, ocean cruises | Ports, operators, ships, ferry routes | OpenStreetMap ferry routes; cruises as port-to-port legs |
| Self-drive road trip | Car, campervan, motorbike | Famous roads and passes, towns as waypoints | Roads, snapped with a road router |
| Human-powered | Hikes, long-distance trails, cycle tours | Named trails (e.g. Camino de Santiago) | Trail geometry from OpenStreetMap |
| Cable and mountain | Cable cars, gondolas, funiculars, cog railways | Named lines | OpenStreetMap aerialway and railway lines |

### 5.2 What a leg records

Only mode, origin and destination are required. Every other field is optional and
appears when the user expands the leg.

| Field | Modes | Notes |
|---|---|---|
| From, to, intermediate stops | All | Station, stop, port, airport or custom pin. Stops passed through are derived from the path. |
| Date | All | Same flexibility as visits (§3.2) |
| Scheduled and actual times | All public modes | Delay = actual − scheduled. Time zones come from the stations, so overnight and cross-border legs are correct. |
| Operator | All public modes | e.g. Vy, SJ, a coach company, a ferry line |
| Service or line number | Rail, coach, transit, flight | Train number, line number, flight number |
| Named service or route | Rail, ferry, road, trail | Links to a catalogue route such as the Bergen Line or the Glacier Express |
| Class or fare type | Rail, coach, ferry, flight | Standard, first, business, sleeper berth, couchette, cabin, deck passage |
| Vehicle | Rail, coach, ferry, flight, road | Train class or type, bus model, ship name, aircraft type and registration, own car |
| Seat, carriage, cabin | All public modes | Structured fields plus free text |
| Purpose | All | Leisure, work or commute. Commute legs can be kept out of stats. |
| Rating and notes | All | 1 to 5 stars, notes, references to photos |
| Distance and duration | All | Computed from the path and times; the user can override either |

| ID | Requirement |
|---|---|
| R-LEG-1 | Mode, origin and destination MUST be the only required fields on a leg. `[M1]` |
| R-LEG-2 | Detail fields MUST be collapsed by default and revealed on expand. `[V1]` |

### 5.3 Logging journeys

A quick leg SHOULD take about four taps after search; detail is added only when the
user wants it.

| ID | Requirement | Milestone |
|---|---|---|
| R-JLOG-1 | **Quick leg**: pick a mode, search origin, search destination, set the date. Path and distance fill in automatically. | `[M1]` (flights) |
| R-JLOG-2 | **Detailed leg**: expand the same leg to add service number, times, class, vehicle, seat and rating. | `[V1]` |
| R-JLOG-3 | **Catalogue route**: pick a named route (e.g. the Glacier Express). Stations are pre-filled; the user rides the whole route or picks a section by choosing where they got on and off. | `[V1]` |
| R-JLOG-4 | **Multi-leg journey**: add legs one after another. Each new leg starts where the last ended, the connection time shows between them, and a connection can be marked as missed. | `[V1]` |
| R-JLOG-5 | **City transit ride**: pick the city, the system, the line, then boarding and alighting stops. Times optional. | `[V1]` |
| R-JLOG-6 | **Repeat rides**: a "ride again" button duplicates a leg with today's date. A regular commute MAY be logged as a *pass* (e.g. "line 1, weekdays, Sep to Dec") that counts the line once for coverage without creating hundreds of records. | `[V1]` |
| R-JLOG-7 | **Import**: flight histories and rail logs from other apps, matched to stations and airports with a review screen. | `[V1]` |
| R-JLOG-8 | Timetables are NOT bundled and nothing is looked up online in v1; times are entered by hand. | `[V1]` |

### 5.4 City transit

Transit is modelled as systems, lines and stops; each ride is stored as the
stop-to-stop segments it covered. The launch set's stations, lines and links come from
Wikidata and are built into the bundled database ([D-29](#121-implementation-decisions)).

| ID | Requirement |
|---|---|
| R-TRAN-1 | A system (e.g. Oslo Metro) has lines; each line has an ordered list of stops and a drawn shape. Branches and loops are separate stop sequences on the same line. `[V1]` |
| R-TRAN-2 | The unit of coverage is the **segment**: the stretch between two adjacent stops on a line. Coverage and completion MUST be measured in unique segments ridden, so riding the same stretch twice adds rides but not coverage. `[V1]` |
| R-TRAN-3 | Stations MUST be tracked three ways — boarded, alighted, passed through — and stats MUST be able to count any of these. `[V1]` |
| R-TRAN-4 | Rides MUST be stored against stop identities and a dated network version, so a 2019 ride on a line that no longer exists still shows correctly. `[V1]` |
| R-TRAN-5 | Transit data ships as **city packs**: a launch set of major systems in the app, other cities downloadable. Every user downloading a city receives the same file. `[V1]` |
| R-TRAN-6 | Rail-based systems (metro, tram, light rail, suburban rail) come first. City bus lines follow per city as data allows. `[LATER]` |

### 5.5 Paths and distances

Ground legs follow real tracks, roads and sea lanes; a straight line is used only as a
labelled fallback.

| ID | Requirement |
|---|---|
| R-PATH-1 | Catalogue routes and transit lines: paths are built in the offline data pipeline by routing along the OpenStreetMap rail, road or ferry network, then simplified and stored in the database. `[V1]` |
| R-PATH-2 | User-built ground legs are snapped **on the device** using a regional network pack (rail lines and main roads). No request leaves the phone. `[V1]` |
| R-PATH-3 | If no pack is installed or no route is found, the leg MUST be drawn as a straight line and marked "approximate" in stats until it can be snapped. `[V1]` |
| R-PATH-4 | Flights use great-circle distance between airports; the arc on the globe follows the same curve. `[M1]` |
| R-PATH-5 | Distance and every distance-based stat MUST come from the stored path, never from a straight-line estimate when a real path exists. `[V1]` |
| R-PATH-6 | Derived from the path: stations and stops passed through, borders crossed, tunnels and bridges passed (from OpenStreetMap tags), and an elevation profile with the highest point. `[V1]` |
| R-PATH-7 | Elevation for catalogue routes is computed in the pipeline; for user-built legs it comes with the regional pack or is skipped. `[V1]` |

### 5.6 Journey data sources

What is in use is licence-reviewed and listed in §6 and
[Tools/placedb/SOURCES.md](../Tools/placedb/SOURCES.md); the rest are candidates, not yet
reviewed.

| Data | Source | Status |
|---|---|---|
| Railways, roads and ferry routes to measure legs along | Natural Earth 1:10m (public domain) | **In use** (D-30) |
| City transit systems, lines and stops | Wikidata (CC0) | **In use** (D-29) |
| Airports | OurAirports (public domain) | **In use** |
| Emission factors | UK DESNZ greenhouse-gas conversion factors (OGL) | **In use** (D-14) |
| Famous routes | Manual curation | **In use** |
| Detailed railway lines, trails, cable cars, tunnels, bridges, stations | OpenStreetMap, OpenRailwayMap tagging | Excluded from the bundled database: ODbL (D-8) |
| Track shapes of transit lines | GTFS feeds through the Mobility Database and Transitland | Not reviewed; licence differs per feed |
| Operators, train classes, bus models, ships | Wikidata, manual curation | Candidate |
| Airlines, aircraft types | Wikidata | Candidate; typed by hand today |

### 5.7 Journey stats

These extend the *Distance and routes* family (§7). Each one MUST be filterable by
mode, year, trip and purpose.

| Group | Stats |
|---|---|
| Totals | Km and hours by mode, times round the Earth, longest leg, longest multi-leg journey, most legs in one day, most modes in one journey |
| Rail | Operators ridden, train classes and types, named services, stations visited and passed through, sleeper nights, countries and borders crossed by rail, highest point reached by rail, longest tunnel |
| Punctuality | Average delay by operator and mode, most and least punctual operator, connections missed |
| City transit | Systems ridden worldwide, lines ridden, stations visited, % of each network ridden |
| Network completion | % of a country's rail network ridden by km, % of a route collection completed, a globe overlay showing ridden and unridden lines |
| Road and sea | Km driven, mountain passes crossed, ferries taken, longest sea crossing, ships sailed on |
| Carbon | Estimated CO₂ per leg, per trip and per year; CO₂ saved by each ground leg compared with flying the same origin and destination |

#### Carbon rules

| ID | Requirement |
|---|---|
| R-CO2-1 | Each leg's estimate is its distance × a per-passenger-km factor for its mode (and class, where the source distinguishes it). `[V1]` |
| R-CO2-2 | The comparison flight uses the great-circle distance between the same two places and the flight factor from the same source. `[V1]` |
| R-CO2-3 | Every carbon figure MUST be labelled an estimate, with the source and year of the factors shown. `[V1]` |

### 5.8 Journey phasing

Flights and intercity rail come first. City transit, the largest data effort, ships in
v1 for a launch set of cities and grows from there.

| Capability | M1 | V1 | Later |
|---|---|---|---|
| Flights, intercity rail, catalogue routes | Yes | Yes | |
| Coach, ferry, road, trails, cable and mountain | | Yes | |
| Full leg detail fields | Basic | Yes | |
| Multi-leg journeys | | Yes | |
| Snapping to real tracks and roads | Catalogue routes only | Yes | |
| City transit (rail-based systems) | | Launch set of cities | More city packs |
| City bus lines | | | Yes |
| Rail, punctuality and network completion stats | | Yes | |
| Carbon comparison | | Yes | |
| Opt-in online timetable lookup | | | Maybe |

---

## 6. Place and route database

The database is the product's moat: a geography core built from open data, plus
hand-curated landmarks and famous routes, shipped inside the app and updated in-app.

| Entity | Key attributes | Sources in use |
|---|---|---|
| Country and territory | ISO code, continent, capital, population, area, languages, currency, UN status | GeoNames (facts), Natural Earth (list and sovereignty), Wikidata (UN membership). Borders are built separately for the globe. |
| Region (state, province) | Name, parent country | GeoNames first-level divisions, keyed by its own admin1 code |
| City | Coordinates, population, elevation, time zone, monthly temperature normals, climate zone | GeoNames; normals and zones from TerraClimate 1991–2020 (D-28). |
| Landmark | Type, theme tags, year built, UNESCO status, height, parent city | Wikidata for every fact; `Tools/placedb/curation/` for which landmarks exist and their themes |
| Airport | IATA and ICAO codes, coordinates, elevation, size class | OurAirports |
| Transit system, line, stop | System city and country; line name, short name and colour; stop name and coordinates; the stop-to-stop links of each line | Wikidata, for 38 curated systems ([D-29](#121-implementation-decisions)) |
| Railway, road and ferry networks | The line between junctions, with its length and simplified line | Natural Earth 1:10m railroads and roads ([D-30](#121-implementation-decisions)) |
| Famous route | Mode, start, end, length (km), typical duration, highest point, countries crossed | Manual curation. **No path geometry** — the only practical source is OpenStreetMap, which is excluded ([D-8](#121-implementation-decisions)). |

### 6.1 Curation rules

| ID | Requirement |
|---|---|
| R-DB-1 | Every landmark MUST carry one or more theme tags from a fixed taxonomy (§7), so the personality stats work. `[V1]` |
| R-DB-2 | Missing attributes MUST stay empty rather than be guessed. Stats MUST show their coverage (e.g. "based on 42 of 50 landmarks"). `[V1]` |
| R-DB-3 | Ages MUST be stored as a year where known and an era where not (e.g. "2nd century BC"). `[V1]` |

### 6.2 Delivery

| ID | Requirement |
|---|---|
| R-DB-4 | Shipped as a read-only SQLite file, kept separate from user data. `[M1]` |
| R-DB-5 | Updates download as versioned files from a static host. Every user requests the same files, so an update reveals nothing about anyone's travels. `[V1]` |
| R-DB-6 | New achievements and curated collections MUST ride along in these updates, without needing an app release. `[V1]` |
| R-DB-7 | Every source MUST be licence-reviewed before it ships, with the obligation recorded in [Tools/placedb/SOURCES.md](../Tools/placedb/SOURCES.md) and any required attribution shown in the app. **Done for the sources in use:** Natural Earth (countries, railways and roads) and OurAirports are public domain, Wikidata is CC0, GeoNames is CC BY 4.0 and its credit is rendered in Settings from the database itself. TerraClimate's climate normals are CC0 (D-28). OpenStreetMap and Trainline are ODbL and are excluded from the bundled database ([D-8](#121-implementation-decisions)); GTFS feeds remain unreviewed. `[V1]` |

---

## 7. Statistics

All five stat families ship in v1. Every number MUST be tappable to show the visits
behind it.

| Family | Example stats |
|---|---|
| Coverage | Countries visited and % of the world, continents, regions (e.g. US states, Norwegian counties), cities, capitals, UNESCO sites, extreme points (northernmost, highest, lowest) |
| Distance and routes | Total km by mode, times round the Earth, longest single journey, flight hours, airports, airlines, aircraft types, rail km, countries crossed overland |
| Place attributes | Average and median landmark age, oldest and newest, average temperature in the month visited, hottest and coldest visit, average elevation, average city population, climate zones, languages, currencies, time zones |
| Time and patterns | Days away per year, trips per year, average trip length, busiest month, seasonality, repeat visits, longest gap since a country, "on this day" |
| Culture and themes | Share of visits by theme (ancient history, religious sites, nature and national parks, nightlife, art and museums, modern architecture, food), spread across historical eras, travel personality |

### 7.1 Travel personality

| ID | Requirement |
|---|---|
| R-PERS-1 | Built from the theme mix of everything a user has visited — e.g. heavy on Roman ruins and light on nightlife reads as a "Historian"; many US national parks reads as a "Trailblazer". `[V1]` |
| R-PERS-2 | MUST be rule-based, not machine learning, so it is explainable. The personality screen MUST always show the theme breakdown behind it. `[V1]` |
| R-PERS-3 | Six archetypes and a balanced default, each a group of themes with a threshold share — [D-15](#121-implementation-decisions). `[V1]` |

### 7.2 Calculation rules

| ID | Requirement |
|---|---|
| R-CALC-1 | By default, *Stayed* and *Day trip* count towards coverage; *Passed through* and *Layover* do not. A global setting overrides this, and every stat MUST respect it. `[M1]` |
| R-CALC-2 | Temperature uses the 30-year climate normal for the city in the month of the visit. If only the year is known, the annual mean is used **and flagged**. Undated visits are excluded. `[V1]` |
| R-CALC-3 | Averages over *places* count each unique place once (visiting the Colosseum twice does not double its weight in average landmark age). Time-based stats count each **visit**. `[M1]` |
| R-CALC-4 | Units follow the device's region settings (km or miles, °C or °F), and MUST be switchable in Settings. `[M1]` The setting covers distances, heights and temperatures. |
| R-CALC-5 | Every stat MUST be able to state how much of its input was usable (coverage and exclusions). `[M1]` |

---

## 8. Achievements and wishlist

Both ship in v1 and share one idea: curated collections of places and routes that users
make progress through.

| ID | Requirement |
|---|---|
| R-ACH-1 | Rule-based badges computed on the device, **defined in the database** so new ones arrive with database updates. `[V1]` |
| R-ACH-2 | Examples: every Nordic capital, crossed the Equator, crossed the Arctic Circle, all seven continents, five UNESCO sites in one trip, first overnight train. `[V1]` |
| R-ACH-3 | Tiered where it makes sense (bronze, silver, gold for 10, 25, 50 countries). `[V1]` |
| R-WISH-1 | Any place or route MUST be saveable as a wishlist item, shown on the globe in a distinct pin style. `[V1]` |
| R-WISH-2 | Curated collections to work through: US national parks, New 7 Wonders, European capitals, famous rail journeys. `[V1]` |
| R-WISH-3 | Progress MUST be shown per collection (e.g. "US national parks: 12 visited"). `[V1]` |
| R-WISH-4 | Logging a visit MUST tick off any matching wishlist item automatically. `[V1]` |

---

## 9. Screens and navigation

On iPhone, four tabs plus a persistent add button. On iPad and Mac the same
destinations sit in a sidebar.

| Screen | What it shows | Key interactions |
|---|---|---|
| **Globe** (home) | 3D globe with visited countries shaded, pins for places, arcs for journeys, wishlist pins in a separate style | Filter by year, trip or mode; tap a pin or arc to open it; scrub a timeline to replay your travel history |
| **Trips** | Trips newest first, each with a mini-map and headline numbers | Open a trip for its map, visits, journeys and per-trip stats |
| **Add** (button) | Search-first sheet over any screen | Search, pick, set date and visit type, assign to a trip |
| **Stats** | Dashboard grouped by the five stat families, personality at the top | Tap any number to see the visits behind it; share any card |
| **Collections** | Achievements, wishlist, curated collections with progress | Browse, add to wishlist, see what is left |
| **Settings** | Your data (backup, restore, export), import, counting rules, units, database version | Reached from the Stats or Collections screen |

### 9.1 The globe

The home screen, and most of why someone would choose this over a checklist app. It is
drawn entirely from the log and from bundled vector borders: no map imagery, no tiles,
no network (D-5).

| ID | Requirement |
|---|---|
| R-GLOBE-1 | The globe MUST render with no network access of any kind, and MUST make no request that depends on the user's own data (R-PRIV-3, R-PRIV-7). `[M1]` |
| R-GLOBE-2 | Visited countries are shaded. Only visits that count towards coverage under the current rules shade a country, so the globe and the coverage number never disagree (R-CALC-1). `[M1]` |
| R-GLOBE-3 | Places are pinned, and journeys are drawn as arcs along the same great circle their distance was measured on (R-PATH-4). A visit that does not count towards coverage is pinned in a fainter style. `[M1]` |
| R-GLOBE-4 | Wishlist places are pinned in a visibly different style from places visited, and never shade a country. `[V1]` |
| R-GLOBE-5 | Filter by year, trip or mode; tapping a pin or an arc opens it. Changing a filter reframes the globe on what is left. `[V1]` |
| R-GLOBE-6 | A timeline scrubs through the log, showing only what had happened by that date. It stops on days with something on them rather than running continuously. `[V1]` |
| R-GLOBE-7 | The globe MUST report what it could not draw and why — places with no coordinate, journeys with no distance, records with no date that cannot be placed in the replay — in the same terms the statistics use (R-CALC-5). `[M1]` |

### 9.2 iPad and Mac layout

| ID | Requirement |
|---|---|
| R-NAV-1 | Sidebar with the same destinations; the globe stays visible beside lists and detail views where space allows. `[V1]` Built (D-22). |
| R-NAV-2 | Mac adds drag-and-drop file import, a table view for editing many visits at once, and keyboard shortcuts. `[V1]` Built. |

---

## 10. Sharing, widgets and Year in Review

All sharing produces images or video rendered on the device. There are no links,
profiles or hosted pages.

| ID | Requirement |
|---|---|
| R-SHARE-1 | Share cards for a stat, a globe snapshot, a trip summary or a single journey, in square and story sizes, sent through the standard share sheet. `[V1]` |
| R-SHARE-2 | Home and Lock Screen widgets: countries count and % of the world; a globe snapshot; "on this day" from a past trip; progress on a chosen collection. `[V1]` |
| R-SHARE-3 | Year in Review: animated cards generated in December from that year's log (countries, km, longest journey, personality shift, top themes), exportable as images or a short video. Built entirely from local data. `[V1]` |

---

## 11. Privacy and storage

**The target App Store privacy label is "Data Not Collected".**

| ID | Requirement |
|---|---|
| R-PRIV-1 | No account, no sign-in, no ads, no third-party analytics. `[M1]` |
| R-PRIV-2 | User data lives on the device and nowhere else: no sync, no server. A backup file the user exports is how to keep a copy or move to another device. The developer never sees it (D-31). `[M1]` |
| R-PRIV-3 | The place database is read-only and identical for everyone; searches never leave the device. `[M1]` |
| R-PRIV-4 | Photo access is opt-in and limitable to selected photos. Photos are processed on the device; only each photo's date and location are read, and nothing about a photo is stored (D-17). `[V1]` |
| R-PRIV-5 | No background location tracking in v1. `[V1]` |
| R-PRIV-6 | Full export (CSV and JSON), restore from a JSON backup, and a one-tap "delete everything". `[M1]` |
| R-PRIV-7 | Any network request the app makes MUST be identical for every user (database and pack downloads only). `[V1]` |

---

## 12. Technical approach

Built solo, natively in Swift and SwiftUI as one multiplatform app, with AI coding
tools.

| Area | Choice | Why |
|---|---|---|
| UI | SwiftUI multiplatform, `NavigationSplitView` on iPad and Mac | One codebase, adaptive layouts |
| User data | SwiftData, on the device only (D-31) | Nothing leaves the device; backups are files the user holds |
| Place database | Read-only SQLite, full-text search with FTS5 | Fast offline search over a large dataset; SwiftData is a poor fit for this |
| Globe | Custom offline globe: an orthographic projection drawn in a SwiftUI `Canvas`, over bundled Natural Earth vector borders, with a satellite style wrapped from one bundled NASA picture (D-26) | MapKit cannot draw a map without fetching it, and what it fetches depends on where the user's own travel puts the camera. Vector borders are ~0.9 MB for the whole world, work in airplane mode and give the distinctive look — D-5, resolves [Q-3](#15-open-questions) |
| Journey arcs | Great-circle paths for flights, stored geometry for surface routes | Accurate distances and good-looking arcs |
| Offline geocoding | Point-in-polygon against bundled country and region borders | Custom pins and photo imports get a country without any network call |
| Charts | Swift Charts | Native look, iPhone to Mac |
| Widgets and share cards | WidgetKit; SwiftUI `ImageRenderer` for card images | Standard, on-device |
| Data pipeline | Offline Python scripts that build the SQLite file from open data plus curation sheets, versioned per release | Repeatable builds; plays to existing Python and SQL skills |

### 12.1 Implementation decisions

These deviate from, or sharpen, the table above. Each is reversible. D-1 to D-11 were
taken during the M1 build, D-12 onwards during the V1 build.

| ID | Decision | Rationale |
|---|---|---|
| D-1 | **No third-party Swift dependencies.** The place database is read through a thin wrapper over the system `SQLite3` C API rather than GRDB. | The MVP needs prepared statements and FTS5 and nothing else. Zero dependencies keeps the build hermetic and offline. GRDB can be swapped in behind `PlaceDatabase` if the query surface grows. |
| D-2 | **The stats engine is pure.** It operates on value types in `AntipodesCore`, not on SwiftData models. `AntipodesStore` maps between them. | Stats are the product's substance and the thing most likely to be wrong. Keeping them free of persistence makes them unit-testable without a `ModelContainer`. |
| D-3 | **Logic lives in a local SwiftPM package** (`AntipodesKit/`); the Xcode project is a thin app shell. | `swift test` runs the whole suite from the command line with no simulator. |
| D-4 | Deployment target **iOS 26 / macOS 26**, built against the iOS 27 SDK. | Latest minus one. Revisit at [Q-2](#15-open-questions). |
| D-5 | **The globe is drawn by the app, not fetched.** An orthographic projection in a SwiftUI `Canvas` over country outlines built from Natural Earth by `Tools/placedb/build_borders.py` into a bundled `.antborders` file; no MapKit, no map tiles, no network (the satellite style, D-26, wraps one bundled picture of the whole Earth, the same for everyone). The geometry, limb clipping, hit testing and replay timeline live in a pure `AntipodesGlobe` module. Resolves [Q-3](#15-open-questions). | MapKit has no bundled basemap: cut its service path and even `MKMapSnapshotter` fails with `MKErrorDomain Code=2`, and a region at city zoom pulls 200–300 KB of server-rendered content, per region viewed. Since the globe is centred on the user's own visits, those requests are shaped by their private travel history — which R-PRIV-7 forbids and the App Store "Data Not Collected" label could not survive. `MKTileOverlay` with bundled tiles would fix the privacy problem but costs tens of MB for a world raster pyramid and still gives MapKit's flat Mercator camera rather than a globe. Vector borders are 96 KB at 1:110m and 821 KB at 1:50m for the whole world, render crisply at any zoom, and are pure data the renderer can be swapped under. The cost is building shading, pins, arcs and gestures by hand, which is why the maths is in a pure module with tests rather than inside a view. |
| D-6 | **The user chooses which countries count**, from three named lists: UN member states (193), UN members and observers (195), and every place with an ISO 3166-1 code (252). The denominators are read from the place database's `meta`, not compiled into the app. Resolves [Q-4](#15-open-questions). | There is no single right answer, and picking one quietly makes the headline "% of the world" wrong for half the users. Naming each list and showing its size turns an arbitrary denominator into an informed choice. Reading the counts from the data means the number and the label can never disagree, and a change in the source shows up as a build failure rather than a silently different statistic. |
| D-7 | **The bundled place database is budgeted at 48 MB, and bundles cities above 5,000 people** (GeoNames `cities5000`: 69,822 cities, 30 MB). Resolves [Q-5](#15-open-questions). | 5,000 keeps the small places people actually travel to — Zermatt has 6,629 residents — while the 1,000 cut-off adds a hundred thousand hamlets, 38 MB and real search noise for little gain. 15,000 would save 13 MB and lose Zermatt. The 48 MB budget leaves room for landmark and route growth inside a file that is unremarkable to download; anything larger belongs in a downloadable pack (R-DB-5) rather than the bundle. |
| D-8 | **No OpenStreetMap-derived data ships in `places.sqlite`.** If route geometry is ever wanted it ships as a separate, self-contained ODbL-licensed pack through the R-DB-5 channel. Trainline's stations dataset is excluded on the same ground, and UNESCO status is taken from Wikidata rather than UNESCO's own list. Resolves the open half of R-DB-7. | ODbL §4.4(b) makes extraction into a new database a Derivative Database and §4.4(a) requires a publicly used one to be ODbL, so OSM geometry inside the bundled file would put share-alike on the whole of it — including material we gathered from CC BY and CC0 sources and cannot relicense. §4.5(a) exempts a *collection* of separate databases, so a separate pack keeps every option open at the cost of one file. The full reasoning is in [Tools/placedb/SOURCES.md](../Tools/placedb/SOURCES.md). |
| D-9 | **Fetching is a separate step from building.** `fetch_sources.py` downloads into `Tools/placedb/vendor/` and records each file's digest and retrieval date; `build_placedb.py` reads only that cache and never the network. | Keeps `scripts/check.sh` runnable offline and makes "deterministic" a claim with a stated scope: identical given its inputs, with the manifest saying exactly what those were. Natural Earth is pinned to a release tag; GeoNames, OurAirports and Wikidata are rolling, so the digest is the only honest record of which snapshot a database holds. |
| D-10 | **Landmarks are curated by identity and themed by hand; every fact comes from Wikidata.** `curation/landmarks.csv` lists a QID, the expected label and the theme tags, and the build fails if Wikidata disagrees about the label or the country. | Automatic selection does not work: the top heritage-designated items in Italy are Verona, Catania and the Croatian *language*, because `P1435` covers intangible heritage and whole cities. Curating identity while sourcing facts keeps the data honest and the list arguable. The label check is not ceremony — it caught "Persepolis" resolving to a football club and "Grand Canyon" to a university. |
| D-11 | **Search ranks on one prominence scale across place kinds**, with the kind used only to break ties between exact matches, and an exact match promoted only above a prominence floor. `place_index` carries an ASCII-folded copy of each name so a query typed without accents can match exactly. | A per-kind tier made every country outrank every city, so "par" offered Paraguay before Paris; promoting every exact match put *Par*, a Cornish village, above both. One scale plus a floor gives all three documented cases: a country before a city of the same name, a city before a region of the same name, and the most prominent place for a prefix. The folded name matters as much as the ranking: without it no accented name could match exactly, and "malmo" ranked a hamlet in Aruba above Malmö. |
| D-12 | **Row ids are the upstream identities**: a city or region is its GeoNames id, a landmark its Wikidata QID number, an airport its OurAirports id, and a country a number derived from its ISO code (NO → 14·100 + 15). | A user's log stores these ids and the database is replaced wholesale by updates (R-DB-5). Positional ids would silently repoint every logged place at the next rebuild; upstream ids survive any rebuild and any reordering. |
| D-13 | **Every bundled place carries an IANA time zone, and a leg's times are read in each end's own zone.** Cities take theirs from GeoNames. Airports and landmarks take the zone of the bundled cities within 75 km when those cities agree, or their country's when it has only one; otherwise the zone stays empty rather than guessed (R-DB-2). | Flight time and connection time are only right if 09:00 in Oslo and 11:30 in New York are compared as instants. Deriving rather than typing zones keeps R-DB-7's "no hand-entered facts", and the unanimity rule refuses to guess near a zone border. |
| D-14 | **Carbon factors are the UK Government's 2025 GHG conversion factors** (DESNZ, Open Government Licence v3), read from the published flat file by the pipeline; `curation/emission_factors.csv` only names which factor each mode and class uses. Flights use the international factors with radiative forcing and vary by class; a road trip's car is per vehicle. Resolves [Q-16](#15-open-questions). | DESNZ is the one widely used source that is openly licensed, versioned yearly, distinguishes cabin class and documents its method. Its flight factors already include the 8% uplift on great-circle distance, so they apply to the distance the app measures. Every figure is labelled an estimate with the source and year (R-CO2-3). |
| D-15 | **The travel personality is seven archetypes and a balanced default**: Historian, Trailblazer and Aesthete (40% of the theme mix), Futurist (35%), Pilgrim (30%), Gourmand and Night owl (20%), each a fixed group of themes (Night owl since 0.7.0, with the nightlife theme); the archetype furthest past its own threshold wins, and Wanderer is the reading when none reaches one. Resolves [Q-7](#15-open-questions). | Narrow groups get lower thresholds because one theme in sixteen at 30% is as strong a signal as five themes at 40%. Rules this simple can be shown in full on the personality screen (R-PERS-2), and a user can see exactly which visits would change the reading. |
| D-16 | **The first import formats are Flighty, myFlightradar24 and OpenFlights CSV, plus any CSV whose header names a date and two airport columns.** Columns are found by name; airports are matched by code against the bundled database, and anything unmatched goes to a review step. Resolves [Q-8](#15-open-questions). | Between them these cover most people's flight histories, and the generic reader covers a spreadsheet kept by hand. Matching by header name survives reordered or extended exports. |
| D-17 | **A photo is never stored, not even as a reference.** The importer reads each permitted photo's date and location on the device, clusters them into suggested visits, and a confirmed suggestion becomes an ordinary visit. Resolves [Q-9](#15-open-questions) and sharpens R-LOG-7 and R-PRIV-4. | A stored asset identifier would follow the log into iCloud and the export without adding anything the statistics use, and would break when the photo is deleted. Nothing stored is the strongest privacy position and costs no feature in V1. |
| D-18 | **The V1 scope is built now.** On 2026-10-20 the owner directed that the app be taken to release standard, superseding the M1-first plan in §13. M1's acceptance criteria (§14) are met; §13.1 records the status of each V1 area, including what is blocked and why. | The owner's call. The milestone tags stay on the requirements as a record of priority. |
| D-19 | **Widgets read a snapshot, never the log.** After every change the app writes a small JSON summary and a rendered globe image into the shared app-group container (`group.com.leeyenkai.antipodes`); the widget extension depends only on `AntipodesCore`. Widgets are iPhone and iPad only. | A widget process has a tight memory budget and must not open SwiftData or the 40 MB place database. A snapshot also means the widget shows exactly what the app last computed, so the two can never disagree. |
| D-20 | **Dark appearance is the default**, with Light and System available in Settings. The launch screen is dark to match. | The globe is a night-side globe and the palette is designed around it; a light default would show the app at its weakest first. |
| D-21 | **Identifiers and entitlements.** Bundle `com.leeyenkai.antipodes` (widgets `.widgets`), app group `group.com.leeyenkai.antipodes`. The Mac app is sandboxed through build settings with user-selected file access and Photos. The app-group entitlement is wired for iOS. There is no iCloud entitlement (D-31). | Simulator builds run unsigned-but-entitled with no account; a device or Mac build needs the owner's team, at which point automatic signing registers the group. |
| D-22 | **The globe stands beside the lists, built differently on iPad and Mac (R-NAV-1, R-PLAT-2).** On the Globe tab a tapped pin or arc opens in an inspector beside the globe on iPad and Mac, and in a sheet on iPhone as before. Trips and Collections keep the globe beside the list and every page pushed from it; the globe frames what is open (a trip alone, a visit, a journey, a country, a collection's members) and a tap on it opens that record in the list. On iPad that is a split view with the list in the floating column. On the Mac each page carries the globe beside itself. Below 720 points of width, and on iPhone, it is the plain list. Stats and All Records stay full width. | On iPad a list laid beside the globe by hand sat under the floating tab bar, which hid its toolbar; the split view is the layout the system keeps clear of it. On the Mac a navigation stack nested in a sidebar tab hands its pushes to the window, which replaces anything beside it, a split view styled the list as a second sidebar, and an inspector made AppKit resize the window and once throw on a layout loop. Charts and a table want the room. |
| D-23 | **A dated record is filed under exactly one year: the year it began.** A range that crosses New Year — 28 December to 3 January — belongs to its first year in every per-year statistic, the globe's year filter, Year in Review and the carbon-by-year chart, and to the month it began for seasonality. Badges and "first visited" dates use only dates known to the day: a visit dated "2019" earns a badge with no earned-on date rather than "1 January 2019". | Before this a New Year range had no year at all and silently vanished from every per-year view, while the Stats screen filed it under its start year — so two screens disagreed. Counting it in both years would double it. The start year is how people already talk about such a trip, and it keeps every total equal to the sum of its years (R-CALC-5). Inventing a day from a coarser date is the guess R-DATE-2 forbids. |
| D-24 | **The app icon is "Great circle", a layered Icon Composer document built from geometry.** Half a great circle, a gold band painted on a glass Earth, runs from a place on its near side over the horizon to that place's antipode on its far side, seen through the glass; each point wears a translucent halo, the way a map marks where you are. The band is drawn in true perspective, so it narrows and wraps the Earth's edge as a line painted on a ball does; it starts at the place and thins as it goes, a way from here to there rather than a belt round the world. Engraved along it in monoline Roman capitals, too small to read but up close, is the motto AD·ASTRA·PER·ASPERA. In the sky, the North Star sits on the Earth's axis beyond the north pole, twinkling with four fainter points between its four long ones, and the Southern Cross hangs on the antipode's side, its long arm pointing along the axis to the south celestial pole; both are drawn from catalogue positions, each star in its own colour, Gacrux a red giant among blue-white stars, with rounded points and no glass, as starlight far behind the glass Earth. The Earth carries real coasts — Natural Earth's 1:50m countries merged into landmasses, with the Greenland and Antarctic ice sheets in white — and a graticule every 30°, projected orthographically so the near point sits on Madrid and the far point on its true antipode off New Zealand, on an Atlantic view leaning at the Earth's axial tilt like a desk globe. `Tools/icon/build_icons.py` writes `App/Antipodes/AppIcon.icon` — flat SVG layers on a 1024-point canvas, the fills and glass in `icon.json`, light and dark palettes, and greys for the tinted and clear icons that step down from the two points so they lead there too — and the system adds the Liquid Glass in every appearance (default, dark, clear, tinted) on iPhone, iPad and Mac from that one file. `Tools/icon/render.sh` renders it, and the two concepts it was chosen over, with Xcode's own `ictool`. | Every great circle through a point passes through its antipode, which is the app's name in one line, and journeys are drawn along great circles throughout the app. Apple's guidance is layered artwork with no baked highlights, shadows or masks, a simple silhouette, and no fine detail that clutters a small icon; here the detail lives inside the one sphere — coasts, ice, graticule — and falls away at Home Screen size instead of crowding it, while the App Store and the Mac show it in full. The motto is an engraving, not a label: the guidance keeps words out of icons unless they are essential, and at Home Screen size its letters are under two pixels tall, so it never reads as text there. Generating the layers from numbers keeps the icon exact, reviewable and rebuildable. It replaces a single flattened PNG that carried an alpha channel, which App Store Connect rejects, and Mac sizes that had been made by hand. |
| D-25 | **Widgets open the app through `antipodes://` links, read on the device.** `DeepLink` in `AntipodesCore` names a tab or a record by its identity (`antipodes://visit/<id>`); the widget extension builds the links and the app reads them. The scheme is registered for the app alone. | A widget can only open its app by URL, and both sides need the same names for places in the app, so the type lives where both can link it. The link carries a record's identity, which never leaves the device: the system hands it from the widget to the app, and nothing sends it anywhere (R-PRIV-7). |
| D-26 | **A satellite globe from one bundled picture.** Beside the standard globe, a satellite style wraps NASA's Blue Marble Next Generation (August 2004, with topography and bathymetry; public domain) round the same orthographic projection. `scripts/fetch-imagery.sh` downloads the one pinned file, verifies its digest and scales it to 4096 × 2048 (1.9 MB as a JPEG, 32 MB decoded) into the bundle; the app decodes it only while the style is chosen. `AntipodesGlobe` runs the projection backwards per pixel and blends the four nearest pixels of the picture, over all cores, at one pixel a point while a finger moves the globe and two at rest. Country outlines are drawn over it, visited ones washed in the visited colour. The style is a preference, chosen from the globe's toolbar or Settings. | The owner asked for a satellite view. Map tiles would bring back exactly what D-5 rules out — requests shaped by where the user has been — while one picture of the whole Earth is the same for everyone, so nothing about the user can leave the device (R-GLOBE-1, R-PRIV-7). At 4096 pixels round the equator it carries about 10 km a pixel, which is sharp at whole-globe and country zoom and soft at city zoom, where the vector outlines still draw crisply over it. A GPU shader would be faster still, but it would bring a Metal build step into a package that today builds and tests with `swift build` alone, and the CPU path draws a release-build frame in a few milliseconds and works in `ImageRenderer` for share cards. |
| D-27 | **One reader for every journey list.** The flight-log reader (D-16) takes rail logs and any other list too: a mode column (read from everyday words — "train", "metro", "ferry"), rail-log column names ("from station", "train"), a stated distance in kilometres or miles, and JSON lists — a bare array, or the first array of objects in an export. A file with no mode column is read as the mode the user picks on the review screen. Airports are matched by code; every other end by name against the bundled towns, cities and landmarks, dropping words until something matches ("Oslo S" → Oslo), with the review screen for anything left. Duplicates are matched by mode as well as day and route. | Rail logs differ from app to app, but every one has a date, two ends and usually a distance along the track, which is better than a straight line (R-PATH-5). The database has no stations (D-8), so the town is the honest match, and the review screen catches the rest. |
| D-28 | **Climate from TerraClimate, at each place's own height.** Monthly normals for 1991–2020 come from TerraClimate (University of Idaho, CC0): maximum and minimum temperature, precipitation and elevation, read through OPeNDAP at every sixth cell of its 1/24° grid (0.25°, about 28 km) in DAP2 binary, which the standard library reads. A place takes the nearest cell with data within two cells; its mean temperature is (Tmax + Tmin) / 2, moved to its own elevation by the standard lapse rate of 6.5 °C a kilometre, and its Köppen-Geiger zone is worked out from those figures by the rules of Peel et al. (2007) with E tested before B and dry seasons kept apart as Kottek et al. (2006) write them. The database gains a `climate` table (schema 4, 6 MB). A visit takes its month's normal; a range weighs each month by its days; a year-only date takes the annual mean and is flagged (R-DATE-3); warmest and coldest visits need a month. | CC0 needs nothing beyond a citation, and the normals period matches the WMO's current one. WorldClim, which TerraClimate builds on, forbids redistribution; the Köppen maps of Beck et al. are CC BY 4.0 but would add a second source and a TIFF reader for what the same normals give. Without the lapse rate a cell spans a mountain city and the peaks around it: Quito read 8 °C instead of 14. |
| D-29 | **City transit from Wikidata, in the bundled database.** A curated launch set of 38 metro systems (`Tools/placedb/curation/transit_systems.csv`) takes its stations, lines and links from Wikidata (CC0): each "adjacent station" (P197) qualified by its line (P81), kept where the line belongs to the system (P361 or P16) or, for a system that records membership only on its stations, where both stations do. Closed, unbuilt and not-yet-opened lines and stations are left out, stations more than 90 km from their city are dropped, and a handful of lines that Wikidata files wrongly are dropped or merged by hand (`transit_line_fixes.csv`). A segment is an unordered pair of adjacent stops on one line (R-TRAN-2). A ride is routed along its line by the fewest stops, which also gives the stations passed through (R-TRAN-3) and the length stop to stop (R-PATH-5), and it stores the line and the network version `wikidata-<retrieval date>` (R-TRAN-4). The tables add about 0.5 MB (schema 5). Lines have no drawn track shape: a line Wikidata leaves in pieces routes within each piece, and a ride across a gap counts its two ends only. Resolves [Q-12](#15-open-questions). | OpenStreetMap and GTFS feeds have track shapes, but OpenStreetMap is ODbL (D-8) and GTFS licences differ by city; Wikidata's links are CC0, fit in the file the app already ships, and need no download or host (R-DB-5). The launch set is the systems whose links were checked line by line against their maps; New York, Munich, Oslo, Stockholm, Hamburg and Vienna wait for Wikidata's links there to join up, and Hong Kong for its stations to match a bundled city. |
| D-30 | **Surface legs are measured along Natural Earth's railways, roads and ferry routes, on the device.** The 1:10m railroads and roads of Natural Earth (public domain, release v5.1.2) are built into the bundled database as three networks (schema 7, about 6 MB): rail (24,534 stretches of track between 20,456 junctions), road with the car ferries that carry it (65,389 stretches), and ferry routes (745). Each stretch keeps its length measured on the full line and its line simplified to 150 m, stored as 16-bit steps. Natural Earth's railways join where they meet; its roads mostly do not, so the build joins roads that cross and links a loose end to the nearest road within 1 km, which takes the road map from 6,277 pieces to 613. A rail, road-trip, coach or ferry leg with no length of its own — no catalogue route ridden in full, no transit line, no figure of the user's — has each end joined to the nearest line of its network within 25 km and takes the shortest way along it (R-PATH-2); that length is saved with the leg and the version `naturalearth-v5.1.2`, as a transit ride saves its network (R-TRAN-4), so a newer map never moves an old figure. The globe draws the leg along that line, solid rather than dashed, and the countries the line runs through count as reached overland, each change of country a border crossed (R-PATH-6). A leg whose ends are too far from the network, or whose path would run more than two and a half times the straight line by rail, twice by road or 1.6 times by ferry — the sign of a link the map lacks, such as the short ferries on Norway's coast road — keeps its straight line, marked approximate (R-PATH-3). Hikes, bike tours and cable cars keep theirs: the roads are not where they went. A catalogue route ridden in full keeps its curated length and countries, and is drawn along the network only where the network's way is within 15% of the route's length — the shortest way from Moscow to Vladivostok cuts through Kazakhstan. | OpenStreetMap is far more detailed but ODbL (D-8); Natural Earth is public domain, already a source, and good enough at country scale: London to Edinburgh by rail measures 633 km against the East Coast Main Line's 632, Tokyo to Kyoto 475 against the Shinkansen's 476; Paris to Lyon by road 438 km against the A6's 465, its generalised roads running a little short. It has no stations and misses some high-speed lines (Rome to Florence measures by the old line, 312 km rather than 261), so stations passed through, tunnels, bridges and elevation profiles (R-PATH-6, R-PATH-7) still wait on a richer source. Shortest path is a guess at the route taken; it is the same guess for everyone and says so. |
| D-31 | **The log stays on the device; there is no sync.** `TravelLogStore` opens with `cloudKitDatabase: .none`, the unwired iCloud entitlement is gone, and nothing in the app says iCloud. Settings gathers export, backup, restore and import under "Your data", near the top, because a backup file is the only other copy there is. The models keep to CloudKit's rules (AGENTS.md §4), so sync would be a change to one initialiser rather than a migration, should it ever be wanted. Supersedes the sync half of R-PRIV-2. | The owner's call (2026-10-22): "It's private only and doesn't sync anywhere." Sync had never been switched on — the entitlement was never wired — yet onboarding, Settings and the privacy section all said the log synced, which a user losing a phone would have found out the hard way. Saying what is true, and putting the backup where it is seen, is the honest version of the same privacy promise. |

### 12.2 Module layout

```
AntipodesKit/
  Sources/
    AntipodesCore      Value types, flexible dates, visit types, modes,
                       great-circle maths, counting rules. No dependencies.
    AntipodesPlaces    Read-only place database: SQLite wrapper, FTS5 search.
    AntipodesStats     Every stat family, achievements, collections, Year in
                       Review. Pure; reads Core types.
    AntipodesExport    CSV and JSON export of the user's whole log.
    AntipodesImport    Flight-log CSV readers and photo clustering. Pure.
    AntipodesStore     SwiftData models, on the device only, mapping to Core.
    AntipodesGlobe     Globe geometry: orthographic projection, limb clipping,
                       bundled border decoding, replay timeline. Pure.
    AntipodesUI        SwiftUI screens: globe, trips, add sheet, stats,
                       collections, Year in Review, import, settings.
  Tests/               One suite per pure module.
App/Antipodes/         Xcode app shell: entry point, assets, Info.plist.
App/AntipodesWidgets/  WidgetKit extension; depends on AntipodesCore only (D-19).
Tools/placedb/         Python pipeline that builds places.sqlite.
```

---

## 13. Scope

The v1 feature list is large for a solo build, so it is split into an internal first
milestone and the public v1 release.

| Feature | M1 (internal) | V1 release | Later |
|---|---|---|---|
| Search and log places, trips, visit types | Yes | Yes | |
| Journeys: flights | Yes | Yes | |
| Journeys: rail, coach, city transit, ferry, road, trails | | Yes | |
| Custom pins | Yes | Yes | |
| Globe home screen | Basic | Full, with replay | |
| Stats: coverage, distance | Yes | Yes | |
| Stats: place attributes, time, culture and themes | | Yes | |
| Achievements and wishlist | | Yes | |
| Photo library import | | Yes | |
| Import from other apps | | One or two formats | More formats |
| Widgets, Year in Review, share cards | | Yes | |
| Export, backup and restore, delete | Yes | Yes | |
| Apple Watch, Shortcuts | | | Yes |
| Live Activities during journeys | | | Yes |
| Opt-in location suggestions | | | Yes |
| Localisation beyond English | | | Yes |

### 13.1 V1 status

As of 2026-10-21 (D-18). "Built" means implemented, tested where the logic is pure, and
checked in the simulator.

| Area | Status |
|---|---|
| Journeys in all eight modes, detail fields, catalogue routes, multi-leg journeys with connections and missed connections (R-LOG-6, R-LEG-*, R-JLOG-1 to 4) | Built |
| Statistics: all five families, drill-downs, personality (R-PERS-*) | Built, filterable by year, trip, mode and purpose (§5.7), every figure opening the records behind it (§7). Temperature and climate zones (D-28). Mountain passes crossed count the passes logged as places — 37 curated from Wikidata, each visit of any type a crossing — since a straight leg cannot say which pass a road went over (R-PATH-1). A nightlife theme rests on 22 curated districts and streets, not venues, which would come from OpenStreetMap (D-8), with a Night owl personality (D-15). Landmarks known only to the century or millennium carry an era (R-DB-3) and join the era spread where it lies within one era |
| Achievements, wishlist, curated collections (R-ACH-*, R-WISH-*) | Built; 36 achievements and 5 collections ship in the database. A place joins the wishlist from search, from a dropped pin or a long press on the globe, or from a collection |
| Carbon estimates (R-CO2-*) | Built (D-14) |
| Globe: wishlist pins, filters, replay (R-GLOBE-4 to 6) | Built. Replay plays through the log or is scrubbed by hand; wishlisted routes are drawn dashed; a satellite style (D-26) |
| Photo import, journey import (R-LOG-7, R-LOG-8, R-JLOG-7) | Built (D-16, D-17, D-27): flight logs from Flighty, myFlightradar24 and OpenFlights, and rail logs or any CSV or JSON journey list, ends matched to bundled towns by name |
| Share cards, widgets, Year in Review (R-SHARE-*) | Built. Every stat card and row, the globe, a trip, a journey and a year can be shared in square and story sizes; Year in Review is shared as a video made on the device, as images, or as one card; a travel personality, a badge and a collection have cards of their own. Widgets open the record or screen they show (D-25), and "On this day" carries two weeks ahead and has a Lock Screen size |
| iPad and Mac (R-PLAT-2, R-PLAT-3, R-NAV-*) | Built (D-22): sidebar navigation; the globe beside Trips, Collections and their detail views, following what is open; a record tapped on the globe opening in an inspector beside it; a bulk-edit table; keyboard shortcuts; and on the Mac, a flight-log CSV or a JSON backup dropped on the window, reviewed before anything is written. Stats and All Records stay full width |
| City transit (R-TRAN-1 to 5, R-JLOG-5) | Built (D-29) for 38 systems in the bundled database: pick the system, the line and the two stops; rides count segments, lines and systems covered, and stations boarded, alighted and passed through. Rides are drawn on the globe through the stops they passed, not along the track, which Wikidata does not have (R-TRAN-1), and a system outside the launch set is logged between two places. Downloadable city packs wait on R-DB-5 |
| Rail, road and ferry legs along their network (R-PATH-2, R-PATH-5, R-PATH-6) | Built (D-30) on Natural Earth's railways, roads and ferry routes: legs are measured and drawn along the shortest way between their ends, and the countries the line crosses count overland. Stations passed through, tunnels, bridges and elevation profiles need a richer source |
| Trail legs, catalogue route geometry and elevation (R-PATH-1, R-PATH-2, R-PATH-7) | **Blocked**: needs OpenStreetMap-derived network packs, which D-8 keeps out of the bundled database. Hikes, bike tours and cable cars are straight lines marked approximate (R-PATH-3) |
| Database updates from a static host (R-DB-5) | **Blocked**: needs a host. Achievements and collections are already read from the database (R-DB-6), and D-12 makes the log survive a replaced file |
| Temperature in the month visited (R-CALC-2), the annual fallback for year-only dates (R-DATE-3), climate zones (§7) | Built (D-28): every visit takes the 1991–2020 normal of its month at the place, ranges weighted by day, year-only dates by the annual mean and flagged; warmest and coldest visits; Köppen-Geiger zones |
| Commute passes, "ride again" as a one-tap duplicate (R-JLOG-6) | "Ride again" is built: one tap from the journey sheet's recent rides, or for any leg of a journey, joining its trip only while that trip is under way. A commute pass is one city transit ride dated across the months it covers, with the purpose Commute: its segments count once for coverage whenever commutes are counted (Q-15), and it is one record, not hundreds |
| Name check (R-NAME-1), App Store listing (R-PLAT-4) | Owner's task |

---

## 14. Acceptance criteria for M1

M1 is done when, on a device or simulator (all met as of 2026-10-20; V1 status is in §13.1):

1. Searching "oslo" offline returns Oslo (city) and OSL (airport), ranked sensibly, in under 100 ms.
2. A visit can be logged in four taps from the add button, with a visit type and a flexible date.
3. A custom pin dropped anywhere resolves to a country without a network call.
4. A flight leg between two airports shows a great-circle distance matching a known reference value within 0.5%.
5. The coverage stat reports countries visited, % of the world, and continents, and excludes *Passed through* and *Layover* unless the setting says otherwise.
6. The distance stat reports total km by mode and "times round the Earth".
7. Every stat states how many records it could not use and why.
8. The globe shades visited countries and draws flight arcs.
9. Export produces CSV and JSON containing every trip, visit and journey.
10. "Delete everything" leaves no user data on the device (and there is no other copy, D-31).
11. `swift test` passes with no network access.

---

## 15. Open questions

| ID | Question | Status |
|---|---|---|
| Q-1 | Name: "Antipodes" chosen; check App Store and trademark availability. | Open |
| Q-2 | Minimum iOS version: latest only, or latest minus one? | Working answer: latest minus one (iOS 26) — D-4 |
| Q-3 | Globe: MapKit (faster to build, needs network) or a custom offline globe? | **Resolved**: custom offline globe — D-5 |
| Q-4 | Country list: which definition counts as a "country" (UN members, plus territories such as Svalbard or Greenland, disputed places)? Offer a choice of lists? | **Resolved** — yes, offer a choice of three named lists; counts come from the database — [D-6](#121-implementation-decisions) |
| Q-5 | Database size budget, and the population cut-off for bundled cities. | **Resolved** — 48 MB budget, cities above 5,000 people (30 MB) — [D-7](#121-implementation-decisions) |
| Q-6 | Theme taxonomy: the final list of themes, and whether tags are curated by hand or derived from Wikidata categories. | Open — working answer: hand-curated, from the seventeen tags in `Tools/placedb/curation/theme_taxonomy.csv` ([D-10](#121-implementation-decisions)) |
| Q-7 | Personality archetypes: names and the rules that assign them. | **Resolved** — six archetypes and a balanced default — [D-15](#121-implementation-decisions) |
| Q-8 | Which import formats to support first. | **Resolved** — Flighty, myFlightradar24, OpenFlights and any date-and-airports CSV — [D-16](#121-implementation-decisions) |
| Q-9 | Should a photo be attachable to a visit as a stored copy, or only as a reference? | **Resolved** — neither: nothing about a photo is stored — [D-17](#121-implementation-decisions) |
| Q-10 | Journeys with no catalogue route: draw the path by hand, or straight lines between waypoints? | Working answer for V1: rail, road and ferry legs follow Natural Earth's networks (D-30); hikes, bike tours and cable cars are a straight line between the ends, marked approximate, unless the user enters the distance or rides a catalogue route (R-PATH-3). Hand-drawn paths are not built |
| Q-11 | Any future monetisation (tip jar, optional supporter tier), or free for good? | Open |
| Q-12 | Which cities make the launch set for city transit? | **Resolved** — 38 metro systems from Wikidata, built into the bundled database — [D-29](#121-implementation-decisions) |
| Q-13 | Size budget for regional network packs and city packs. | City transit: about 0.5 MB inside the 48 MB database (D-29). Regional network packs: open, blocked with R-PATH-2 |
| Q-14 | Offer an opt-in online timetable lookup, or stay fully offline? | Working answer: stay fully offline (R-JLOG-8) |
| Q-15 | Should commute legs be in stats by default, or out? | Working answer: out by default, with a switch under Settings → What counts |
| Q-16 | Which carbon factor source, and does class (e.g. first vs standard) change the estimate? | **Resolved** — DESNZ 2025 factors; class changes flight estimates — [D-14](#121-implementation-decisions) |

---

## 16. Spec changelog

| Date | Spec version | Change |
|---|---|---|
| 2026-10-18 | 0.1.0 | First markdown spec, transcribed from the 2026-10-15 draft. Added requirement IDs, M1 acceptance criteria (§14), and the implementation decisions in §12.1. |
| 2026-10-18 | 0.2.0 | The place database is built from real open data. Completed the licence review behind R-DB-7 and rewrote §6's source table to what is actually used. Resolved Q-4 (a choice of three country lists) and Q-5 (48 MB budget, cities above 5,000) as D-6 and D-7, and recorded D-8 to D-11: no OpenStreetMap data in the bundled database, fetching split from building, curated landmark identity with sourced facts, and a single cross-kind search prominence scale. |
| 2026-10-18 | 0.3.0 | Resolved Q-3 as D-5: the globe is drawn by the app over bundled Natural Earth borders rather than fetched through MapKit, after measuring what MapKit actually requests when it cannot reach its service. Added §9.1 (R-GLOBE-1 to R-GLOBE-7) and the pure `AntipodesGlobe` module in §12.2. |
| 2026-10-20 | 0.4.0 | The V1 scope is built (D-18); §13.1 records what is done and what is blocked. Recorded D-12 to D-21: upstream row ids, per-place time zones, DESNZ carbon factors, the personality rules, the first import formats, storing nothing about photos, widgets reading a snapshot, dark by default, and the app's identifiers and entitlements. Resolved Q-7, Q-8, Q-9 and Q-16; gave working answers to Q-10, Q-14 and Q-15. Sharpened R-LOG-7, R-PERS-3 and R-PRIV-4. Added `AntipodesImport` and the widget extension to §12.2. |
| 2026-10-20 | 0.4.1 | The iPad and Mac layout is built: recorded D-22 (the globe beside the lists, and the inspector for what is tapped on it) and marked R-PLAT-2, R-PLAT-3, R-NAV-1 and R-NAV-2 built in §13.1. |
| 2026-10-21 | 0.5.0 | Release audit. Recorded D-23 (a dated record is filed under the year it began; badges need day-precise dates), D-24 (the app icon is a layered Icon Composer document built from geometry) and D-25 (widgets open the app through `antipodes://` links). Marked R-DATE-3 blocked with R-CALC-2, noted what R-CALC-4's setting covers today, and brought §13.1 up to date: Year in Review as video, sharing from every stat, widget links and a fortnight of "On this day", and the wishlist from search and the globe. |
| 2026-10-21 | 0.6.0 | Polish and completion. Recorded D-26 (a satellite globe from one bundled NASA picture) and D-27 (one reader for every journey list, rail logs included); extended D-24 with the icon's real continents. §13.1 now records stats filters, the road and sea group, drill-downs for every figure, ride again from recent rides, replay that plays, wishlisted routes on the globe, more share cards and the Lock Screen "On this day", and names what is still missing for want of data: climate zones, mountain passes, a nightlife theme and eras for undated landmarks. |
| 2026-10-21 | 0.7.0 | Open data for what had waited on it. Recorded D-28 (temperature normals and climate zones from TerraClimate, corrected to each place's elevation), marked R-CALC-2, R-DATE-3 and R-DB-3 built, and widened D-15 to a Night owl. 86 curated places from Wikidata: mountain passes, nightlife districts and food markets. |
| 2026-10-21 | 0.8.0 | City transit. Recorded D-29 (38 metro systems from Wikidata in the bundled database, routed stop to stop), resolved Q-12, answered Q-13 for city transit, marked R-TRAN-1 to 5 and R-JLOG-5 built and split path snapping into its own §13.1 row. A commute pass is a city transit ride dated across its months (R-JLOG-6). |
| 2026-10-21 | 0.9.0 | Rail along the track. Recorded D-30 (rail legs measured and drawn along Natural Earth's railways, with the countries the track crosses), marked R-PATH-2, R-PATH-5 and R-PATH-6 built for rail, and narrowed what path snapping still waits for to road, ferry and trail legs and route geometry. |
| 2026-10-21 | 0.10.0 | Widened D-30 to roads and car ferries for road trips and coaches, and to ferry routes for ferry legs, with the road map repaired where Natural Earth's roads do not join. Narrowed what is still blocked on OpenStreetMap to trails, route geometry and elevation. |
| 2026-10-22 | 0.11.0 | Refined D-24's icon: the great circle drawn in true perspective round the Earth, coasts at 1:50m with ice sheets and a graticule, haloes on both points, and an Atlantic view at the Earth's axial tilt. |
| 2026-10-22 | 0.12.0 | Extended D-24's icon: the North Star and the Southern Cross on the Earth's axis, a 10° scale on the great circle, and tinted and clear renditions graded so the two points lead. |
| 2026-10-22 | 0.13.0 | D-24's icon: the great circle becomes a route from the place over the horizon to its antipode, thinning as it goes, with the motto engraved on it in place of the scale; the stars get rounded points, their own colours and, for the North Star, a twinkle. |
