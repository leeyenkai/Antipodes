#!/usr/bin/env python3
"""Builds the app icon's Icon Composer document from geometry (decision D-24).

The app ships "Great circle": one great circle on a glass Earth, carrying a place
on its near side and that place's antipode on its far side. The Earth carries the
real coastlines, ice sheets and graticule, projected from Natural Earth's
public-domain country outlines and turned so the two points are a true pair:
Madrid, and its antipode near Wellington. The circle is a band painted on the
sphere and seen in true perspective, so it wraps the Earth's edge rather than
floating round it, and it carries a scale like a desk globe's meridian ring. Above,
the North Star sits on the Earth's axis; below, the Southern Cross points along it
to the south celestial pole. The other two concepts it was chosen from are kept
here so the choice can be revisited and compared.

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


def simplify(points: list[Point], tolerance: float, closed: bool = True) -> list[Point]:
    """Drops the points that move the outline by less than `tolerance` (Douglas–Peucker).

    A closed ring is split at the point farthest from its first, and each half kept
    to the same tolerance.
    """

    def open_line(line: list[Point]) -> list[Point]:
        keep = [False] * len(line)
        keep[0] = keep[-1] = True
        stack = [(0, len(line) - 1)]
        while stack:
            i, j = stack.pop()
            a, b = line[i], line[j]
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            worst, at = 0.0, None
            for k in range(i + 1, j):
                p = line[k]
                d = abs(dx * (a[1] - p[1]) - dy * (a[0] - p[0])) / length if length else math.dist(a, p)
                if d > worst:
                    worst, at = d, k
            if at is not None and worst > tolerance:
                keep[at] = True
                stack += [(i, at), (at, j)]
        return [p for p, k in zip(line, keep) if k]

    if len(points) < 8:
        return points
    if not closed:
        return open_line(points)
    far = max(range(len(points)), key=lambda i: math.dist(points[0], points[i]))
    return open_line(points[: far + 1])[:-1] + open_line(points[far:] + points[:1])[:-1]


# ---------------------------------------------------------------------------
# The Earth's land, seen from space
# ---------------------------------------------------------------------------

# Natural Earth's 1:50m countries, public domain, already vendored for the place
# database. Their borders cancel out, which leaves the coasts.
NATURAL_EARTH = (
    Path(__file__).resolve().parent.parent / "placedb" / "vendor" / "naturalearth" / "ne_50m_admin_0_countries.geojson"
)

# Countries almost wholly under an ice sheet, drawn in ice rather than land.
ICE_SHEETS = {"Greenland", "Antarctica"}

Vec3 = tuple[float, float, float]
LonLat = tuple[float, float]


def unit_vector(latitude: float, longitude: float) -> Vec3:
    phi, lam = math.radians(latitude), math.radians(longitude)
    return (math.cos(phi) * math.cos(lam), math.cos(phi) * math.sin(lam), math.sin(phi))


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def normalised(a: Vec3) -> Vec3:
    length = math.sqrt(dot(a, a))
    return (a[0] / length, a[1] / length, a[2] / length)


def opposite(a: Vec3) -> Vec3:
    return (-a[0], -a[1], -a[2])


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


def coastlines(features: list[dict]) -> list[list[LonLat]]:
    """The outlines of the land the countries cover together, one ring per landmass.

    Neighbouring countries in this data share the vertices of their border, so each
    border edge comes once in each direction; dropping those pairs leaves the coast,
    which then chains into rings. Land runs anticlockwise and water enclosed by land,
    such as the Caspian, clockwise. With the borders gone the coasts can be simplified
    without opening a hairline between two countries.
    """
    edges: dict[tuple[LonLat, LonLat], None] = {}
    for feature in features:
        geometry = feature["geometry"]
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        for polygon in polygons:
            for index, ring in enumerate(polygon):
                points = [(round(lon, 7), round(lat, 7)) for lon, lat in ring[:-1]]
                if (polygon_area(points) > 0) != (index == 0):
                    points.reverse()
                for a, b in zip(points, points[1:] + points[:1]):
                    if (b, a) in edges:
                        del edges[(b, a)]
                    else:
                        edges[(a, b)] = None
    onward: dict[LonLat, LonLat] = {}
    for a, b in edges:
        assert a not in onward, f"the coast touches itself at {a}"
        onward[a] = b
    rings = []
    while onward:
        start = point = next(iter(onward))
        ring = []
        while point in onward:
            ring.append(point)
            point = onward.pop(point)
        assert point == start, f"the coast from {start} does not close"
        rings.append(ring)
    return rings


def near_side(rings: list[list[LonLat]], view: View, radius: float, min_area: float) -> list[list[Point]]:
    """The parts of `rings` that face the viewer, as canvas outlines.

    Pieces smaller than `min_area` square points, as seen, would only be speckle on a
    Home Screen, so they are left out. Water enclosed by land is clipped as if it were
    land and then turned back round, so it still cuts through what surrounds it.

    Outlines are simplified to a tenth of a point, well under a pixel at the largest
    size the icon is drawn, which keeps the land within a hair of the sea's edge.
    """
    out = []
    for ring in rings:
        water = polygon_area(ring) < 0
        ordered = list(reversed(ring)) if water else ring
        projected = [view.project(unit_vector(lat, lon)) for lon, lat in densify(ordered, 1.0)]
        for outline in clip_to_near_side(projected):
            canvas = [(CENTRE[0] + radius * x, CENTRE[1] - radius * y) for x, y in outline]
            if abs(polygon_area(canvas)) >= min_area:
                canvas = simplify(canvas, 0.1)
                out.append(list(reversed(canvas)) if water else canvas)
    return out


def land_and_ice(view: View, radius: float, min_area: float) -> tuple[list[list[Point]], list[list[Point]]]:
    """The near side's land, and its ice sheets, as canvas outlines."""
    features = json.loads(NATURAL_EARTH.read_text())["features"]
    land = [f for f in features if f["properties"]["ADMIN"] not in ICE_SHEETS]
    ice = [f for f in features if f["properties"]["ADMIN"] in ICE_SHEETS]
    return (
        near_side(coastlines(land), view, radius, min_area),
        near_side(coastlines(ice), view, radius, min_area),
    )


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


