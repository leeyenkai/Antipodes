#!/usr/bin/env python3
"""Monthly climate normals and Köppen-Geiger zones for every bundled place.

TerraClimate's 1991-2020 climatologies (CC0) arrive as three DAP2 binary responses —
maximum and minimum temperature and precipitation for each month, on a 0.25° grid.
This module reads them with the standard library alone, works out each place's
monthly mean temperature and its climate zone, and nothing else: the build decides
which places to ask about and where the answers go.

Two choices worth knowing:

* **The mean temperature is (Tmax + Tmin) / 2**, the convention TerraClimate and
  WorldClim both use for monthly means.
* **A place takes the nearest cell with data**, searching up to two cells (about
  56 km) away. A coastal city often sits in a cell the grid calls sea; the nearest land
  cell is the honest answer, and a place with no land within reach gets no climate at
  all rather than a guess (R-DB-2).
* **Temperatures are moved to the place's own height** by the standard environmental
  lapse rate, 6.5 °C a kilometre, between TerraClimate's elevation for the cell and the
  place's recorded elevation. A cell is 28 km across; in the Andes it spans a city and
  the peaks above it, and without this Quito reads 6 °C colder than it is. A place
  with no recorded elevation keeps the cell's figures.
"""

from __future__ import annotations

import math
import sys
from array import array
from dataclasses import dataclass
from pathlib import Path

#: Cells searched outward from a place's own before giving up.
SEARCH_RADIUS_CELLS = 2

#: The standard environmental lapse rate, °C per metre (ICAO standard atmosphere).
LAPSE_RATE_C_PER_M = 0.0065


class ClimateError(Exception):
    """A climate file could not be read."""


# --------------------------------------------------------------------- DAP2 reading


@dataclass(frozen=True)
class DodsGrid:
    """One variable on a regular latitude/longitude grid, twelve months deep or one."""

    name: str
    months: int
    latitudes: tuple[float, ...]
    longitudes: tuple[float, ...]
    #: Stored values, month-major then latitude then longitude.
    raw: array
    scale: float
    offset: float
    fill: float

    def value(self, month: int, row: int, column: int) -> float | None:
        stored = self.raw[(month * len(self.latitudes) + row) * len(self.longitudes) + column]
        if stored == self.fill or stored != stored:  # the fill, or NaN
            return None
        return stored * self.scale + self.offset


def _read_xdr(data: memoryview, start: int, count: int, code: str) -> tuple[array, int]:
    """`count` big-endian four- or eight-byte values from `start`, and where they end.
    A 16-bit integer is widened to 32 bits on the wire, so it reads as `i`."""
    values = array(code)
    end = start + values.itemsize * count
    values.frombytes(data[start:end])
    if sys.byteorder == "little":
        values.byteswap()
    return values, end


def _array_length(data: memoryview, start: int) -> tuple[int, int]:
    """A DAP2 array opens with its length, written twice."""
    first, second = (
        int.from_bytes(data[start : start + 4], "big"),
        int.from_bytes(data[start + 4 : start + 8], "big"),
    )
    if first != second:
        raise ClimateError(f"array length mismatch: {first} and {second}")
    return first, start + 8


def read_dods_grid(path: Path, *, scale: float, offset: float, fill: float) -> DodsGrid:
    """Reads a DAP2 `.dods` response holding one Grid: the array, then its maps.

    The layout is the DDS text, a line reading ``Data:``, and then XDR: each array is
    its length twice followed by its values. The grid is twelve months by latitude by
    longitude, or latitude by longitude alone for a static layer such as elevation.
    """
    blob = path.read_bytes()
    marker = b"\nData:\n"
    split = blob.find(marker)
    if split < 0:
        raise ClimateError(f"{path.name} is not a DAP2 data response")
    header = blob[:split].decode("ascii", errors="replace")
    name = _grid_name(header)
    kind, shape = _array_shape(header, name)
    data = memoryview(blob)
    position = split + len(marker)

    count, position = _array_length(data, position)
    expected = math.prod(shape)
    if count != expected:
        raise ClimateError(f"{path.name}: {count} values for a {shape} grid")
    raw, position = _read_xdr(data, position, count, "f" if kind == "Float32" else "i")

    maps: list[tuple[float, ...]] = []
    for length in shape:
        found, position = _array_length(data, position)
        if found != length:
            raise ClimateError(f"{path.name}: map of {found} for an axis of {length}")
        values, position = _read_xdr(data, position, found, "d")
        maps.append(tuple(values))

    return DodsGrid(
        name=name,
        months=shape[0] if len(shape) == 3 else 1,
        latitudes=maps[-2],
        longitudes=maps[-1],
        raw=raw,
        scale=scale,
        offset=offset,
        fill=fill,
    )


