import Foundation
import AppKit

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let library = home.appendingPathComponent("Library")

    static func home(_ path: String) -> URL { home.appendingPathComponent(path) }
    static func library(_ path: String) -> URL { library.appendingPathComponent(path) }
}

enum FileSizer {
    static let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    /// Bir dosyanın ya da klasörün diskte kapladığı toplam alan (sembolik linkler takip edilmez).
    static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return fileSize(url) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += fileSize(file)
        }
        return total
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    /// Klasörün doğrudan alt öğelerini boyutlarıyla döndürür.
    static func children(
        of dir: URL,
        base: SafetyLevel = .review,
        skipping skipped: Set<String> = [".DS_Store", ".localized"]
    ) -> [CleanableItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return contents
            .filter { !skipped.contains($0.lastPathComponent) }
            .map { CleanableItem(url: $0, size: size(of: $0), base: base) }
            .filter { $0.size > 0 }
    }
}

/// Dosyaları silmenin tek yolu. Varsayılan olarak her şey Çöp Sepeti'ne taşınır, böylece geri alınabilir.
/// Yasaklı yollar hiçbir koşulda, kritik yollar ise yalnızca koruma kilidi açıkken silinir.
enum Trasher {
    struct Outcome {
        var removed: Set<URL> = []
        var failures: [String] = []
    }

    enum Method { case trash, permanent, shred }

    @MainActor
    /// `sizes`: bilinen boyutlar; yalnızca silme geçmişinde gösterilmek için.
    static func remove(_ urls: [URL], method: Method = .trash, sizes: [URL: Int64] = [:]) async -> Outcome {
        var outcome = Outcome()
        var log: [DeletionLog.Entry] = []
        defer { DeletionLog.shared.record(log) }

        for url in urls {
            if Exclusions.shared.contains(url) {
                outcome.failures.append("\(url.lastPathComponent): hariç tutulanlar listesinde, atlandı")
                continue
            }
            if SafetyPolicy.isForbidden(url) {
                outcome.failures.append("\(url.path): sistem için zorunlu konum, silinemez")
                continue
            }
            if let reason = SafetyPolicy.criticalReason(for: url), !ProtectionLock.shared.isUnlocked {
                outcome.failures.append("\(url.lastPathComponent): kilitli (\(reason))")
                continue
            }
            do {
                // Simülatör cihazları her zaman simctl ile silinir; elle silmek CoreSimulator'ı bozar.
                var trashedURL: URL?
                let logged: DeletionLog.Entry.Method
                if Simulators.isDeviceFolder(url) {
                    let udid = url.lastPathComponent
                    try await Task.detached(priority: .userInitiated) { try Simulators.delete(udid: udid) }.value
                    logged = .simulator
                } else {
                    switch method {
                    case .trash:
                        // NSWorkspace, gerekirse (ör. root'a ait uygulamalar) yönetici parolası ister.
                        trashedURL = try await NSWorkspace.shared.recycle([url])[url]
                        logged = .trash
                    case .permanent:
                        try FileManager.default.removeItem(at: url)
                        logged = .permanent
                    case .shred:
                        try await Task.detached(priority: .userInitiated) { try Shredder.shred(url) }.value
                        logged = .shred
                    }
                }
                outcome.removed.insert(url)
                log.append(DeletionLog.Entry(
                    date: Date(), originalPath: url.path, trashedPath: trashedURL?.path, size: sizes[url], method: logged
                ))
            } catch {
                outcome.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return outcome
    }
}

/// Dosyaların üzerine rastgele veri yazıp siler.
enum Shredder {
    static func shred(_ url: URL) throws {
        let fm = FileManager.default
        // attributesOfItem sembolik linkleri takip etmez: link ise yalnızca linkin kendisi silinir,
        // işaret ettiği klasöre veya dosyaya asla dokunulmaz.
        guard let type = try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else { return }
        switch type {
        case .typeDirectory:
            for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try shred(child) }
        case .typeRegular:
            try overwrite(url)
        default:
            break
        }
        try fm.removeItem(at: url)
    }

    private static func overwrite(_ url: URL) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let chunkSize = 1024 * 1024
        var written = 0
        while written < size {
            let count = min(chunkSize, size - written)
            var bytes = [UInt8](repeating: 0, count: count)
            _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
            try handle.write(contentsOf: bytes)
            written += count
        }
        try handle.synchronize()
        try handle.truncate(atOffset: 0)
    }
}

enum SystemInfo {
    struct Disk { let total: Int64; let available: Int64; var used: Int64 { total - available } }
    struct Memory { let total: UInt64; let used: UInt64 }

    static func disk() -> Disk? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Disk(total: Int64(total), available: available)
    }

    static func memory() -> Memory {
        let stats = MemoryMonitor.stats()
        return Memory(total: stats.total, used: stats.used)
    }

    /// Tam Disk Erişimi verilmiş mi? Safari klasörü bu izin olmadan okunamaz.
    static var hasFullDiskAccess: Bool {
        // Bu konumlar yalnızca Tam Disk Erişimi ile okunabilir; biri bile okunabiliyorsa izin var demektir.
        if (try? FileManager.default.contentsOfDirectory(atPath: Paths.library("Safari").path)) != nil { return true }
        if let handle = FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") {
            try? handle.close()
            return true
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
