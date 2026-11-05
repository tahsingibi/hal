// Hâl uygulama ikonunu üretir: koyu yuvarlak kare üzerinde marka işareti.
// Geometri Resources/Icons/hal.svg ile aynıdır. Dışarıdan kütüphane gerektirmez;
// CoreGraphics ile çizer, ImageIO ile çok çözünürlüklü ICNS yazar.
// Kullanım: make-icon <çıktı.icns>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// İşaretin 800×800 tasarım alanındaki ölçüleri (y aşağı doğru).
let center = 400.0
let outer = 310.0, inner = 190.0
let gapCenter = 315.0, gapHalf = 40.0
let dotRadius = 100.0, dotDistance = 250.0
let ink = CGColor(srgbRed: 247 / 255, green: 240 / 255, blue: 214 / 255, alpha: 1)
let background = CGColor(srgbRed: 14 / 255, green: 14 / 255, blue: 16 / 255, alpha: 1)

func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

/// 800×800 tasarım alanına göre işareti çizer; bağlam y-aşağı koordinatta olmalı.
func drawMark(in context: CGContext) {
    // Halka: boşluk açısı dışında kalan dilim, içi boş.
    let ring = CGMutablePath()
    ring.move(to: CGPoint(x: center, y: center))
    var angle = gapCenter + gapHalf
    let end = gapCenter - gapHalf + 360
    while angle <= end {
        ring.addLine(to: CGPoint(x: center + outer * cos(radians(angle)), y: center + outer * sin(radians(angle))))
        angle += 0.25
    }
    ring.closeSubpath()
    context.setFillColor(ink)
    context.addPath(ring)
    context.fillPath()

    context.setBlendMode(.clear)
    context.fillEllipse(in: CGRect(x: center - inner, y: center - inner, width: inner * 2, height: inner * 2))
    context.setBlendMode(.normal)

    let dot = CGPoint(x: center + dotDistance * cos(radians(gapCenter)),
                      y: center + dotDistance * sin(radians(gapCenter)))
    context.setFillColor(ink)
    context.fillEllipse(in: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
}

func icon(size: Int) -> CGImage? {
    let side = CGFloat(size)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    // Görüntü koordinatları (y aşağı) ile çiz.
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)

    let pad = side * 0.08
    let tile = CGRect(x: pad, y: pad, width: side - pad * 2, height: side - pad * 2)
    context.setFillColor(background)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: side * 0.22, cornerHeight: side * 0.22, transform: nil))
    context.fillPath()

    // İşaret ayrı bir katmanda çizilir: iç dairenin silinmesi zemini delmesin.
    let markSide = max(1, Int(side * 0.56))
    guard let layer = CGContext(data: nil, width: markSide, height: markSide, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    layer.setShouldAntialias(true)
    layer.translateBy(x: 0, y: CGFloat(markSide))
    layer.scaleBy(x: CGFloat(markSide) / 800, y: -CGFloat(markSide) / 800)
    drawMark(in: layer)
    guard let mark = layer.makeImage() else { return nil }
    let offset = CGFloat((size - markSide) / 2)
    // Katman zaten doğru yönde; çevirmeyi geri alıp yerleştir.
    context.saveGState()
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)
    context.draw(mark, in: CGRect(x: offset, y: offset, width: CGFloat(markSide), height: CGFloat(markSide)))
    context.restoreGState()
    return context.makeImage()
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Kullanım: make-icon <çıktı.icns>\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
// Her mantıksal boyut için 1x (72 dpi) ve Retina @2x (144 dpi) temsilleri.
let representations: [(pixels: Int, dpi: Int)] = [
    (16, 72), (32, 144), (32, 72), (64, 144), (128, 72), (256, 144),
    (256, 72), (512, 144), (512, 72), (1024, 144)
]
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString,
                                                        representations.count, nil) else {
    FileHandle.standardError.write("ICNS yazılamadı\n".data(using: .utf8)!)
    exit(1)
}
for representation in representations {
    guard let image = icon(size: representation.pixels) else { exit(1) }
    let properties = [kCGImagePropertyDPIWidth: representation.dpi,
                      kCGImagePropertyDPIHeight: representation.dpi] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
}
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("ICNS tamamlanamadı\n".data(using: .utf8)!)
    exit(1)
}
