import AppKit
// Ícone provisório do Meety: fundo arredondado em degradê e uma onda de áudio. Uso: swift make-icon.swift <pasta>
let out = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    let grad = NSGradient(colors: [NSColor(red: 0.16, green: 0.36, blue: 0.62, alpha: 1), NSColor(red: 0.10, green: 0.22, blue: 0.42, alpha: 1)])!
    grad.draw(in: path, angle: -70)
    NSColor.white.setStroke()
    let bars: [CGFloat] = [0.22, 0.42, 0.68, 0.9, 0.56, 0.34, 0.2]
    let w = s * 0.07, gap = s * 0.05
    let total = CGFloat(bars.count) * w + CGFloat(bars.count - 1) * gap
    var x = (s - total) / 2
    for h in bars {
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: (s - s * h * 0.6) / 2, width: w, height: s * h * 0.6), xRadius: w / 2, yRadius: w / 2)
        NSColor.white.setFill(); bar.fill()
        x += w + gap
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    rep.size = NSSize(width: s, height: s)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(out)/icon_\(size).png"))
}
