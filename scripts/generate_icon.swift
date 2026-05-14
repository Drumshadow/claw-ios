#!/usr/bin/env swift
import AppKit

let size = 1024
let mascotPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/openclaw_mascot.png"
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

guard let mascotNS = NSImage(contentsOfFile: mascotPath) else {
    print("Could not load mascot from \(mascotPath)")
    exit(1)
}

let icon = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // Seafoam green → seafoam blue gradient
    let gradient = NSGradient(
        colors: [
            NSColor(red: 0.29, green: 0.87, blue: 0.78, alpha: 1),
            NSColor(red: 0.20, green: 0.67, blue: 0.90, alpha: 1)
        ],
        atLocations: [0, 1],
        colorSpace: .sRGB
    )!
    gradient.draw(in: rect, angle: -45)

    // Composite mascot centered, scaled to 62% of icon
    let mascotSize = CGFloat(size) * 0.62
    let offset = CGPoint(
        x: (rect.width - mascotSize) / 2,
        y: (rect.height - mascotSize) / 2
    )
    mascotNS.draw(
        in: CGRect(x: offset.x, y: offset.y, width: mascotSize, height: mascotSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    return true
}

let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let rep = NSBitmapImageRep(cgImage: cgImage)
let pngData = rep.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
