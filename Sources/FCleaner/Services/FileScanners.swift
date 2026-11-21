import Foundation
import CryptoKit

/// Ev klasörünü gezer; ~/Library ve gizli dosyalar atlanır (bunlar Sistem Çöpü'nün işi).
enum HomeWalker {
    static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]

    static func walk(_ root: URL = Paths.home, visit: (URL, URLResourceValues) -> Bool) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        let skipped: Set<String> = [Paths.library.path, Paths.home(".Trash").path]
        for case let url as URL in enumerator {
            if skipped.contains(url.path) || Exclusions.shared.contains(url) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            if !visit(url, values) { return }
        }
    }
}

enum LargeFileScanner {
    static func scan(minSize: Int64, progress: @escaping @Sendable (Int) -> Void) -> [LargeFile] {
        var results: [LargeFile] = []
        var scanned = 0
        HomeWalker.walk { url, values in
            scanned += 1
            if scanned % 500 == 0 { progress(scanned) }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size >= minSize {
                results.append(LargeFile(url: url, size: size, modified: values.contentModificationDate))
            }
            return !Task.isCancelled
        }
        progress(scanned)
        return results.sorted { $0.size > $1.size }
    }
}

enum DuplicateScanner {
    static func scan(minSize: Int64, progress: @escaping @Sendable (String) -> Void) -> [DuplicateGroup] {
        // 1) Aynı boyuttaki dosyaları grupla.
        var bySize: [Int64: [URL]] = [:]
        var scanned = 0
        HomeWalker.walk { url, values in
            scanned += 1
            if scanned % 500 == 0 { progress("\(scanned) dosya tarandı…") }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size >= minSize { bySize[size, default: []].append(url) }
            return !Task.isCancelled
        }
        let candidates = bySize.filter { $0.value.count > 1 }

        // 2) Önce ilk 64 KB'a, eşleşenlerde tüm içeriğe göre SHA-256 karşılaştır.
        var groups: [DuplicateGroup] = []
        var checked = 0
        for (size, urls) in candidates {
            if Task.isCancelled { break }
            checked += 1
            progress("İçerikler karşılaştırılıyor (\(checked)/\(candidates.count))…")

            let byPrefix = Dictionary(grouping: urls) { hash($0, limit: 64 * 1024) ?? UUID().uuidString }
            for (_, sameStart) in byPrefix where sameStart.count > 1 {
                let byFull = Dictionary(grouping: sameStart) { hash($0, limit: nil) ?? UUID().uuidString }
                for (digest, files) in byFull where files.count > 1 {
                    let sorted = files.sorted { creationDate($0) < creationDate($1) }
                    groups.append(DuplicateGroup(id: digest, size: size, files: sorted))
                }
            }
        }
        return groups.sorted { $0.wastedSize > $1.wastedSize }
    }

    private static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? .max
        while remaining > 0 {
            let chunk = min(1024 * 1024, remaining)
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
    }
}
