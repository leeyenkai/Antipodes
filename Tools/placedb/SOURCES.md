# Place database sources and licences

Every row in the place database records the source it came from, in a `source` column.
This file is the register of those sources and what each one obliges us to do.

**Nothing enters the pipeline without a row in this table first.** Attribution is a
licence condition for several of these datasets, not a courtesy (R-DB-7 in
[the specification](../../docs/SPECIFICATION.md)).

---

## Current state

| Source | Used for | Licence | Obligation | Status |
|---|---|---|---|---|
| `seed/hand-entered` | Everything currently in `seed/` | Not applicable — plain geographic facts, entered by hand | None | **In use** |

The seed is a development placeholder: roughly 60 countries, 86 cities, 35 landmarks,
85 airports and 8 routes, enough to exercise search, logging and statistics. Figures
are approximate and rounded, and coordinates are good to a few decimal places. It is
**not** the dataset the app will ship, and nothing in it should be treated as
authoritative.

## Candidate sources, not yet cleared

None of these has been fetched, checked or licence-reviewed. They are the shortlist
from the specification (§6, §5.6), recorded here so the review has somewhere to land.

| Source | Would be used for | Licence | Obligation if used |
|---|---|---|---|
| Natural Earth | Country and region borders, continents | Public domain | None |
| GeoNames | Cities, regions, elevations, time zones | CC BY 4.0 | **Attribution required** in the app and in this file |
| OurAirports | Airports, IATA/ICAO codes, elevations | Public domain | None |
| Wikidata | Landmarks, operators, rolling stock, airlines | CC0 | None |
| UNESCO World Heritage list | UNESCO status on landmarks | Check terms before use | Unknown |
| OpenStreetMap / OpenRailwayMap | Railway lines, ferry routes, trails, aerialways, tunnels, bridges | ODbL 1.0 | **Share-alike applies to a derived database** — see below |
| GTFS feeds (via Mobility Database, Transitland) | Transit systems, lines, stops, shapes | Differs per feed | Must be checked feed by feed |
| Trainline open stations dataset | European rail stations | Check terms before use | Unknown |
| UK DESNZ conversion factors | Carbon emission factors | Open Government Licence | Attribution; factors change yearly |
| European Environment Agency | Carbon emission factors | Check terms before use | Unknown |
| A gridded climate-normals dataset | Monthly climate normals per city | Not chosen yet | Unknown |

### The OpenStreetMap question

ODbL's share-alike terms attach to a *derived database*. Shipping OSM-derived geometry
inside the app plausibly creates one, which would oblige us to publish that database
under ODbL. That is a decision about the product, not a detail of the build, and it is
**unresolved**.

Until it is resolved:

- Treat OSM-derived geometry as not cleared for release.
- Keep it behind the pipeline. Do not hand-copy OSM data into seed files or source code,
  where it would be much harder to remove or relicense later.
- Get an answer before any release that includes rail, ferry, road or trail geometry.

## When you add a source

1. Add a row to the table above, with the licence and the obligation.
2. Set `source` on every row the pipeline writes from it, to a stable identifier.
3. If attribution is required, add it to the app's Settings screen as well as here.
4. Re-run `scripts/build-placedb.sh` and confirm the rebuild is still byte-identical.
5. Note the change in [CHANGELOG.md](../../CHANGELOG.md) under `Data`.
