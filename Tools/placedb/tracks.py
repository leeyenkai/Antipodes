#!/usr/bin/env python3
"""Routable networks of railways, roads and ferry routes from Natural Earth (D-30).

The app joins a surface leg's two ends to the network for its mode and measures the leg
along the shortest way between them (R-PATH-2, R-PATH-5): a train from Oslo to Bergen
counts the railway's length, a drive from Paris to Lyon the road's. Natural Earth is
public domain, so unlike OpenStreetMap (D-8) it can sit in the bundled database.

Everything here is pure: `build_placedb.py` reads the GeoJSON, calls these functions
and writes what they return, and `test_tracks.py` tests them on their own.

Each network is a graph:

* **Nodes are junctions**: the ends of lines, and every vertex where three or more
  stretches meet. Vertices are merged at 4 decimal places (about 11 m).
* **Edges are the line between two junctions**, with their length measured on the full
  geometry and the geometry itself simplified to `SIMPLIFY_M` for drawing and snapping.
* Ids are given in coordinate order, so the same input builds the same database.

Natural Earth's railways join where they meet. Its roads mostly do not — two highways
cross without sharing a vertex, and a road often stops a few hundred metres short of
the one it joins — so `repair` joins them first: a junction where two lines cross, and
a short link from a loose end to the nearest other line within `SNAP_M`. Without it
the road map is 6,000 pieces; with it, one per landmass, near enough.
"""

from __future__ import annotations

import math
import struct
from collections import defaultdict
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field

#: Decimal places at which vertices are the same point (about 11 m).
PRECISION = 4
#: How far the drawn line may stray from the real one. Lengths use the full geometry.
SIMPLIFY_M = 150.0
#: How far a loose end of a road may be from the line it meets.
SNAP_M = 1000.0
#: Coordinates are stored as integers of this many units a degree.
SCALE = 100_000
#: The largest step between two stored points, so each fits a 16-bit delta.
MAX_STEP = 32_767
#: The grid `repair` buckets segments in, in degrees.
_CELL = 0.1

Point = tuple[float, float]  # (latitude, longitude)
Line = list[Point]


@dataclass
class Edge:
    a: int
    b: int
    length_m: int
    #: From node `a` to node `b`, both ends included, simplified.
    points: list[Point]


@dataclass
class Network:
    #: Node `i` is `nodes[i - 1]`: ids start at 1.
    nodes: list[Point]
    edges: list[Edge]
    #: Closed rings with no junction on them, which cannot be entered.
    loops_dropped: int = 0
    stats: dict[str, int] = field(default_factory=dict)


def distance_m(a: Point, b: Point) -> float:
    phi1, phi2 = math.radians(a[0]), math.radians(b[0])
    d_phi = phi2 - phi1
    d_lambda = math.radians(b[1] - a[1])
    h = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * 6_371_008.8 * math.asin(min(1.0, math.sqrt(h)))


def lines_of(features: Iterable[dict], keep: Callable[[dict], bool]) -> list[Line]:
    """The lines of every feature `keep` accepts, as (latitude, longitude) points."""
    lines: list[Line] = []
    for feature in features:
        if not keep(feature.get("properties") or {}):
            continue
        geometry = feature.get("geometry") or {}
        if geometry.get("type") == "LineString":
            parts = [geometry["coordinates"]]
        elif geometry.get("type") == "MultiLineString":
            parts = geometry["coordinates"]
        else:
            continue
        for part in parts:
            line = [(round(c[1], 5), round(c[0], 5)) for c in part]
            if len(line) > 1:
                lines.append(line)
    return lines


