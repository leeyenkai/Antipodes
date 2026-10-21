#!/usr/bin/env python3
"""Builds the app icon's Icon Composer document from geometry (decision D-24).

The app ships "Great circle": one great circle on a glass Earth, carrying a place
on its near side and that place's antipode on its far side. The Earth carries the
real continents, projected from Natural Earth's public-domain country outlines and
turned so the two points are a true pair: Madrid, and its antipode near Wellington.
The other two concepts it was chosen from are kept here so the choice can be
revisited and compared.

Each concept is an `.icon` bundle: an `icon.json` describing groups, glass and
fills, plus one flat SVG per layer on a 1024 x 1024 canvas. The system adds the
Liquid Glass lighting, the shadows and the mask, so the layers carry none of
that (Human Interface Guidelines, "App icons"): square and unmasked, clear edges,
no baked highlights, no hairlines.

Every shape is written as a filled outline rather than a stroke, so a layer's
colour comes from `icon.json` in every appearance.

Standard library only, and deterministic: the same script writes the same bytes.

    python3 -I Tools/icon/build_icons.py            # the app's icon, App/Antipodes/AppIcon.icon
    python3 -I Tools/icon/build_icons.py --all      # every concept, into Tools/icon/out/concepts
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
from dataclasses import dataclass, field
from pathlib import Path

CANVAS = 1024
CENTRE = (CANVAS / 2, CANVAS / 2)

Point = tuple[float, float]

# ---------------------------------------------------------------------------
# Palette — the app's own colours (AntipodesUI/DesignSystem.swift), used by the
# concepts that were not chosen. "Great circle" has its own, further down.
# ---------------------------------------------------------------------------

GOLD = (0.99, 0.83, 0.40)  # Palette.pin
GOLD_DARK = (0.96, 0.78, 0.34)
TEAL = (0.31, 0.78, 0.62)  # Palette.visited
CREAM = (1.00, 0.97, 0.88)

SKY_LIGHT = [(0.10, 0.25, 0.36), (0.02, 0.08, 0.15)]
SKY_DARK = [(0.04, 0.08, 0.12), (0.00, 0.01, 0.03)]


def srgb(rgb: tuple[float, float, float], alpha: float = 1.0) -> str:
    r, g, b = rgb
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


def add(a: Point, b: Point) -> Point:
    return (a[0] + b[0], a[1] + b[1])


def scale(a: Point, k: float) -> Point:
    return (a[0] * k, a[1] * k)


def rotate(p: Point, degrees: float) -> Point:
    """Rotates clockwise on screen (y points down), as SVG's rotate() does."""
    t = math.radians(degrees)
    return (p[0] * math.cos(t) - p[1] * math.sin(t), p[0] * math.sin(t) + p[1] * math.cos(t))


def axis(tilt_degrees: float) -> Point:
    """A unit vector tilted clockwise from straight up."""
    t = math.radians(tilt_degrees)
    return (math.sin(t), -math.cos(t))


def circle_points(centre: Point, radius: float, steps: int = 180) -> list[Point]:
    return [
        (centre[0] + radius * math.cos(2 * math.pi * i / steps), centre[1] + radius * math.sin(2 * math.pi * i / steps))
        for i in range(steps)
    ]


def stroke_outline(points: list[Point], width: float, round_caps: bool = True, cap_steps: int = 24) -> list[Point]:
    """The filled outline of a polyline stroked with round caps, or square-cut ends."""
    half = width / 2

    def normal(i: int) -> Point:
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        return (-dy / length, dx / length)

    left = [add(p, scale(normal(i), half)) for i, p in enumerate(points)]
    right = [add(p, scale(normal(i), -half)) for i, p in enumerate(points)]

    def cap(centre: Point, start: Point) -> list[Point]:
        # Half a turn round `centre`, beginning at `start`.
        if not round_caps:
            return []
        angle = math.atan2(start[1] - centre[1], start[0] - centre[0])
        return [
            (centre[0] + half * math.cos(angle + math.pi * k / cap_steps),
             centre[1] + half * math.sin(angle + math.pi * k / cap_steps))
            for k in range(1, cap_steps)
        ]

    return left + cap(points[-1], left[-1]) + list(reversed(right)) + cap(points[0], right[0])


