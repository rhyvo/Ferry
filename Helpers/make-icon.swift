
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let size: CGFloat = 1024

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func render(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func verticalGradient(_ ctx: CGContext, _ colors: [CGColor], from top: CGFloat, to bottom: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func water(surface: CGFloat, amplitude: CGFloat, period: CGFloat, phase: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: size))
    var x: CGFloat = 0
    while x <= size {
        p.addLine(to: CGPoint(x: x, y: surface + amplitude * sin(2 * .pi * x / period + phase)))
        x += 4
    }
    p.addLine(to: CGPoint(x: size, y: size))
    p.closeSubpath()
    return p
}

let deckY: CGFloat = 600
let hullBottom: CGFloat = 724
let paneSize: CGFloat = 158, paneGap: CGFloat = 25, paneLeft: CGFloat = 342
let paneTop = deckY - (paneSize * 2 + paneGap)

let background = render { ctx in
    verticalGradient(ctx, [rgb(32, 42, 90), rgb(24, 96, 128), rgb(18, 146, 166)], from: 0, to: size)
}

let backWater = render { ctx in
    ctx.addPath(water(surface: 668, amplitude: 14, period: 300, phase: 1.2))
    ctx.clip()
    verticalGradient(ctx, [rgb(46, 150, 178), rgb(20, 102, 138)], from: 646, to: size)
}

let boat = render { ctx in
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: rgb(8, 20, 48, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    let hull = CGMutablePath()
    hull.move(to: CGPoint(x: 236, y: deckY))
    hull.addLine(to: CGPoint(x: 788, y: deckY))
    hull.addLine(to: CGPoint(x: 712, y: hullBottom - 18))
    hull.addQuadCurve(to: CGPoint(x: 688, y: hullBottom), control: CGPoint(x: 704, y: hullBottom))
    hull.addLine(to: CGPoint(x: 330, y: hullBottom))
    hull.addQuadCurve(to: CGPoint(x: 306, y: hullBottom - 18), control: CGPoint(x: 314, y: hullBottom))
    hull.closeSubpath()
    ctx.saveGState()
    ctx.addPath(hull)
    ctx.clip()
    verticalGradient(ctx, [rgb(255, 255, 255), rgb(214, 228, 238)], from: deckY, to: hullBottom)
    ctx.setFillColor(rgb(170, 196, 214))
    ctx.fill(CGRect(x: 0, y: deckY, width: size, height: 7))
    ctx.restoreGState()

    for row in 0..<2 {
        for col in 0..<2 {
            let rect = CGRect(x: paneLeft + CGFloat(col) * (paneSize + paneGap),
                              y: paneTop + CGFloat(row) * (paneSize + paneGap),
                              width: paneSize, height: paneSize)
            let pane = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
            ctx.saveGState()
            ctx.addPath(pane)
            ctx.clip()
            verticalGradient(ctx, [rgb(255, 255, 255), rgb(226, 236, 243)], from: rect.minY, to: rect.maxY)
            ctx.restoreGState()
        }
    }
    ctx.endTransparencyLayer()
}

let frontWater = render { ctx in
    let front = water(surface: 696, amplitude: 12, period: 260, phase: 0.2)
    ctx.saveGState()
    ctx.addPath(front)
    ctx.clip()
    verticalGradient(ctx, [rgb(66, 170, 196), rgb(22, 110, 146), rgb(16, 92, 128)], from: 684, to: size)
    ctx.restoreGState()
    let crest = CGMutablePath()
    var x: CGFloat = 0
    crest.move(to: CGPoint(x: 0, y: 696 + 12 * sin(0.2)))
    while x <= size {
        crest.addLine(to: CGPoint(x: x, y: 696 + 12 * sin(2 * .pi * x / 260 + 0.2)))
        x += 4
    }
    ctx.addPath(crest)
    ctx.setStrokeColor(rgb(225, 244, 250, 0.9))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

let layers = [("1-background", background), ("2-water-back", backWater), ("3-ferry", boat), ("4-water-front", frontWater)]
let layerDir = out.appendingPathComponent("IconLayers")
try? FileManager.default.createDirectory(at: layerDir, withIntermediateDirectories: true)
for (name, image) in layers { save(image, "IconLayers/\(name).png") }

let icon = render { ctx in
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    for (_, image) in layers { ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size)) }
}
save(icon, "AppIcon.png")
print("Wrote AppIcon.png and IconLayers/ to \(out.path)")
