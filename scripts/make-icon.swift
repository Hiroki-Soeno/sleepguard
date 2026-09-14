import Cocoa

// メニューバーと同じ「月＋斜線」をアプリアイコンに起こす。
// 斜線の太さ・くり抜き幅は pointSize に対する比率で、Sources/main.swift の値と合わせてある。
let knockRatio: CGFloat = 3.4 / 14
let widthRatio: CGFloat = 1.8 / 14
let lengthFactor: CGFloat = 0.80

func glyph(pointSize: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(paletteColors: [color])
        .applying(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
    let base = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let size = base.size
    let out = NSImage(size: size)
    out.lockFocus()
    base.draw(in: NSRect(origin: .zero, size: size))
    let ctx = NSGraphicsContext.current!
    let angle: CGFloat = 60 * .pi / 180
    let half = min(size.width, size.height) * lengthFactor
    let cx = size.width / 2, cy = size.height / 2
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx - cos(angle) * half, y: cy - sin(angle) * half))
    path.line(to: NSPoint(x: cx + cos(angle) * half, y: cy + sin(angle) * half))
    path.lineCapStyle = .round
    ctx.compositingOperation = .destinationOut      // 斜線の下地を抜く＝背景が透けて見える
    path.lineWidth = pointSize * knockRatio
    NSColor.black.setStroke(); path.stroke()
    ctx.compositingOperation = .sourceOver
    path.lineWidth = pointSize * widthRatio
    color.setStroke(); path.stroke()
    out.unlockFocus()
    return out
}

func icon(_ px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: Int(px) * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS標準の余白比率（1024キャンバスに824のタイル）と角丸
    let inset = px * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: px - inset * 2, height: px - inset * 2)
    let radius = tile.width * 0.2237
    let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.11, green: 0.14, blue: 0.26, alpha: 1),
                        NSColor(srgbRed: 0.04, green: 0.05, blue: 0.11, alpha: 1)])!
        .draw(in: tile, angle: -90)

    let g = glyph(pointSize: px * 0.30, color: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1))
    let scale = tile.width * 0.68 / max(g.size.width, g.size.height)
    let w = g.size.width * scale, h = g.size.height * scale
    g.draw(in: NSRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h),
           from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments[1]
for (name, px) in [("16x16", 16.0), ("16x16@2x", 32.0), ("32x32", 32.0), ("32x32@2x", 64.0),
                   ("128x128", 128.0), ("128x128@2x", 256.0), ("256x256", 256.0), ("256x256@2x", 512.0),
                   ("512x512", 512.0), ("512x512@2x", 1024.0)] {
    let data = icon(CGFloat(px)).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
print("iconset written to \(outDir)")
