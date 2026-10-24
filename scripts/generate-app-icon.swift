#!/usr/bin/env swift
// Draws the Sulsul app icon and writes every file that carries it:
//   VoiceInk/Assets.xcassets/AppIcon.appiconset/{16,32,64,128,256,512,1024}-mac.png
//   VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon.png   (black template, waveform cut out)
//   release/dmg/volume-icon.icns                                    (needs iconutil)
//
//   swift scripts/generate-app-icon.swift                  # rewrite the files in this repository
//   swift scripts/generate-app-icon.swift --output-dir DIR # write the same tree under DIR instead
//
// The art is shapes only (no font), so there is nothing to license beyond this repository's GPL-3.0.
import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
if let i = CommandLine.arguments.firstIndex(of: "--output-dir"), i + 1 < CommandLine.arguments.count {
    root = URL(fileURLWithPath: CommandLine.arguments[i + 1])
} else if FileManager.default.fileExists(atPath: scriptURL.path) {
    root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
}

let canvas: CGFloat = 1024
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)  // macOS icon body inside the 1024 canvas
let radius: CGFloat = 185

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func bitmap(_ size: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func render(size: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = bitmap(size)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    ctx.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to relativePath: String) {
    let url = root.appendingPathComponent(relativePath)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// Colors
let navyTop: UInt32 = 0x1B2540
let navyBottom: UInt32 = 0x070B16
let coral: UInt32 = 0xFFA45C
let pink: UInt32 = 0xFF3F7A

// Shapes
let barHeights: [CGFloat] = [110, 230, 330, 210, 130]

func bubble() -> (NSBezierPath, NSBezierPath) {
    let body = NSBezierPath(roundedRect: CGRect(x: 190, y: 330, width: 644, height: 420), xRadius: 150, yRadius: 150)
    let tail = NSBezierPath()
    tail.move(to: CGPoint(x: 290, y: 360))
    tail.line(to: CGPoint(x: 240, y: 210))
    tail.line(to: CGPoint(x: 430, y: 340))
    tail.close()
    return (body, tail)
}

/// Below 128 px the drop shadow would bleed to the canvas edge, so small sizes go without it.
func drawIcon(withShadow: Bool) {
    let squircle = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
    if withShadow {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.shadowBlurRadius = 26
        shadow.set()
        NSColor.black.setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(starting: color(navyTop), ending: color(navyBottom))!.draw(in: bodyRect, angle: -80)

    let (body, tail) = bubble()
    NSColor.white.setFill()
    body.fill()
    tail.fill()

    let width: CGFloat = 56, gap: CGFloat = 38
    let total = CGFloat(barHeights.count) * width + CGFloat(barHeights.count - 1) * gap
    let accent = NSGradient(starting: color(coral), ending: color(pink))!
    for (i, h) in barHeights.enumerated() {
        let x = 512 - total / 2 + CGFloat(i) * (width + gap)
        let bar = NSBezierPath(roundedRect: CGRect(x: x, y: 540 - h / 2, width: width, height: h), xRadius: width / 2, yRadius: width / 2)
        NSGraphicsContext.saveGraphicsState()
        bar.addClip()
        accent.draw(in: bar.bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func icon(size: Int) -> NSBitmapImageRep { render(size: size) { drawIcon(withShadow: size > 64) } }

// App icon set: the asset catalog maps these 7 files onto its 11 slots.
for px in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(icon(size: px), to: "VoiceInk/Assets.xcassets/AppIcon.appiconset/\(px)-mac.png")
}

// Menu bar template: black silhouette, the waveform is transparent, 750x750 on a 750 canvas.
let menuBar = bitmap(750)
let menuContext = NSGraphicsContext(bitmapImageRep: menuBar)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = menuContext
NSColor.black.setFill()
NSBezierPath(roundedRect: CGRect(x: 55, y: 210, width: 640, height: 420), xRadius: 130, yRadius: 130).fill()
let menuTail = NSBezierPath()
menuTail.move(to: CGPoint(x: 150, y: 250))
menuTail.line(to: CGPoint(x: 100, y: 100))
menuTail.line(to: CGPoint(x: 300, y: 235))
menuTail.close()
menuTail.fill()
menuContext.compositingOperation = .clear
for (i, h) in barHeights.enumerated() {
    let x = 375 - CGFloat(5 * 52 + 4 * 34) / 2 + CGFloat(i) * 86
    NSBezierPath(roundedRect: CGRect(x: x, y: 420 - h / 2, width: 52, height: h), xRadius: 26, yRadius: 26).fill()
}
NSGraphicsContext.restoreGraphicsState()
writePNG(menuBar, to: "VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon.png")

// DMG volume icon: build an .iconset in a temporary folder and let iconutil pack it.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("sulsul-volume-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let slots: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in slots {
    try! icon(size: px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("\(name).png"))
}
let icnsURL = root.appendingPathComponent("release/dmg/volume-icon.icns")
try! FileManager.default.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let pack = Process()
pack.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
pack.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try! pack.run()
pack.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard pack.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("icon files written under \(root.path)")
