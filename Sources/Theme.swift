import AppKit
import SwiftUI

/// UserDefaults keys and their defaults, shared by @AppStorage and the sampler.
enum Settings {
    static let showCPU = "showCPU", showMemory = "showMemory", showDisk = "showDisk"
    static let interval = "updateInterval", displayMode = "displayMode", theme = "colorTheme"
    static let cpuWarn = "cpuWarning", memoryWarn = "memoryWarning", diskWarn = "diskFreeWarning"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showCPU: true, showMemory: true, showDisk: true, interval: 2,
            displayMode: DisplayMode.graph.rawValue, theme: ColorTheme.classic.rawValue,
            cpuWarn: 80.0, memoryWarn: 85.0, diskWarn: 10.0,
        ])
    }
}

/// Whether the CPU menu bar item shows a mini bar graph or a percentage.
enum DisplayMode: String, CaseIterable, Identifiable {
    case graph, number
    var id: String { rawValue }
    var title: String { self == .graph ? "Graph" : "Number" }
}

/// Severity level used to colour meters.
enum Level { case normal, warning, critical }

/// Colour palettes for meters; each maps a severity to a colour.
enum ColorTheme: String, CaseIterable, Identifiable {
    case classic, ocean, mono
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func nsColor(_ level: Level) -> NSColor {
        switch (self, level) {
        case (.classic, .normal): return .systemGreen
        case (.classic, .warning): return .systemYellow
        case (.classic, .critical): return .systemRed
        case (.ocean, .normal): return .systemTeal
        case (.ocean, .warning): return .systemOrange
        case (.ocean, .critical): return .systemPink
        case (.mono, .normal): return .secondaryLabelColor
        case (.mono, .warning): return .labelColor
        case (.mono, .critical): return .systemRed
        }
    }

    func color(_ level: Level) -> Color { Color(nsColor: nsColor(level)) }

    static var current: ColorTheme {
        ColorTheme(rawValue: UserDefaults.standard.string(forKey: Settings.theme) ?? "") ?? .classic
    }
}

/// Small formatting helpers used by every view.
enum Format {
    static let dash = "—"

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return dash }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func memory(_ bytes: UInt64?) -> String {
        guard let bytes else { return dash }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    static func disk(_ bytes: Int64?) -> String {
        guard let bytes else { return dash }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return dash }
        return disk(Int64(bytesPerSecond)) + "/s"
    }
}

/// Draws compact menu bar images (text meters and the CPU mini graph).
enum MenuBarImage {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let height: CGFloat = 18

    /// Text meter with an optional coloured dot in front.
    static func text(_ string: String, dot: NSColor? = nil, textColor: NSColor? = nil) -> NSImage {
        let template = dot == nil && textColor == nil
        let foreground = textColor ?? (template ? NSColor.black : NSColor.labelColor)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let textSize = (string as NSString).size(withAttributes: attributes)
        let dotWidth: CGFloat = dot == nil ? 0 : 10
        let size = NSSize(width: ceil(textSize.width + dotWidth), height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            if let dot {
                dot.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: (height - 7) / 2, width: 7, height: 7)).fill()
            }
            (string as NSString).draw(at: NSPoint(x: dotWidth, y: (height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        // Plain text adapts to the menu bar appearance; coloured content must not be templated.
        image.isTemplate = template
        return image
    }

    /// Bar graph of recent CPU load (0...1), newest on the right.
    static func graph(_ values: [Double], color: NSColor, slots: Int = 20) -> NSImage {
        let barWidth: CGFloat = 1.5, step: CGFloat = 2
        let size = NSSize(width: CGFloat(slots) * step + 2, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.gray.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: size.width, height: height - 2), xRadius: 2, yRadius: 2).fill()
            color.setFill()
            let recent = values.suffix(slots)
            let offset = slots - recent.count
            for (i, value) in recent.enumerated() {
                let h = max(1, CGFloat(min(1, max(0, value))) * (height - 4))
                NSRect(x: 1 + CGFloat(offset + i) * step, y: 2, width: barWidth, height: h).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
