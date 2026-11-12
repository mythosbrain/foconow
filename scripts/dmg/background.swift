import AppKit

let width = 720
let height = 588
let size = CGSize(width: width, height: height)

func gray(_ white: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: size.height - top - h, width: w, height: h)
}

func rounded(_ bounds: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let shape = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    fill.setFill()
    shape.fill()
    if let stroke {
        stroke.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}

func line(_ points: [(CGFloat, CGFloat)], white: CGFloat, width: CGFloat = 1) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    for (index, point) in points.enumerated() {
        let location = CGPoint(x: point.0, y: size.height - point.1)
        if index == 0 { path.move(to: location) } else { path.line(to: location) }
    }
    gray(white).setStroke()
    path.stroke()
}

func label(_ value: String, x: CGFloat, top: CGFloat, pointSize: CGFloat,
           weight: NSFont.Weight, white: CGFloat, tracking: CGFloat = 0, centered: Bool = false) {
    let text = NSAttributedString(string: value, attributes: [
        .font: NSFont.systemFont(ofSize: pointSize, weight: weight),
        .foregroundColor: gray(white),
        .kern: tracking,
    ])
    let measured = text.size()
    text.draw(at: CGPoint(
        x: centered ? x - measured.width / 2 : x,
        y: size.height - top - measured.height
    ))
}

func draw(scale: Int, to url: URL) throws {
    let context = CGContext(
        data: nil, width: width * scale, height: height * scale,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }

    gray(0).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
    let glow = CGGradient(colorsSpace: context.colorSpace!, colors: [
        gray(0.10).cgColor, gray(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(
        glow, startCenter: CGPoint(x: 360, y: 280), startRadius: 0,
        endCenter: CGPoint(x: 360, y: 280), endRadius: 420, options: []
    )

    rounded(rect(34, 28, 38, 38), radius: 10, fill: gray(0.98))
    line([(43, 44), (43, 38), (49, 38)], white: 0.06, width: 1.6)
    line([(57, 38), (63, 38), (63, 44)], white: 0.06, width: 1.6)
    line([(63, 50), (63, 56), (57, 56)], white: 0.06, width: 1.6)
    line([(49, 56), (43, 56), (43, 50)], white: 0.06, width: 1.6)
    let dot = NSBezierPath(ovalIn: rect(50, 44, 6, 6))
    gray(0.06).setStroke()
    dot.lineWidth = 1.6
    dot.stroke()

    label("FocoNow", x: 85, top: 34, pointSize: 22, weight: .semibold, white: 0.98, tracking: -0.7)
    rounded(rect(552, 33, 134, 28), radius: 14, fill: gray(0.07), stroke: gray(0.21))
    label("MAC INSTALLER", x: 619, top: 41, pointSize: 10, weight: .semibold, white: 0.66, tracking: 1.45, centered: true)
    line([(34, 87), (686, 87)], white: 0.17)

    label("Drag FocoNow to Applications", x: 360, top: 112, pointSize: 19, weight: .medium, white: 0.89, tracking: -0.35, centered: true)
    for center in [CGFloat(206), 514] {
        rounded(rect(center - 75, 158, 150, 142), radius: 23, fill: gray(0.074), stroke: gray(0.20))
        rounded(rect(center - 62, 269, 124, 25), radius: 8, fill: gray(0.465))
    }

    rounded(rect(329, 190, 62, 62), radius: 31, fill: gray(0.10), stroke: gray(0.25))
    line([(344, 221), (375, 221)], white: 0.93, width: 2.3)
    line([(365, 211), (375, 221), (365, 231)], white: 0.93, width: 2.3)

    line([(34, 324), (686, 324)], white: 0.17)
    label("Trouble opening? Optional helper and first-launch guide", x: 360, top: 345, pointSize: 14, weight: .medium, white: 0.75, centered: true)
    label("Make your time count.", x: 360, top: 520, pointSize: 38, weight: .semibold, white: 0.98, tracking: -1.55, centered: true)
    label("A daily workspace for Mac.", x: 360, top: 570, pointSize: 14, weight: .regular, white: 0.65, centered: true)

    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    bitmap.size = size
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try draw(scale: 1, to: output.appendingPathComponent("background.png"))
try draw(scale: 2, to: output.appendingPathComponent("background@2x.png"))
