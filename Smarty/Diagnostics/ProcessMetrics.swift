import Darwin
import Foundation

/// One point-in-time reading of this process's resource usage.
struct ProcessMetricsSnapshot: Equatable, Sendable {
    /// Percent of one core; can exceed 100 on multi-core work, matching Activity Monitor.
    var cpuPercent: Double
    /// `phys_footprint` — the number Activity Monitor shows as "Memory".
    var memoryFootprintBytes: UInt64
    var threadCount: Int
    var uptime: TimeInterval

    static let empty = ProcessMetricsSnapshot(cpuPercent: 0, memoryFootprintBytes: 0, threadCount: 0, uptime: 0)
}

/// Samples CPU from rusage deltas, so the first reading after creation reports 0%.
struct ProcessMetricsSampler {
    private var lastCPUTime: TimeInterval?
    private var lastWallTime: TimeInterval?
    private let launchDate: Date

    init(launchDate: Date = Self.processStartDate() ?? Date()) {
        self.launchDate = launchDate
    }

    mutating func sample(now: Date = Date()) -> ProcessMetricsSnapshot {
        let cpuTime = Self.totalCPUTime()
        let wallTime = ProcessInfo.processInfo.systemUptime

        var cpuPercent = 0.0
        if let lastCPUTime, let lastWallTime, wallTime > lastWallTime {
            cpuPercent = Self.cpuPercent(cpuDelta: cpuTime - lastCPUTime, wallDelta: wallTime - lastWallTime)
        }
        lastCPUTime = cpuTime
        lastWallTime = wallTime

        return ProcessMetricsSnapshot(
            cpuPercent: cpuPercent,
            memoryFootprintBytes: Self.memoryFootprint() ?? 0,
            threadCount: Self.threadCount() ?? 0,
            uptime: max(0, now.timeIntervalSince(launchDate))
        )
    }

    static func cpuPercent(cpuDelta: TimeInterval, wallDelta: TimeInterval) -> Double {
        guard wallDelta > 0, cpuDelta >= 0 else { return 0 }
        return cpuDelta / wallDelta * 100
    }

    // MARK: - Darwin probes

    private static func totalCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ tv: timeval) -> TimeInterval {
            TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func memoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private static func threadCount() -> Int? {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return nil }
        // task_threads hands back one send right per thread plus an out-of-line array we own.
        for index in 0..<Int(count) {
            mach_port_deallocate(mach_task_self_, threads[index])
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threads)),
            vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)
        )
        return Int(count)
    }

    private static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
