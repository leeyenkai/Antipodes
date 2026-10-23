# Place database sources and licences

Every row in the place database records the source it came from, in a `source` column
pointing at a row of the `data_source` table. This file is the register of those
sources and what each one obliges us to do.

**Nothing enters the pipeline without a row in the table below and an entry in
[`sources.py`](sources.py).** Attribution is a licence condition for GeoNames, not a
courtesy (R-DB-7 in [the specification](../../docs/SPECIFICATION.md)).

| | |
|---|---|
| **Review status** | Complete for everything the database ships today |
| **Reviewed** | 2026-10-18; DESNZ added 2026-10-20 |
| **Reviewed against** | The licence texts themselves, linked below — not summaries |
| **Not legal advice** | A solo developer's reading. The conclusions are recorded so they can be checked, and the OpenStreetMap conclusion in particular should be confirmed before a paid release. |

---

## 1. Cleared and in use

These six, plus this repository's own curation, are everything in `places.sqlite`. The
last row, NASA's Blue Marble, is not in the database: it is the one picture the app
bundles, for the satellite globe.

| Source | Used for | Licence | Obligation | Met by |
|---|---|---|---|---|
| [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) | Country list, ISO codes, continents, sovereignty classification; **the country outlines the globe screen draws** (1:110m and 1:50m `admin_0_countries`, built by `build_borders.py` into the bundled `.antborders` files — D-5); and **the railway, road and ferry networks surface legs are measured along** (1:10m `railroads` and `roads`, built by `tracks.py` into `track_edge` — D-30) | Public domain | **None.** "No permission is needed to use *Natural Earth*. Crediting the authors is unnecessary." | Credited anyway, in Settings |
| [GeoNames](https://creativecommons.org/licenses/by/4.0/) | Cities, regions, elevations, time zones, country facts | **CC BY 4.0** | **Attribution, and an indication that we changed it** | A verbatim credit line in `data_source.attribution`, shown in Settings |
| [OurAirports](https://ourairports.com/data/) | Airports, IATA and ICAO codes, elevations | Public domain | **None.** "All data is released to the Public Domain"; credit is requested "but you're not required to." | Credited anyway, in Settings |
| [Wikidata](https://creativecommons.org/publicdomain/zero/1.0/) | Landmark facts, UNESCO status, UN membership; city transit stations, lines and the links between them for the curated systems (D-29) | CC0 1.0 | **None.** Main-namespace structured data "is released into the public domain under Creative Commons Zero." | Credited anyway, in Settings |
| [UK DESNZ GHG conversion factors 2025](https://www.gov.uk/government/collections/government-conversion-factors-for-company-reporting) | Carbon emission factors per mode and class (R-CO2-1, decision D-14) | [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) | **Attribution**; no share-alike, commercial use permitted, compatible with CC BY 4.0 | The OGL credit line, written into `data_source` and shown in Settings; the factor year shown with every carbon figure (R-CO2-3). `curation/emission_factors.csv` names which factor each mode uses and the build reads the value from the published flat file, pinned by digest |
| `antipodes-curation` | Landmark selection, theme tags, famous routes | CC0 1.0, part of this repository | None | — |
| [TerraClimate](https://www.climatologylab.org/terraclimate.html) (University of Idaho) | Monthly temperature normals for 1991-2020 and the Köppen-Geiger zone they make, for every city, landmark and airport (R-CALC-2, D-28): maximum and minimum temperature, precipitation and elevation, read through OPeNDAP at every sixth cell (0.25°) and corrected to each place's own elevation | CC0 1.0 ("public domain as licensed under the Creative Commons Public Domain (CC0) license") | **None.** The authors ask to be cited | Cited in Settings: Abatzoglou et al. (2018), *Scientific Data* 5:170191 |
| [NASA Blue Marble Next Generation](https://visibleearth.nasa.gov/collection/1484/blue-marble) | **Not in `places.sqlite`.** The picture the satellite globe wraps round the sphere: `world.topo.bathy.200408` (August 2004, topography and bathymetry), scaled to 4096 × 2048 by `scripts/fetch-imagery.sh` into the bundled `earth-satellite.jpg` (D-26) | Public domain (a NASA work, not subject to copyright in the United States) | **None**, beyond [NASA's media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/): credit NASA as the source and never imply NASA endorses the app | Credited in Settings as "Blue Marble Next Generation, NASA Earth Observatory (Reto Stöckli)" and in the globe's style menu. No NASA name or insignia is used anywhere else |

### The GeoNames obligation, precisely

GeoNames' own `readme.txt` in the export dump is the authoritative statement, and it is
unambiguous: *"This work is licensed under a Creative Commons Attribution 4.0
License"*. The web page says "cc-by" without naming a version; the readme names 4.0, so
4.0 is what we comply with.

CC BY 4.0 §3(a) requires the creator identified, the licence identified, and **an
indication if the material was modified**. The pipeline filters GeoNames' extracts,
drops columns, reshapes rows and joins them to other sources, so the modification
clause is not optional for us. The credit line is therefore:

> Contains data from GeoNames (geonames.org), modified, licensed under CC BY 4.0.

It lives in `sources.py`, is written into the database's `data_source` table at build
time, and the app renders it verbatim in Settings → *Where the places come from*. A
test asserts that it names GeoNames, the licence and the modification
(`dataSourcesAreRegistered`), so the obligation cannot be dropped silently.

CC BY 4.0 has **no share-alike term**, so none of this reaches the app's own code or the
rest of the database.

---

### Why the globe's borders come from here too

The globe needs country polygons to shade, and the obvious alternative — OpenStreetMap
administrative boundaries — is exactly what §2 rules out. Natural Earth is public
domain, so the geometry can ship inside the app with no share-alike question attached
to it, which is the whole reason the globe could be built offline at all (D-5).

**A wrinkle worth knowing.** Natural Earth's `admin_0_countries` is a map of
*sovereign administrations*, not of ISO 3166-1 codes. Its Norway polygon includes
Svalbard and Jan Mayen, which have their own code (`SJ`) and are separate places in the
place database. So logging Oslo shades Svalbard too, and logging Longyearbyen shades
nothing until Norway is visited. The same goes for other dependencies folded into their
sovereign's outline. Splitting them would mean the `map_units` or `map_subunits` layer
and a decision about which units count — which is [Q-4](../../docs/SPECIFICATION.md#15-open-questions)
territory, so it is recorded here rather than guessed at.

Two resolutions are fetched: 1:110m (96 KB built, the whole globe) and 1:50m (821 KB
built, for when it is zoomed in). `scripts/fetch-placedb-sources.sh` already caches the
1:110m file for the country list; `scripts/fetch-borders.sh` adds the 1:50m one and
verifies both against the same pinned tag and digests. Nothing in the app fetches
either: they are build inputs.

## 2. The OpenStreetMap question — resolved: a pack of its own

**Decision: no OpenStreetMap-derived data in `places.sqlite`, now or later.** Route
geometry ships as a separate ODbL-licensed pack, `routes-osm.sqlite`, built by
`Tools/osmpack/` and bundled beside the place database (decision D-36, 2026-10-23). This
also rules out Trainline's stations dataset, which is ODbL too.

### The reasoning

[ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) turns on three definitions:

- A **Derivative Database** is one "based upon the Database", including a reworked or
  reformatted copy. §4.4(b) is explicit that extracting or re-utilising the whole or a
  substantial part of the contents **into a new database creates one**.
- A **Collective Database** is the *unmodified* Database included in a larger group of
  separate databases that together form one whole, and is expressly **not** a
  Derivative Database.
- A **Produced Work** is an image, text or sound resulting from a query — a rendered
  map, for instance.

Applying them:

1. Pulling OSM railway, ferry or trail geometry into `places.sqlite` is extraction of a
   substantial part of the contents into a new database. That is a **Derivative
   Database** under §4.4(b).
2. Shipping it inside an App Store app is Public Use — distribution to "Persons other
   than You or under Your control". §4.4(a) then requires the Derivative Database to be
   licensed **only** under ODbL or a compatible licence.
3. Drawing the lines on the globe does not help. §4.5(b) says creating a Produced Work
   does not itself create a Derivative Database, but §4.4(c) says share-alike is
   triggered when a Produced Work *created from* a Derivative Database is publicly
   used. Rendering OSM geometry we shipped still pulls the obligation in.
4. §4.5(a) is the way through: incorporating the database into a collection does not
   require **the collection** to be ODbL. A separate, self-contained ODbL file sitting
   next to our own does not put share-alike on ours.

### What that rules in and out

**Ruled out.** Any OSM-derived row, column or geometry inside `places.sqlite`. Any OSM
data hand-copied into curation files or Swift source, where it would be far harder to
find and remove later. The **Trainline EU stations** dataset, whose README says
`stations.csv` is "distributed under the Open Database License (ODbL)" and that "any
modification to this data source must be published" — it is not a way around OSM, it is
the same obligation wearing a different name. The same goes for **OpenRailwayMap**,
which is OSM data.

**Ruled in, and now built.** A separate `routes-osm.sqlite` pack, under ODbL, with the
ODbL notice and attribution in its `meta` table and in Settings. Under §4.5(a) the app
bundle is then a Collective Database and `places.sqlite` stays outside the share-alike
scope. The three conditions this file set for taking that route, and how D-36 meets them:

- **The pack is built by its own pipeline and shares no table with `places.sqlite`.**
  `Tools/osmpack/` has its own fetcher, cache (`vendor/osm/`), schema and build. It
  reads `places.sqlite` only to learn which catalogue routes and Wikidata lines exist,
  and writes nothing back; its curation holds identifiers and choices, not OSM data.
- **The derived database is actually published, not merely offered.** The pack ships
  whole inside the app, so everyone who has the app has the derivative database in full,
  in a documented SQLite schema — more than ODbL §4.6 asks, which is an offer of the
  database or of the means to rebuild it. When the app is distributed publicly, the same
  file is also attached to the release, and the pipeline that rebuilds it is in the
  repository.
- **It is a deliberate decision, recorded here and as D-36**, made when the owner asked
  for real trail, lift, route and transit shapes.

R-DB-5's update channel is not needed for any of this: the pack arrives with the app,
and a later pack replaces it with the next build.

**What it holds.** Signed hiking and cycling routes in four regions as routable
networks, the world's passenger aerial lifts, the catalogue routes' shapes, and the lines,
stops and shapes of about a hundred rail transit systems and the buses of ten cities.
Famous routes in `places.sqlite` still carry only curated scalar facts — length,
typical duration, highest point — which are facts we state, not an extraction.

It is worth being clear about *why* this is the decision, because the obligation itself
is not objectionable: we would be content to publish a geometry pack under ODbL. What
is objectionable is mixing it in. A single file combining OSM geometry with GeoNames'
CC BY data and our own curation would have to be published under ODbL as a whole, which
means asserting database rights over material we did not gather and cannot relicense,
and it would make removing or replacing the OSM part a rebuild of everything. Keeping
it separate costs a file and keeps every option open.

---

## 3. Reviewed and not used

| Source | Would be used for | Finding | Status |
|---|---|---|---|
| OpenStreetMap / OpenRailwayMap | Railway, ferry, trail, aerialway geometry | ODbL 1.0 share-alike on a derived database — §2 above | **Excluded** from `places.sqlite`; **in use** in the separate `routes-osm.sqlite` pack (D-36) |
| Trainline EU open stations | European rail stations | ODbL, same analysis as OSM | **Excluded** |
| UNESCO World Heritage List | UNESCO status on landmarks | No licence covers the List as data. The World Heritage Centre's FAQ states that republication of UNESCO/WHC data requires **prior written authorisation**, and the syndication terms add further conditions. Individual items on the site carry assorted CC licences, several non-commercial. | **Excluded.** UNESCO status comes from Wikidata's `P1435` instead (CC0), which needs no permission |
| GTFS feeds (Mobility Database, Transitland) | Transit systems, lines, stops, shapes | Licence differs per feed; many are ODbL or CC BY-SA, some have no licence at all | **Not used.** City transit comes from Wikidata instead (D-29), which gives stations and links but no track shapes; a feed would be reviewed on its own if shapes are ever wanted |
| A gridded climate-normals dataset | Monthly climate normals per city (R-CALC-2) | No candidate chosen yet | **Not cleared.** Blocks R-CALC-2 `[V1]` |
| European Environment Agency | Carbon emission factors | Not examined; DESNZ is cleared and sufficient | **Not needed** |

### A limit worth knowing about UNESCO status

Taking the designation from Wikidata means `landmark.unesco` is true when **the item
itself** carries the World Heritage designation, not when it sits inside a designated
site. The Colosseum is a component of *Historic Centre of Rome* rather than a listed
site in its own right, so its flag is false; 61 of the 236 curated landmarks are
flagged. That is narrower than most people mean by "is it a World Heritage Site", and
it is the honest answer the data supports rather than a guess. Any stat built on the
flag should say what it counts.

---

## 4. Reproducibility of each source

Determinism is a property of the pipeline given its inputs, so what pins each input
matters. `vendor/manifest.json` records the URL, size, sha256 and retrieval date of
every file a build read, and the combined digest per source goes into `data_source`,
where the app can show it.

| Source | Pinned? | How a build identifies its snapshot |
|---|---|---|
| Natural Earth | **Yes** — release tag `v5.1.2`, digest verified on download | Same bytes every time |
| GeoNames | No — a rolling daily feed | Digest and retrieval date in the manifest |
| OurAirports | No — a rolling feed | Digest and retrieval date in the manifest |
| Wikidata | No — queried live, bounded to the curated QIDs in `queries/` and `curation/` | Digest of the cached answer; transit rides store `wikidata-<retrieval date>` as their network version (R-TRAN-4) |
| NASA Blue Marble | **Yes** — one file, digest verified on download (`scripts/fetch-imagery.sh`) | Same bytes every time; `sips` scales it the same way |
| TerraClimate | **Yes** — four fixed OPeNDAP requests over a static climatology, digests pinned | Same bytes every time |

A release build should pass `--built-at` and archive the matching `vendor/` directory,
because that directory is the only way to reproduce its database byte for byte.

---

## 5. When you add a source

1. Add a row to the table in §1 **and** a `Source` to [`sources.py`](sources.py), with
   the licence, the licence URL and the exact credit the licence requires.
2. Set `source` on every row the pipeline writes from it, to that source's id. A test
   asserts no row names an unregistered source.
3. If attribution is required, put the licence's own words in `attribution`. The app
   renders it verbatim; do not paraphrase it at the call site.
4. If the licence has a **share-alike** term, stop and read §2 before writing any code.
   The answer is probably a separate pack, not a new table.
5. Re-run `scripts/build-placedb.sh` and confirm the rebuild is still byte-identical.
6. Note the change in [CHANGELOG.md](../../CHANGELOG.md) under `Data`.
