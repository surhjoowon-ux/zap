// 앱 아이콘 생성: swift make_icon.swift <out.iconset>
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let S = CGFloat(px), u = S / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: 100*u, y: 100*u, width: 824*u, height: 824*u), xRadius: 185*u, yRadius: 185*u)
    NSColor(white: 0.07, alpha: 1).setFill(); bg.fill()
    let t = NSAffineTransform(); t.translateX(by: S/2, yBy: S/2); t.rotate(byDegrees: 35); t.concat()
    let r = NSRect(x: -470*u, y: -120*u, width: 940*u, height: 240*u)
    NSColor(white: 1, alpha: 0.78).setFill()
    NSBezierPath(roundedRect: r, xRadius: 22*u, yRadius: 22*u).fill()
    NSColor(white: 0.07, alpha: 1).setFill()
    for i in 0...36 {
        let h: CGFloat = i % 10 == 0 ? 120 : i % 5 == 0 ? 80 : 45
        NSRect(x: r.minX + 55*u + CGFloat(i) * 23.3*u, y: r.maxY - h*u, width: 7*u, height: h*u).fill()
    }
    NSColor(calibratedRed: 1, green: 0.18, blue: 0.2, alpha: 1).setFill()
    NSRect(x: 110*u, y: r.minY - 40*u, width: 8*u, height: r.height + 80*u).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
