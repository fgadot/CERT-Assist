#!/usr/bin/env swift

// Generates 1024x1024 app icon variants styled after the official CERT logo:
// dark background, "CERT" in CERT-brand green, "ASSIST" in white.

import AppKit
import CoreGraphics

// CERT brand green: #39B54A
let certGreen = CGColor(red: 0.224, green: 0.710, blue: 0.290, alpha: 1.0)
let white     = CGColor(red: 1, green: 1, blue: 1, alpha: 1.0)
let black     = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)

// ─── Text helpers ─────────────────────────────────────────────────────────────

struct DrawnLine {
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    var height: CGFloat { ascent + descent }
}

func makeLine(_ text: String, font: CTFont, color: CGColor) -> DrawnLine {
    let nsColor = NSColor(cgColor: color)!
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: nsColor
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attrs))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    return DrawnLine(line: line, width: CGFloat(width), ascent: ascent, descent: descent)
}

func drawLine(_ dl: DrawnLine, ctx: CGContext, cx: CGFloat, baselineY: CGFloat) {
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: cx - dl.width / 2, y: baselineY)
    CTLineDraw(dl.line, ctx)
}

// ─── Icon renderer ────────────────────────────────────────────────────────────

func makeIcon(size: Int, dark: Bool, tinted: Bool) -> Data? {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // ── Background ────────────────────────────────────────────────────────────
    if tinted {
        ctx.setFillColor(black)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    } else {
        let top = dark
            ? CGColor(red: 0.04, green: 0.10, blue: 0.22, alpha: 1)
            : CGColor(red: 0.06, green: 0.10, blue: 0.20, alpha: 1)
        let bottom = dark
            ? CGColor(red: 0.00, green: 0.02, blue: 0.06, alpha: 1)
            : CGColor(red: 0.00, green: 0.03, blue: 0.09, alpha: 1)
        let gradient = CGGradient(colorsSpace: cs,
                                  colors: [top, bottom] as CFArray,
                                  locations: [0.0, 1.0])!
        ctx.drawLinearGradient(gradient,
            start: CGPoint(x: s/2, y: s),
            end: CGPoint(x: s/2, y: 0),
            options: [])
    }

    let cx = s / 2
    let accentColor = tinted ? white : certGreen
    let textColor   = white

    // ── CERT text ─────────────────────────────────────────────────────────────
    let certFont  = CTFontCreateWithName("Impact" as CFString, s * 0.310, nil)
    let certLine  = makeLine("CERT", font: certFont, color: accentColor)

    // ── ASSIST text ───────────────────────────────────────────────────────────
    let assistFont = CTFontCreateWithName("Helvetica-Bold" as CFString, s * 0.110, nil)
    let assistLine = makeLine("ASSIST", font: assistFont, color: textColor)

    // ── Divider ───────────────────────────────────────────────────────────────
    let divW: CGFloat = s * 0.68
    let divH: CGFloat = max(3, s * 0.005)

    // Layout: stack centered vertically
    let gap: CGFloat    = s * 0.025
    let totalH = certLine.height + divH + gap * 2 + assistLine.height
    let blockTop = (s + totalH) / 2   // top of "CERT" ascent in CoreGraphics coords (y up)

    let certBaseline   = blockTop - certLine.ascent
    let divY           = certBaseline - certLine.descent - gap - divH
    let assistBaseline = divY - gap - assistLine.ascent

    // Draw CERT
    drawLine(certLine, ctx: ctx, cx: cx, baselineY: certBaseline)

    // Draw divider
    ctx.setFillColor(accentColor)
    ctx.fill(CGRect(x: cx - divW/2, y: divY, width: divW, height: divH))

    // Draw ASSIST
    drawLine(assistLine, ctx: ctx, cx: cx, baselineY: assistBaseline)

    // ── Green border frame ────────────────────────────────────────────────────
    let inset: CGFloat = s * 0.035
    let lineW: CGFloat = max(6, s * 0.010)
    let corner: CGFloat = s * 0.12
    ctx.setStrokeColor(accentColor)
    ctx.setLineWidth(lineW)
    let rect = CGRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.strokePath()

    // ── Export ────────────────────────────────────────────────────────────────
    guard let cgImage = ctx.makeImage() else { return nil }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    guard let tiff = nsImage.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

// ─── Generate all variants ────────────────────────────────────────────────────

let appiconset = "/Users/frank/Library/Mobile Documents/com~apple~CloudDocs/DEV/XCODE/CERT Command/CERT Command/Assets.xcassets/AppIcon.appiconset"

let variants: [(name: String, dark: Bool, tinted: Bool)] = [
    ("AppIcon.png",        false, false),
    ("AppIcon-Dark.png",   true,  false),
    ("AppIcon-Tinted.png", false, true),
]

for v in variants {
    if let data = makeIcon(size: 1024, dark: v.dark, tinted: v.tinted) {
        let url = URL(fileURLWithPath: "\(appiconset)/\(v.name)")
        try! data.write(to: url)
        print("✓ \(v.name)")
    } else {
        print("✗ Failed: \(v.name)")
    }
}
