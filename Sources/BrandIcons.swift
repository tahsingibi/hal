import AppKit
import SwiftUI

enum BrandIcon: String {
    /// Hiçbir modül görünür değilken menü çubuğunda duran genel ikonun kimliği.
    static let appItemID = "app"

    case claude
    case codex
    case grok
    case prayer
    case app
    case custom

    static func from(id: String) -> BrandIcon {
        switch id {
        case "claude": return .claude
        case "codex": return .codex
        case "grok": return .grok
        case "prayer": return .prayer
        case "app": return .app
        default: return .custom
        }
    }

    private var assetName: String? {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .grok: return "grok"
        case .prayer, .app: return "hal"
        case .custom: return nil
        }
    }

    private var usesNativePath: Bool {
        self == .codex || self == .grok || self == .app || self == .prayer
    }

    func templateImage(size: CGFloat = 16) -> NSImage {
        if usesNativePath {
            return drawnTemplate(size: size)
        }
        if let name = assetName, let image = Self.load(name, variant: .template, size: size) {
            return image
        }
        return drawnTemplate(size: size)
    }

    func image(dark: Bool, size: CGFloat = 16) -> NSImage {
        if usesNativePath {
            return drawnTemplate(size: size)
        }
        if let name = assetName {
            let variant: AssetVariant = dark ? .white : .dark
            if let image = Self.load(name, variant: variant, size: size) {
                return image
            }
        }
        return templateImage(size: size)
    }

    private func drawnTemplate(size: CGFloat) -> NSImage {
        let icon = self
        return BrandIcon.render(size: size) { rect in
            switch icon {
            case .codex: BrandIcon.drawCodex(in: rect)
            case .grok: BrandIcon.drawGrok(in: rect)
            case .app, .prayer: BrandIcon.drawMark(in: rect)
            default: BrandIcon.drawCustom(in: rect)
            }
        }
    }

    private enum AssetVariant {
        case template
        case dark
        case white

        var suffix: String {
            switch self {
            case .template, .dark: return ""
            case .white: return "-white"
            }
        }
    }

    private static func load(_ name: String, variant: AssetVariant, size: CGFloat) -> NSImage? {
        let file = name + variant.suffix
        let source = resourceImage(file)
        guard let source else { return nil }
        let raster = rasterize(source, size: size)
        raster.isTemplate = variant == .template
        return raster
    }

    private static func resourceImage(_ name: String) -> NSImage? {
        if let url = resourceURL(name, ext: "png"), let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = resourceURL(name, ext: "svg"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 128, height: 128)
            return image
        }
        return nil
    }

    private static func resourceURL(_ name: String, ext: String) -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Icons") {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        if let root = bundle.resourceURL?.appendingPathComponent("Icons/\(name).\(ext)"),
           FileManager.default.fileExists(atPath: root.path) {
            return root
        }
        return nil
    }

    private static func rasterize(_ source: NSImage, size: CGFloat) -> NSImage {
        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        source.draw(
            in: NSRect(origin: .zero, size: NSSize(width: size, height: size)),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1
        )
        output.unlockFocus()
        return output
    }

    private static func render(size: CGFloat, draw: @escaping (CGRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor.black.setFill()
            NSColor.black.setStroke()
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let codexPath = "M8.086.457a6.105 6.105 0 013.046-.415c1.333.153 2.521.72 3.564 1.7a.117.117 0 00.107.029c1.408-.346 2.762-.224 4.061.366l.063.03.154.076c1.357.703 2.33 1.77 2.918 3.198.278.679.418 1.388.421 2.126a5.655 5.655 0 01-.18 1.631.167.167 0 00.04.155 5.982 5.982 0 011.578 2.891c.385 1.901-.01 3.615-1.183 5.14l-.182.22a6.063 6.063 0 01-2.934 1.851.162.162 0 00-.108.102c-.255.736-.511 1.364-.987 1.992-1.199 1.582-2.962 2.462-4.948 2.451-1.583-.008-2.986-.587-4.21-1.736a.145.145 0 00-.14-.032c-.518.167-1.04.191-1.604.185a5.924 5.924 0 01-2.595-.622 6.058 6.058 0 01-2.146-1.781c-.203-.269-.404-.522-.551-.821a7.74 7.74 0 01-.495-1.283 6.11 6.11 0 01-.017-3.064.166.166 0 00.008-.074.115.115 0 00-.037-.064 5.958 5.958 0 01-1.38-2.202 5.196 5.196 0 01-.333-1.589 6.915 6.915 0 01.188-2.132c.45-1.484 1.309-2.648 2.577-3.493.282-.188.55-.334.802-.438.286-.12.573-.22.861-.304a.129.129 0 00.087-.087A6.016 6.016 0 015.635 2.31C6.315 1.464 7.132.846 8.086.457zm-.804 7.85a.848.848 0 00-1.473.842l1.694 2.965-1.688 2.848a.849.849 0 001.46.864l1.94-3.272a.849.849 0 00.007-.854l-1.94-3.393zm5.446 6.24a.849.849 0 000 1.695h4.848a.849.849 0 000-1.696h-4.848z"

    private static func drawCodex(in rect: CGRect) {
        let pad = min(rect.width, rect.height) * 0.04
        SVGPath.fill(codexPath, viewBox: 24, in: rect.insetBy(dx: pad, dy: pad))
    }

    private static let grokPath = "M9.27 15.29l7.978-5.897c.391-.29.95-.177 1.137.272.98 2.369.542 5.215-1.41 7.169-1.951 1.954-4.667 2.382-7.149 1.406l-2.711 1.257c3.889 2.661 8.611 2.003 11.562-.953 2.341-2.344 3.066-5.539 2.388-8.42l.006.007c-.983-4.232.242-5.924 2.75-9.383.06-.082.12-.164.179-.248l-3.301 3.305v-.01L9.267 15.292M7.623 16.723c-2.792-2.67-2.31-6.801.071-9.184 1.761-1.763 4.647-2.483 7.166-1.425l2.705-1.25a7.808 7.808 0 00-1.829-1A8.975 8.975 0 005.984 5.83c-2.533 2.536-3.33 6.436-1.962 9.764 1.022 2.487-.653 4.246-2.34 6.022-.599.63-1.199 1.259-1.682 1.925l7.62-6.815"

    private static func drawGrok(in rect: CGRect) {
        let pad = min(rect.width, rect.height) * 0.04
        SVGPath.fill(grokPath, viewBox: 24, in: rect.insetBy(dx: pad, dy: pad))
    }

    private static let markGauge = "M708.8 373.0A310 310 0 1 1 427.0 91.2L416.6 210.7A190 190 0 1 0 589.3 383.4Z"
    private static let markDot = "M476.8 223.2A100 100 0 1 0 676.8 223.2A100 100 0 1 0 476.8 223.2Z"

    /// Hâl markası: sağa açılan gösterge halkası ve içindeki konum noktası.
    private static func drawMark(in rect: CGRect) {
        let pad = min(rect.width, rect.height) * 0.02
        let inset = rect.insetBy(dx: pad, dy: pad)
        SVGPath.fill(markGauge, viewBox: 800, in: inset)
        SVGPath.fill(markDot, viewBox: 800, in: inset)
    }

    private static func drawCustom(in rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let s = min(rect.width, rect.height)
        starPath(center: c, points: 5, outer: s * 0.46, inner: s * 0.20).fill()
    }

    private static func starPath(center: CGPoint, points: Int, outer: CGFloat, inner: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let count = points * 2
        for i in 0..<count {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let rad = i % 2 == 0 ? outer : inner
            let p = CGPoint(x: center.x + cos(angle) * rad, y: center.y + sin(angle) * rad)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }
}

extension ProviderKind {
    var brand: BrandIcon {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        case .grok: return .grok
        case .custom: return .custom
        }
    }
}

struct BrandMark: View {
    let icon: BrandIcon
    var size: CGFloat = 12

    var body: some View {
        Image(nsImage: icon.templateImage(size: size * 2))
            .resizable()
            .interpolation(.high)
            .renderingMode(.template)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }
}
