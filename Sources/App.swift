import SwiftUI
import AppKit

/// Entry point: one MenuBarExtra per enabled resource plus the Settings window.
@main
struct ResourceGlanceBarApp: App {
    @AppStorage(Settings.showCPU) private var showCPU = true
    @AppStorage(Settings.showMemory) private var showMemory = true
    @AppStorage(Settings.showDisk) private var showDisk = true
    @StateObject private var monitor: SystemMonitor

    init() {
        Settings.registerDefaults()
        _monitor = StateObject(wrappedValue: SystemMonitor.shared)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showCPU) {
            PopoverContainer(title: "CPU") { CPUView() }.environmentObject(monitor)
        } label: {
            CPULabel().environmentObject(monitor)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $showMemory) {
            PopoverContainer(title: "Memory") { MemoryView() }.environmentObject(monitor)
        } label: {
            MemoryLabel().environmentObject(monitor)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $showDisk) {
            PopoverContainer(title: "Disk") { DiskView() }.environmentObject(monitor)
        } label: {
            DiskLabel().environmentObject(monitor)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView()
        }
    }
}

/// Menu bar label for CPU: a 20-sample mini graph or a percentage.
struct CPULabel: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @AppStorage(Settings.displayMode) private var mode = DisplayMode.graph.rawValue
    @AppStorage(Settings.cpuWarn) private var warn = 80.0
    @AppStorage(Settings.theme) private var theme = ColorTheme.classic.rawValue

    var body: some View {
        let load = monitor.cpu?.total
        let level: Level = (load ?? 0) * 100 >= warn ? .critical : .normal
        let palette = ColorTheme(rawValue: theme) ?? .classic
        if mode == DisplayMode.graph.rawValue {
            let values = monitor.cpuHistory.map { min(1, $0.user + $0.system) }
            Image(nsImage: MenuBarImage.graph(values, color: palette.nsColor(level)))
                .accessibilityLabel("CPU \(Format.percent(load))")
        } else {
            Image(nsImage: MenuBarImage.text("CPU \(Format.percent(load))",
                                             textColor: level == .normal ? nil : palette.nsColor(level)))
        }
    }
}

/// Menu bar label for memory: used percentage with a pressure-coloured dot.
struct MemoryLabel: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @AppStorage(Settings.memoryWarn) private var warn = 85.0
    @AppStorage(Settings.theme) private var theme = ColorTheme.classic.rawValue

    var body: some View {
        let palette = ColorTheme(rawValue: theme) ?? .classic
        let dot = monitor.memory.map { palette.nsColor(memoryLevel($0, warn: warn)) } ?? .tertiaryLabelColor
        Image(nsImage: MenuBarImage.text("MEM \(Format.percent(monitor.memory?.usedFraction))", dot: dot))
    }
}

/// Severity combining kernel memory pressure with the user's used-percentage threshold.
func memoryLevel(_ memory: MemorySnapshot, warn: Double) -> Level {
    if memory.pressure >= 4 { return .critical }
    if memory.pressure == 2 || memory.usedFraction * 100 >= warn { return .warning }
    return .normal
}

/// Menu bar label for disk: free space on the startup volume.
struct DiskLabel: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @AppStorage(Settings.diskWarn) private var warn = 10.0
    @AppStorage(Settings.theme) private var theme = ColorTheme.classic.rawValue

    var body: some View {
        let low = (monitor.disk?.freeFraction ?? 1) * 100 < warn
        let palette = ColorTheme(rawValue: theme) ?? .classic
        Image(nsImage: MenuBarImage.text("SSD \(Format.disk(monitor.disk?.free))",
                                         textColor: low ? palette.nsColor(.critical) : nil))
    }
}

/// Opens the donation page in the default browser.
func openDonationPage() {
    // Compile-time constant URL, so the unwrap cannot fail.
    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
}
