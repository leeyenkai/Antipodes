import Dispatch
import Foundation

/// A picture of the whole Earth laid out flat: x runs from 180° W to 180° E and y from
/// 90° N down to 90° S, every pixel the same step of longitude and latitude.
///
/// The satellite globe wraps one of these around the sphere (decision D-26). It is
/// bundled with the app, like the country outlines, so turning the globe never fetches
/// anything: the picture is the same whatever the user has logged (R-PRIV-7).
public struct EquirectangularImage: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major, four bytes a pixel in the order red, green, blue, alpha.
    public let pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 1, height > 1, pixels.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// The part of the view a rasterised globe covers, and its pixels.
public struct GlobeRaster: Sendable {
    /// Top-left corner, in points.
    public let originX: Double
    public let originY: Double
    /// Pixels per point.
    public let scale: Double
    public let width: Int
    public let height: Int
    /// Row-major RGBA with premultiplied alpha: opaque on the disc, clear around it, and
    /// partly covered along the limb so the edge is smooth.
    public let pixels: [UInt8]
}

public extension OrthographicGlobe {
    /// The image wrapped onto this globe as seen by the camera, at `scale` pixels per
    /// point, covering only the part of the view the disc occupies.
    ///
    /// Each pixel runs the projection backwards — view point to sphere point to
    /// latitude and longitude — and blends the four nearest pixels of the image, so the
    /// picture neither blocks up when zoomed in nor shimmers as the globe turns. Rows are
    /// shared out across the cores; a full-screen globe is a few milliseconds' work.
    func rasterise(
        _ image: EquirectangularImage,
        viewSize: GlobeSize,
        scale: Double
    ) -> GlobeRaster? {
        guard radius > 0, scale > 0 else { return nil }
        let left = max(0, centre.x - radius)
        let top = max(0, centre.y - radius)
        let right = min(viewSize.width, centre.x + radius)
        let bottom = min(viewSize.height, centre.y + radius)
        guard right > left, bottom > top else { return nil }

        let width = Int((right - left) * scale).clamped(to: 1 ... 8192)
        let height = Int((bottom - top) * scale).clamped(to: 1 ... 8192)
        let frame = RasterFrame(
            globe: self,
            originX: left,
            originY: top,
            scale: scale,
            width: width,
            height: height
        )

        let pixels = [UInt8](unsafeUninitializedCapacity: width * height * 4) { buffer, count in
            guard let output = buffer.baseAddress else { return }
            output.initialize(repeating: 0, count: width * height * 4)
            image.pixels.withUnsafeBufferPointer { source in
                guard let texture = source.baseAddress else { return }
                let target = SharedPixels(texture: texture, output: output)
                // Bands of rows rather than single rows, so each task does enough work
                // to be worth handing out.
                let bands = min(height, ProcessInfo.processInfo.activeProcessorCount * 4)
                DispatchQueue.concurrentPerform(iterations: bands) { band in
                    let first = band * height / bands
                    let last = (band + 1) * height / bands
                    for row in first ..< last {
                        frame.drawRow(row, of: image, into: target)
                    }
                }
            }
            count = width * height * 4
        }

        return GlobeRaster(
            originX: left,
            originY: top,
            scale: scale,
            width: width,
            height: height,
            pixels: pixels
        )
    }
}

/// The pointers one rasterising pass reads and writes. Each band writes only its own
/// rows and the image is only read, so sharing them across the cores is safe.
private struct SharedPixels: @unchecked Sendable {
    let texture: UnsafePointer<UInt8>
    let output: UnsafeMutablePointer<UInt8>
}

/// Everything a row needs, worked out once per pass and in single precision: the
/// picture is eight bits a channel, and floats halve the cost of the maths per pixel.
private struct RasterFrame: Sendable {
    let originX: Float
    let originY: Float
    let pixelSize: Float
    let width: Int
    let height: Int
    let centreX: Float
    let centreY: Float
    let radius: Float
    /// How many output pixels the radius spans, for the anti-aliased edge.
    let radiusInPixels: Float
    let axis: (x: Float, y: Float, z: Float)
    let east: (x: Float, y: Float, z: Float)
    let north: (x: Float, y: Float, z: Float)

    init(
        globe: OrthographicGlobe,
        originX: Double,
        originY: Double,
        scale: Double,
        width: Int,
        height: Int
    ) {
        self.originX = Float(originX)
        self.originY = Float(originY)
        pixelSize = Float(1 / scale)
        self.width = width
        self.height = height
        centreX = Float(globe.centre.x)
        centreY = Float(globe.centre.y)
        radius = Float(globe.radius)
        radiusInPixels = Float(globe.radius * scale)
        axis = (Float(globe.axis.x), Float(globe.axis.y), Float(globe.axis.z))
        east = (Float(globe.east.x), Float(globe.east.y), Float(globe.east.z))
        north = (Float(globe.north.x), Float(globe.north.y), Float(globe.north.z))
    }