# ---------------------------------------------------------------------------
# A great circle, painted on the Earth
# ---------------------------------------------------------------------------
#
# These work on the unit sphere in view coordinates: x to the right, y up and z
# towards the viewer, as View.project returns them.


def ring_pole(tilt: float, openness: float) -> Vec3:
    """The pole of a great circle that, seen from the front, is an ellipse whose long
    axis rises `tilt` degrees to the right and whose short axis is `openness` times
    the long one. Its near half passes below the centre: a ring seen from just above."""
    t = math.radians(tilt)
    s = math.sqrt(1 - openness**2)
    return (-math.sin(t) * s, math.cos(t) * s, openness)


def on_ring(pole: Vec3, angle: float) -> Vec3:
    """The point `angle` radians round the great circle from where it crosses the limb
    on the right, turning towards the viewer."""
    across = normalised((pole[1], -pole[0], 0.0))
    nearest = cross(across, pole)
    assert across[0] > 0 and nearest[2] > 0
    return tuple(math.cos(angle) * a + math.sin(angle) * n for a, n in zip(across, nearest))


def on_canvas(v: Vec3, radius: float) -> Point:
    return (CENTRE[0] + radius * v[0], CENTRE[1] - radius * v[1])


def limb_between(a: Point, b: Point, step: float = math.radians(0.5)) -> list[Point]:
    """Points along the unit circle strictly between two points on it, the short way."""
    start = math.atan2(a[1], a[0])
    sweep = (math.atan2(b[1], b[0]) - start + math.pi) % math.tau - math.pi
    n = max(1, math.ceil(abs(sweep) / step))
    return [(math.cos(start + sweep * k / n), math.sin(start + sweep * k / n)) for k in range(1, n)]


