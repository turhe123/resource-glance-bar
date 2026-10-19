import Foundation
import Darwin
import IOKit

/// CPU load derived from per-core tick deltas between two samples.
struct CPUSnapshot {
    var user: Double
    var system: Double
    var cores: [Double]
    var loadAverage: [Double]
    var total: Double { min(1, user + system) }
}

/// Memory breakdown in bytes, using the same categories as Activity Monitor.
struct MemorySnapshot {
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cached: UInt64
    var free: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    /// 1 = normal, 2 = warning, 4 = critical (kern.memorystatus_vm_pressure_level).
    var pressure: Int32
    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

/// Startup volume capacity plus aggregate block-device throughput.
struct DiskSnapshot {
    var total: Int64
    var free: Int64
    var readPerSec: Double?
    var writePerSec: Double?
    var used: Int64 { max(0, total - free) }
    var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 0 }
}

/// One readable process with its CPU share (percent of one core) and resident memory.
struct ProcessEntry: Identifiable, Equatable {
    var pid: pid_t
    var name: String
    var cpu: Double
    var memory: UInt64
    /// Root-owned or unidentifiable processes may never be quit from the UI.
    var isProtected: Bool
    var id: pid_t { pid }
}

/// Everything gathered in one timer tick.
struct Sample {
    var cpu: CPUSnapshot?
    var memory: MemorySnapshot?
    var disk: DiskSnapshot?
    var topCPU: [ProcessEntry]?
    var topMemory: [ProcessEntry]?
}

/// Reads raw counters from Mach, sysctl, IOKit and libproc. Not thread-safe: use from one serial queue.
final class Sampler {
    private var prevCoreTicks: [[UInt32]] = []
    private var prevIO: (read: UInt64, write: UInt64)?
    private var prevProcTimes: [pid_t: UInt64] = [:]
    private var lastTime: Date?
    private let nanosPerTick: Double
    private let ownPid = getpid()

    init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        nanosPerTick = tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }

    /// Takes a sample. Returns nil (after re-priming baselines) when the gap since the
    /// last sample is far longer than expected, e.g. after the Mac woke from sleep.
    func sample(expectedInterval: Double) -> Sample? {
        let now = Date()
        let elapsed = lastTime.map { now.timeIntervalSince($0) } ?? 0
        lastTime = now
        if elapsed > max(expectedInterval, 5) * 3 {
            prevCoreTicks = []; prevIO = nil; prevProcTimes = [:]
            _ = readCPU(); _ = readIO(elapsed: 0); _ = readProcesses(elapsed: 0)
            return nil
        }
        let procs = readProcesses(elapsed: elapsed)
        var disk = readDisk()
        if let io = readIO(elapsed: elapsed) {
            disk?.readPerSec = io.0
            disk?.writePerSec = io.1
        }
        return Sample(cpu: readCPU(), memory: readMemory(), disk: disk,
                      topCPU: procs.map { Array($0.sorted { $0.cpu > $1.cpu }.prefix(5)) },
                      topMemory: procs.map { Array($0.sorted { $0.memory > $1.memory }.prefix(5)) })
    }

    // MARK: CPU

    private func readCPU() -> CPUSnapshot? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        let ticks: [[UInt32]] = (0..<Int(cpuCount)).map { core in
            (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
        }
        defer { prevCoreTicks = ticks }
        guard prevCoreTicks.count == ticks.count else { return nil }

        var cores: [Double] = []
        var user = 0.0, system = 0.0, all = 0.0
        for (cur, old) in zip(ticks, prevCoreTicks) {
            let d = { (i: Int32) in Double(cur[Int(i)] &- old[Int(i)]) }
            let u = d(CPU_STATE_USER) + d(CPU_STATE_NICE), s = d(CPU_STATE_SYSTEM)
            let total = u + s + d(CPU_STATE_IDLE)
            cores.append(total > 0 ? (u + s) / total : 0)
            user += u; system += s; all += total
        }
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) != 3 { load = [] }
        return CPUSnapshot(user: all > 0 ? user / all : 0, system: all > 0 ? system / all : 0,
                           cores: cores, loadAverage: load)
    }

    // MARK: Memory

    private func readMemory() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let anonymous = UInt64(stats.internal_page_count), purgeable = UInt64(stats.purgeable_count)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) != 0 { swap = xsw_usage() }
        var pressure: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) != 0 { pressure = 1 }

        return MemorySnapshot(
            total: ProcessInfo.processInfo.physicalMemory,
            app: (anonymous > purgeable ? anonymous - purgeable : 0) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page,
            free: UInt64(stats.free_count) * page,
            swapUsed: swap.xsu_used, swapTotal: swap.xsu_total, pressure: pressure)
    }

    // MARK: Disk

    private func readDisk() -> DiskSnapshot? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSnapshot(total: Int64(total), free: free)
    }

    /// Bytes/second read and written across all IOBlockStorageDriver instances.
    private func readIO(elapsed: Double) -> (Double, Double)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, written: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        defer { prevIO = (read, written) }
        guard let prev = prevIO, elapsed > 0, read >= prev.read, written >= prev.write else { return nil }
        return (Double(read - prev.read) / elapsed, Double(written - prev.write) / elapsed)
    }

    // MARK: Processes

    /// All processes readable by this user; nil if the process table itself can't be listed.
    private func readProcesses(elapsed: Double) -> [ProcessEntry]? {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.size + 64)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return nil }

        var entries: [ProcessEntry] = []
        var times: [pid_t: UInt64] = [:]
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size), bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where pid > 0 {
            var task = proc_taskinfo()
            // Processes of other users are usually unreadable: skip them silently.
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else { continue }
            var bsd = proc_bsdinfo()
            let hasBSD = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize

            let cpuTime = task.pti_total_user + task.pti_total_system
            times[pid] = cpuTime
            var cpu = 0.0
            if let old = prevProcTimes[pid], cpuTime >= old, elapsed > 0 {
                cpu = Double(cpuTime - old) * nanosPerTick / 1e9 / elapsed * 100
            }
            entries.append(ProcessEntry(pid: pid, name: processName(pid), cpu: cpu,
                                        memory: task.pti_resident_size,
                                        isProtected: !hasBSD || bsd.pbi_uid == 0 || pid == ownPid))
        }
        prevProcTimes = times
        return entries
    }

    private func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            return String(cString: buffer)
        }
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            return (String(cString: buffer) as NSString).lastPathComponent
        }
        return "pid \(pid)"
    }
}