def simplify(points: list[Point], tolerance_m: float) -> list[Point]:
    """Douglas-Peucker on a local equirectangular projection; the ends always stay."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        if last - first < 2:
            continue
        a, b = points[first], points[last]
        scale = math.cos(math.radians((a[0] + b[0]) / 2)) * 111_320.0
        ax, ay = a[1] * scale, a[0] * 110_540.0
        bx, by = b[1] * scale, b[0] * 110_540.0
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        worst, index = -1.0, first
        for i in range(first + 1, last):
            px, py = points[i][1] * scale, points[i][0] * 110_540.0
            if length == 0:
                off = math.hypot(px - ax, py - ay)
            else:
                off = abs(dy * px - dx * py + bx * ay - by * ax) / length
            if off > worst:
                worst, index = off, i
        if worst > tolerance_m:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [point for point, kept in zip(points, keep) if kept]


# ------------------------------------------------------------------------------ repair


def _cells(a: Point, b: Point) -> Iterable[tuple[int, int]]:
    rows = sorted((math.floor(a[0] / _CELL), math.floor(b[0] / _CELL)))
    columns = sorted((math.floor(a[1] / _CELL), math.floor(b[1] / _CELL)))
    for row in range(rows[0], rows[1] + 1):
        for column in range(columns[0], columns[1] + 1):
            yield row, column


def _crossing(p1: Point, p2: Point, p3: Point, p4: Point) -> tuple[float, float, Point] | None:
    """Where two segments cross inside both, as a fraction along each and a point."""
    d1 = (p2[1] - p1[1], p2[0] - p1[0])
    d2 = (p4[1] - p3[1], p4[0] - p3[0])
    denominator = d1[0] * d2[1] - d1[1] * d2[0]
    if denominator == 0:
        return None
    w = (p3[1] - p1[1], p3[0] - p1[0])
    t = (w[0] * d2[1] - w[1] * d2[0]) / denominator
    u = (w[0] * d1[1] - w[1] * d1[0]) / denominator
    if not (1e-9 < t < 1 - 1e-9 and 1e-9 < u < 1 - 1e-9):
        return None
    point = (round(p1[0] + t * (p2[0] - p1[0]), 5), round(p1[1] + t * (p2[1] - p1[1]), 5))
    return t, u, point


def _projection(point: Point, a: Point, b: Point) -> tuple[float, Point]:
    scale = math.cos(math.radians(point[0]))
    ax, ay, bx, by = a[1] * scale, a[0], b[1] * scale, b[0]
    px, py = point[1] * scale, point[0]
    dx, dy = bx - ax, by - ay
    squared = dx * dx + dy * dy
    t = 0.0 if squared == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / squared))
    return t, (round(a[0] + t * (b[0] - a[0]), 5), round(a[1] + t * (b[1] - a[1]), 5))


def repair(lines: list[Line], snap_m: float = SNAP_M) -> list[Line]:
    """Joins lines that cross, and links each loose end to the nearest other line
    within `snap_m`, so the lines make a network a route can follow."""
    grid: dict[tuple[int, int], list[tuple[int, int]]] = defaultdict(list)
    for index, line in enumerate(lines):
        for segment in range(len(line) - 1):
            for cell in _cells(line[segment], line[segment + 1]):
                grid[cell].append((index, segment))

    # Points to add to each line: (segment, fraction along it, point).
    inserts: dict[int, list[tuple[int, float, Point]]] = defaultdict(list)
    tested: set[tuple[int, int, int, int]] = set()
    for cell in sorted(grid):
        members = grid[cell]
        for i, (li, si) in enumerate(members):
            for lj, sj in members[i + 1 :]:
                if (li == lj and abs(si - sj) <= 1) or (li, si, lj, sj) in tested:
                    continue
                tested.add((li, si, lj, sj))
                found = _crossing(lines[li][si], lines[li][si + 1], lines[lj][sj], lines[lj][sj + 1])
                if found:
                    t, u, point = found
                    inserts[li].append((si, t, point))
                    inserts[lj].append((sj, u, point))

    links: list[Line] = []
    for index, line in enumerate(lines):
        for end in (line[0], line[-1]):
            row, column = math.floor(end[0] / _CELL), math.floor(end[1] / _CELL)
            best: tuple[float, int, int, float, Point] | None = None
            for d_row in (-1, 0, 1):
                for d_column in (-1, 0, 1):
                    for lj, sj in grid.get((row + d_row, column + d_column), []):
                        if lj == index:
                            continue
                        t, near = _projection(end, lines[lj][sj], lines[lj][sj + 1])
                        gap = distance_m(end, near)
                        if best is None or (gap, lj, sj) < best[:3]:
                            best = (gap, lj, sj, t, near)
            if best is None or best[0] > snap_m or best[0] < 1:
                continue
            _, lj, sj, t, near = best
            if t <= 0:
                near = lines[lj][sj]
            elif t >= 1:
                near = lines[lj][sj + 1]
            else:
                inserts[lj].append((sj, t, near))
            links.append([end, near])

    repaired: list[Line] = []
    for index, line in enumerate(lines):
        added = sorted(inserts.get(index, []))
        if not added:
            repaired.append(line)
            continue
        out: Line = []
        k = 0
        for segment, point in enumerate(line):
            out.append(point)
            while k < len(added) and added[k][0] == segment:
                out.append(added[k][2])
                k += 1
        repaired.append(out)
    return repaired + links


# ----------------------------------------------------------------------------- network


def build_network(lines: list[Line]) -> Network:
    """The junction graph of a set of lines."""

    def key(point: Point) -> Point:
        return (round(point[0], PRECISION), round(point[1], PRECISION))

    neighbours: dict[Point, set[Point]] = defaultdict(set)
    for line in lines:
        previous: Point | None = None
        for raw in line:
            point = key(raw)
            if previous is not None and point != previous:
                neighbours[previous].add(point)
                neighbours[point].add(previous)
            previous = point

    junctions = sorted(point for point, near in neighbours.items() if len(near) != 2)
    ids = {point: index + 1 for index, point in enumerate(junctions)}

    walked: set[tuple[Point, Point]] = set()
    edges: list[Edge] = []
    for start in junctions:
        for step in sorted(neighbours[start]):
            if (start, step) in walked:
                continue
            chain = [start, step]
            walked.add((start, step))
            walked.add((step, start))
            previous, current = start, step
            while current not in ids:
                following = next(p for p in sorted(neighbours[current]) if p != previous)
                walked.add((current, following))
                walked.add((following, current))
                chain.append(following)
                previous, current = current, following
            length = sum(distance_m(p, q) for p, q in zip(chain, chain[1:]))
            edges.append(
                Edge(
                    a=ids[chain[0]],
                    b=ids[chain[-1]],
                    length_m=round(length),
                    points=_within_steps(simplify(chain, SIMPLIFY_M)),
                )
            )

    # A ring with no junction on it was never reached from one.
    reached = {pair[0] for pair in walked}
    unreached = {point for point, near in neighbours.items() if len(near) == 2} - reached
    loops = 0
    while unreached:
        loops += 1
        frontier = [unreached.pop()]
        while frontier:
            point = frontier.pop()
            for near in neighbours[point]:
                if near in unreached:
                    unreached.discard(near)
                    frontier.append(near)

    edges.sort(key=lambda edge: (edge.a, edge.b, edge.points))
    return Network(
        nodes=junctions,
        edges=edges,
        loops_dropped=loops,
        stats={"points": sum(len(edge.points) for edge in edges)},
    )


def _within_steps(points: list[Point]) -> list[Point]:
    """Adds points along any segment too long for a 16-bit step."""
    result = [points[0]]
    for a, b in zip(points, points[1:]):
        span = max(abs(b[0] - a[0]), abs(b[1] - a[1])) * SCALE
        pieces = max(1, math.ceil(span / MAX_STEP))
        for piece in range(1, pieces + 1):
            fraction = piece / pieces
            result.append((a[0] + (b[0] - a[0]) * fraction, a[1] + (b[1] - a[1]) * fraction))
    return result


# ---------------------------------------------------------------------------- encoding


def encode_points(points: list[Point]) -> bytes:
    """The first point as two little-endian int32, latitude then longitude, in
    1/100,000 of a degree; each later point as two int16 steps from the one before."""
    values = [(round(lat * SCALE), round(lon * SCALE)) for lat, lon in points]
    out = [struct.pack("<ii", *values[0])]
    for (lat0, lon0), (lat1, lon1) in zip(values, values[1:]):
        out.append(struct.pack("<hh", lat1 - lat0, lon1 - lon0))
    return b"".join(out)


def decode_points(blob: bytes) -> list[Point]:
    lat, lon = struct.unpack_from("<ii", blob, 0)
    points = [(lat / SCALE, lon / SCALE)]
    for d_lat, d_lon in struct.iter_unpack("<hh", blob[8:]):
        lat += d_lat
        lon += d_lon
        points.append((lat / SCALE, lon / SCALE))
    return points
