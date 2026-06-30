// Render the "Finn" wordmark brand assets for tvOS:
//   - App Icon (home screen)       400x240   layered .imagestack (back + front)
//   - App Icon (App Store)         1280x768  layered .imagestack (back + front)
//   - Top Shelf Image              1920x720  imageset
//   - Top Shelf Image Wide         2320x720  imageset
//
// Run:  swift tools/GenerateIcon.swift
//
// Design: Avenir Next Heavy "Finn" wordmark with a cyan -> white vertical
// gradient, layered over a deep navy -> teal ocean background (a nod to
// Jellyfin's maritime theme). Each icon is a real two-layer imagestack so
// the Apple TV home-screen parallax actually does something: the wordmark
// floats above the gradient.

import AppKit
import CoreText
import Foundation

// MARK: - Color palette

struct RGB { let r, g, b: CGFloat }

let bgTop       = RGB(r: 0.039, g: 0.098, b: 0.161)   // #0A1929 — deep navy
let bgBottom    = RGB(r: 0.075, g: 0.282, b: 0.431)   // #13486E — ocean teal
let textTop     = RGB(r: 0.541, g: 0.914, b: 1.000)   // #8AE9FF — bright cyan
let textBottom  = RGB(r: 1.000, g: 1.000, b: 1.000)   // #FFFFFF — white

// MARK: - Helpers

func cgColor(_ c: RGB) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
}

func makeContext(width: Int, height: Int) -> (CGContext, NSBitmapImageRep) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
    return (ctx, rep)
}

func linearGradient(top: RGB, bottom: RGB) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [cgColor(top), cgColor(bottom)] as CFArray,
        locations: [0, 1]
    )!
}

func fillVerticalGradient(ctx: CGContext, width: CGFloat, height: CGFloat, gradient: CGGradient) {
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()
}

func radialHighlight(ctx: CGContext, center: CGPoint, radius: CGFloat, color: RGB) {
    let g = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 0.28),
            CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// Draw `text` with a vertical gradient fill, centered at `center`,
/// scaled so its width does not exceed `maxWidth`. Leaves everything but
/// the glyphs transparent — used for the floating front layer.
func drawGradientWordmark(
    ctx: CGContext,
    text: String,
    fontRef: CTFont,
    center: CGPoint,
    maxWidth: CGFloat,
    textGradient: CGGradient,
    letterSpacing: CGFloat
) {
    func makeLine(sizePt: CGFloat) -> CTLine {
        let font = CTFontCreateCopyWithAttributes(fontRef, sizePt, nil, nil)
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if letterSpacing != 0 {
            attrs[.kern] = letterSpacing
        }
        let attr = NSAttributedString(string: text, attributes: attrs)
        return CTLineCreateWithAttributedString(attr)
    }

    func lineWidth(_ line: CTLine) -> CGFloat {
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        return CGFloat(CTLineGetTypographicBounds(line, &a, &d, &l))
    }

    func lineMetrics(_ line: CTLine) -> (ascent: CGFloat, descent: CGFloat) {
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &a, &d, &l)
        return (a, d)
    }

    // Bisection-fit font size to maxWidth.
    var lo: CGFloat = 8
    var hi: CGFloat = 2000
    for _ in 0..<50 {
        let mid = (lo + hi) / 2
        if lineWidth(makeLine(sizePt: mid)) <= maxWidth { lo = mid } else { hi = mid }
    }
    let line = makeLine(sizePt: lo)
    let w = lineWidth(line)
    let (ascent, descent) = lineMetrics(line)

    let textOriginX = center.x - w / 2
    let baselineY = center.y - (ascent - descent) / 2

    ctx.saveGState()
    ctx.textPosition = CGPoint(x: textOriginX, y: baselineY)
    ctx.setTextDrawingMode(.clip)
    CTLineDraw(line, ctx)
    ctx.drawLinearGradient(
        textGradient,
        start: CGPoint(x: 0, y: baselineY + ascent),
        end: CGPoint(x: 0, y: baselineY - descent),
        options: []
    )
    ctx.restoreGState()
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG at \(path)")
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

// MARK: - Layer renderers for icons