def segment(start: Point, end: Point, steps: int = 2) -> list[Point]:
    return [(start[0] + (end[0] - start[0]) * i / steps, start[1] + (end[1] - start[1]) * i / steps) for i in range(steps + 1)]


def ellipse_arc(
    centre: Point, semi_major: float, semi_minor: float, tilt: float, start: float, end: float, steps: int = 160
) -> list[Point]:
    """Points along an ellipse rotated by `tilt` degrees, between two parameter angles."""
    out = []
    for i in range(steps + 1):
        t = math.radians(start + (end - start) * i / steps)
        out.append(add(centre, rotate((semi_major * math.cos(t), semi_minor * math.sin(t)), tilt)))
    return out


def ellipse_point(centre: Point, semi_major: float, semi_minor: float, tilt: float, at: float) -> Point:
    t = math.radians(at)
    return add(centre, rotate((semi_major * math.cos(t), semi_minor * math.sin(t)), tilt))


def pin_outline(tip: Point, direction_degrees: float, length: float, head_radius: float) -> list[Point]:
    """A map pin whose point sits at `tip` and whose head lies along the tilt."""
    d = length - head_radius
    beta = math.acos(head_radius / d)
    centre = (0.0, -d)
    local: list[Point] = [(0.0, 0.0)]
    # From the right tangent point, over the top of the head, to the left one.
    start = math.pi / 2 - beta
    sweep = -(2 * math.pi - 2 * beta)
    steps = 96
    for k in range(steps + 1):
        a = start + sweep * k / steps
        local.append((centre[0] + head_radius * math.cos(a), centre[1] + head_radius * math.sin(a)))
    return [add(tip, rotate(p, direction_degrees)) for p in local]


def pin_head_centre(tip: Point, direction_degrees: float, length: float, head_radius: float) -> Point:
    return add(tip, rotate((0.0, -(length - head_radius)), direction_degrees))


def path_data(*subpaths: list[Point]) -> str:
    parts = []
    for points in subpaths:
        head, *rest = points
        parts.append(f"M{head[0]:.2f} {head[1]:.2f}" + "".join(f"L{x:.2f} {y:.2f}" for x, y in rest) + "Z")
    return "".join(parts)


def svg(subpaths: list[list[Point]], holes: bool, union: bool = False) -> str:
    """One path per shape, so crossing bands stay solid; for a shape with holes
    punched in it, one even-odd path; or, for many shapes that share edges, one
    non-zero path, so the edges they share leave no anti-aliased seam."""
    shapes = [subpaths] if holes or union else [[outline] for outline in subpaths]
    rule = "evenodd" if holes else "nonzero"
    body = "".join(f'  <path fill="#000000" fill-rule="{rule}" d="{path_data(*shape)}"/>\n' for shape in shapes)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">\n'
        f"{body}</svg>\n"
    )


def polygon_area(points: list[Point]) -> float:
    """Signed area by the shoelace formula: positive when the points run anticlockwise
    with y pointing up."""
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1])) / 2


# ---------------------------------------------------------------------------
# The Earth's land, seen from space
# ---------------------------------------------------------------------------

# Natural Earth's 1:110m countries, public domain, already vendored for the place
# database. Filling every country the same colour, with no strokes, draws the land.
NATURAL_EARTH = (
    Path(__file__).resolve().parent.parent / "placedb" / "vendor" / "naturalearth" / "ne_110m_admin_0_countries.geojson"
)

Vec3 = tuple[float, float, float]


def unit_vector(latitude: float, longitude: float) -> Vec3:
    phi, lam = math.radians(latitude), math.radians(longitude)
    return (math.cos(phi) * math.cos(lam), math.cos(phi) * math.sin(lam), math.sin(phi))


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


