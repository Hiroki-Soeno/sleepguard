import Cocoa

// SlackやX等のリンクプレビュー用の画像（1200x630）を作る。
let W: CGFloat = 1200, H: CGFloat = 630

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: Int(W) * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 背景：アプリアイコンと同じ夜空のグラデーション
NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.16, blue: 0.28, alpha: 1),
                    NSColor(srgbRed: 0.05, green: 0.06, blue: 0.12, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// アプリアイコン
let iconSide: CGFloat = 260
let iconX: CGFloat = 96, iconY = (H - iconSide) / 2
if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") {
    icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSide, height: iconSide),
              from: .zero, operation: .sourceOver, fraction: 1)
}

let textX = iconX + iconSide + 64
let textW = W - textX - 96

struct Block { let text: String; let font: NSFont; let color: NSColor; let height: CGFloat }

func measure(_ text: String, _ font: NSFont) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 1.2
    return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
        .boundingRect(with: NSSize(width: textW, height: 600),
                      options: [.usesLineFragmentOrigin, .usesFontLeading]).height
}

func make(_ text: String, _ font: NSFont, _ color: NSColor) -> Block {
    Block(text: text, font: font, color: color, height: measure(text, font))
}

let blocks = [
    make("SleepGuard", .systemFont(ofSize: 82, weight: .bold), .white),
    make("蓋を閉じてもMacをスリープさせない。\nメニューバーから1クリックで切り替え。",
         .systemFont(ofSize: 33, weight: .regular), NSColor(white: 1, alpha: 0.72)),
    make("hiroki-soeno.github.io/sleepguard",
         .systemFont(ofSize: 25, weight: .medium), NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)),
]
let gaps: [CGFloat] = [26, 34]   // ブロック間の余白
let total = blocks.reduce(0) { $0 + $1.height } + gaps.reduce(0, +)

// 上端からの位置で積む（NSRectは左下原点なので H から引く）
var top = (H - total) / 2
for (i, b) in blocks.enumerated() {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 1.2
    NSAttributedString(string: b.text, attributes: [.font: b.font, .foregroundColor: b.color, .paragraphStyle: style])
        .draw(with: NSRect(x: textX, y: H - top - b.height, width: textW, height: b.height),
              options: [.usesLineFragmentOrigin, .usesFontLeading])
    top += b.height + (i < gaps.count ? gaps[i] : 0)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/og.png"))
print("wrote docs/og.png (1200x630)")
