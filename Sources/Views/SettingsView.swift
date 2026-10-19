import SwiftUI
import ServiceManagement

/// Settings window: visible items, refresh rate, display mode, thresholds, theme and launch at login.
struct SettingsView: View {
    @AppStorage(Settings.showCPU) private var showCPU = true
    @AppStorage(Settings.showMemory) private var showMemory = true
    @AppStorage(Settings.showDisk) private var showDisk = true
    @AppStorage(Settings.interval) private var interval = 2
    @AppStorage(Settings.displayMode) private var mode = DisplayMode.graph.rawValue
    @AppStorage(Settings.cpuWarn) private var cpuWarn = 80.0
    @AppStorage(Settings.memoryWarn) private var memoryWarn = 85.0
    @AppStorage(Settings.diskWarn) private var diskWarn = 10.0
    @AppStorage(Settings.theme) private var theme = ColorTheme.classic.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    /// Prevents hiding the last item, which would leave no way back into the app.
    private var enabledCount: Int { [showCPU, showMemory, showDisk].filter { $0 }.count }

    var body: some View {
        Form {
            Section("Menu bar items") {
                Toggle("CPU", isOn: $showCPU).disabled(showCPU && enabledCount == 1)
                Toggle("Memory", isOn: $showMemory).disabled(showMemory && enabledCount == 1)
                Toggle("Disk", isOn: $showDisk).disabled(showDisk && enabledCount == 1)
                Picker("CPU display", selection: $mode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Update interval", selection: $interval) {
                    Text("1 s").tag(1); Text("2 s").tag(2); Text("5 s").tag(5)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Updates slow to every 5 seconds while no dropdown is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Warning thresholds") {
                threshold("CPU load above", value: $cpuWarn, range: 50...100)
                threshold("Memory used above", value: $memoryWarn, range: 50...100)
                threshold("Disk free below", value: $diskWarn, range: 1...50)
            }
            Section("Appearance") {
                Picker("Color theme", selection: $theme) {
                    ForEach(ColorTheme.allCases) { palette in
                        HStack {
                            ForEach([Level.normal, .warning, .critical], id: \.self) {
                                Circle().fill(palette.color($0)).frame(width: 8, height: 8)
                            }
                            Text(palette.title)
                        }
                        .tag(palette.rawValue)
                    }
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Support / Donate ❤️", action: openDonationPage)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func threshold(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: 5)
            Text("\(Int(value.wrappedValue))%").monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription). "
                + "You can manage it in System Settings › General › Login Items."
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}