def _grid_name(header: str) -> str:
    for line in header.splitlines():
        stripped = line.strip()
        if stripped.startswith("}") and stripped.endswith(";") and "TERRA" not in stripped:
            return stripped.strip("}; ").strip()
    raise ClimateError("no grid in the DAP2 header")


def _array_shape(header: str, name: str) -> tuple[str, tuple[int, ...]]:
    for line in header.splitlines():
        stripped = line.strip()
        if stripped.startswith(("Int16", "Int32", "Float32")) and f" {name}[" in stripped:
            sizes = tuple(
                int(part.split("=")[1].strip(" ];")) for part in stripped.split("[")[1:]
            )
            if len(sizes) in (2, 3):
                return stripped.split(" ", 1)[0], sizes
    raise ClimateError(f"no grid array named {name}")


# ----------------------------------------------------------------- Köppen-Geiger


def koppen(temperature: list[float], precipitation: list[float], latitude: float) -> str:
    """The Köppen-Geiger class of twelve monthly means, January first.

    The rules are those of Peel et al. (2007), as Beck et al. (2018, 2023) use them:
    a 0 °C boundary between temperate and cold, and the polar test (E) applied before
    the arid one (B), so an ice cap is EF rather than a desert, as on every published
    map. Summer is April to September north of the Equator and October to March south
    of it.
    """
    if len(temperature) != 12 or len(precipitation) != 12:
        raise ValueError("twelve months of each are needed")

    mean_temperature = sum(temperature) / 12
    annual_precipitation = sum(precipitation)
    hottest = max(temperature)
    coldest = min(temperature)
    warm_months = sum(1 for value in temperature if value > 10)

    summer_months = range(3, 9) if latitude >= 0 else (9, 10, 11, 0, 1, 2)
    winter_months = [month for month in range(12) if month not in summer_months]
    summer = [precipitation[month] for month in summer_months]
    winter = [precipitation[month] for month in winter_months]

    # E: no month reaches 10 °C.
    if hottest < 10:
        return "ET" if hottest > 0 else "EF"

    # B: too dry for the warmth, by the seasonal threshold.
    if annual_precipitation > 0 and sum(winter) >= 0.7 * annual_precipitation:
        threshold = 2 * mean_temperature
    elif annual_precipitation > 0 and sum(summer) >= 0.7 * annual_precipitation:
        threshold = 2 * mean_temperature + 28
    else:
        threshold = 2 * mean_temperature + 14
    if annual_precipitation < 10 * threshold:
        kind = "W" if annual_precipitation < 5 * threshold else "S"
        return "B" + kind + ("h" if mean_temperature >= 18 else "k")

    # A: every month at least 18 °C.
    if coldest >= 18:
        driest = min(precipitation)
        if driest >= 60:
            return "Af"
        if driest >= 100 - annual_precipitation / 25:
            return "Am"
        return "Aw"

    # C and D share their rainfall pattern and summer letters. Dry summer and dry
    # winter are kept apart as Kottek et al. (2006) write them — the dry season has to
    # be the drier one — so a place that meets both tests reads by its real dry season.
    if min(summer) < 40 and min(summer) < max(winter) / 3 and min(summer) < min(winter):
        pattern = "s"
    elif min(winter) < max(summer) / 10 and min(winter) < min(summer):
        pattern = "w"
    else:
        pattern = "f"

    if hottest >= 22:
        summer_letter = "a"
    elif warm_months >= 4:
        summer_letter = "b"
    elif coldest <= -38:
        summer_letter = "d"
    else:
        summer_letter = "c"

    return ("C" if coldest > 0 else "D") + pattern + summer_letter


# ----------------------------------------------------------------------- the grid


@dataclass(frozen=True)
class Normals:
    """A place's twelve monthly mean temperatures (°C) and its climate zone."""

    mean_temperature: tuple[float, ...]
    koppen: str


@dataclass(frozen=True)
class _Cell:
    temperature: tuple[float, ...]
    precipitation: tuple[float, ...]
    latitude: float
    elevation: float | None