def ribbon(pole: Vec3, width: float, radius: float, front: bool, steps: int = 360) -> list[Point]:
    """The half of a band round a great circle that faces towards the viewer, or away,
    as one canvas outline.

    The band is painted on the sphere, `width` points wide where it passes nearest the
    viewer. Each of its edges is a small circle, drawn as far as the limb; the two
    edges are joined along the limb, so the band narrows and wraps the Earth's edge as
    a line painted on a ball does, and the front and back halves meet there exactly.
    """
    s = math.hypot(pole[0], pole[1])
    half = math.asin(width / (2 * radius * s))

    def edge(side: int, angle: float) -> Point:
        centre = on_ring(pole, angle)
        x, y, _ = (math.cos(half) * c + side * math.sin(half) * p for c, p in zip(centre, pole))
        return (x, y)

    def run(side: int, backwards: bool) -> list[Point]:
        # An edge faces the viewer between the two angles where it meets the limb.
        lift = math.asin(-side * math.tan(half) * pole[2] / s)
        start, end = (lift, math.pi - lift) if front else (math.pi - lift, math.tau + lift)
        if backwards:
            start, end = end, start
        return [edge(side, start + (end - start) * i / steps) for i in range(steps + 1)]

    upper, lower = run(+1, False), run(-1, True)
    outline = upper + limb_between(upper[-1], lower[0]) + lower + limb_between(lower[-1], upper[0])
    return [on_canvas((x, y, 0.0), radius) for x, y in outline]


def graticule_of(view: View, radius: float, width: float, spacing: int = 30) -> list[list[Point]]:
    """The parallels and meridians every `spacing` degrees on the near side, as bands.

    As on printed globes, only every third meridian runs on to the poles and the rest
    stop at the last parallel, so the lines do not crowd together where they meet.
    Each line ends `width` short of the limb, so its square end stays on the Earth.
    """
    reach = 1 - width / radius

    def visible_runs(samples: list[Vec3]) -> list[list[Point]]:
        runs, current = [], []
        for v in samples:
            x, y, z = view.project(v)
            if z >= 0 and math.hypot(x, y) <= reach:
                current.append(on_canvas((x, y, z), radius))
            elif current:
                runs.append(current)
                current = []
        if current:
            runs.append(current)
        return [simplify(r, 0.1, closed=False) for r in runs if len(r) > 3]

    lines = []
    for lat in range(-90 + spacing, 90, spacing):
        lines += visible_runs([unit_vector(lat, lon / 2) for lon in range(-360, 361)])
    for lon in range(-180, 180, spacing):
        last = 89 if lon % 90 == 0 else 90 - spacing
        lines += visible_runs([unit_vector(lat / 2, lon) for lat in range(-2 * last, 2 * last + 1)])
    return [stroke_outline(line, width, round_caps=False) for line in lines]


def great_arc(a: Vec3, b: Vec3, step: float = math.radians(0.5)) -> list[Vec3]:
    """Points along the shorter great circle from a towards b, a included and b not."""
    omega = math.acos(max(-1.0, min(1.0, dot(a, b))))
    if omega < 1e-12:
        return [a]
    n = max(1, math.ceil(omega / step))
    return [
        tuple((math.sin((1 - k / n) * omega) * p + math.sin(k / n * omega) * q) / math.sin(omega) for p, q in zip(a, b))
        for k in range(n)
    ]


def painted(corners: list[Vec3], radius: float) -> tuple[list[list[Point]], list[list[Point]]]:
    """A small shape painted on the sphere, its corners in view coordinates and its
    sides great-circle arcs: the canvas outlines of the part facing the viewer, and of
    the part facing away, as seen through the Earth."""
    ring = [p for a, b in zip(corners, corners[1:] + corners[:1]) for p in great_arc(a, b)]
    middle = tuple(sum(c) for c in zip(*ring))
    turning = tuple(sum(c) for c in zip(*(cross(a, b) for a, b in zip(ring, ring[1:] + ring[:1]))))
    if dot(turning, middle) < 0:  # clip_to_near_side wants it anticlockwise from outside
        ring.reverse()
    behind = [(x, y, -z) for x, y, z in reversed(ring)]
    return (
        [[on_canvas((x, y, 0.0), radius) for x, y in o] for o in clip_to_near_side(ring)],
        [[on_canvas((x, y, 0.0), radius) for x, y in o] for o in clip_to_near_side(behind)],
    )


