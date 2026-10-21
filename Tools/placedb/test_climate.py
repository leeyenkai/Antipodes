#!/usr/bin/env python3
"""Tests for climate.py: the Köppen-Geiger rules, the DAP2 reader and the lapse rate.

Every classification below is worked by hand in its comment from the rules in
`climate.koppen`; the monthly figures are round versions of published normals.
Run with `python3 -I -m unittest discover -s Tools/placedb -p 'test_*.py'`.
"""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import climate  # noqa: E402


class KoppenTests(unittest.TestCase):
    def test_london_is_temperate_oceanic(self) -> None:
        # Warmest 18.7 °C, so not E. MAT 11.35, MAP 602; neither half holds 70 %, so
        # the threshold is 2 × 11.35 + 14 = 36.7 and 10 × 36.7 = 367 < 602: not B.
        # Coldest 5.2 > 0: C. Driest summer month 44 ≥ 40: not s; driest winter 40 is
        # not under a tenth of 50: not w. Six months above 10 °C, none at 22: Cfb.
        temperature = [5.2, 5.3, 7.6, 9.9, 13.3, 16.5, 18.7, 18.5, 15.7, 12.0, 8.0, 5.5]
        precipitation = [55, 40, 42, 44, 49, 45, 45, 50, 49, 69, 59, 55]
        self.assertEqual(climate.koppen(temperature, precipitation, 51.5), "Cfb")

    def test_cairo_is_hot_desert(self) -> None:
        # MAP 23 mm with 22 of it October to March (96 %): threshold 2 × 21.65 = 43.3,
        # and 23 < 5 × 43.3: BW; MAT ≥ 18: BWh.
        temperature = [14.0, 15.3, 17.6, 21.2, 24.6, 27.1, 27.9, 27.9, 26.2, 23.6, 19.0, 15.4]
        precipitation = [5, 4, 4, 1, 0, 0, 0, 0, 0, 1, 3, 5]
        self.assertEqual(climate.koppen(temperature, precipitation, 30.0), "BWh")

    def test_singapore_is_tropical_rainforest(self) -> None:
        # Coldest 26.4 ≥ 18: A. Driest month 114 ≥ 60: Af.
        temperature = [26.5, 27.1, 27.5, 28.0, 28.3, 28.3, 27.9, 27.9, 27.6, 27.6, 26.9, 26.4]
        precipitation = [234, 114, 170, 154, 171, 132, 158, 176, 163, 194, 256, 287]
        self.assertEqual(climate.koppen(temperature, precipitation, 1.3), "Af")

    def test_mexico_city_has_dry_winters(self) -> None:
        # 675 of 769 mm falls April to September: threshold 2 × 16.7 + 28 = 61.4, and
        # 769 > 614: not B. Coldest 14.4: C. Driest summer month 25 is not under a third
        # of the wettest winter month (18.3): not s. Driest winter month 5 is under a
        # tenth of 170 and drier than any summer month: w. Warmest 19.0, all twelve
        # above 10: Cwb.
        temperature = [14.4, 15.6, 17.6, 18.8, 19.0, 18.1, 17.0, 17.2, 16.8, 16.1, 15.3, 14.5]
        precipitation = [8, 5, 10, 25, 55, 135, 170, 160, 130, 55, 10, 6]
        self.assertEqual(climate.koppen(temperature, precipitation, 19.4), "Cwb")

    def test_perth_takes_its_summer_from_the_southern_hemisphere(self) -> None:
        # South of the Equator summer is October to March: 117 mm, against 600 in winter
        # (84 %), so the threshold is 2 × 19.03 = 38.1 and 717 > 381: not B. Coldest
        # 13.1: C. Driest summer month 10 is under 40, under a third of 145 and drier
        # than winter's driest (35): s. Warmest 24.9 ≥ 22: Csa.
        temperature = [24.5, 24.9, 23.0, 19.8, 16.3, 14.1, 13.1, 13.6, 14.9, 17.3, 20.3, 22.6]
        precipitation = [15, 10, 17, 35, 90, 130, 145, 120, 80, 40, 25, 10]
        self.assertEqual(climate.koppen(temperature, precipitation, -31.95), "Csa")

    def test_yakutsk_is_extremely_cold(self) -> None:
        # MAP 231 with 172 in summer (74 %): threshold 2 × −8.8 + 28 = 10.4, 231 > 104:
        # not B. Coldest −38.6 ≤ 0: D. Neither dry-season test passes: f. Three months
        # above 10 °C and the coldest at or below −38: Dfd.
        temperature = [-38.6, -33.8, -20.1, -4.8, 7.5, 16.4, 19.5, 15.2, 6.1, -7.8, -27.0, -37.6]
        precipitation = [8, 7, 6, 10, 20, 35, 42, 40, 25, 16, 13, 9]
        self.assertEqual(climate.koppen(temperature, precipitation, 62.0), "Dfd")

    def test_polar(self) -> None:
        # Warmest month 6 °C: below 10 but above 0, tundra. Every month frozen: ice cap,
        # however little falls — the polar test comes before the arid one.
        tundra = [-15, -15, -14, -10, -3, 3, 6, 5, 1, -5, -10, -13]
        self.assertEqual(climate.koppen(tundra, [10] * 12, 78.0), "ET")
        self.assertEqual(climate.koppen([-30] * 12, [1] * 12, -80.0), "EF")

    def test_twelve_months_are_needed(self) -> None:
        with self.assertRaises(ValueError):
            climate.koppen([10] * 11, [10] * 12, 0)


