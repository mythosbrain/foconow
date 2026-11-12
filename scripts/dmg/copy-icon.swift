import AppKit

let file = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { _ in
    let tile = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 448, height: 448), xRadius: 112, yRadius: 112)
    NSGradient(colors: [NSColor(srgbRed: 0.23, green: 0.25, blue: 0.29, alpha: 1), NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)])!.draw(in: tile, angle: -70)
    NSColor(white: 0.65, alpha: 0.35).setStroke()
    tile.lineWidth = 5
    tile.stroke()
    let back = NSBezierPath(roundedRect: NSRect(x: 142, y: 181, width: 168, height: 196), xRadius: 25, yRadius: 25)
    NSColor(white: 0.65, alpha: 1).setStroke()
    back.lineWidth = 13
    back.stroke()
    let front = NSBezierPath(roundedRect: NSRect(x: 202, y: 129, width: 168, height: 196), xRadius: 25, yRadius: 25)
    NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1).setFill()
    front.fill()
    NSColor(white: 0.96, alpha: 1).setStroke()
    front.lineWidth = 13
    front.stroke()
    return true
}
guard NSWorkspace.shared.setIcon(image, forFile: file.path, options: []) else {
    fatalError("Could not apply copy icon")
}
var values = URLResourceValues()
values.hasHiddenExtension = true
var target = file
try target.setResourceValues(values)
if CommandLine.arguments.count > 2, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
