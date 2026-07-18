import Foundation
import Darwin

// CPU and memory usage via the same public Mach host APIs Activity Monitor
// itself is built on; no private frameworks, no entitlements.
enum SystemMeter {
    // In practice only ever touched serially, from whichever thread is
    // rendering a tile/knob at a given moment; worst case on a genuine race
    // is one momentarily-off percentage, never a crash, so opting out of
    // strict-concurrency isolation here is a fair trade against making
    // every TileRenderer call site (itself nonisolated, called from several
    // different Tasks) async just to read one cached struct.
    nonisolated(unsafe) private static var lastCPUTicks: host_cpu_load_info?

    /// Fraction (0...1) of total CPU used since the last call. The first
    /// call after launch has nothing to diff against, so returns 0.
    static func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        defer { lastCPUTicks = info }
        guard result == KERN_SUCCESS, let last = lastCPUTicks else { return 0 }

        let user = Double(info.cpu_ticks.0 &- last.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- last.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- last.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- last.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return (user + system + nice) / total
    }

    /// Fraction (0...1) of physical memory in use (active + wired +
    /// compressed pages), roughly matching Activity Monitor's "Memory Used".
    static func memoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(getpagesize())
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return used / total
    }
}
