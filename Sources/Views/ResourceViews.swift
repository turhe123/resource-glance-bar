import SwiftUI
import Charts

/// CPU popover: user/system load, history chart, per-core bars, load average and busiest processes.
struct CPUView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @AppStorage(Settings.theme) private var theme = ColorTheme.classic.rawValue
    @AppStorage(Settings.cpuWarn) private var warn = 80.0

    var body: some View {
        let palette = ColorTheme(rawValue: theme) ?? .classic
        let cpu = monitor.cpu
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.percent(cpu?.total)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Spacer()
                VStack(alignment: .trailing) {
                    Text("User \(Format.percent(cpu?.user))")
                    Text("System \(Format.percent(cpu?.system))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Chart(monitor.cpuHistory) { point in
                AreaMark(x: .value("Sample", point.id), y: .value("Load", point.system * 100))
                    .foregroundStyle(by: .value("Kind", "System"))
                AreaMark(x: .value("Sample", point.id), y: .value("Load", point.user * 100))
                    .foregroundStyle(by: .value("Kind", "User"))
            }
            .chartForegroundStyleScale(["User": palette.color(.normal), "System": Color.blue])
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .chartLegend(.hidden)
            .frame(height: 70)

            if let cores = cpu?.cores, !cores.isEmpty {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(cores.enumerated()), id: \.offset) { _, load in
                        let level: Level = load * 100 >= warn ? .critical : .normal
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5).fill(palette.color(level))
                                .frame(height: max(2, 32 * load))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 32)
                .help("Per-core load")
            }
            StatRow(label: "Load average",
                    value: cpu.map { $0.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  ") } ?? Format.dash)
            ProcessListView(title: "Top processes", processes: monitor.topCPU, pending: !monitor.hasSample) {
                String(format: "%.1f%%", $0.cpu)
            }
        }
    }
}

/// Memory popover: breakdown of used/wired/compressed/cached/free, swap, and top memory processes.
struct MemoryView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @AppStorage(Settings.theme) private var theme = ColorTheme.classic.rawValue
    @AppStorage(Settings.memoryWarn) private var warn = 85.0

    var body: some View {
        let palette = ColorTheme(rawValue: theme) ?? .classic
        let mem = monitor.memory
        let level = mem.map { memoryLevel($0, warn: warn) } ?? .normal
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.percent(mem?.usedFraction)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Spacer()
                Text(pressureTitle(mem?.pressure)).font(.caption).foregroundStyle(palette.color(level))
            }
            MeterBar(fraction: mem?.usedFraction ?? 0, color: palette.color(level))
            VStack(spacing: 4) {
                StatRow(label: "Used", value: Format.memory(mem?.used))
                StatRow(label: "App", value: Format.memory(mem?.app))
                StatRow(label: "Wired", value: Format.memory(mem?.wired))
                StatRow(label: "Compressed", value: Format.memory(mem?.compressed))
                StatRow(label: "Cached files", value: Format.memory(mem?.cached))
                StatRow(label: "Free", value: Format.memory(mem?.free))
                StatRow(label: "Swap used", value: mem.map { "\(Format.memory($0.swapUsed)) of \(Format.memory($0.swapTotal))" } ?? Format.dash)
                StatRow(label: "Installed", value: Format.memory(mem?.total))
            }
            ProcessListView(title: "Top processes", processes: monitor.topMemory, pending: mem == nil) {
                Format.memory($0.memory)
            }
        }
    }

    private func pressureTitle(_ level: Int32?) -> String {
        switch level {
        case nil: return Format.dash
        case 4?: return "Pressure: critical"
        case 2?: return "Pressure: warning"
        default: return "Pressure: normal"
        }
    }
}

/// Disk popover: startup volume capacity and a read/write throughput chart.
struct DiskView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @AppStorage(Settings.theme) private var theme = ColorTheme.classic.rawValue
    @AppStorage(Settings.diskWarn) private var warn = 10.0

    var body: some View {
        let palette = ColorTheme(rawValue: theme) ?? .classic
        let disk = monitor.disk
        let level: Level = (disk?.freeFraction ?? 1) * 100 < warn ? .critical : .normal
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.disk(disk?.free)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Text("free").foregroundStyle(.secondary)
            }
            MeterBar(fraction: disk.map { 1 - $0.freeFraction } ?? 0, color: palette.color(level))
            VStack(spacing: 4) {
                StatRow(label: "Capacity", value: Format.disk(disk?.total))
                StatRow(label: "Used", value: Format.disk(disk?.used))
                StatRow(label: "Free", value: Format.disk(disk?.free))
                StatRow(label: "Read", value: Format.rate(disk?.readPerSec), color: palette.color(.normal))
                StatRow(label: "Write", value: Format.rate(disk?.writePerSec), color: .blue)
            }
            Chart(monitor.ioHistory) { point in
                LineMark(x: .value("Sample", point.id), y: .value("Bytes/s", point.read))
                    .foregroundStyle(by: .value("Kind", "Read"))
                LineMark(x: .value("Sample", point.id), y: .value("Bytes/s", point.write))
                    .foregroundStyle(by: .value("Kind", "Write"))
            }
            .chartForegroundStyleScale(["Read": palette.color(.normal), "Write": Color.blue])
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { Text(Format.rate(value.as(Double.self))) }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 80)
        }
    }
}
