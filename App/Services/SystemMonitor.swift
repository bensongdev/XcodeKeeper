import Darwin
import Foundation

/// 메모리·스왑·프로세스 정보를 읽는다. 테스트와 UI 테스트에서는 고정값 구현을 쓴다.
protocol SystemMonitoring: Sendable {
    /// 메모리 통계, 압박 단계, 스왑. 읽지 못하면 nil.
    func snapshot() -> MemorySnapshot?
    /// 메모리 사용량 상위 프로세스. 비용이 있으므로 팝오버가 열려 있을 때만 부른다.
    func topProcesses(limit: Int) -> [ProcessMemory]
}

/// 실제 시스템 값을 읽는다. 모두 읽기 전용 C API다.
struct LiveSystemMonitor: SystemMonitoring {
    func snapshot() -> MemorySnapshot? {
        guard let stats = Self.vmStatistics(), let total = Self.sysctlValue("hw.memsize", as: UInt64.self) else {
            return nil
        }
        return MemorySnapshot.make(
            totalBytes: total, pageSize: UInt64(getpagesize()),
            pages: MemorySnapshot.PageCounts(
                internalPages: UInt64(stats.internal_page_count), purgeablePages: UInt64(stats.purgeable_count),
                wiredPages: UInt64(stats.wire_count), compressedPages: UInt64(stats.compressor_page_count)
            ),
            swap: Self.sysctlValue("vm.swapusage", as: xsw_usage.self).map {
                SwapUsage(used: $0.xsu_used, total: $0.xsu_total)
            },
            pressureLevel: Self.sysctlValue("kern.memorystatus_vm_pressure_level", as: Int32.self)
        )
    }

    func topProcesses(limit: Int) -> [ProcessMemory] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        // 그 사이 프로세스가 늘어날 수 있어 여유를 둔다.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        let processes = pids.prefix(Int(count)).compactMap { pid -> ProcessMemory? in
            guard pid > 0, let footprint = Self.footprint(of: pid), let name = Self.name(of: pid) else { return nil }
            return ProcessMemory(pid: pid, name: name, bytes: Int64(clamping: footprint))
        }
        return ProcessMemory.top(processes, limit: limit)
    }

    private static func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    private static func sysctlValue<T>(_ name: String, as type: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard sysctlbyname(name, pointer, &size, nil, 0) == 0, size == MemoryLayout<T>.size else { return nil }
        return pointer.load(as: T.self)
    }

    /// 같은 사용자의 프로세스만 읽힌다. 권한이 없으면 nil.
    private static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// 실행 파일 이름(proc_name은 16자에서 잘리므로 경로의 마지막 부분을 쓴다).
    private static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}

/// 고정값을 돌려주는 모니터(단위 테스트, UI 테스트, 스냅샷).
struct FixedSystemMonitor: SystemMonitoring {
    var memory: MemorySnapshot?
    var processes: [ProcessMemory] = []

    func snapshot() -> MemorySnapshot? { memory }
    func topProcesses(limit: Int) -> [ProcessMemory] { ProcessMemory.top(processes, limit: limit) }
}
