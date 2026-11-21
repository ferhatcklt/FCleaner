import Foundation
import Darwin

/// Etkinlik Monitörü'ndeki Bellek sekmesiyle aynı kalemler.
struct MemoryStats: Sendable, Equatable {
    let total: UInt64
    /// Uygulamaların kullandığı bellek.
    let app: UInt64
    /// Çekirdeğin ayırdığı, diske yazılamayan bellek.
    let wired: UInt64
    /// Yer açmak için sıkıştırılmış bellek.
    let compressed: UInt64
    /// Diskten okunan dosyaların önbelleği; gerektiğinde anında boşaltılır.
    let cached: UInt64
    let free: UInt64
    let swapUsed: UInt64

    /// Etkinlik Monitörü'ndeki "Kullanılan Bellek".
    var used: UInt64 { min(app + wired + compressed, total) }

    enum Pressure { case low, medium, high }

    var pressure: Pressure {
        let ratio = Double(used) / Double(max(total, 1))
        if ratio > 0.85 || swapUsed > total / 4 { return .high }
        if ratio > 0.7 { return .medium }
        return .low
    }
}

/// Bir uygulamanın (yardımcı işlemleriyle birlikte) kullandığı bellek.
struct AppMemoryUsage: Identifiable, Sendable, Equatable {
    /// Uygulama paketinin ya da çalıştırılabilir dosyanın yolu.
    let id: String
    let name: String
    let bundleURL: URL?
    let pids: [pid_t]
    let footprint: UInt64

    var processCount: Int { pids.count }
}

enum MemoryMonitor {
    static func stats() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryStats(total: total, app: 0, wired: 0, compressed: 0, cached: 0, free: total, swapUsed: 0)
        }
        let page = UInt64(vm_kernel_page_size)
        let anonymous = UInt64(vm.internal_page_count)
        let purgeable = UInt64(vm.purgeable_count)
        return MemoryStats(
            total: total,
            app: (anonymous > purgeable ? anonymous - purgeable : 0) * page,
            wired: UInt64(vm.wire_count) * page,
            compressed: UInt64(vm.compressor_page_count) * page,
            cached: (UInt64(vm.external_page_count) + purgeable) * page,
            free: UInt64(vm.free_count) * page,
            swapUsed: swapUsed()
        )
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// Kullanıcının işlemlerini uygulamalarına göre gruplayıp bellek kullanımını döndürür.
    /// Root'a ait sistem işlemleri yönetici izni olmadan okunamaz ve listede yer almaz.
    static func appUsage() -> [AppMemoryUsage] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let found = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        guard found > 0 else { return [] }

        struct Group { var name: String; var bundleURL: URL?; var pids: [pid_t] = []; var footprint: UInt64 = 0 }
        var groups: [String: Group] = [:]

        for pid in pids.prefix(Int(found)) where pid > 0 {
            guard let footprint = footprint(of: pid), footprint > 0, let path = executablePath(of: pid) else { continue }
            let key: String
            let group: Group
            if let app = outermostAppBundle(in: path) {
                // Chrome Helper gibi yardımcı işlemler ana uygulamanın altında toplanır.
                key = app
                group = groups[key] ?? Group(
                    name: FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: ""),
                    bundleURL: URL(fileURLWithPath: app)
                )
            } else {
                key = path
                group = groups[key] ?? Group(name: URL(fileURLWithPath: path).lastPathComponent, bundleURL: nil)
            }
            var updated = group
            updated.pids.append(pid)
            updated.footprint += footprint
            groups[key] = updated
        }

        return groups.map { key, group in
            AppMemoryUsage(id: key, name: group.name, bundleURL: group.bundleURL, pids: group.pids, footprint: group.footprint)
        }
    }

    /// Etkinlik Monitörü'nün "Bellek" sütunundaki değer (phys_footprint).
    private static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…" → "/Applications/Google Chrome.app"
    static func outermostAppBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
