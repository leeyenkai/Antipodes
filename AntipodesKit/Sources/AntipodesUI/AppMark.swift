import SwiftUI

/// The app's mark, drawn as vectors so it is crisp at any size: a place, and the place
/// exactly opposite it through the Earth. Used where the app signs its work — share
/// cards and Year in Review — instead of a generic globe symbol.
///
/// It follows the app icon (`Tools/icon/build_icons.py`), simplified for small sizes:
/// the Earth, the diameter through it, and the two antipodal points.
struct AppMark: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let centre = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = side / 2
            context.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: side,
                    height: side
                )),
                with: .color(Palette.visited.opacity(0.85))
            )
            // Up and to the right at 38° from vertical, as on the icon.
            let angle = 38.0 * .pi / 180
            let reach = radius * 0.62
            let near = CGPoint(x: centre.x + reach * sin(angle), y: centre.y - reach * cos(angle))
            let far = CGPoint(x: centre.x - reach * sin(angle), y: centre.y + reach * cos(angle))
            var diameter = Path()
            diameter.move(to: far)
            diameter.addLine(to: near)
            context.stroke(
                diameter,
                with: .color(.white.opacity(0.75)),
                style: StrokeStyle(lineWidth: max(1, side * 0.09), lineCap: .round)
            )
            let farRadius = side * 0.11
            context.fill(
                Path(ellipseIn: CGRect(
                    x: far.x - farRadius,
                    y: far.y - farRadius,
                    width: farRadius * 2,
                    height: farRadius * 2
                )),
                with: .color(.white.opacity(0.85))
            )
            let nearRadius = side * 0.17
            context.fill(
                Path(ellipseIn: CGRect(
                    x: near.x - nearRadius,
                    y: near.y - nearRadius,
                    width: nearRadius * 2,
                    height: nearRadius * 2
                )),
                with: .color(Palette.pin)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
