import Cocoa

// ダウンロードページの「アイコンの見方」用に、メニューバーでの見え方をそのまま画像にする。
// 描画ロジックは Sources/main.swift の Icon と同じ。
let knockRatio: CGFloat = 3.0 / 14, widthRatio: CGFloat = 1.5 / 14, lengthFactor: CGFloat = 0.80

func glyph(pointSize: CGFloat, color: NSColor, slash: Bool) -> NSImage {
    let config = NSImage.SymbolConfiguration(paletteColors: [color])
        .applying(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
    let base = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    guard slash else { return base }
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
    ctx.compositingOperation = .destinationOut
    path.lineWidth = pointSize * knockRatio
    NSColor.black.setStroke(); path.stroke()
    ctx.compositingOperation = .sourceOver
    path.lineWidth = pointSize * widthRatio
    color.setStroke(); path.stroke()
    out.unlockFocus()
    return out
}

/// メニューバーを模した黒いタイルの上にアイコンを置く（明背景でも暗背景でも読めるように）
func chip(color: NSColor, slash: Bool, px: CGFloat = 132) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: Int(px) * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let tile = NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: px * 0.02, dy: px * 0.02)
    let shape = NSBezierPath(roundedRect: tile, xRadius: px * 0.2, yRadius: px * 0.2)
    NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill(); shape.fill()
    NSColor(white: 1, alpha: 0.16).setStroke(); shape.lineWidth = px * 0.016; shape.stroke()

    let g = glyph(pointSize: px * 0.30, color: color, slash: slash)
    let scale = px * 0.56 / max(g.size.width, g.size.height)
    let w = g.size.width * scale, h = g.size.height * scale
    g.draw(in: NSRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h),
           from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
try! chip(color: .white, slash: false).write(to: URL(fileURLWithPath: "\(dir)/menubar-off.png"))
try! chip(color: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1), slash: true)
    .write(to: URL(fileURLWithPath: "\(dir)/menubar-on.png"))
try! chip(color: NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1), slash: true)
    .write(to: URL(fileURLWithPath: "\(dir)/menubar-battery.png"))
print("wrote menubar-{off,on,battery}.png to \(dir)")