@dataclass(frozen=True)
class View:
    """An orthographic view of the Earth from far away: the place at the centre of
    the disc, and how far the picture is turned clockwise from north-up."""

    latitude: float
    longitude: float
    roll: float = 0.0

    def axes(self) -> tuple[Vec3, Vec3, Vec3]:
        """Screen right, screen up and towards the viewer, in Earth-centred coordinates."""
        phi, lam, gamma = map(math.radians, (self.latitude, self.longitude, self.roll))
        east = (-math.sin(lam), math.cos(lam), 0.0)
        north = (-math.sin(phi) * math.cos(lam), -math.sin(phi) * math.sin(lam), math.cos(phi))
        c, s = math.cos(gamma), math.sin(gamma)
        right = tuple(e * c + n * s for e, n in zip(east, north))
        up = tuple(n * c - e * s for e, n in zip(east, north))
        return right, up, unit_vector(self.latitude, self.longitude)

    def project(self, v: Vec3) -> Vec3:
        """(x, y, depth) on the unit disc, y up; depth is negative on the far side."""
        right, up, toward = self.axes()
        return (dot(v, right), dot(v, up), dot(v, toward))

    @staticmethod
    def placing(place: tuple[float, float], at: Point, radius: float, roll: float = 0.0) -> View:
        """The view, turned by `roll`, that shows `place` (latitude, longitude) at canvas
        point `at`, on the near side of a globe of `radius` centred on the canvas.

        In this projection the antipode of whatever lies at `at` lies at `at` mirrored
        through the centre, on the far side, so this places the antipode too.
        """
        x, y = (at[0] - CENTRE[0]) / radius, (CENTRE[1] - at[1]) / radius
        gamma = math.radians(roll)
        east = x * math.cos(gamma) - y * math.sin(gamma)
        north = x * math.sin(gamma) + y * math.cos(gamma)
        phi = math.radians(place[0])
        d_lam = math.asin(east / math.cos(phi))
        a, b = math.sin(phi), math.cos(phi) * math.cos(d_lam)
        h, delta = math.hypot(a, b), math.atan2(b, a)
        for sign in (1, -1):
            phi0 = sign * math.acos(north / h) - delta
            if abs(phi0) <= math.pi / 2 and a * math.sin(phi0) + b * math.cos(phi0) > 0:
                view = View(math.degrees(phi0), place[1] - math.degrees(d_lam), roll)
                px, py, _ = view.project(unit_vector(*place))
                assert math.isclose(px, x, abs_tol=1e-9) and math.isclose(py, y, abs_tol=1e-9)
                return view
        raise ValueError(f"no view puts {place} at {at}")


