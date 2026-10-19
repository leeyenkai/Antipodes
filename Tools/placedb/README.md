# Place database pipeline

Builds the read-only SQLite file the app bundles and searches (R-DB-4), from open data.

```bash
scripts/fetch-placedb-sources.sh     # once: downloads ~25 MB into vendor/
scripts/build-placedb.sh             # offline from here on
```

`build-placedb.sh` fetches for you if the cache is missing, and copies the result into
the app bundle's resources. Pass `--skip-copy` to leave the bundle alone.

## Files

| | |
|---|---|
| `sources.py` | The source register: URLs, licences, the exact credit each one requires |
| `fetch_sources.py` | The only part that touches the network. Downloads into `vendor/`, writes `vendor/manifest.json` |
| `build_placedb.py` | The build: reads `vendor/` and `curation/`, validates, writes the database |
| `schema.sql` | Schema version 3: places with upstream ids (D-12) and time zones (D-13), `data_source`, `place_index` and its FTS5 index, and the catalogue tables — routes, themes, collections, achievements, carbon factors |
| `queries/` | The SPARQL sent to Wikidata, as files so they can be read and reviewed |
| `curation/` | Deliberate human input — see below |
| `SOURCES.md` | Every source, its licence, and the licence review (R-DB-7) |
| `vendor/` | Downloaded sources. Not committed; re-fetchable |
| `out/` | Build output. Not committed |

`build_borders.py` is a separate pipeline: it compiles the Natural Earth country borders
the globe draws into its own `.antborders` file, deliberately not a table here
(decision D-5). It shares `vendor/naturalearth/` and the same pinned release.

## Where the data comes from

| | |
|---|---|
| Countries, ISO codes, continents, sovereignty | Natural Earth (public domain) |
| Country facts, regions, cities, elevations, time zones | GeoNames (**CC BY 4.0 — attribution required**) |
| Airports, IATA and ICAO codes | OurAirports (public domain) |
| Landmark facts, UNESCO status, UN membership | Wikidata (CC0) |
| Carbon emission factors | UK DESNZ 2025 (Open Government Licence v3 — attribution required) |
| Which landmarks and routes exist, and their themes | `curation/` |

There is **no OpenStreetMap data here and there will not be**: ODbL's share-alike terms
would attach to this database. [SOURCES.md](SOURCES.md) has the full reasoning and says
what would have to be true to ship OSM geometry as a separate pack.

## What is curated, and why

The sources above carry facts, not judgements. The judgements live in `curation/`
where they can be read and argued with:

| | |
|---|---|
| `landmarks.csv` | Which landmarks exist, which city each belongs to, and its theme tags. Every *fact* — name, coordinate, year built, height, UNESCO status — comes from Wikidata at build time. |
| `theme_taxonomy.csv` | The fixed theme list every landmark draws from (R-DB-1; working answer to Q-6) |
| `landmark_kinds.csv` | Wikidata class → the `kind` label shown, by priority |
| `routes.csv` | The famous routes, with scalar facts only, and where each starts and ends as a reference to a bundled place |
| `collections.csv`, `collection_members.csv` | Curated collections and the places in each (R-WISH-2) |
| `achievements.csv` | Badge definitions: a rule the app knows, a parameter and a tier (R-ACH-1) |
| `emission_factors.csv` | Which DESNZ factor each mode and class uses — names only, never a number (D-14) |
| `un_membership.csv` | The reconciliations upstream data cannot express, each with its reason |

`landmarks.csv` records the **expected** Wikidata label and country for each QID, and
the build fails if Wikidata disagrees. That is not ceremony: assembling the current list
caught "Persepolis" resolving to a football club, "Grand Canyon" to a university, and
"The Bund" to a Jewish labour party. A mistyped QID cannot ship the wrong landmark.

## Two properties it must keep

**Deterministic.** The same cache produces a byte-identical file. Everything is sorted
and nothing depends on dict or filesystem ordering, so if a rebuild changes the file,
the inputs changed. `--built-at` defaults to a fixed string for this reason; pass a real
date only for a release build.

```bash
python3 -I build_placedb.py --out out/a.sqlite && python3 -I build_placedb.py --out out/b.sqlite
cmp out/a.sqlite out/b.sqlite && echo identical
```

