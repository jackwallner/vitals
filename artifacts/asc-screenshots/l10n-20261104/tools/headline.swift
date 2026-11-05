// Draws a two-line screenshot header with CoreText, which shapes Arabic, Hebrew,
// Thai and Devanagari correctly (Pillow here has no raqm).
// stdin: JSON array of {first, second, locale, color:[r,g,b], accent:[r,g,b], out}
// stdout: JSON array of {locale, out, size, width, gap, fits}
import AppKit
import Foundation

struct Job: Codable { let first, second, locale, out: String; let color, accent: [Int] }
struct Result: Codable { let locale, out: String; let size: Int; let width: Int; let gap: Int; let fits: Bool }

let canvasWidth = 1284, canvasHeight = 700, softWidth = 1110.0, hardWidth = 1190.0, floorSize = 136, ceilingSize = 202
let top = 145.0

func nsColor(_ c: [Int]) -> NSColor {
    NSColor(srgbRed: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255, blue: CGFloat(c[2]) / 255, alpha: 1)
}

/// Scripts with no real italic stay upright; the accent colour carries the emphasis.
func font(_ locale: String, size: CGFloat, emphasised: Bool) -> NSFont {
    let named: [String: String] = [
        "ja": "HiraginoSans-W8", "zh-Hans": "PingFangSC-Semibold", "zh-Hant": "PingFangTC-Semibold",
        "ko": "AppleSDGothicNeo-Heavy", "th": "SukhumvitSet-Bold", "hi": "KohinoorDevanagari-Bold",
    ]
    if let name = named[locale], let f = NSFont(name: name, size: size) { return f }
    if locale == "ar-SA" { return NSFont(name: "SFArabicRounded-Bold", size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold) }
    if locale == "he" { return NSFont(name: "SFHebrewRounded-Bold", size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold) }
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    if emphasised {
        // withSymbolicTraits(.italic) alone drops back to regular weight.
        let italic = base.fontDescriptor.withSymbolicTraits([.italic, .bold])
        return NSFont(descriptor: italic, size: size) ?? base
    }
    let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return NSFont(descriptor: rounded, size: size) ?? base
}

func line(_ text: String, _ locale: String, size: Int, emphasised: Bool, color: NSColor) -> NSAttributedString {
    let stroke = -(4.0 / Double(size)) * 100
    return NSAttributedString(string: text, attributes: [
        .font: font(locale, size: CGFloat(size), emphasised: emphasised),
        .foregroundColor: color, .strokeColor: color, .strokeWidth: stroke,
        .languageIdentifier: locale,
    ])
}

func ink(_ s: NSAttributedString) -> CGRect {
    CTLineGetImageBounds(CTLineCreateWithAttributedString(s), NSGraphicsContext.current!.cgContext)
}

func draw(_ job: Job) -> Result {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvasWidth, pixelsHigh: canvasHeight,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    var size = ceilingSize
    var a = line(job.first, job.locale, size: size, emphasised: false, color: nsColor(job.color))
    var b = line(job.second, job.locale, size: size, emphasised: true, color: nsColor(job.accent))
    while size > floorSize {
        if max(ink(a).width, ink(b).width) <= softWidth { break }
        size -= 2
        a = line(job.first, job.locale, size: size, emphasised: false, color: nsColor(job.color))
        b = line(job.second, job.locale, size: size, emphasised: true, color: nsColor(job.accent))
    }
    let boxA = ink(a), boxB = ink(b)
    // Same rhythm as the English set: first baseline, then one font size minus 8.
    // Stacked diacritics (Thai, Vietnamese, Devanagari) push the second line down
    // until the two lines clear each other by 14 px.
    let firstBaseline = top + Double(size) * 0.95
    var secondBaseline = firstBaseline + Double(size) - 8
    let firstBottom = firstBaseline - boxA.minY
    let secondTop = secondBaseline - boxB.maxY
    if secondTop - firstBottom < 14 { secondBaseline += 14 - (secondTop - firstBottom) }
    let height = Double(canvasHeight)
    for (text, baseline, box) in [(a, firstBaseline, boxA), (b, secondBaseline, boxB)] {
        let ctLine = CTLineCreateWithAttributedString(text)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: (Double(canvasWidth) - box.width) / 2 - box.minX, y: height - baseline)
        CTLineDraw(ctLine, ctx)
    }
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: job.out))
    let width = max(boxA.width, boxB.width)
    let gap = Int(secondBaseline - boxB.maxY - firstBottom)
    return Result(locale: job.locale, out: job.out, size: size, width: Int(width), gap: gap, fits: width <= hardWidth)
}

let jobs = try! JSONDecoder().decode([Job].self, from: FileHandle.standardInput.readDataToEndOfFile())
print(String(data: try! JSONEncoder().encode(jobs.map(draw)), encoding: .utf8)!)