    // One tight loop in plain scalars: generic SIMD and nested functions cost little
    // when optimised but dominate an unoptimised debug build.
    // swiftlint:disable:next function_body_length
    func drawRow(_ row: Int, of image: EquirectangularImage, into target: SharedPixels) {
        let pointY = originY + (Float(row) + 0.5) * pixelSize
        let unitY = (centreY - pointY) / radius
        // Half a pixel's slack past the limb, for the soft edge.
        let slack = 1 + 1.5 / radiusInPixels
        guard abs(unitY) <= slack else { return }

        // Only the stretch of the row that crosses the disc.
        let halfWidth = max(0, slack * slack - unitY * unitY).squareRoot() * radius
        let firstColumn = max(0, Int(((centreX - halfWidth) - originX) / pixelSize))
        let lastColumn = min(width - 1, Int(((centreX + halfWidth) - originX) / pixelSize) + 1)
        guard firstColumn <= lastColumn else { return }

        let textureWidth = image.width
        let textureHeight = image.height
        let columnsPerRadian = Float(textureWidth) / (2 * .pi)
        let rowsPerRadian = Float(textureHeight) / .pi
        let texture = target.texture
        var offset = (row * width + firstColumn) * 4
        let (ax, ay, az) = (axis.x, axis.y, axis.z)
        let (ex, ey, ez) = (east.x, east.y, east.z)
        let (nx, ny, nz) = (north.x, north.y, north.z)

        for column in firstColumn ... lastColumn {
            defer { offset += 4 }
            let pointX = originX + (Float(column) + 0.5) * pixelSize
            var unitX = (pointX - centreX) / radius
            var unitYOnDisc = unitY
            let distance = (unitX * unitX + unitY * unitY).squareRoot()
            let coverage = min(1, max(0, (1 - distance) * radiusInPixels + 0.5))
            guard coverage > 0 else { continue }
            if distance > 1 {
                // Just past the limb: sample the limb itself.
                unitX /= distance
                unitYOnDisc /= distance
            }
            let depth = max(0, 1 - unitX * unitX - unitYOnDisc * unitYOnDisc).squareRoot()
            let px = ax * depth + ex * unitX + nx * unitYOnDisc
            let py = ay * depth + ey * unitX + ny * unitYOnDisc
            let pz = az * depth + ez * unitX + nz * unitYOnDisc

            // Latitude and longitude, then the four pixels around them: wrapping round
            // in longitude, stopping at the poles.
            let sampleX = (atan2f(py, px) + .pi) * columnsPerRadian - 0.5
            let sampleY = (.pi / 2 - asinf(min(1, max(-1, pz)))) * rowsPerRadian - 0.5
            let floorX = sampleX.rounded(.down)
            let floorY = sampleY.rounded(.down)
            let fx = sampleX - floorX
            let fy = sampleY - floorY
            var x0 = Int(floorX) % textureWidth
            if x0 < 0 {
                x0 += textureWidth
            }
            let x1 = x0 + 1 == textureWidth ? 0 : x0 + 1
            let y0 = min(textureHeight - 1, max(0, Int(floorY)))
            let y1 = min(textureHeight - 1, y0 + 1)
            let topLeft = (y0 * textureWidth + x0) * 4
            let topRight = (y0 * textureWidth + x1) * 4
            let bottomLeft = (y1 * textureWidth + x0) * 4
            let bottomRight = (y1 * textureWidth + x1) * 4
            let w00 = (1 - fx) * (1 - fy) * coverage
            let w10 = fx * (1 - fy) * coverage
            let w01 = (1 - fx) * fy * coverage
            let w11 = fx * fy * coverage
            let output = target.output + offset
            let red = Float(texture[topLeft]) * w00 + Float(texture[topRight]) * w10
                + Float(texture[bottomLeft]) * w01 + Float(texture[bottomRight]) * w11
            let green = Float(texture[topLeft + 1]) * w00 + Float(texture[topRight + 1]) * w10
                + Float(texture[bottomLeft + 1]) * w01 + Float(texture[bottomRight + 1]) * w11
            let blue = Float(texture[topLeft + 2]) * w00 + Float(texture[topRight + 2]) * w10
                + Float(texture[bottomLeft + 2]) * w01 + Float(texture[bottomRight + 2]) * w11
            output[0] = UInt8(min(255, red + 0.5))
            output[1] = UInt8(min(255, green + 0.5))
            output[2] = UInt8(min(255, blue + 0.5))
            output[3] = UInt8(255 * coverage + 0.5)
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