def densify(ring: list[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    """Adds points along each edge, straight in longitude and latitude as the data
    means them, so long edges bend as they should once projected."""
    out = []
    for (lon1, lat1), (lon2, lat2) in zip(ring, ring[1:] + ring[:1]):
        n = max(1, math.ceil(max(abs(lon2 - lon1), abs(lat2 - lat1)) / step))
        out += [(lon1 + (lon2 - lon1) * k / n, lat1 + (lat2 - lat1) * k / n) for k in range(n)]
    return out


def clip_to_near_side(ring: list[Vec3]) -> list[list[tuple[float, float]]]:
    """The part of an anticlockwise ring on the near side, on the unit disc.

    Where the ring passes round the back of the Earth, its outline instead follows
    the limb, anticlockwise from where it left to where it next comes back, so the
    land meets the edge of the Earth along the Earth's own curve.
    """
    if all(p[2] >= 0 for p in ring):
        return [[(p[0], p[1]) for p in ring]]
    if all(p[2] < 0 for p in ring):
        return []
    first_hidden = next(i for i, p in enumerate(ring) if p[2] < 0)
    ring = ring[first_hidden:] + ring[:first_hidden]

    def crossing(a: Vec3, b: Vec3) -> tuple[float, float]:
        t = a[2] / (a[2] - b[2])
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        length = math.hypot(x, y)
        return (x / length, y / length)

    runs: list[tuple[list[tuple[float, float]], float, float]] = []
    current: list[tuple[float, float]] = []
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if a[2] < 0 <= b[2]:
            current = [crossing(a, b), (b[0], b[1])]
        elif a[2] >= 0 and b[2] >= 0:
            current.append((b[0], b[1]))
        elif a[2] >= 0 > b[2]:
            current.append(crossing(a, b))
            entry, exit_ = current[0], current[-1]
            runs.append((current, math.atan2(entry[1], entry[0]), math.atan2(exit_[1], exit_[0])))
            current = []

    def limb(start: float, end: float) -> list[tuple[float, float]]:
        sweep = (end - start) % math.tau
        n = max(1, math.ceil(sweep / math.radians(1)))
        return [(math.cos(start + sweep * k / n), math.sin(start + sweep * k / n)) for k in range(1, n)]

    outlines, used = [], set()
    for first in range(len(runs)):
        outline, i = [], first
        while i not in used:
            used.add(i)
            points, _, leaves = runs[i]
            i = min(range(len(runs)), key=lambda j: (runs[j][1] - leaves) % math.tau)
            outline += points + limb(leaves, runs[i][1])
        if outline:
            outlines.append(outline)
    return outlines


def land(view: View, radius: float, min_area: float) -> list[list[Point]]:
    """Every country on the near side of the Earth, as canvas outlines.

    Islands smaller than `min_area` square points, as seen, would only be speckle on
    a Home Screen, so they are left out. An island here is a whole landmass, every
    country on it counted together: neighbouring countries share the vertices of
    their border in this data, so a small country inside a continent always stays.

    The outlines are not simplified: two countries simplified apart no longer meet
    exactly, and the sea shows through the hairline between them.
    """
    features = json.loads(NATURAL_EARTH.read_text())["features"]
    pieces: list[tuple[set[tuple[float, float]], list[list[Point]]]] = []
    for feature in features:
        geometry = feature["geometry"]
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        for polygon in polygons:
            # The outer ring only: the one hole in this data, Lesotho in South Africa,
            # is itself a country.
            ring = [(lon, lat) for lon, lat in polygon[0][:-1]]
            if polygon_area(ring) < 0:
                ring.reverse()
            projected = [view.project(unit_vector(lat, lon)) for lon, lat in densify(ring, 1.0)]
            outlines = [
                [(CENTRE[0] + radius * x, CENTRE[1] - radius * y) for x, y in outline]
                for outline in clip_to_near_side(projected)
            ]
            pieces.append(({(round(lon, 6), round(lat, 6)) for lon, lat in ring}, outlines))

    # Join pieces that share a vertex into landmasses.
    parent = list(range(len(pieces)))

    def root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    owner: dict[tuple[float, float], int] = {}
    for i, (vertices, _) in enumerate(pieces):
        for vertex in vertices:
            if vertex in owner:
                parent[root(i)] = root(owner[vertex])
            else:
                owner[vertex] = i
    areas: dict[int, float] = {}
    for i, (_, outlines) in enumerate(pieces):
        areas[root(i)] = areas.get(root(i), 0.0) + sum(abs(polygon_area(o)) for o in outlines)
    return [
        outline
        for i, (_, outlines) in enumerate(pieces)
        if areas[root(i)] >= min_area
        for outline in outlines
    ]


# ---------------------------------------------------------------------------
# The document model
# ---------------------------------------------------------------------------


RGB = tuple[float, float, float]
# A solid colour, or a list of colours for a gradient from the top of the shape down.
Fill = RGB | list[RGB]


def fill_value(fill: Fill) -> dict:
    if isinstance(fill, list):
        return {
            "linear-gradient": [srgb(c) for c in fill],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
        }
    return {"solid": srgb(fill)}


@dataclass
class Layer:
    name: str
    file: str
    outline: list[list[Point]]
    colour: Fill
    dark: Fill | None = None
    opacity: float = 1.0
    glass: bool = True
    holes: bool = False
    union: bool = False
    # Tinted (monochrome) icons draw every layer in the tint, so the only way to keep
    # the points standing out from the Earth there is to let the Earth recede.
    tinted_opacity: float | None = None
    # Or, more strongly: the grey a layer is drawn in for the tinted and clear icons,
    # whose tint and glass then take their light and dark from it. Without one they
    # read the layer's colour, and a cream and a sage end up almost the same.
    tinted_grey: float | None = None


@dataclass
class Group:
    name: str
    layers: list[Layer]
    shadow: float = 0.5
    specular: bool = True
    translucency: float | None = None


@dataclass
class Concept:
    slug: str
    title: str
    groups: list[Group]  # front first, as Icon Composer lists them
    sky: list[tuple[float, float, float]] = field(default_factory=lambda: SKY_LIGHT)
    sky_dark: list[tuple[float, float, float]] = field(default_factory=lambda: SKY_DARK)

    def document(self) -> dict:
        groups = []
        for group in self.groups:
            layers = []
            for layer in group.layers:
                layers.append(
                    {
                        "fill-specializations": [
                            {"value": fill_value(layer.colour)},
                            {"appearance": "dark", "value": fill_value(layer.dark or layer.colour)},
                        ]
                        + (
                            [{"appearance": "tinted", "value": fill_value((layer.tinted_grey,) * 3)}]
                            if layer.tinted_grey is not None
                            else []
                        ),
                        "glass": layer.glass,
                        "image-name": layer.file,
                        "name": layer.name,
                        "opacity": layer.opacity,
                    }
                    | (
                        {
                            "opacity-specializations": [
                                {"value": layer.opacity},
                                {"appearance": "tinted", "value": layer.tinted_opacity},
                            ]
                        }
                        if layer.tinted_opacity is not None
                        else {}
                    )
                )
            groups.append(
                {
                    "layers": layers,
                    "name": group.name,
                    "shadow": {"kind": "neutral", "opacity": group.shadow},
                    "specular": group.specular,
                    "translucency": {
                        "enabled": group.translucency is not None,
                        "value": group.translucency or 0.0,
                    },
                }
            )
        return {
            "fill-specializations": [
                {"value": fill_value(self.sky)},
                {"appearance": "dark", "value": fill_value(self.sky_dark)},
            ],
            "groups": groups,
            "supported-platforms": {"squares": "shared"},
        }

    def write(self, out: Path) -> None:
        if out.exists():
            shutil.rmtree(out)
        (out / "Assets").mkdir(parents=True)
        for group in self.groups:
            for layer in group.layers:
                (out / "Assets" / layer.file).write_text(svg(layer.outline, layer.holes, layer.union))
        (out / "icon.json").write_text(json.dumps(self.document(), indent=2, sort_keys=True) + "\n")


# ---------------------------------------------------------------------------
# The concepts
# ---------------------------------------------------------------------------

GLOBE_RADIUS = 300.0
GLOBE_FILL = (0.30, 0.72, 0.66)
GLOBE_FILL_DARK = (0.22, 0.56, 0.52)


GRATICULE = (0.13, 0.42, 0.44)
GRATICULE_DARK = (0.09, 0.30, 0.32)


def graticule(radius: float, pole_toward_viewer: float, spin: float, width: float) -> list[list[Point]]:
    """The near half of a few parallels and meridians, as filled bands.

    The globe's north pole leans `pole_toward_viewer` degrees towards the viewer and
    the whole drawing is turned `spin` degrees clockwise. Only what faces the viewer
    is drawn: a sphere seen from outside shows one face.
    """
    d = math.radians(pole_toward_viewer)

    def project(lat: float, lon: float) -> tuple[Point, float]:
        phi, lam = math.radians(lat), math.radians(lon)
        x, y, z = math.cos(phi) * math.sin(lam), math.sin(phi), math.cos(phi) * math.cos(lam)
        y2, z2 = y * math.cos(d) - z * math.sin(d), y * math.sin(d) + z * math.cos(d)
        return add(CENTRE, rotate((radius * x, -radius * y2), spin)), z2

    def visible_runs(samples: list[tuple[Point, float]]) -> list[list[Point]]:
        runs, current = [], []
        for point, depth in samples:
            if depth >= 0:
                current.append(point)
            elif current:
                runs.append(current)
                current = []
        if current:
            runs.append(current)
        return [run for run in runs if len(run) > 2]

    bands = []
    for lat in (-35, 0, 35):
        samples = [project(lat, lon / 2) for lon in range(-360, 361)]
        bands += visible_runs(samples)
    for lon in (-60, 0, 60):
        samples = [project(lat / 4, lon) for lat in range(-360, 361)]
        bands += visible_runs(samples)
    return [stroke_outline(run, width, round_caps=False) for run in bands]


def globe_group(
    radius: float = GLOBE_RADIUS, translucency: float = 0.45, lines: list[list[Point]] | None = None
) -> Group:
    layers = []
    if lines:
        layers.append(Layer("Graticule", "graticule.svg", lines, GRATICULE, GRATICULE_DARK, opacity=0.42, glass=False))
    layers.append(
        Layer("Earth", "earth.svg", [circle_points(CENTRE, radius, 360)], GLOBE_FILL, GLOBE_FILL_DARK, tinted_opacity=0.5)
    )
    return Group("Earth", layers, shadow=0.45, translucency=translucency)


def through_the_earth(lines: bool = True) -> Concept:
    """A place, and the place exactly opposite it, seen through the glass Earth.

    In an orthographic view the antipode of a point on the near face projects to
    the point mirrored through the centre, on the far face. So the near point
    sits in front of the glass, and its antipode and the diameter joining them
    lie behind it, softened by the glass they are seen through.
    """
    u = axis(38)
    offset = scale(u, GLOBE_RADIUS * 0.62)
    near = add(CENTRE, offset)
    far = add(CENTRE, scale(offset, -1))
    grid = graticule(GLOBE_RADIUS, 18, -10, 16) if lines else None
    return Concept(
        "through-the-earth",
        "Through the earth",
        [
            Group("Here", [Layer("Here", "here.svg", [circle_points(near, 70)], GOLD, GOLD_DARK)], shadow=0.55),
            globe_group(translucency=0.55, lines=grid),
            Group(
                "Opposite",
                [
                    Layer("Diameter", "diameter.svg", [stroke_outline(segment(far, near), 30)], CREAM),
                    Layer("Antipode", "antipode.svg", [circle_points(far, 48)], CREAM),
                ],
                shadow=0.0,
                specular=False,
            ),
        ],
    )


# "Great circle" has its own, deeper palette: a night sky, a real ocean and land.
NIGHT_SKY = [(0.11, 0.15, 0.33), (0.02, 0.03, 0.10)]
NIGHT_SKY_DARK = [(0.05, 0.06, 0.13), (0.00, 0.01, 0.03)]
OCEAN = [(0.16, 0.55, 0.72), (0.05, 0.27, 0.47)]
OCEAN_DARK = [(0.11, 0.40, 0.55), (0.03, 0.18, 0.33)]
LAND = [(0.67, 0.85, 0.62), (0.51, 0.72, 0.49)]
LAND_DARK = [(0.53, 0.71, 0.49), (0.39, 0.56, 0.38)]
BAND = (0.99, 0.76, 0.30)
BAND_DARK = (0.96, 0.71, 0.26)
DOT = (1.00, 0.96, 0.87)
# Greys for the tinted and clear icons, brightest first: the point, the circle, the
# land, the sea.
TINTED = {"dot": 1.0, "band": 0.96, "land": 0.72, "ocean": 0.18}

# Islands smaller than this, in square points as seen, are left off: Ireland and
# Iceland stay, Sicily and Jamaica would be specks.
LAND_MIN_AREA = 120.0

# The place on the near side: Madrid. Its antipode is in New Zealand, near Wellington.
MADRID = (40.42, -3.70)


def great_circle(lines: bool = False, near_at: float = 68.0, roll: float = 30.0) -> Concept:
    """One great circle on the Earth, carrying a place and its antipode.

    Every great circle through a point passes through its antipode, and the app
    draws journeys along great circles. The front half of the circle and the near
    point ride on top of the glass; the back half and the antipode lie behind it.
    The band is cut square where it meets the edge of the Earth, so the two halves
    join there without a seam.

    The Earth is turned so the near point sits on Madrid, and leans like a desk
    globe, its north pole tipped `roll` degrees to the right. The far point, mirrored
    through the centre, is then Madrid's true antipode, in New Zealand.
    """
    width = 40.0
    a, b, tilt = GLOBE_RADIUS - width / 2, 112.0, -32.0
    front = ellipse_arc(CENTRE, a, b, tilt, 0, 180)
    back = ellipse_arc(CENTRE, a, b, tilt, 180, 360)
    near = ellipse_point(CENTRE, a, b, tilt, near_at)
    far = ellipse_point(CENTRE, a, b, tilt, near_at + 180)
    view = View.placing(MADRID, near, GLOBE_RADIUS, roll)
    continents = land(view, GLOBE_RADIUS, min_area=LAND_MIN_AREA)
    sphere = [circle_points(CENTRE, GLOBE_RADIUS, 360)]
    earth = [
        # Printed on the ocean rather than glass of its own, so the coasts stay crisp
        # and the Earth catches the light as one sphere.
        Layer("Land", "land.svg", continents, LAND, LAND_DARK, glass=False, union=True, tinted_grey=TINTED["land"]),
        Layer("Ocean", "earth.svg", sphere, OCEAN, OCEAN_DARK, tinted_grey=TINTED["ocean"]),
    ]
    if lines:
        grid = graticule(GLOBE_RADIUS, 18, -10, 14)
        earth.insert(1, Layer("Graticule", "graticule.svg", grid, GRATICULE, GRATICULE_DARK, opacity=0.42, glass=False))
    return Concept(
        "great-circle",
        "Great circle",
        [
            Group(
                "Near side",
                [
                    Layer("Here", "here.svg", [circle_points(near, 64)], DOT, tinted_grey=TINTED["dot"]),
                    Layer("Route", "route-front.svg", [stroke_outline(front, width, round_caps=False)], BAND,
                          BAND_DARK, tinted_grey=TINTED["band"]),
                ],
                shadow=0.5,
            ),
            Group("Earth", earth, shadow=0.45, translucency=0.6),
            Group(
                "Far side",
                [
                    Layer("Antipode", "antipode.svg", [circle_points(far, 50)], DOT, tinted_grey=TINTED["dot"]),
                    Layer("Route", "route-back.svg", [stroke_outline(back, width, round_caps=False)], BAND,
                          BAND_DARK, tinted_grey=TINTED["band"]),
                ],
                shadow=0.0,
                specular=False,
            ),
        ],
        sky=NIGHT_SKY,
        sky_dark=NIGHT_SKY_DARK,
    )


def down_under(lines: bool = True) -> Concept:
    """Two pins on opposite sides of the Earth, one standing on its head.

    The pair is symmetric under a half-turn about the centre, which is exactly
    what taking the antipode does. The axis leans at the Earth's own 23.4°.
    """
    tilt = 23.4
    radius = 240.0
    length, head = 184.0, 72.0
    u = axis(tilt)
    top_tip = add(CENTRE, scale(u, radius - 8))
    bottom_tip = add(CENTRE, scale(u, -(radius - 8)))
    grid = graticule(radius, 18, tilt, 14) if lines else None

    def pin(tip: Point, direction: float) -> list[list[Point]]:
        return [
            pin_outline(tip, direction, length, head),
            circle_points(pin_head_centre(tip, direction, length, head), head * 0.40),
        ]

    return Concept(
        "down-under",
        "Down under",
        [
            Group(
                "Pins",
                [
                    Layer("Here", "here.svg", pin(top_tip, tilt), GOLD, GOLD_DARK, holes=True),
                    Layer("Antipode", "antipode.svg", pin(bottom_tip, tilt + 180), CREAM, holes=True),
                ],
                shadow=0.5,
            ),
            globe_group(radius=radius, translucency=0.4, lines=grid),
        ],
    )


CONCEPTS = {c.slug: c for c in (through_the_earth(), great_circle(), down_under())}


SHIPPING = "great-circle"


def main() -> None:
    here = Path(__file__).resolve().parent
    repo = here.parent.parent
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true", help="write every concept, to compare them")
    args = parser.parse_args()

    if args.all:
        for slug, concept in sorted(CONCEPTS.items()):
            out = here / "out" / "concepts" / f"{slug}.icon"
            concept.write(out)
            print(f"wrote {out}")
    else:
        out = repo / "App" / "Antipodes" / "AppIcon.icon"
        CONCEPTS[SHIPPING].write(out)
        print(f"wrote {out}")


if __name__ == "__main__":
    main()