/// Back layer: solid gradient ocean background + soft cyan glow, no text.
func renderBackLayer(width: Int, height: Int, center: CGPoint, outputPath: String) {
    let (ctx, rep) = makeContext(width: width, height: height)
    fillVerticalGradient(ctx: ctx, width: CGFloat(width), height: CGFloat(height), gradient: linearGradient(top: bgTop, bottom: bgBottom))
    radialHighlight(ctx: ctx, center: center, radius: CGFloat(min(width, height)) * 0.75, color: textTop)
    savePNG(rep, to: outputPath)
    print("wrote back \(width)x\(height) -> \(outputPath)")
}

/// Front layer: transparent canvas with the gradient wordmark floating above.
func renderFrontLayer(width: Int, height: Int, center: CGPoint, maxTextWidthRatio: CGFloat, letterSpacing: CGFloat, outputPath: String) {
    let (ctx, rep) = makeContext(width: width, height: height)
    let font = CTFontCreateWithName("Avenir Next Heavy" as CFString, 0, nil)
    drawGradientWordmark(
        ctx: ctx,
        text: "Finn",
        fontRef: font,
        center: center,
        maxWidth: CGFloat(width) * maxTextWidthRatio,
        textGradient: linearGradient(top: textTop, bottom: textBottom),
        letterSpacing: letterSpacing
    )
    savePNG(rep, to: outputPath)
    print("wrote front \(width)x\(height) -> \(outputPath)")
}

/// Top-shelf imageset: single full-canvas PNG (background + wordmark together).
func renderFullCanvas(width: Int, height: Int, textCenter: CGPoint, textMaxWidthRatio: CGFloat, letterSpacing: CGFloat, outputPath: String) {
    let (ctx, rep) = makeContext(width: width, height: height)
    fillVerticalGradient(ctx: ctx, width: CGFloat(width), height: CGFloat(height), gradient: linearGradient(top: bgTop, bottom: bgBottom))
    radialHighlight(ctx: ctx, center: textCenter, radius: CGFloat(min(width, height)) * 0.75, color: textTop)
    let font = CTFontCreateWithName("Avenir Next Heavy" as CFString, 0, nil)
    drawGradientWordmark(
        ctx: ctx,
        text: "Finn",
        fontRef: font,
        center: textCenter,
        maxWidth: CGFloat(width) * textMaxWidthRatio,
        textGradient: linearGradient(top: textTop, bottom: textBottom),
        letterSpacing: letterSpacing
    )
    savePNG(rep, to: outputPath)
    print("wrote \(width)x\(height) -> \(outputPath)")
}

// MARK: - Render the brand assets

let base = "Finn/Assets.xcassets/App Icon & Top Shelf Image.brandassets"

// Home-screen icon (400x240): wordmark centered, comfortable margins.
renderBackLayer(width: 400, height: 240, center: CGPoint(x: 200, y: 130),
                outputPath: "\(base)/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back.png")
renderFrontLayer(width: 400, height: 240, center: CGPoint(x: 200, y: 130), maxTextWidthRatio: 0.78, letterSpacing: -2,
                 outputPath: "\(base)/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front.png")

// App Store icon (1280x768): same layout, scaled up.
renderBackLayer(width: 1280, height: 768, center: CGPoint(x: 640, y: 416),
                outputPath: "\(base)/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/back.png")
renderFrontLayer(width: 1280, height: 768, center: CGPoint(x: 640, y: 416), maxTextWidthRatio: 0.78, letterSpacing: -6,
                 outputPath: "\(base)/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/front.png")

// Top Shelf Image (1920x720): left-anchored wordmark for the standard shelf.
renderFullCanvas(width: 1920, height: 720, textCenter: CGPoint(x: 360, y: 360), textMaxWidthRatio: 0.30, letterSpacing: -3,
                 outputPath: "\(base)/Top Shelf Image.imageset/finn-top-shelf.png")

// Top Shelf Image Wide (2320x720): wider shelf, same anchor.
renderFullCanvas(width: 2320, height: 720, textCenter: CGPoint(x: 380, y: 360), textMaxWidthRatio: 0.25, letterSpacing: -3,
                 outputPath: "\(base)/Top Shelf Image Wide.imageset/finn-top-shelf-wide.png")

print("done")