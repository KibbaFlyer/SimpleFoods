import AppKit

private let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
private let outputDirectory = sourceDirectory.appendingPathComponent("CreativeAssets", isDirectory: true)

private func image(named name: String) -> NSImage {
    let url = sourceDirectory.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: url) else {
        fatalError("Unable to load \(url.path)")
    }
    return image
}

private func drawAspectFill(_ image: NSImage, in bounds: NSRect) {
    let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let destination = NSRect(
        x: bounds.midX - size.width / 2,
        y: bounds.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
    image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
}

private func drawPhone(_ image: NSImage, in rect: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.9).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: radius, yRadius: radius)
    border.lineWidth = 14
    border.stroke()
}

private func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor = .white) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    text.draw(at: point, withAttributes: attributes)
}

private func render(width: Int, height: Int, drawing: (NSRect) -> Void) -> NSBitmapImageRep {
    let canvas = NSImage(size: NSSize(width: width, height: height))
    canvas.lockFocus()
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    drawing(NSRect(x: 0, y: 0, width: width, height: height))
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        fatalError("Unable to rasterize canvas")
    }
    return bitmap
}

private func writeJPEG(_ bitmap: NSBitmapImageRep, named name: String) throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.94]) else {
        fatalError("Unable to encode JPEG")
    }
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}

let focus = image(named: "background-focus.png")
let progress = image(named: "background-progress.png")
let today = image(named: "today.png")
let goals = image(named: "goals.png")
let recipes = image(named: "recipes.png")

let header = render(width: 3840, height: 1646) { bounds in
    drawAspectFill(focus, in: bounds)
    NSColor.black.withAlphaComponent(0.30).setFill()
    bounds.fill()

    drawText("Simple Foods", at: NSPoint(x: 300, y: 1025), size: 188, weight: .bold)
    drawText("Know your day. Reach your goals.", at: NSPoint(x: 315, y: 855), size: 76, weight: .semibold, color: NSColor.white.withAlphaComponent(0.92))
    drawText("Calories, macros, goals, and recipes — beautifully clear.", at: NSPoint(x: 315, y: 700), size: 52, weight: .medium, color: NSColor.white.withAlphaComponent(0.76))

    drawPhone(today, in: NSRect(x: 2260, y: -420, width: 720, height: 1565), radius: 92)
    drawPhone(goals, in: NSRect(x: 2980, y: -610, width: 650, height: 1413), radius: 82)
}

let search = render(width: 3840, height: 2560) { bounds in
    drawAspectFill(progress, in: bounds)
    NSColor.black.withAlphaComponent(0.34).setFill()
    bounds.fill()

    drawText("Your nutrition,", at: NSPoint(x: 260, y: 1985), size: 180, weight: .bold)
    drawText("beautifully clear.", at: NSPoint(x: 260, y: 1780), size: 180, weight: .bold)
    drawText("Track calories and macros. Set goals. Save recipes.", at: NSPoint(x: 275, y: 1515), size: 65, weight: .semibold, color: NSColor.white.withAlphaComponent(0.84))

    drawPhone(today, in: NSRect(x: 485, y: -385, width: 828, height: 1800), radius: 104)
    drawPhone(goals, in: NSRect(x: 1506, y: -385, width: 828, height: 1800), radius: 104)
    drawPhone(recipes, in: NSRect(x: 2527, y: -385, width: 828, height: 1800), radius: 104)
}

try writeJPEG(header, named: "product-page-header-3840x1646.jpg")
try writeJPEG(search, named: "search-results-3840x2560.jpg")
