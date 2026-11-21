#!/usr/bin/env swift
// FCleaner uygulama ikonunu çizer: swift scripts/make-icon.swift  →  Resources/AppIcon.icns
import AppKit

let canvas: CGFloat = 1024

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / canvas, y: size / canvas)

    // macOS ikon ızgarası: 1024'lük tuvalde 824'lük gövde.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Gölge
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Arka plan: camgöbeğinden mora çapraz geçiş.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.10, green: 0.85, blue: 0.95, alpha: 1).cgColor,
        NSColor(srgbRed: 0.22, green: 0.45, blue: 1.00, alpha: 1).cgColor,
        NSColor(srgbRed: 0.48, green: 0.22, blue: 0.95, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])

    // Üstte yumuşak parlama.
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 860), endRadius: 620, options: [])
    ctx.restoreGState()

    // "F" harfi: yuvarlatılmış üç çubuk.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(srgbRed: 0.1, green: 0.05, blue: 0.4, alpha: 0.45).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    let bars = [
        CGRect(x: 300, y: 250, width: 124, height: 524),  // gövde
        CGRect(x: 300, y: 650, width: 380, height: 124),  // üst kol
        CGRect(x: 300, y: 450, width: 290, height: 116),  // orta kol
    ]
    let letter = CGMutablePath()
    for bar in bars { letter.addPath(CGPath(roundedRect: bar, cornerWidth: 54, cornerHeight: 54, transform: nil)) }
    ctx.addPath(letter)
    ctx.fillPath()
    ctx.restoreGState()

    // Parıltılar: "tertemiz" vurgusu.
    func sparkle(center c: CGPoint, radius r: CGFloat, alpha: CGFloat) {
        let p = CGMutablePath()
        let k = r * 0.18  // içe bükülme
        p.move(to: CGPoint(x: c.x, y: c.y + r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 0.5, color: NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.addPath(p)
        ctx.fillPath()
        ctx.restoreGState()
    }
    sparkle(center: CGPoint(x: 700, y: 345), radius: 118, alpha: 1)
    sparkle(center: CGPoint(x: 800, y: 500), radius: 52, alpha: 0.95)
    sparkle(center: CGPoint(x: 590, y: 225), radius: 36, alpha: 0.85)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = renderIcon(size: px).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
try renderIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "✅ Resources/AppIcon.icns oluşturuldu" : "❌ iconutil başarısız")
