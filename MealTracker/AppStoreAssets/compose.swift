import AppKit

struct Composition {
    let background: String
    let screenshot: String
    let output: String
    let title: String
    let subtitle: String
}

let canvasSize = NSSize(width: 1320, height: 2868)
let compositions = [
    Composition(background: "background-focus.png", screenshot: "today.png", output: "01-know-your-day.png", title: "Know your day", subtitle: "Calories and macros, beautifully clear."),
    Composition(background: "background-progress.png", screenshot: "goals.png", output: "02-see-your-progress.png", title: "See your progress", subtitle: "Goals that make every day count."),
    Composition(background: "background-plan.png", screenshot: "recipes.png", output: "03-plan-with-ease.png", title: "Plan with ease", subtitle: "Save recipes. Track every serving.")
]

func image(at path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else {
        fatalError("Could not load \(path)")
    }
    return image
}

for item in compositions {
    let result = NSImage(size: canvasSize)
    result.lockFocus()

    image(at: item.background).draw(in: NSRect(origin: .zero, size: canvasSize), from: .zero, operation: .copy, fraction: 1)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 94, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1),
        .paragraphStyle: paragraph
    ]
    item.title.draw(in: NSRect(x: 80, y: 2610, width: 1160, height: 120), withAttributes: titleAttributes)
    item.subtitle.draw(in: NSRect(x: 80, y: 2525, width: 1160, height: 70), withAttributes: subtitleAttributes)

    let phoneRect = NSRect(x: 180, y: 130, width: 960, height: 2087)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.75)
    shadow.shadowBlurRadius = 46
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: phoneRect.insetBy(dx: -8, dy: -8), xRadius: 76, yRadius: 76).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: phoneRect, xRadius: 68, yRadius: 68).addClip()
    image(at: item.screenshot).draw(in: phoneRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    let border = NSBezierPath(roundedRect: phoneRect, xRadius: 68, yRadius: 68)
    border.lineWidth = 3
    border.stroke()

    result.unlockFocus()
    guard let tiff = result.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(item.output)")
    }
    try data.write(to: URL(fileURLWithPath: item.output))
}
