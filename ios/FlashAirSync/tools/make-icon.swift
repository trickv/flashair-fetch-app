#!/usr/bin/env swift
//
// make-icon.swift — generates the App Store app icon.
//
//   xcrun swift ios/FlashAirSync/tools/make-icon.swift \
//     ios/FlashAirSync/FlashAirSync/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//
// Why a script instead of a checked-in design file: the icon is a placeholder
// (SD card + Wi-Fi fan + photo), and regenerating it deterministically beats
// round-tripping a binary through a design tool every time a colour changes.
// The PNG *is* committed — this script is the recipe, not a build step.
//
// Two hard App Store constraints are encoded below and must survive edits:
//   * exactly 1024x1024, sRGB, 8 bit;
//   * NO ALPHA CHANNEL. An icon with an alpha channel is rejected on upload
//     (ITMS-90717), which is why the bitmap context is created with
//     .noneSkipLast rather than .premultipliedLast.
//
// Verify after regenerating:
//   sips -g pixelWidth -g pixelHeight -g hasAlpha -g space AppIcon-1024.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

// Design is laid out in y-DOWN coordinates (y = 0 at the top edge), which is
// how every other UI framework thinks; the CTM is flipped once, below.
struct Palette {
    static let bgTop = CGColor(srgbRed: 0.161, green: 0.451, blue: 0.859, alpha: 1)
    static let bgBottom = CGColor(srgbRed: 0.051, green: 0.161, blue: 0.361, alpha: 1)
    static let card = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    static let amber = CGColor(srgbRed: 1.0, green: 0.761, blue: 0.290, alpha: 1)
    static let photo = CGColor(srgbRed: 0.102, green: 0.290, blue: 0.580, alpha: 1)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.png>\n".data(using: .utf8)!)
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: srgb,
    // noneSkipLast => the rendered CGImage carries no alpha, so ImageIO emits
    // an RGB (colour type 2) PNG. This is the ITMS-90717 guard.
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write("failed to create bitmap context\n".data(using: .utf8)!)
    exit(1)
}

ctx.interpolationQuality = .high
ctx.setShouldAntialias(true)

// Flip to y-down so the numbers below read like a layout, not like algebra.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// MARK: - Background

// Full-bleed: iOS applies its own squircle mask, so the artwork must not
// round its own corners or a dark halo appears at the mask edge.
let gradient = CGGradient(
    colorsSpace: srgb,
    colors: [Palette.bgTop, Palette.bgBottom] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: 0, y: size),
    options: []
)

// MARK: - Wi-Fi fan (drawn first, so the card's top edge clips its feet)

let fanCenter = CGPoint(x: 512, y: 352)
let fanStroke: CGFloat = 40
// Angles are measured in the flipped (y-down) user space: -90 deg is straight
// up, so a sweep of -170..-10 is a 160-degree fan centred on vertical.
let fanStart = -170.0 * Double.pi / 180.0
let fanEnd = -10.0 * Double.pi / 180.0

ctx.setStrokeColor(Palette.amber)
ctx.setLineWidth(fanStroke)
ctx.setLineCap(.round)
for radius in [CGFloat(92), 172, 252] {
    ctx.beginPath()
    ctx.addArc(
        center: fanCenter,
        radius: radius,
        startAngle: CGFloat(fanStart),
        endAngle: CGFloat(fanEnd),
        clockwise: false
    )
    ctx.strokePath()
}

// MARK: - SD card body

// Proportions track a real SD card (24 x 32 mm) with the write-protect notch
// corner chamfered — that chamfer is what makes the silhouette read as "SD"
// rather than "rounded rectangle" at 40x40.
let cardLeft: CGFloat = 276
let cardRight: CGFloat = 748
let cardTop: CGFloat = 312
let cardBottom: CGFloat = 936
let corner: CGFloat = 46
let chamfer: CGFloat = 132

let card = CGMutablePath()
card.move(to: CGPoint(x: cardLeft, y: cardTop + chamfer))
card.addLine(to: CGPoint(x: cardLeft + chamfer, y: cardTop))
card.addArc(
    tangent1End: CGPoint(x: cardRight, y: cardTop),
    tangent2End: CGPoint(x: cardRight, y: cardBottom),
    radius: corner
)
card.addArc(
    tangent1End: CGPoint(x: cardRight, y: cardBottom),
    tangent2End: CGPoint(x: cardLeft, y: cardBottom),
    radius: corner
)
card.addArc(
    tangent1End: CGPoint(x: cardLeft, y: cardBottom),
    tangent2End: CGPoint(x: cardLeft, y: cardTop),
    radius: corner
)
card.closeSubpath()

ctx.addPath(card)
ctx.setFillColor(Palette.card)
ctx.fillPath()

// MARK: - Photo plate inside the card

let plate = CGRect(x: 348, y: 452, width: 328, height: 300)
let platePath = CGPath(roundedRect: plate, cornerWidth: 26, cornerHeight: 26, transform: nil)
ctx.addPath(platePath)
ctx.setFillColor(Palette.photo)
ctx.fillPath()

ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()

ctx.setFillColor(Palette.card)
ctx.fillEllipse(in: CGRect(x: 566, y: 500, width: 66, height: 66))

let ridge = CGMutablePath()
ridge.move(to: CGPoint(x: 348, y: 752))
ridge.addLine(to: CGPoint(x: 448, y: 588))
ridge.addLine(to: CGPoint(x: 528, y: 700))
ridge.addLine(to: CGPoint(x: 588, y: 622))
ridge.addLine(to: CGPoint(x: 676, y: 752))
ridge.closeSubpath()
ctx.addPath(ridge)
ctx.fillPath()

ctx.restoreGState()

// MARK: - Contact pins

// Four chunky pins instead of a real card's nine: at 40x40 nine pads turn into
// a grey smear, four still read as "connector".
let pinWidth: CGFloat = 62
let pinGap: CGFloat = 28
let pinCount = 4
let pinsWidth = CGFloat(pinCount) * pinWidth + CGFloat(pinCount - 1) * pinGap
var pinX = 512 - pinsWidth / 2
ctx.setFillColor(Palette.amber)
for _ in 0..<pinCount {
    let pin = CGRect(x: pinX, y: 828, width: pinWidth, height: 68)
    ctx.addPath(CGPath(roundedRect: pin, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.fillPath()
    pinX += pinWidth + pinGap
}

// MARK: - Write PNG

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write("failed to render image\n".data(using: .utf8)!)
    exit(1)
}
guard let dest = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write("failed to create PNG destination\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("failed to write PNG\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outputURL.path) (\(image.width)x\(image.height), alphaInfo=\(image.alphaInfo.rawValue))")
