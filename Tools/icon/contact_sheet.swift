// Lays rendered icons out on one sheet, labelled, for comparing concepts and
// appearances side by side.
//
//     swift Tools/icon/contact_sheet.swift <out.png> <columns> <cell> <label=image.png>...
//
// A label of "-" leaves the caption off; an image of "-" leaves the cell empty.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 5, let columns = Int(arguments[2]), let cell = Double(arguments[3]) else {
    FileHandle.standardError.write(Data("usage: contact_sheet.swift <out.png> <columns> <cell> <label=image>...\n".utf8))
    exit(64)
}

let entries: [(label: String, path: String)] = arguments.dropFirst(4).map { entry in
    let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
    return (parts[0], parts.count > 1 ? parts[1] : "-")
}

let gutter = cell * 0.12
let caption = cell * 0.16
let rows = (entries.count + columns - 1) / columns
let width = Double(columns) * cell + Double(columns + 1) * gutter
let height = Double(rows) * (cell + caption) + Double(rows + 1) * gutter

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(70) }

context.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = graphics

for (index, entry) in entries.enumerated() {
    let column = index % columns
    let row = index / columns
    let x = gutter + Double(column) * (cell + gutter)
    let top = height - gutter - Double(row) * (cell + caption + gutter)
    let frame = CGRect(x: x, y: top - cell, width: cell, height: cell)

    if entry.path != "-", let image = NSImage(contentsOfFile: entry.path) {
        image.draw(in: frame)
    }
    if entry.label != "-" {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(string: entry.label, attributes: [
            .font: NSFont.systemFont(ofSize: caption * 0.42, weight: .medium),
            .foregroundColor: NSColor(white: 0.2, alpha: 1),
            .paragraphStyle: style,
        ])
        text.draw(in: CGRect(x: x, y: top - cell - caption * 0.85, width: cell, height: caption * 0.7))
    }
}

guard let image = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { exit(70) }
try data.write(to: URL(fileURLWithPath: arguments[1]))
