#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size = 1024
let s = CGFloat(size)

let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

ctx.saveGState()
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

// Seafoam green → seafoam blue gradient background
let gradColors = [
    CGColor(red: 0.29, green: 0.87, blue: 0.78, alpha: 1),
    CGColor(red: 0.20, green: 0.67, blue: 0.90, alpha: 1)
] as CFArray
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: gradColors,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: s, y: s),
    options: [])

ctx.restoreGState()

// Draw 🦀 emoji centered
let nsImage = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // Draw gradient background
    let gradient = NSGradient(
        colors: [
            NSColor(red: 0.29, green: 0.87, blue: 0.78, alpha: 1),
            NSColor(red: 0.20, green: 0.67, blue: 0.90, alpha: 1)
        ],
        atLocations: [0, 1],
        colorSpace: .sRGB
    )!
    gradient.draw(in: rect, angle: -45)

    // Draw crab emoji
    let emoji = "🦀"
    let fontSize = CGFloat(size) * 0.62
    let font = NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let strSize = str.size()
    let origin = CGPoint(
        x: (rect.width - strSize.width) / 2,
        y: (rect.height - strSize.height) / 2
    )
    str.draw(at: origin)
    return true
}

let rep = nsImage.representations.first as? NSBitmapImageRep
    ?? NSBitmapImageRep(cgImage: nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
let pngData = rep.representation(using: .png, properties: [:])!
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
try! pngData.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
