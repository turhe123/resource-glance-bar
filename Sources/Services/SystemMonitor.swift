import Foundation
import Combine
import Darwin

/// A point in the disk-throughput history chart.
struct IOPoint: Identifiable {
    let id: Int
    let read: Double
    let write: Double
}

/// A point in the CPU history chart.
struct LoadPoint: Identifiable {
    let id: Int
    let user: Double
    let system: Double
}

/// Owns the single background sampling timer and publishes results to the main actor.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    static let historyLength = 60

    @Published private(set) var cpu: CPUSnapshot?
    @Published private(set) var memory: MemorySnapshot?
    @Published private(set) var disk: DiskSnapshot?
    @Published private(set) var topCPU: [ProcessEntry]?
    @Published private(set) var topMemory: [ProcessEntry]?
    @Published private(set) var cpuHistory: [LoadPoint] = []
    @Published private(set) var ioHistory: [IOPoint] = []
    /// True once at least one complete sample has arrived.
    @Published private(set) var hasSample = false

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "com.turhe123.resourceglancebar.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var currentInterval: Double = 0
    private var openPopovers = 0
    private var tick = 0
    private var defaultsObserver: AnyCancellable?

    private init() {
        reschedule(force: true)
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reschedule() }
    }

    /// User-selected interval when a popover is visible; never faster than 5 s otherwise to stay under 1% CPU.
    private var desiredInterval: Double {
        let setting = Double(UserDefaults.standard.integer(forKey: Settings.interval))
        let chosen = [1.0, 2.0, 5.0].contains(setting) ? setting : 2
        return openPopovers > 0 ? chosen : max(chosen, 5)
    }

    func popoverOpened() {
        openPopovers += 1
        reschedule()
    }

    func popoverClosed() {
        openPopovers = max(0, openPopovers - 1)
        reschedule()
    }

    private func reschedule(force: Bool = false) {
        let interval = desiredInterval
        guard force || interval != currentInterval else { return }
        currentInterval = interval
        timer?.cancel()

        let sampler = self.sampler
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 0.05, repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        source.setEventHandler {
            guard let sample = sampler.sample(expectedInterval: interval) else { return }
            Task { @MainActor in SystemMonitor.shared.apply(sample) }
        }
        source.resume()
        timer = source
    }

    private func apply(_ sample: Sample) {
        tick += 1
        memory = sample.memory
        topMemory = sample.topMemory
        if let newCPU = sample.cpu {
            cpu = newCPU
            topCPU = sample.topCPU
            cpuHistory.append(LoadPoint(id: tick, user: newCPU.user, system: newCPU.system))
            if cpuHistory.count > Self.historyLength { cpuHistory.removeFirst(cpuHistory.count - Self.historyLength) }
        }
        if let newDisk = sample.disk {
            disk = newDisk
            if let r = newDisk.readPerSec, let w = newDisk.writePerSec {
                ioHistory.append(IOPoint(id: tick, read: r, write: w))
                if ioHistory.count > Self.historyLength { ioHistory.removeFirst(ioHistory.count - Self.historyLength) }
            }
        }
        if sample.cpu != nil { hasSample = true }
    }

    /// Sends SIGTERM to a process owned by the current user. Returns an error message on failure.
    func terminate(_ process: ProcessEntry) -> String? {
        guard !process.isProtected else { return "System processes can't be quit." }
        if kill(process.pid, SIGTERM) == 0 { return nil }
        return String(cString: strerror(errno))
    }
}
