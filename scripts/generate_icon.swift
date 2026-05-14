#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size = 1024
let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let s = CGFloat(size)
ctx.saveGState()

// Flip coordinate system so (0,0) is top-left like SwiftUI
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

// --- Background gradient (seafoam green → seafoam blue) ---
let gradColors = [
    CGColor(red: 0.29, green: 0.87, blue: 0.78, alpha: 1),
    CGColor(red: 0.20, green: 0.67, blue: 0.90, alpha: 1)
]
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: gradColors as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: s, y: s),
    options: [])

// Helpers
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGRect {
    CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
}
func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
}

let cx = s / 2
let cy = s * 0.50
let bodyR = s * 0.35

// --- Left claw ---
fill(0.74, 0.14, 0.12)
ctx.fillEllipse(in: CGRect(x: cx - bodyR - s*0.13, y: cy - s*0.08, width: s*0.16, height: s*0.14))

// --- Right claw ---
ctx.fillEllipse(in: CGRect(x: cx + bodyR - s*0.03, y: cy - s*0.08, width: s*0.16, height: s*0.14))

// --- Left leg ---
let legW = s * 0.07, legH = s * 0.14
ctx.fill(CGRect(x: cx - s*0.13 - legW/2, y: cy + bodyR - s*0.02, width: legW, height: legH))

// --- Right leg ---
ctx.fill(CGRect(x: cx + s*0.07 - legW/2, y: cy + bodyR - s*0.02, width: legW, height: legH))

// --- Body ---
let bodyGrad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.96, green: 0.35, blue: 0.30, alpha: 1),
        CGColor(red: 0.75, green: 0.14, blue: 0.12, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.saveGState()
ctx.addEllipse(in: circle(cx, cy, bodyR))
ctx.clip()
ctx.drawRadialGradient(bodyGrad,
    startCenter: CGPoint(x: cx - bodyR * 0.2, y: cy - bodyR * 0.3),
    startRadius: 0,
    endCenter: CGPoint(x: cx, y: cy),
    endRadius: bodyR,
    options: [.drawsAfterEndLocation])
ctx.restoreGState()

// --- Left antenna ---
ctx.setStrokeColor(CGColor(red: 0.96, green: 0.50, blue: 0.45, alpha: 1))
ctx.setLineWidth(s * 0.035)
ctx.setLineCap(.round)
ctx.beginPath()
ctx.move(to: CGPoint(x: cx - s*0.10, y: cy - bodyR + s*0.02))
ctx.addQuadCurve(
    to: CGPoint(x: cx - s*0.22, y: cy - bodyR - s*0.18),
    control: CGPoint(x: cx - s*0.22, y: cy - bodyR - s*0.04))
ctx.strokePath()

// --- Right antenna ---
ctx.beginPath()
ctx.move(to: CGPoint(x: cx + s*0.10, y: cy - bodyR + s*0.02))
ctx.addQuadCurve(
    to: CGPoint(x: cx + s*0.22, y: cy - bodyR - s*0.18),
    control: CGPoint(x: cx + s*0.22, y: cy - bodyR - s*0.04))
ctx.strokePath()

// --- Left eye ---
fill(0.06, 0.06, 0.06)
ctx.fillEllipse(in: circle(cx - s*0.115, cy - s*0.04, s*0.07))
fill(0.20, 0.87, 0.80)
ctx.fillEllipse(in: circle(cx - s*0.095, cy - s*0.058, s*0.03))

// --- Right eye ---
fill(0.06, 0.06, 0.06)
ctx.fillEllipse(in: circle(cx + s*0.115, cy - s*0.04, s*0.07))
fill(0.20, 0.87, 0.80)
ctx.fillEllipse(in: circle(cx + s*0.135, cy - s*0.058, s*0.03))

ctx.restoreGState()

// --- Export PNG ---
let cgImage = ctx.makeImage()!
let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
let rep = NSBitmapImageRep(cgImage: cgImage)
let pngData = rep.representation(using: .png, properties: [:])!
let outPath = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png")
try! pngData.write(to: outPath)
print("Wrote \(outPath.path)")
