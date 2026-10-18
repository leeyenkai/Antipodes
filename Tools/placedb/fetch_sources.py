#!/usr/bin/env python3
"""Download the open-data sources the place database is built from.

This is the only part of the pipeline that touches the network, and it is separate from
``build_placedb.py`` on purpose: once the cache is populated, a rebuild needs no
connection at all, which is what keeps `scripts/check.sh` usable offline and keeps the
build reproducible from a known set of inputs.

Everything lands in ``vendor/<source-id>/`` alongside a ``vendor/manifest.json``
recording each file's URL, size, sha256 and the date it was retrieved. The build reads
that manifest and copies the digests into the database's `data_source` table, so a
shipped artefact can always say exactly which upstream snapshot it rests on.

Reproducibility differs by source, and the manifest is the only honest record of it:

* **Natural Earth** is pinned to release tag ``v5.1.2`` and its digest is checked, so
  the same bytes come back every time. The globe pipeline (``build_borders.py``) pins
  the same tag for the same file and shares this directory rather than downloading a
  second copy.
* **GeoNames** and **OurAirports** are rolling feeds that change daily. Nothing can pin
  them, so the manifest records which day's data a build used.
* **Wikidata** is queried live from the SPARQL files in ``queries/``, bounded to the
  QIDs curated in ``curation/landmarks.csv``.

Usage::

    python3 fetch_sources.py                 # fill any gaps in the cache
    python3 fetch_sources.py --refresh       # re-download everything
    python3 fetch_sources.py --only geonames # one source
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent

# The scripts run this under `python3 -I`, which keeps a planted module in the working
# directory from being imported — worth having, since this pipeline's whole job is
# reading files it downloaded. Isolated mode also drops the script's own directory from
# the path, so `sources` has to be found explicitly.
sys.path.insert(0, str(HERE))

import sources as registry  # noqa: E402 - must follow the sys.path line above
VENDOR = HERE / "vendor"
MANIFEST = VENDOR / "manifest.json"

# Wikidata's query service asks clients to back off on 429 and limits a client to 60
# seconds of processing per minute, so queries go out in chunks with a pause between.
WIKIDATA_CHUNK = 40
WIKIDATA_PAUSE_SECONDS = 1.5
WIKIDATA_ATTEMPTS = 5


class FetchError(Exception):
    """A download or query failed in a way that should stop the fetch."""


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            sha.update(block)
    return sha.hexdigest()


def today() -> str:
    return dt.datetime.now(dt.UTC).date().isoformat()


def http_get(url: str, *, accept: str | None = None, timeout: int = 300) -> bytes:
    headers = {"User-Agent": registry.USER_AGENT}
    if accept:
        headers["Accept"] = accept
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def download(file: registry.RemoteFile, destination: Path, *, refresh: bool) -> bool:
    """Returns True if the file was downloaded, False if the cache already had it."""
    if destination.exists() and not refresh:
        if file.sha256 is None or digest(destination) == file.sha256:
            return False
        print(f"    {destination.name}: cached copy has the wrong digest, re-fetching")

    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    try:
        partial.write_bytes(http_get(file.url))
    except (urllib.error.URLError, TimeoutError) as error:
        partial.unlink(missing_ok=True)
        raise FetchError(f"could not download {file.url}: {error}") from error

    if file.sha256 is not None:
        actual = digest(partial)
        if actual != file.sha256:
            partial.unlink(missing_ok=True)
            raise FetchError(
                f"{file.name} digest mismatch: expected {file.sha256}, got {actual}. "
                "Either the pinned release moved or the download was corrupted."
            )
    partial.replace(destination)
    return True


# ------------------------------------------------------------------------- Wikidata


def sparql(query: str) -> dict:
    """Runs a query, retrying on the 429 and 5xx the public endpoint hands out."""
    url = f"{registry.WIKIDATA_SPARQL}?{urllib.parse.urlencode({'query': query})}"
    last: Exception | None = None
    for attempt in range(WIKIDATA_ATTEMPTS):
        try:
            raw = http_get(url, accept="application/sparql-results+json", timeout=120)
            return json.loads(raw.decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            last = error
            wait = WIKIDATA_PAUSE_SECONDS * (attempt + 1) * 4
            print(f"    query failed ({error}); retrying in {wait:.0f}s")
            time.sleep(wait)
    raise FetchError(f"Wikidata query failed after {WIKIDATA_ATTEMPTS} attempts: {last}")


def read_query(name: str) -> str:
    path = HERE / "queries" / name
    if not path.exists():
        raise FetchError(f"missing query: {path}")
    return path.read_text(encoding="utf-8")


def curated_qids() -> list[str]:
    """The landmark QIDs to fetch, read straight from the curation file."""
    path = HERE / "curation" / "landmarks.csv"
    if not path.exists():
        raise FetchError(f"missing curation file: {path}")
    qids: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or line.startswith("qid,"):
            continue
        qid = line.split(",", 1)[0].strip()
        if qid:
            qids.append(qid)
    if not qids:
        raise FetchError(f"{path} lists no landmarks")
    return sorted(set(qids))


def fetch_un_members(destination: Path) -> None:
    results = sparql(read_query("un_members.rq"))
    codes = sorted(
        binding["iso2"]["value"]
        for binding in results["results"]["bindings"]
        if "iso2" in binding
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Written sorted, one per line, so the cached file is byte-identical whenever the
    # answer is.
    destination.write_text("iso2\n" + "\n".join(codes) + "\n", encoding="utf-8")
    print(f"    {len(codes)} current UN member codes")


def fetch_landmarks(destination: Path) -> None:
    qids = curated_qids()
    template = read_query("landmarks.rq")
    records: dict[str, dict] = {}

    for index in range(0, len(qids), WIKIDATA_CHUNK):
        chunk = qids[index : index + WIKIDATA_CHUNK]
        values = " ".join(f"wd:{qid}" for qid in chunk)
        results = sparql(template.replace("{{VALUES}}", values))

        for binding in results["results"]["bindings"]:

            def value(key: str) -> str | None:
                return binding.get(key, {}).get("value")

            qid = (value("item") or "").rsplit("/", 1)[-1]
            if not qid:
                continue
            record = records.setdefault(
                qid,
                {
                    "qid": qid,
                    "label": None,
                    # A list, not a single value: Niagara Falls, the Matterhorn and
                    # Iguaçu Falls each carry two P17 statements, and keeping whichever
                    # arrived first would make the cache differ between runs. The
                    # curation file picks which side such a landmark is filed under.
                    "country_codes": [],
                    "latitude": None,
                    "longitude": None,
                    "sitelinks": None,
                    "classes": {},
                    "inception": None,
                    "height_m": None,
                    "unesco": False,
                },
            )
            record["label"] = value("itemLabel") or record["label"]
            if value("iso2") and value("iso2") not in record["country_codes"]:
                record["country_codes"].append(value("iso2"))
            if value("lat") and record["latitude"] is None:
                record["latitude"] = float(value("lat"))  # type: ignore[arg-type]
                record["longitude"] = float(value("lon"))  # type: ignore[arg-type]
            if value("sitelinks") is not None:
                record["sitelinks"] = max(
                    record["sitelinks"] or 0, int(value("sitelinks"))  # type: ignore[arg-type]
                )
            if value("class"):
                class_qid = value("class").rsplit("/", 1)[-1]  # type: ignore[union-attr]
                record["classes"][class_qid] = value("classLabel") or class_qid
            if value("inception") and record["inception"] is None:
                record["inception"] = value("inception")
            if value("height") and record["height_m"] is None:
                record["height_m"] = float(value("height"))  # type: ignore[arg-type]
            if value("unesco") == "true":
                record["unesco"] = True

        print(f"    {min(index + WIKIDATA_CHUNK, len(qids))}/{len(qids)} landmarks")
        time.sleep(WIKIDATA_PAUSE_SECONDS)

    missing = sorted(set(qids) - set(records))
    if missing:
        raise FetchError(
            f"Wikidata returned nothing for {len(missing)} curated QIDs: "
            f"{', '.join(missing[:10])}"
        )

    for record in records.values():
        record["country_codes"] = sorted(record["country_codes"])

    destination.parent.mkdir(parents=True, exist_ok=True)
    # sort_keys and a fixed separator keep the cached JSON byte-identical whenever the
    # upstream answer is, so a rebuild can be compared meaningfully.
    destination.write_text(
        json.dumps(
            [records[qid] for qid in sorted(records)],
            sort_keys=True,
            indent=1,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


WIKIDATA_FETCHERS = {
    "un_members.csv": fetch_un_members,
    "landmarks.json": fetch_landmarks,
}


# ----------------------------------------------------------------------------- main


def load_manifest() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text(encoding="utf-8"))
    return {"files": {}}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Re-download even when the cache already holds the file.",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=None,
        metavar="SOURCE",
        help="Fetch just this source id; repeatable.",
    )
    parser.add_argument(
        "--cities",
        default=registry.DEFAULT_CITIES_DATASET,
        choices=sorted(registry.CITIES_DATASET_ROWS),
        help="Which GeoNames populated-place extract to fetch (Q-5).",
    )
    arguments = parser.parse_args(argv)

    manifest = load_manifest()
    wanted = set(arguments.only) if arguments.only else None

    try:
        for source in registry.all_sources(arguments.cities):
            if not source.files or (wanted and source.id not in wanted):
                continue
            print(f"==> {source.name} ({source.licence})")
            directory = VENDOR / source.id

            for file in source.files:
                destination = directory / file.name
                if source.id == "wikidata":
                    if destination.exists() and not arguments.refresh:
                        print(f"    {file.name} already cached")
                    else:
                        WIKIDATA_FETCHERS[file.name](destination)
                        print(f"    wrote {file.name}")
                else:
                    downloaded = download(file, destination, refresh=arguments.refresh)
                    print(f"    {file.name} {'fetched' if downloaded else 'already cached'}")

                entry = manifest["files"].get(f"{source.id}/{file.name}", {})
                sha = digest(destination)
                if entry.get("sha256") != sha:
                    entry = {"retrieved": today()}
                entry.update(
                    {
                        "url": file.url,
                        "sha256": sha,
                        "bytes": destination.stat().st_size,
                        "licence": source.licence,
                    }
                )
                manifest["files"][f"{source.id}/{file.name}"] = entry
    except FetchError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    manifest["cities_dataset"] = arguments.cities
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\n==> Cache ready in {VENDOR}")
    print(f"    manifest: {MANIFEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