Determinism is relative to the inputs, and only Natural Earth is pinned to an immutable
release. GeoNames and OurAirports publish daily and Wikidata changes continuously, so
`vendor/manifest.json` records the digest and date of every file a build read, and those
digests go into the database where the app can show them. To reproduce a release's
database, you need its `vendor/` directory, not just this repository.

**Nothing guessed.** A missing attribute is written NULL and the app reports its
coverage (R-DB-2); the build prints that coverage too, so a column that is mostly empty
is visible before shipping rather than after. The build fails rather than writing a
wrong row, on:

- an unknown country code, or a UN member with no country row;
- a coordinate out of range, or a city or landmark with none;
- a duplicate IATA code;
- a landmark with no theme tag (R-DB-1), or a theme outside the taxonomy;
- a curated landmark whose Wikidata label or country does not match the curation;
- a curated city name that is not in the bundled city set;
- a UN member total that is not 193 — the "% of the world" denominator cannot drift
  because of an upstream edit (Q-4).

Landmark problems are collected and reported together rather than one per run.

## Choices worth knowing about

**Region codes are GeoNames admin1 codes** (`IT.07` for Lazio), not ISO 3166-2. The two
are different levels in some countries: Natural Earth's admin-1 layer gives Italy its
110 provinces while GeoNames gives its 20 regions, and reconciling them would be
guesswork. Using GeoNames throughout means a city's own admin1 code joins the region
table exactly.

**The bundled city set is `cities5000`** — every place above 5,000 people, plus the
seats of first-level divisions: 69,822 cities and 31 MB (Q-5, decision D-7).
`--cities` switches it:

| Dataset | Cities | Database |
|---|---|---|
| `cities15000` | 34,167 | 18 MB |
| `cities5000` | 69,822 | **31 MB** ← bundled |
| `cities1000` | 171,329 | 68 MB |

The build warns if the file goes past the 48 MB budget rather than failing: a byte count
is a judgement, not a correctness property.

**Airports are narrowed** to those with a size class a scheduled flight could use or an
IATA code, and never `closed`: 9,763 rows rather than 86,258. The rest are heliports,
seaplane bases and disused strips nobody logs a journey through.

**Landmark fame is measured, not assigned.** `prominence` for a landmark comes from its
Wikipedia language-edition count, which is why searching "colosseum" works and why a
curated list needs no hand-written importance score. A region's prominence is the summed
population of the cities bundled inside it, divided by ten — an aggregate of sourced
figures, used only for ranking and never shown as a statistic.

**`place_index.name_folded`** holds an ASCII-folded copy of every name, so a query typed
without accents can match one *exactly*. Dropping it is not a small matter: without it
"malmo" ranked a hamlet in Aruba and an airport above Malmö, and "zurich" ranked the
canton above the city.

## Known gaps

- **Alternate names are not indexed.** GeoNames names the Swedish city "Gothenburg", so
  searching "goteborg" does not find it. Indexing the `alternatenames` column would fix
  a whole class of these at a real cost in size, and is the obvious next improvement.
- **`landmark.era` is always NULL.** Only Wikidata's inception date is fetched, so the
  era half of R-DB-3 waits for a source that carries one. 67% of landmarks have a year.
- **`landmark.unesco` is narrower than it reads.** It is true when the item itself holds
  the World Heritage designation, not when it sits inside a designated site — the
  Colosseum is a component of *Historic Centre of Rome*, so its flag is false. See
  SOURCES.md §3.
- **Country rows have no representative point.** GeoNames' `countryInfo.txt` carries
  none and inventing one would be a guess; country geometry lives in the globe's border
  file (decision D-5).

## Changing the schema

Raise `SCHEMA_VERSION` in `build_placedb.py` and `PlaceDatabase.expectedSchemaVersion`
in Swift together — the app refuses a database whose schema version it does not
recognise, rather than running the wrong query.

### The alternate-name gap, measured

GeoNames stores English names for most major cities — Munich, Florence, Copenhagen,
Vienna, Prague, Gothenburg are all there under those spellings — but not all of them.
Köln is stored as `Köln`, so searching "Cologne" returns **Cologne, Italy**, a village
of a few thousand, rather than the German city. The `alternatenames` column holds the
exonyms that would fix this; indexing it is the obvious next improvement to search, at a
real cost in database size.
