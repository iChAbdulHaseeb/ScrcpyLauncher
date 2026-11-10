import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1), NSColor(red: 0.05, green: 0.45, blue: 0.55, alpha: 1)])!.draw(in: bg, angle: -60)
// phone
let phone = NSRect(x: 352, y: 210, width: 320, height: 604)
NSColor(white: 1, alpha: 0.97).setFill()
NSBezierPath(roundedRect: phone, xRadius: 56, yRadius: 56).fill()
let screen = phone.insetBy(dx: 22, dy: 26)
NSColor(red: 0.07, green: 0.12, blue: 0.16, alpha: 1).setFill()
NSBezierPath(roundedRect: screen, xRadius: 36, yRadius: 36).fill()
// play triangle
let t = NSBezierPath()
let c = NSPoint(x: screen.midX + 12, y: screen.midY)
t.move(to: NSPoint(x: c.x - 70, y: c.y + 90)); t.line(to: NSPoint(x: c.x + 85, y: c.y)); t.line(to: NSPoint(x: c.x - 70, y: c.y - 90)); t.close()
NSColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1).setFill(); t.fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
