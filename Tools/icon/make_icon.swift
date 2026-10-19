import AppKit
import CoreGraphics

let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// Background: deep night sky.
let background = CGGradient(colorsSpace: space, colors: [color(0.06, 0.12, 0.20), color(0.01, 0.02, 0.05)] as CFArray,
                            locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

let centre = CGPoint(x: size / 2, y: size / 2)
let radius = size * 0.355

// Atmosphere glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: color(0.31, 0.78, 0.62, 0.55))
ctx.setFillColor(color(0.05, 0.15, 0.22))
ctx.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
ctx.restoreGState()

// Ocean, lit from the upper left.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
ctx.clip()
let ocean = CGGradient(colorsSpace: space,
                       colors: [color(0.16, 0.38, 0.52), color(0.07, 0.18, 0.29), color(0.02, 0.06, 0.11)] as CFArray,
                       locations: [0, 0.55, 1])!
ctx.drawRadialGradient(ocean, startCenter: CGPoint(x: centre.x - radius * 0.35, y: centre.y + radius * 0.35),
                       startRadius: 0, endCenter: centre, endRadius: radius * 1.25, options: [])

// Graticule: meridians as ellipses, parallels as chords.
ctx.setStrokeColor(color(1, 1, 1, 0.13))
ctx.setLineWidth(4)
for fraction in [0.35, 0.7] {
    let w = radius * fraction
    ctx.strokeEllipse(in: CGRect(x: centre.x - w, y: centre.y - radius, width: w * 2, height: radius * 2))
}
ctx.move(to: CGPoint(x: centre.x, y: centre.y - radius)); ctx.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
for latitude in [-0.5, 0.0, 0.5] {
    let y = centre.y + radius * latitude
    let half = sqrt(max(0, radius * radius - (y - centre.y) * (y - centre.y)))
    ctx.move(to: CGPoint(x: centre.x - half, y: y)); ctx.addLine(to: CGPoint(x: centre.x + half, y: y))
}
ctx.strokePath()

// Limb shadow.
let limb = CGGradient(colorsSpace: space, colors: [color(0, 0, 0, 0), color(0, 0, 0, 0.55)] as CFArray,
                      locations: [0.6, 1])!
ctx.drawRadialGradient(limb, startCenter: CGPoint(x: centre.x - radius * 0.15, y: centre.y + radius * 0.15),
                       startRadius: 0, endCenter: centre, endRadius: radius * 1.05, options: [])
ctx.restoreGState()

// The arc: a journey across the globe, in the app's flight gold.
let start = CGPoint(x: centre.x - radius * 0.62, y: centre.y - radius * 0.42)
let end = CGPoint(x: centre.x + radius * 0.66, y: centre.y + radius * 0.30)
let control = CGPoint(x: centre.x - radius * 0.10, y: centre.y + radius * 0.78)
let arc = CGMutablePath()
arc.move(to: start); arc.addQuadCurve(to: end, control: control)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 28, color: color(1.0, 0.72, 0.30, 0.9))
ctx.setStrokeColor(color(1.0, 0.80, 0.38))
ctx.setLineWidth(20)
ctx.setLineCap(.round)
ctx.addPath(arc); ctx.strokePath()
ctx.restoreGState()

for point in [start, end] {
    ctx.setFillColor(color(1.0, 0.86, 0.45))
    ctx.fillEllipse(in: CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60))
    ctx.setStrokeColor(color(0.02, 0.05, 0.10, 0.9))
    ctx.setLineWidth(9)
    ctx.strokeEllipse(in: CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60))
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