def dods(name: str, kind: str, shape: tuple[int, ...], values: list, axes: list[list[float]]) -> bytes:
    """A minimal DAP2 response: the DDS, `Data:`, then XDR arrays."""
    dims = "".join(f"[{axis} = {size}]" for axis, size in zip(("time", "lat", "lon")[-len(shape):], shape))
    header = (
        "Dataset {\n    Grid {\n     ARRAY:\n"
        f"        {kind} {name}{dims};\n     MAPS:\n    }} {name};\n}} TERRA/test.nc;\n"
    )
    body = bytearray()

    def array_header(count: int) -> None:
        body.extend(struct.pack(">ii", count, count))

    array_header(len(values))
    code = ">f" if kind == "Float32" else ">i"
    for value in values:
        body.extend(struct.pack(code, value))
    for axis in axes:
        array_header(len(axis))
        for value in axis:
            body.extend(struct.pack(">d", value))
    return header.encode() + b"\nData:\n" + bytes(body)


class ReaderTests(unittest.TestCase):
    def test_reads_a_monthly_grid_with_scale_offset_and_fill(self) -> None:
        # 12 × 1 × 2: month m's first cell stores 730 + m (0.0 °C + m tenths after the
        # −73 °C offset); every second cell is the fill.
        values = []
        for month in range(12):
            values += [730 + month, -32768]
        blob = dods("tmax", "Int16", (12, 1, 2), values, [list(range(1, 13)), [10.0], [20.0, 20.25]])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tmax.dods"
            path.write_bytes(blob)
            grid = climate.read_dods_grid(path, scale=0.1, offset=-73.0, fill=-32768)
        self.assertEqual(grid.months, 12)
        self.assertEqual(grid.longitudes, (20.0, 20.25))
        self.assertAlmostEqual(grid.value(3, 0, 0), 0.3)
        self.assertIsNone(grid.value(3, 0, 1))

    def test_reads_a_static_float_layer(self) -> None:
        blob = dods("elevation", "Float32", (1, 2), [15000.0, 0.0], [[10.0], [20.0, 20.25]])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dem.dods"
            path.write_bytes(blob)
            grid = climate.read_dods_grid(path, scale=0.1, offset=0.0, fill=-32768.0)
        self.assertEqual(grid.months, 1)
        self.assertAlmostEqual(grid.value(0, 0, 0), 1500.0)


def flat(name: str, months: int, value: float, scale: float, offset: float, fill: float) -> climate.DodsGrid:
    """A 3 × 3 grid at 0.25° holding one stored value everywhere."""
    from array import array

    stored = round((value - offset) / scale)
    code = "f" if isinstance(fill, float) else "i"
    return climate.DodsGrid(
        name=name,
        months=months,
        latitudes=(10.25, 10.0, 9.75),
        longitudes=(20.0, 20.25, 20.5),
        raw=array(code, [stored] * (months * 9)),
        scale=scale,
        offset=offset,
        fill=fill,
    )


class LapseRateTests(unittest.TestCase):
    def test_a_place_below_its_cell_is_warmer(self) -> None:
        # Cell mean 10 °C at 1,000 m; a place at sea level is 1,000 m lower, so
        # 6.5 °C warmer: 16.5 °C in every month.
        grid = climate.ClimateGrid(
            flat("tmax", 12, 15.0, 0.1, -73.0, -32768),
            flat("tmin", 12, 5.0, 0.1, -73.0, -32768),
            flat("ppt", 12, 100.0, 0.1, 0.0, -2147483648),
            flat("elevation", 1, 1000.0, 0.1, 0.0, -32768.0),
        )
        normals = grid.normals(10.0, 20.25, 0.0)
        self.assertIsNotNone(normals)
        self.assertEqual(normals.mean_temperature, (16.5,) * 12)
        unknown = grid.normals(10.0, 20.25, None)
        self.assertEqual(unknown.mean_temperature, (10.0,) * 12)

    def test_nothing_within_reach_is_no_climate(self) -> None:
        empty = flat("tmax", 12, 0.0, 0.1, -73.0, -32768)
        for index in range(len(empty.raw)):
            empty.raw[index] = -32768
        grid = climate.ClimateGrid(
            empty,
            flat("tmin", 12, 5.0, 0.1, -73.0, -32768),
            flat("ppt", 12, 100.0, 0.1, 0.0, -2147483648),
        )
        self.assertIsNone(grid.normals(10.0, 20.25))


if __name__ == "__main__":
    unittest.main()