def graduations(
    pole: Vec3, width: float, radius: float, start: float, every: int = 10, major: int = 30
) -> tuple[list[list[Point]], list[list[Point]]]:
    """A scale along the band, like the one on a desk globe's meridian ring: a short
    mark across it every `every` degrees round the circle from `start`, a longer one
    every `major`. None at 0° and 180°, which the two points cover. Returns the marks
    facing the viewer and those facing away."""
    s = math.hypot(pole[0], pole[1])
    half = math.asin(width / (2 * radius * s))
    thickness = math.radians(0.3)
    front, back = [], []
    for degrees in range(every, 360, every):
        if degrees == 180:
            continue
        reach = half * (0.6 if degrees % major == 0 else 0.3)
        at = start + math.radians(degrees)
        corners = []
        for along, side in ((-thickness, -1), (thickness, -1), (thickness, 1), (-thickness, 1)):
            centre = on_ring(pole, at + along)
            corners.append(
                tuple(math.cos(reach) * c + side * math.sin(reach) * p for c, p in zip(centre, pole))
            )
        near, far = painted(corners, radius)
        front += near
        back += far
    return front, back


# ---------------------------------------------------------------------------
# The two stars travellers steer by
# ---------------------------------------------------------------------------


def chaikin(points: list[Point], iterations: int = 1) -> list[Point]:
    """Rounds a closed outline's corners by cutting each a quarter of the way in."""
    for _ in range(iterations):
        points = [
            q
            for a, b in zip(points, points[1:] + points[:1])
            for q in ((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]),
                      (0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        ]
    return points


def sparkle(centre: Point, size: float, bearing: float, sharpness: float = 3.4) -> list[Point]:
    """A four-pointed star with concave sides, a stretched astroid, its points `size`
    from the centre, the first on `bearing` (radians clockwise from up). The tips are
    rounded a little, so they stay crisp rather than sharp."""
    c, s = math.cos(bearing), math.sin(bearing)
    outline = []
    for i in range(480):
        t = math.tau * i / 480
        x = size * math.copysign(abs(math.cos(t)) ** sharpness, math.cos(t))
        y = size * math.copysign(abs(math.sin(t)) ** sharpness, math.sin(t))
        outline.append((centre[0] + x * s - y * c, centre[1] - x * c - y * s))
    return simplify(chaikin(outline), 0.1)


# The Southern Cross's four bright stars, J2000: right ascension (h, m, s),
# declination (°, ′, ″) and visual magnitude.
SOUTHERN_CROSS = {
    "Acrux": ((12, 26, 35.9), (-63, 5, 57), 0.76),
    "Mimosa": ((12, 47, 43.3), (-59, 41, 19), 1.25),
    "Gacrux": ((12, 31, 9.96), (-57, 6, 47.6), 1.64),
    "Imai": ((12, 15, 8.7), (-58, 44, 56), 2.79),
}


def southern_cross(centre: Point, height: float, towards: Point) -> list[tuple[Point, float]]:
    """The Cross as it looks from the ground, east to the left of north, as (position,
    magnitude) on the canvas: scaled so Gacrux is `height` from Acrux, and turned so
    the long arm, from Gacrux through Acrux, points at `towards`, the way it points
    at the south celestial pole."""

    def degrees(d: float, m: float, s: float) -> float:
        return math.copysign(abs(d) + m / 60 + s / 3600, d)

    stars = {name: (degrees(*ra) * 15, degrees(*dec), mag) for name, (ra, dec, mag) in SOUTHERN_CROSS.items()}
    ra0 = sum(ra for ra, _, _ in stars.values()) / len(stars)
    dec0 = sum(dec for _, dec, _ in stars.values()) / len(stars)
    # Flat sky coordinates, x to the east (left) and y north (up), in degrees.
    flat = {n: (-(ra - ra0) * math.cos(math.radians(dec0)), dec - dec0, mag) for n, (ra, dec, mag) in stars.items()}
    top, foot = flat["Gacrux"], flat["Acrux"]
    k = height / math.hypot(foot[0] - top[0], foot[1] - top[1])
    mid = ((top[0] + foot[0]) / 2, (top[1] + foot[1]) / 2)
    # On the canvas y points down: the long arm, from Gacrux to Acrux, is (dx, -dy).
    arm = math.atan2(-(foot[1] - top[1]), foot[0] - top[0])
    turn = math.atan2(towards[1] - centre[1], towards[0] - centre[0]) - arm
    out = []
    for x, y, mag in flat.values():
        u, v = (x - mid[0]) * k, -(y - mid[1]) * k
        out.append(((centre[0] + u * math.cos(turn) - v * math.sin(turn),
                     centre[1] + u * math.sin(turn) + v * math.cos(turn)), mag))
    return out


# "Great circle" has its own, deeper palette: a night sky, a sapphire ocean, celadon
# land, white ice, a gold route and starlight.
NIGHT_SKY = [(0.10, 0.13, 0.30), (0.03, 0.04, 0.11)]
NIGHT_SKY_DARK = [(0.05, 0.06, 0.14), (0.00, 0.01, 0.04)]
OCEAN = [(0.18, 0.52, 0.76), (0.06, 0.24, 0.50)]
OCEAN_DARK = [(0.12, 0.38, 0.58), (0.03, 0.16, 0.34)]
LAND = [(0.74, 0.87, 0.66), (0.52, 0.71, 0.50)]
LAND_DARK = [(0.60, 0.74, 0.54), (0.40, 0.56, 0.40)]
ICE = (0.93, 0.96, 0.98)
ICE_DARK = (0.80, 0.84, 0.88)
GRID = (0.75, 0.90, 1.00)
BAND = [(1.00, 0.84, 0.45), (0.96, 0.66, 0.24)]
BAND_DARK = [(0.98, 0.80, 0.42), (0.92, 0.62, 0.24)]
SCALE = (0.86, 0.56, 0.20)
SCALE_DARK = (0.82, 0.53, 0.19)
DOT = (1.00, 0.97, 0.90)
DOT_DARK = (0.97, 0.94, 0.86)
STAR = (1.00, 0.97, 0.88)
STAR_DARK = (0.98, 0.95, 0.86)
# Greys for the tinted and clear icons. Tinted dark can draw nothing brighter than the
# tint itself, so the points stand out only if everything else steps down beneath them:
# the points and stars, then the route, its scale and the ice, the land, the sea.
TINTED = {"dot": 1.0, "star": 1.0, "band": 0.78, "scale": 0.62, "ice": 0.68, "land": 0.52, "grid": 0.30,
          "ocean": 0.12}

# Islands smaller than this, in square points as seen, are left off: about 12,000 km²
# face on. Sicily, Corsica and Iceland stay; Jamaica and the Canaries would be dust.
LAND_MIN_AREA = 30.0

# The place on the near side: Madrid. Its antipode is in New Zealand, near Wellington.
MADRID = (40.42, -3.70)

# The Earth's axial tilt, in degrees: the angle a desk globe leans at.
AXIAL_TILT = 23.44


def great_circle() -> Concept:
    """One great circle on the Earth, carrying a place and its antipode, under the two
    stars travellers steer by.

    Every great circle through a point passes through its antipode, and the app
    draws journeys along great circles. The circle is a gold band painted on the
    Earth and marked every 10° like the meridian ring of a desk globe; its front half
    and the near point ride on top of the glass, and its back half and the antipode
    lie behind it, seen through.

    The Earth is turned so the near point sits on Madrid, and leans like a desk globe,
    its north pole tipped right by the Earth's own axial tilt. That frames the
    Atlantic, between the Americas and Europe and Africa; the far point, mirrored
    through the centre, is Madrid's true antipode, in New Zealand.

    The sky holds the north and the south. The North Star sits on the Earth's axis,
    beyond the north pole, as it does in the real sky. The Southern Cross, the
    southern hemisphere's own sign, hangs on the antipode's side, its long arm
    pointing along the axis to the south celestial pole, as it does for anyone
    finding south by it.

    Each point wears a translucent halo, the way a map marks where you are, which
    gives the glass something to refract and the eye a second depth to read.
    """
    radius, width = 316.0, 38.0
    pole = ring_pole(tilt=35.0, openness=0.30)
    start = math.radians(60)
    here = on_ring(pole, start)
    near = on_canvas(here, radius)
    far = on_canvas(opposite(here), radius)
    view = View.placing(MADRID, near, radius, AXIAL_TILT)
    land, ice = land_and_ice(view, radius, LAND_MIN_AREA)
    earth = [
        # Printed on the ocean rather than glass of their own, so the coasts stay crisp
        # and the Earth catches the light as one sphere.
        Layer("Ice", "ice.svg", ice, ICE, ICE_DARK, glass=False, union=True, tinted_grey=TINTED["ice"]),
        Layer("Land", "land.svg", land, LAND, LAND_DARK, glass=False, union=True, tinted_grey=TINTED["land"]),
        Layer("Graticule", "graticule.svg", graticule_of(view, radius, 4.0), GRID, opacity=0.18, glass=False,
              union=True, tinted_grey=TINTED["grid"]),
        Layer("Ocean", "earth.svg", [circle_points(CENTRE, radius, 720)], OCEAN, OCEAN_DARK,
              tinted_grey=TINTED["ocean"]),
    ]

    def marker(name: str, file: str, at: Point, size: float) -> list[Layer]:
        return [
            Layer(name, f"{file}.svg", [circle_points(at, size, 180)], DOT, DOT_DARK, tinted_grey=TINTED["dot"]),
            Layer("Halo", f"{file}-halo.svg", [circle_points(at, size * 1.68, 180)], DOT, DOT_DARK, opacity=0.32,
                  tinted_grey=TINTED["dot"]),
        ]

    marks_front, marks_back = graduations(pole, width, radius, start)

    def route(file: str, front: bool) -> list[Layer]:
        # The scale is printed on the band, so it takes the band's glass rather than its own.
        marks = marks_front if front else marks_back
        return [
            Layer("Scale", f"scale-{file}.svg", marks, SCALE, SCALE_DARK, glass=False, union=True,
                  tinted_grey=TINTED["scale"]),
            Layer("Route", f"route-{file}.svg", [ribbon(pole, width, radius, front)], BAND, BAND_DARK,
                  tinted_grey=TINTED["band"]),
        ]

    # The axis's direction on the canvas, from the centre towards the north pole.
    x, y, _ = view.project(unit_vector(90, 0))
    north = (x / math.hypot(x, y), -y / math.hypot(x, y))
    bearing = math.atan2(north[0], -north[1])
    polaris = (CENTRE[0] + north[0] * radius * 1.36, CENTRE[1] + north[1] * radius * 1.36)
    south_pole_of_sky = (CENTRE[0] - north[0] * radius * 1.9, CENTRE[1] - north[1] * radius * 1.9)
    cross = [
        # Sized by brightness, flux to the half power, so Imai still reads at the smallest
        # sizes; Polaris, the one star that marks north, is drawn larger than its own.
        sparkle(at, max(13.0, 27.0 * 10 ** (-0.2 * (magnitude - 0.76))), bearing)
        for at, magnitude in southern_cross((166.0, 792.0), 165.0, south_pole_of_sky)
    ]
    # Starlight, not glass: on a dark sky the glass's edge rings each star like a sticker,
    # and leaving the stars flat keeps them far behind the glass Earth.
    sky = [
        Layer("North Star", "north-star.svg", [sparkle(polaris, 48.0, bearing)], STAR, STAR_DARK, glass=False,
              tinted_grey=TINTED["star"]),
        Layer("Southern Cross", "southern-cross.svg", cross, STAR, STAR_DARK, glass=False,
              tinted_grey=TINTED["star"]),
    ]

    return Concept(
        "great-circle",
        "Great circle",
        [
            Group("Near side", marker("Here", "here", near, 36.0) + route("front", True), shadow=0.5),
            Group("Earth", earth, shadow=0.45, translucency=0.6),
            Group("Far side", marker("Antipode", "antipode", far, 29.0) + route("back", False), shadow=0.0,
                  specular=False),
            Group("Sky", sky, shadow=0.0, specular=False),
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