class ClimateGrid:
    """The three TerraClimate grids, answering for any coordinate."""

    def __init__(
        self,
        tmax: DodsGrid,
        tmin: DodsGrid,
        ppt: DodsGrid,
        elevation: DodsGrid | None = None,
    ):
        for other in (tmin, ppt) + ((elevation,) if elevation else ()):
            if other.latitudes != tmax.latitudes or other.longitudes != tmax.longitudes:
                raise ClimateError("the three climate grids do not line up")
        self.tmax, self.tmin, self.ppt, self.elevation = tmax, tmin, ppt, elevation
        self.first_latitude = tmax.latitudes[0]
        self.latitude_step = tmax.latitudes[1] - tmax.latitudes[0]
        self.first_longitude = tmax.longitudes[0]
        self.longitude_step = tmax.longitudes[1] - tmax.longitudes[0]
        self._cache: dict[tuple[int, int], _Cell | None] = {}

    @classmethod
    def load(cls, directory: Path) -> "ClimateGrid":
        """The grids as `fetch_sources.py` cached them. Temperatures are stored as
        tenths of a degree above -73 °C, rainfall as tenths of a millimetre."""
        def grid(file: str, offset: float, fill: float) -> DodsGrid:
            path = directory / file
            if not path.exists():
                raise ClimateError(f"missing {path}; run fetch_sources.py --only terraclimate")
            return read_dods_grid(path, scale=0.1, offset=offset, fill=fill)

        return cls(
            grid("tmax_1991_2020_p25.dods", -73.0, -32768),
            grid("tmin_1991_2020_p25.dods", -73.0, -32768),
            grid("ppt_1991_2020_p25.dods", 0.0, -2147483648),
            # Elevation is stored in tenths of a metre.
            grid("dem_p25.dods", 0.0, -32768.0),
        )

    def _cell(self, row: int, column: int) -> _Cell | None:
        key = (row, column)
        if key in self._cache:
            return self._cache[key]
        temperature: list[float] = []
        precipitation: list[float] = []
        result: _Cell | None = None
        for month in range(12):
            high = self.tmax.value(month, row, column)
            low = self.tmin.value(month, row, column)
            rain = self.ppt.value(month, row, column)
            if high is None or low is None or rain is None:
                break
            temperature.append((high + low) / 2)
            precipitation.append(rain)
        else:
            result = _Cell(
                temperature=tuple(temperature),
                precipitation=tuple(precipitation),
                latitude=self.tmax.latitudes[row],
                elevation=self.elevation.value(0, row, column) if self.elevation else None,
            )
        self._cache[key] = result
        return result

    def normals(
        self,
        latitude: float,
        longitude: float,
        elevation_m: float | None = None,
    ) -> Normals | None:
        """The nearest cell with data, within `SEARCH_RADIUS_CELLS`, moved to the place's
        own elevation where both are known. Nearest by distance on the ground, ties
        broken by row then column, so the answer never varies."""
        rows = len(self.tmax.latitudes)
        columns = len(self.tmax.longitudes)
        row = round((latitude - self.first_latitude) / self.latitude_step)
        column = round((longitude - self.first_longitude) / self.longitude_step) % columns
        best: tuple[float, int, int] | None = None
        for d_row in range(-SEARCH_RADIUS_CELLS, SEARCH_RADIUS_CELLS + 1):
            candidate_row = row + d_row
            if not 0 <= candidate_row < rows:
                continue
            for d_column in range(-SEARCH_RADIUS_CELLS, SEARCH_RADIUS_CELLS + 1):
                candidate_column = (column + d_column) % columns
                if self._cell(candidate_row, candidate_column) is None:
                    continue
                cell_latitude = self.tmax.latitudes[candidate_row]
                cell_longitude = self.tmax.longitudes[candidate_column]
                distance = _distance_km(latitude, longitude, cell_latitude, cell_longitude)
                choice = (distance, candidate_row, candidate_column)
                if best is None or choice < best:
                    best = choice
        if best is None:
            return None
        cell = self._cell(best[1], best[2])
        assert cell is not None
        shift = 0.0
        if elevation_m is not None and cell.elevation is not None:
            shift = LAPSE_RATE_C_PER_M * (cell.elevation - elevation_m)
        temperature = [value + shift for value in cell.temperature]
        return Normals(
            mean_temperature=tuple(round(value, 1) for value in temperature),
            koppen=koppen(temperature, list(cell.precipitation), cell.latitude),
        )


def _distance_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    phi1, phi2 = math.radians(a_lat), math.radians(b_lat)
    d_lambda = math.radians(b_lon - a_lon)
    d_phi = phi2 - phi1
    h = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * 6371.0088 * math.asin(min(1.0, math.sqrt(h)))
