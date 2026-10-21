#!/usr/bin/env python3
"""Builds the app icon's Icon Composer document from geometry (decision D-24).

The app ships "Great circle": one great circle on a glass Earth, carrying a place
on its near side and that place's antipode on its far side. The other two concepts
it was chosen from are kept here so the choice can be revisited and compared.

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
# Palette — the app's own colours (AntipodesUI/DesignSystem.swift), so the icon
# and the globe inside the app are recognisably the same object.
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


def svg(subpaths: list[list[Point]], holes: bool) -> str:
    """One path per shape, so crossing bands stay solid; or, for a shape with holes
    punched in it, one even-odd path."""
    shapes = [subpaths] if holes else [[outline] for outline in subpaths]
    rule = "evenodd" if holes else "nonzero"
    body = "".join(f'  <path fill="#000000" fill-rule="{rule}" d="{path_data(*shape)}"/>\n' for shape in shapes)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">\n'
        f"{body}</svg>\n"
    )


# ---------------------------------------------------------------------------
# The document model
# ---------------------------------------------------------------------------


@dataclass
class Layer:
    name: str
    file: str
    outline: list[list[Point]]
    colour: tuple[float, float, float]
    dark: tuple[float, float, float] | None = None
    opacity: float = 1.0
    glass: bool = True
    holes: bool = False
    # Tinted (monochrome) icons ignore fill colours and draw every layer in the
    # tint, so the only way to keep the points standing out from the Earth there is
    # to let the Earth recede.
    tinted_opacity: float | None = None


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
        def fill(colours: list[tuple[float, float, float]]) -> dict:
            return {
                "linear-gradient": [srgb(c) for c in colours],
                "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
            }

        groups = []
        for group in self.groups:
            layers = []
            for layer in group.layers:
                layers.append(
                    {
                        "fill-specializations": [
                            {"value": {"solid": srgb(layer.colour)}},
                            {"appearance": "dark", "value": {"solid": srgb(layer.dark or layer.colour)}},
                        ],
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
                {"value": fill(self.sky)},
                {"appearance": "dark", "value": fill(self.sky_dark)},
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
                (out / "Assets" / layer.file).write_text(svg(layer.outline, layer.holes))
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


def great_circle(lines: bool = False) -> Concept:
    """One great circle on the Earth, carrying a place and its antipode.

    Every great circle through a point passes through its antipode, and the app
    draws journeys along great circles. The front half of the circle and the near
    point ride on top of the glass; the back half and the antipode lie behind it.
    The band is cut square where it meets the edge of the Earth, so the two halves
    join there without a seam.
    """
    width = 40.0
    a, b, tilt = GLOBE_RADIUS - width / 2, 112.0, -32.0
    front = ellipse_arc(CENTRE, a, b, tilt, 0, 180)
    back = ellipse_arc(CENTRE, a, b, tilt, 180, 360)
    near = ellipse_point(CENTRE, a, b, tilt, 124)
    far = ellipse_point(CENTRE, a, b, tilt, 304)
    grid = graticule(GLOBE_RADIUS, 18, -10, 14) if lines else None
    return Concept(
        "great-circle",
        "Great circle",
        [
            Group(
                "Near side",
                [
                    Layer("Here", "here.svg", [circle_points(near, 64)], CREAM),
                    Layer("Route", "route-front.svg", [stroke_outline(front, width, round_caps=False)], GOLD, GOLD_DARK),
                ],
                shadow=0.5,
            ),
            globe_group(translucency=0.5, lines=grid),
            Group(
                "Far side",
                [
                    Layer("Antipode", "antipode.svg", [circle_points(far, 50)], CREAM),
                    Layer("Route", "route-back.svg", [stroke_outline(back, width, round_caps=False)], GOLD, GOLD_DARK),
                ],
                shadow=0.0,
                specular=False,
            ),
        ],
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
