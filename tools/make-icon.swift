import AppKit

// 白底 + 极简红色火山（未喷发）
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// 白色圆角底板
let boardRect = NSRect(x: 82, y: 82, width: 860, height: 860)
let board = NSBezierPath(roundedRect: boardRect, xRadius: 190, yRadius: 190)
NSColor.white.setFill()
board.fill()
// 极淡描边，避免在白底环境里边界消失
NSColor(calibratedWhite: 0.93, alpha: 1).setStroke()
board.lineWidth = 3
board.stroke()

// 火山主体：梯形，顶部为浅浅的火山口凹陷
let red = NSColor(calibratedRed: 0.86, green: 0.20, blue: 0.16, alpha: 1)
let darkRed = NSColor(calibratedRed: 0.66, green: 0.11, blue: 0.09, alpha: 1)

let volcano = NSBezierPath()
volcano.move(to: NSPoint(x: 246, y: 250))
volcano.line(to: NSPoint(x: 418, y: 700))
// 火山口：中间微微下凹
volcano.curve(to: NSPoint(x: 606, y: 700),
              controlPoint1: NSPoint(x: 478, y: 662),
              controlPoint2: NSPoint(x: 546, y: 662))
volcano.line(to: NSPoint(x: 778, y: 250))
volcano.close()
red.setFill()
volcano.fill()

// 火山口沿：一条更深的短线，强调“未喷发”的静止感
let rim = NSBezierPath()
rim.move(to: NSPoint(x: 424, y: 697))
rim.curve(to: NSPoint(x: 600, y: 697),
          controlPoint1: NSPoint(x: 480, y: 661),
          controlPoint2: NSPoint(x: 544, y: 661))
rim.lineWidth = 14
rim.lineCapStyle = .round
darkRed.setStroke()
rim.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try? png.write(to: URL(fileURLWithPath: out))
print("icon -> \(out)")
