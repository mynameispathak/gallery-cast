// Renders the Gallery Cast app icon and logo with CoreGraphics.
// Usage: swift scripts/make-icon.swift
// Writes:  assets/AppIcon.iconset/*.png (all standard macOS sizes)
//          assets/logo.png (512pt, for docs)
//
// Design (matches DESIGN.md): amber squircle, stacked photo cards in white,
// sun + mountains motif echoing the welcome screen tile.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDir = URL(fileURLWithPath: "assets")
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// MARK: - Palette

extension CGColor {
    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
    static let amberLight = rgb(0xFF, 0xA8, 0x29)
    static let amber = rgb(0xFF, 0x95, 0x00)
    static let amberDeep = rgb(0xE0, 0x7C, 0x00)
}

// MARK: - Drawing

func makeContext(_ size: CGFloat) -> CGContext {
    guard let ctx = CGContext(
        data: nil,
        width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }
    ctx.setAllowsAntialiasing(true)
    return ctx
}

/// One rounded-rect "photo card".
func drawCard(
    _ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat,
    radius: CGFloat, rotation: CGFloat, color: CGColor
) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)
    let rect = CGRect(
        x: -width / 2, y: -height / 2, width: width, height: height
    )
    let path = CGPath(
        roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil
    )
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawIcon(_ size: CGFloat) -> CGImage {
    let ctx = makeContext(size)
    let s = size

    // Background: amber squircle, gently shaded top-to-bottom.
    let margin = s * 0.100
    let radius = s * 0.185
    let body = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let bodyPath = CGPath(
        roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let colors = [CGColor.amberLight, CGColor.amber] as CFArray
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.minY),
            options: []
        )
    }
    ctx.restoreGState()

    let center = CGPoint(x: s / 2, y: s / 2)

    // Back card: tilted, translucent, peeking behind.
    drawCard(
        ctx,
        center: CGPoint(x: center.x + s * 0.055, y: center.y + s * 0.050),
        width: s * 0.500, height: s * 0.390,
        radius: s * 0.045,
        rotation: .pi / 14,
        color: .init(red: 1, green: 1, blue: 1, alpha: 0.34)
    )

    // Front card: white, straight.
    let cardWidth = s * 0.520
    let cardHeight = s * 0.400
    drawCard(
        ctx,
        center: CGPoint(x: center.x - s * 0.012, y: center.y - s * 0.012),
        width: cardWidth, height: cardHeight,
        radius: s * 0.050,
        rotation: 0,
        color: .init(red: 1, green: 1, blue: 1, alpha: 1)
    )

    // Scene inside the front card: sun + two mountains, amber on white.
    let cardCX = center.x - s * 0.012
    let cardCY = center.y - s * 0.012

    // Sun, upper right, clear of the peaks.
    let sunRect = CGRect(
        x: cardCX + cardWidth * 0.14, y: cardCY + cardHeight * 0.12,
        width: s * 0.085, height: s * 0.085
    )
    ctx.setFillColor(.amber)
    ctx.fillEllipse(in: sunRect)

    // Mountains (drawn as triangles from the card's lower edge):
    // tall back peak first, then its snow cap, then the shorter front
    // peak drawn last so it cleanly overlaps the back one — no gaps.
    func mountain(_ apex: CGPoint, _ left: CGPoint, _ right: CGPoint, _ color: CGColor) {
        ctx.beginPath()
        ctx.move(to: apex)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    let baseY = cardCY - cardHeight / 2 + s * 0.020
    let leftEdge = cardCX - cardWidth / 2 + s * 0.045
    let rightEdge = cardCX + cardWidth / 2 - s * 0.045

    // Tall back peak.
    let backApex = CGPoint(x: cardCX - s * 0.075, y: cardCY + cardHeight * 0.17)
    mountain(
        backApex,
        CGPoint(x: leftEdge, y: baseY),
        CGPoint(x: cardCX + s * 0.060, y: baseY),
        .amberDeep
    )

    // Snow cap on the tall peak, kept inside its slopes.
    ctx.beginPath()
    ctx.move(to: backApex)
    ctx.addLine(to: CGPoint(x: backApex.x + s * 0.030, y: backApex.y - s * 0.058))
    ctx.addLine(to: CGPoint(x: backApex.x + s * 0.016, y: backApex.y - s * 0.048))
    ctx.addLine(to: CGPoint(x: backApex.x + s * 0.004, y: backApex.y - s * 0.062))
    ctx.addLine(to: CGPoint(x: backApex.x - s * 0.030, y: backApex.y - s * 0.058))
    ctx.closePath()
    ctx.setFillColor(.white)
    ctx.fillPath()

    // Shorter front peak, overlapping the back one's flank.
    mountain(
        CGPoint(x: cardCX + s * 0.095, y: cardCY + cardHeight * 0.06),
        CGPoint(x: cardCX - s * 0.010, y: baseY),
        CGPoint(x: rightEdge, y: baseY),
        .amber
    )

    return ctx.makeImage()!
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("no destination: \(url)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed: \(url)") }
}

let iconSizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for entry in iconSizes {
    let image = drawIcon(entry.size)
    writePNG(image, to: iconsetDir.appendingPathComponent(entry.name))
}

// Marketing / docs logo.
writePNG(drawIcon(1024), to: iconsetDir.appendingPathComponent("icon_1024x1024.png") )
writePNG(drawIcon(512), to: outputDir.appendingPathComponent("logo.png"))

print("Icon set written to \(iconsetDir.path)")
print("Logo written to assets/logo.png")
