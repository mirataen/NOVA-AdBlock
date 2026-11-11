import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 1024px NOVA shield icon, matching the dashboard's navy/cyan branding.
// Source artwork stays in this script; no external icon-generation service.
guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift make_app_icon.swift OUTPUT.png\n", stderr)
    exit(1)
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(
    at: destination.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create icon bitmap") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

ctx.setFillColor(rgb(0.035, 0.11, 0.175))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Calm dark-blue gradient, fully opaque to avoid a transparent/blank icon.
if let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0.035,0.09,0.16),rgb(0.022,0.048,0.098)] as CFArray,
    locations: [0, 1]
) {
    ctx.drawLinearGradient(background,
                           start: CGPoint(x: 0, y: 1024),
                           end: CGPoint(x: 1024, y: 0),
                           options: [])
}

// Outer shield: bold cyan symbol that remains legible on the Home Screen.
let outer = CGMutablePath()
outer.move(to: CGPoint(x: 512, y: 150))
outer.addCurve(to: CGPoint(x: 265, y: 431),
               control1: CGPoint(x: 364, y: 220),
               control2: CGPoint(x: 265, y: 294))
outer.addLine(to: CGPoint(x: 265, y: 729))
outer.addQuadCurve(to: CGPoint(x: 313, y: 789), control: CGPoint(x: 265, y: 775))
outer.addLine(to: CGPoint(x: 512, y: 873))
outer.addLine(to: CGPoint(x: 711, y: 789))
outer.addQuadCurve(to: CGPoint(x: 759, y: 729), control: CGPoint(x: 759, y: 775))
outer.addLine(to: CGPoint(x: 759, y: 431))
outer.addCurve(to: CGPoint(x: 512, y: 150),
               control1: CGPoint(x: 759, y: 294),
               control2: CGPoint(x: 660, y: 220))
outer.closeSubpath()
ctx.addPath(outer)
ctx.setFillColor(rgb(0.18, 0.84, 0.98))
ctx.fillPath()

// Inner navy silhouette produces the recognizable half-shield treatment.
let inset = CGMutablePath()
inset.move(to: CGPoint(x: 512, y: 232))
inset.addCurve(to: CGPoint(x: 344, y: 455),
               control1: CGPoint(x: 402, y: 289),
               control2: CGPoint(x: 344, y: 350))
inset.addLine(to: CGPoint(x: 344, y: 723))
inset.addLine(to: CGPoint(x: 512, y: 790))
inset.addLine(to: CGPoint(x: 680, y: 723))
inset.addLine(to: CGPoint(x: 680, y: 455))
inset.addCurve(to: CGPoint(x: 512, y: 232),
               control1: CGPoint(x: 680, y: 350),
               control2: CGPoint(x: 622, y: 289))
inset.closeSubpath()
ctx.addPath(inset)
ctx.setFillColor(rgb(0.055, 0.19, 0.29))
ctx.fillPath()

let half = CGMutablePath()
half.move(to: CGPoint(x: 512, y: 790))
half.addLine(to: CGPoint(x: 344, y: 723))
half.addLine(to: CGPoint(x: 344, y: 455))
half.addCurve(to: CGPoint(x: 512, y: 232),
              control1: CGPoint(x: 344, y: 350),
              control2: CGPoint(x: 402, y: 289))
half.closeSubpath()
ctx.addPath(half)
ctx.setFillColor(rgb(0.13, 0.67, 0.87))
ctx.fillPath()

guard let image = ctx.makeImage(),
      let output = CGImageDestinationCreateWithURL(
        destination as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else { fatalError("Unable to encode icon") }
CGImageDestinationAddImage(output, image, nil)
guard CGImageDestinationFinalize(output) else {
    fatalError("PNG output failed")
}
print("Generated NOVA icon: \(destination.path)")
