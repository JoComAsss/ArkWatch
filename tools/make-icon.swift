import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// 圆角底板
let board = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860),
                         xRadius: 190, yRadius: 190)
let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.12, alpha: 1)
])!
bg.draw(in: board, angle: -70)

// 闪电
let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 596, y: 806))
bolt.line(to: NSPoint(x: 372, y: 496))
bolt.line(to: NSPoint(x: 528, y: 496))
bolt.line(to: NSPoint(x: 428, y: 214))
bolt.line(to: NSPoint(x: 668, y: 548))
bolt.line(to: NSPoint(x: 516, y: 548))
bolt.close()
let boltGradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.31, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.05, alpha: 1)
])!
boltGradient.draw(in: bolt, angle: -80)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try? png.write(to: URL(fileURLWithPath: out))
print("icon -> \(out)")
