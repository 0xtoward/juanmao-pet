import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: make-app-icon.swift input-spritesheet.png output.icns\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let iconsetURL = outputURL.deletingPathExtension().appendingPathExtension("iconset")

let cellWidth = 192
let cellHeight = 208
let canvasSize = 1024
let iconNames: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

guard let sheet = NSImage(contentsOf: inputURL),
      let sheetImage = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let frameImage = sheetImage.cropping(to: CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight)) else {
    fail("Could not read or crop spritesheet: \(inputURL.path)")
}

let source = NSImage(cgImage: frameImage, size: NSSize(width: cellWidth, height: cellHeight))
let base = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
base.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

let scale = min(CGFloat(canvasSize) * 0.82 / CGFloat(cellWidth), CGFloat(canvasSize) * 0.78 / CGFloat(cellHeight))
let width = CGFloat(cellWidth) * scale
let height = CGFloat(cellHeight) * scale
source.draw(in: NSRect(
    x: (CGFloat(canvasSize) - width) / 2,
    y: (CGFloat(canvasSize) - height) / 2 + CGFloat(canvasSize) * 0.02,
    width: width,
    height: height
))
base.unlockFocus()

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (name, size) in iconNames {
    let icon = NSImage(size: NSSize(width: size, height: size))
    icon.lockFocus()
    base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    icon.unlockFocus()

    guard let tiff = icon.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fail("Could not render \(name).")
    }
    try png.write(to: iconsetURL.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fail("iconutil failed.")
}

try? FileManager.default.removeItem(at: iconsetURL)
