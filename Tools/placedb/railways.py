#!/usr/bin/env python3
"""A routable railway network from Natural Earth's 1:10m railroads (D-30).

The app snaps a rail leg's two ends to this network and measures the leg along the
shortest way between them (R-PATH-2, R-PATH-5), so a train from Oslo to Bergen counts
the railway's length rather than the straight line's. Natural Earth is public domain,
so unlike OpenStreetMap (D-8) it can sit in the bundled database.

Everything here is pure: `build_placedb.py` reads the GeoJSON, calls `build_network`
and writes what it returns, and `test_railways.py` tests it on its own.

The network is a graph:

* **Nodes are junctions**: the ends of lines, and every vertex where three or more
  stretches of track meet. Vertices are merged at 4 decimal places (about 11 m), which
  is how Natural Earth's own lines join: one line ends on a vertex of another.
* **Edges are the track between two junctions**, with their length measured on the full
  geometry and the geometry itself simplified to `SIMPLIFY_M` for drawing and snapping.
* Ids are given in coordinate order, so the same input builds the same database.
* Railroad ferries are left out: a train ferry is a ferry leg.
"""

from __future__ import annotations

import math
import struct
from collections import defaultdict
from dataclasses import dataclass, field

#: Decimal places at which vertices are the same point (about 11 m).
PRECISION = 4
#: How far the drawn line may stray from the real one. Lengths use the full geometry.
SIMPLIFY_M = 150.0
#: Coordinates are stored as integers of this many units a degree.
SCALE = 100_000

Point = tuple[float, float]  # (latitude, longitude)


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
    #: Closed rings of track with no junction on them, which cannot be entered.
    loops_dropped: int = 0
    features: int = 0
    stats: dict[str, int] = field(default_factory=dict)


def distance_m(a: Point, b: Point) -> float:
    phi1, phi2 = math.radians(a[0]), math.radians(b[0])
    d_phi = phi2 - phi1
    d_lambda = math.radians(b[1] - a[1])
    h = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * 6_371_008.8 * math.asin(min(1.0, math.sqrt(h)))


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


def build_network(features: list[dict]) -> Network:
    """The junction graph of every railroad line in a GeoJSON feature list."""

    def key(lon: float, lat: float) -> Point:
        return (round(lat, PRECISION), round(lon, PRECISION))

    neighbours: dict[Point, set[Point]] = defaultdict(set)
    used = 0
    for feature in features:
        if (feature.get("properties") or {}).get("featurecla") != "Railroad":
            continue
        geometry = feature.get("geometry") or {}
        if geometry.get("type") == "LineString":
            lines = [geometry["coordinates"]]
        elif geometry.get("type") == "MultiLineString":
            lines = geometry["coordinates"]
        else:
            continue
        used += 1
        for line in lines:
            previous: Point | None = None
            for coordinate in line:
                point = key(coordinate[0], coordinate[1])
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
                    points=simplify(chain, SIMPLIFY_M),
                )
            )

    # A ring with no junction on it was never reached from one.
    on_edges = {point for point, near in neighbours.items() if len(near) == 2}
    reached = {pair[0] for pair in walked} | {pair[1] for pair in walked}
    loops = 0
    unreached = on_edges - reached
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
        features=used,
        stats={"points": sum(len(edge.points) for edge in edges)},
    )


def encode_points(points: list[Point]) -> bytes:
    """Little-endian int32 pairs, latitude then longitude, in 1/100,000 of a degree."""
    return b"".join(
        struct.pack("<ii", round(lat * SCALE), round(lon * SCALE)) for lat, lon in points
    )


def decode_points(blob: bytes) -> list[Point]:
    return [
        (lat / SCALE, lon / SCALE) for lat, lon in struct.iter_unpack("<ii", blob)
    ]
