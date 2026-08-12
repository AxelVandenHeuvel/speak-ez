// Renders the speakEZ app icon ("EZ" on a violet gradient squircle) and
// packs it into Resources/AppIcon.icns.
// Run: swift Scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
// Standard macOS icon grid: artwork fills ~82% of the canvas.
let inset: CGFloat = 92
let cornerRadius: CGFloat = 186

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let rect = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

// Soft drop shadow behind the tile, like system icons have.
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let top = NSColor(calibratedRed: 0.58, green: 0.34, blue: 0.98, alpha: 1)
let bottom = NSColor(calibratedRed: 0.24, green: 0.15, blue: 0.72, alpha: 1)
NSGradient(starting: bottom, ending: top)!.draw(in: squircle, angle: 90)

// A faint highlight that fades in toward the top gives the tile some depth
// without any visible seam.
let highlight = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
NSGraphicsContext.current?.saveGraphicsState()
highlight.setClip()
NSGradient(
    starting: NSColor.white.withAlphaComponent(0.0),
    ending: NSColor.white.withAlphaComponent(0.18)
)!.draw(in: rect, angle: 90)
NSGraphicsContext.current?.restoreGraphicsState()

// "EZ" in SF Rounded, heavy, white, optically centered.
let baseFont = NSFont.systemFont(ofSize: 420, weight: .heavy)
let font: NSFont =
    baseFont.fontDescriptor.withDesign(.rounded)
    .flatMap { NSFont(descriptor: $0, size: 420) } ?? baseFont

let textShadow = NSShadow()
textShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
textShadow.shadowOffset = NSSize(width: 0, height: -8)
textShadow.shadowBlurRadius = 12

let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .shadow: textShadow,
    .kern: -8,
]
let text = NSAttributedString(string: "EZ", attributes: attributes)
let textSize = text.size()
text.draw(at: NSPoint(
    x: (canvas - textSize.width) / 2,
    y: (canvas - textSize.height) / 2 + 8))

image.unlockFocus()

// Write the master PNG, downscale into an iconset, pack as icns.
guard let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("could not render icon")
}

let fileManager = FileManager.default
let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fileManager.removeItem(at: iconsetURL)
try! fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
let masterURL = iconsetURL.appendingPathComponent("icon_512x512@2x.png")
try! png.write(to: masterURL)

func run(_ command: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    try! process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "\(command) failed")
}

for size in [16, 32, 64, 128, 256, 512] {
    let base = iconsetURL.appendingPathComponent("icon_\(size)x\(size).png").path
    run("/usr/bin/sips", ["-z", "\(size)", "\(size)", masterURL.path, "--out", base])
    if size < 512 {
        let retina = iconsetURL.appendingPathComponent("icon_\(size)x\(size)@2x.png").path
        run("/usr/bin/sips", ["-z", "\(size * 2)", "\(size * 2)", masterURL.path, "--out", retina])
    }
}

try? fileManager.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
run("/usr/bin/iconutil", ["-c", "icns", iconsetURL.path, "-o", "Resources/AppIcon.icns"])
try? fileManager.removeItem(at: iconsetURL)
print("wrote Resources/AppIcon.icns")
