import SwiftUI

/// The app's mark, drawn as vectors so it is crisp at any size: one great circle on the
/// Earth, carrying a place on its near side and that place's antipode on its far side
/// — every great circle through a point passes through its antipode. Used where the
/// app signs its work, share cards and Year in Review, instead of a generic globe.
///
/// It is the app icon (`Tools/icon/build_icons.py`, decision D-24) without the glass:
/// the same circle, tilt and points, for sizes where the icon itself would be a blur.
struct AppMark: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let centre = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = side / 2

            func point(_ angle: Double) -> CGPoint {
                let x = Geometry.semiMajor * cos(angle)
                let y = Geometry.semiMinor * sin(angle)
                return CGPoint(
                    x: centre.x + radius * (x * cos(Geometry.tilt) - y * sin(Geometry.tilt)),
                    y: centre.y + radius * (x * sin(Geometry.tilt) + y * cos(Geometry.tilt))
                )
            }

            func arc(from start: Double, to end: Double) -> Path {
                var path = Path()
                let steps = 48
                for step in 0 ... steps {
                    let angle = start + (end - start) * Double(step) / Double(steps)
                    if step == 0 {
                        path.move(to: point(angle))
                    } else {
                        path.addLine(to: point(angle))
                    }
                }
                return path
            }

            func dot(at angle: Double, radius dotRadius: CGFloat) -> Path {
                let centre = point(angle)
                return Path(ellipseIn: CGRect(
                    x: centre.x - dotRadius,
                    y: centre.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                ))
            }

            let line = max(1, side * 0.075)
            // The far side first, faint, as if seen through the Earth.
            context.stroke(
                arc(from: .pi, to: 2 * .pi),
                with: .color(Palette.pin.opacity(0.4)),
                style: StrokeStyle(lineWidth: line * 0.8, lineCap: .butt)
            )
            context.fill(
                dot(at: Geometry.far, radius: side * 0.08),
                with: .color(.white.opacity(0.45))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: side,
                    height: side
                )),
                with: .color(Palette.visited.opacity(0.8))
            )
            context.stroke(
                arc(from: 0, to: .pi),
                with: .color(Palette.pin),
                style: StrokeStyle(lineWidth: line, lineCap: .butt)
            )
            context.fill(dot(at: Geometry.near, radius: side * 0.11), with: .color(.white))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The icon's geometry, as fractions of the Earth's radius. Outside the view so the
/// canvas, which draws off the main actor, can read it. The icon's circle reaches the
/// limb and is 0.30 as deep as it is wide; here it is drawn just inside, so the stroke
/// stays on the Earth.
private enum Geometry {
    static let semiMajor = 0.925
    static let semiMinor = 0.2775
    static let tilt = -35.0 * Double.pi / 180
    static let near = 60.0 * Double.pi / 180
    static let far = 240.0 * Double.pi / 180
}
