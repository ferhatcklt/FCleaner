import Foundation
import Observation

/// FCleaner'ın sildiği her şeyin kaydı. Çöp Sepeti'ne taşınanlar buradan geri yüklenebilir.
@MainActor
@Observable
final class DeletionLog {
    static let shared = DeletionLog()
    static let maxEntries = 2000

    struct Entry: Codable, Identifiable, Equatable {
        enum Method: String, Codable {
            case trash, permanent, shred, simulator

            var title: String {
                switch self {
                case .trash: "Çöp Sepeti"
                case .permanent: "Kalıcı silindi"
                case .shred: "Parçalandı"
                case .simulator: "Simülatör silindi"
                }
            }
        }

        var id = UUID()
        let date: Date
        let originalPath: String
        /// Çöp Sepeti'ndeki yeni konumu; yalnızca `.trash` için.
        let trashedPath: String?
        let size: Int64?
        let method: Method

        var name: String { URL(fileURLWithPath: originalPath).lastPathComponent }

        /// Çöp Sepeti'nde hâlâ duruyorsa geri yüklenebilir.
        var canRestore: Bool {
            guard method == .trash, let trashedPath else { return false }
            return FileManager.default.fileExists(atPath: trashedPath)
        }
    }

    private(set) var entries: [Entry] = []
    private let fileURL: URL

    init(fileURL: URL = Paths.library("Application Support/FCleaner/history.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.iso.decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func record(_ newEntries: [Entry]) {
        guard !newEntries.isEmpty else { return }
        entries.insert(contentsOf: newEntries.reversed(), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        save()
    }

    enum RestoreError: LocalizedError {
        case notInTrash, destinationExists(String)
        var errorDescription: String? {
            switch self {
            case .notInTrash: "Öğe artık Çöp Sepeti'nde değil."
            case .destinationExists(let path): "Eski konumda aynı adlı bir öğe var: \(path)"
            }
        }
    }

    /// Çöp Sepeti'ndeki öğeyi eski yerine taşır.
    func restore(_ entry: Entry) throws {
        guard entry.canRestore, let trashedPath = entry.trashedPath else { throw RestoreError.notInTrash }
        let fm = FileManager.default
        let destination = URL(fileURLWithPath: entry.originalPath)
        if fm.fileExists(atPath: destination.path) { throw RestoreError.destinationExists(destination.path) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: URL(fileURLWithPath: trashedPath), to: destination)
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.iso.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // Geçmiş kaydedilemese de silme işlemi engellenmez.
        }
    }
}

/// Kullanıcının "asla dokunma" dediği klasör ve dosyalar. Taramalarda gösterilmez, silinemez.
///
/// Arka plandaki tarayıcılar da okuduğu için kilitle korunur; gözlem elle bildirilir.
final class Exclusions: Observable, @unchecked Sendable {
    static let shared = Exclusions()

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "excludedPaths"
    private var storage: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storage = defaults.stringArray(forKey: key) ?? []
    }

    /// SwiftUI'nin değişiklikleri izlemesi için.
    var paths: [String] {
        registrar.access(self, keyPath: \.paths)
        return lock.withLock { storage }
    }

    func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        update { list in
            guard !list.contains(path) else { return }
            list.append(path)
            list.sort()
        }
    }

    func remove(_ path: String) {
        update { $0.removeAll { $0 == path } }
    }

    /// Kendisi ya da bir üst klasörü hariç tutulmuş mu?
    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return lock.withLock { storage }.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func update(_ change: (inout [String]) -> Void) {
        registrar.withMutation(of: self, keyPath: \.paths) {
            lock.withLock {
                change(&storage)
                defaults.set(storage, forKey: key)
            }
        }
    }
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
