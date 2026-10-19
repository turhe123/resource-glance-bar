import SwiftUI
import AppKit

/// Common 300-pt popover chrome: title, content, and a footer with Settings, Donate and Quit.
struct PopoverContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
            Divider()
            HStack {
                SettingsLink { Image(systemName: "gearshape") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                    .help("Settings")
                Spacer()
                Button("Support / Donate ❤️", action: openDonationPage)
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit ResourceGlanceBar")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { monitor.popoverOpened() }
        .onDisappear { monitor.popoverClosed() }
    }
}

/// Label/value row used in the detail grids.
struct StatRow: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack {
            if let color { Circle().fill(color).frame(width: 7, height: 7) }
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

/// Horizontal fill bar for a 0...1 fraction.
struct MeterBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// Top-five process list with an inline "Quit Process" confirmation per row.
struct ProcessListView: View {
    let title: String
    let processes: [ProcessEntry]?
    let pending: Bool
    let value: (ProcessEntry) -> String
    @EnvironmentObject private var monitor: SystemMonitor
    @State private var confirming: pid_t?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if pending {
                Text(Format.dash).foregroundStyle(.secondary)
            } else if let processes, !processes.isEmpty {
                ForEach(processes) { row($0) }
            } else {
                Text("Process list unavailable.").font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private func row(_ process: ProcessEntry) -> some View {
        HStack(spacing: 6) {
            Text(process.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            if confirming == process.pid {
                Button("Quit") {
                    error = monitor.terminate(process).map { "Couldn't quit \(process.name): \($0)" }
                    confirming = nil
                }
                .foregroundStyle(.red)
                Button("Cancel") { confirming = nil }
            } else {
                Text(value(process)).monospacedDigit().foregroundStyle(.secondary)
                Button { confirming = process.pid } label: { Image(systemName: "xmark.circle") }
                    .disabled(process.isProtected)
                    .help(process.isProtected ? "System processes can't be quit" : "Quit Process…")
            }
        }
        .font(.callout)
        .buttonStyle(.borderless)
    }
}
