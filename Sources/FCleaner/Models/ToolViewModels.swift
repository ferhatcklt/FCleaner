import Foundation
import AppKit
import Observation

/// Disk Analizcisi ağacındaki bir dosya veya klasör. Alt öğeler ilk açılışta yüklenir.
@MainActor
@Observable
final class DiskNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    let modified: Date?
    var size: Int64?
    /// nil: henüz yüklenmedi.
    var children: [DiskNode]?
    var isExpanded = false
    var isLoading = false
    /// Ad yanında gösterilecek açıklama (ör. simülatör cihazının adı).
    var label: String?
    weak var parent: DiskNode?

    nonisolated var id: URL { url }
    var name: String { url.lastPathComponent }
    var safety: SafetyLevel { SafetyPolicy.level(for: url) }
    var depth: Int { parent.map { $0.depth + 1 } ?? 0 }

    init(url: URL, isDirectory: Bool, modified: Date?, size: Int64? = nil, parent: DiskNode? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.modified = modified
        self.size = size
        self.parent = parent
    }
}

@MainActor
@Observable
final class DiskAnalyzerViewModel {
    private(set) var root: DiskNode
    var sort = SortState()
    var errors: [String] = []
    private(set) var pendingCount = 0
    private var cache: [URL: Int64] = [:]
    private var started = false

    var isCalculating: Bool { pendingCount > 0 }

    init() {
        root = DiskNode(url: Paths.home, isDirectory: true, modified: nil)
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        setRoot(Paths.home)
    }

    func setRoot(_ url: URL) {
        root = DiskNode(url: url, isDirectory: true, modified: nil)
        root.isExpanded = true
        loadChildren(of: root)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Analiz Et"
        if panel.runModal() == .OK, let url = panel.url { setRoot(url) }
    }

    func refresh() {
        cache = [:]
        setRoot(root.url)
    }

    func sortedChildren(of node: DiskNode) -> [DiskNode] {
        (node.children ?? []).sorted(sort, size: { $0.size ?? -1 }, name: \.name, date: \.modified)
    }

    /// Ağacın ekranda görünen satırları: açık klasörlerin alt öğeleri, seçili sıralamayla düzleştirilmiş.
    var visibleNodes: [DiskNode] {
        var result: [DiskNode] = []
        func walk(_ node: DiskNode) {
            for child in sortedChildren(of: node) {
                result.append(child)
                if child.isExpanded { walk(child) }
            }
        }
        walk(root)
        return result
    }

    /// Kökten yukarıya doğru üst klasörler (yol çubuğu için).
    var rootAncestors: [URL] { Self.ancestors(of: root.url) }

    nonisolated static func ancestors(of url: URL) -> [URL] {
        // "/" için deletingLastPathComponent "/.." döndürdüğünden yol bileşenlerinden kurulur.
        var current = URL(fileURLWithPath: "/")
        var urls = [current]
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            urls.append(current)
        }
        return urls
    }

    func collapseAll() {
        func walk(_ node: DiskNode) {
            for child in node.children ?? [] {
                child.isExpanded = false
                walk(child)
            }
        }
        walk(root)
    }

    func toggle(_ node: DiskNode) {
        guard node.isDirectory else { return }
        node.isExpanded.toggle()
        if node.isExpanded { loadChildren(of: node) }
    }

    /// Klasörün içeriğini arka planda listeler, ardından alt klasörlerin boyutlarını paralel olarak hesaplar.
    func loadChildren(of node: DiskNode) {
        guard node.children == nil, !node.isLoading else { return }
        node.isLoading = true
        let url = node.url
        Task {
            let entries = await Task.detached(priority: .userInitiated) { Self.listEntries(of: url) }.value
            let children = entries.map { entry in
                DiskNode(
                    url: entry.url,
                    isDirectory: entry.isFolder,
                    modified: entry.modified,
                    size: entry.fileSize ?? cache[entry.url],
                    parent: node
                )
            }
            node.children = children
            node.isLoading = false
            if url.standardizedFileURL.path == Simulators.devicesDir.standardizedFileURL.path {
                labelSimulators(children)
            }
            await computeSizes(of: children, in: node)
        }
    }

    private struct Entry: Sendable {
        let url: URL
        let isFolder: Bool
        let modified: Date?
        /// Düz dosyalar için hemen okunan boyut; klasör ve paketlerde nil (hesaplanması gerekir).
        let fileSize: Int64?
    }

    private nonisolated static func listEntries(of dir: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return nil }
            let isDirectory = values.isDirectory == true
            return Entry(
                url: url,
                isFolder: isDirectory && values.isPackage != true,
                modified: values.contentModificationDate,
                fileSize: isDirectory ? nil : FileSizer.fileSize(url)
            )
        }
    }

    /// Sonuçlar tek tek değil ~150 ms'lik gruplar halinde uygulanır; her güncelleme tüm ağacı yeniden sıralattığı için.
    private func computeSizes(of children: [DiskNode], in node: DiskNode) async {
        let pending = children.filter { $0.size == nil }
        guard !pending.isEmpty else {
            if node.size == nil { node.size = children.reduce(0) { $0 + ($1.size ?? 0) } }
            return
        }
        pendingCount += pending.count
        let byURL = Dictionary(pending.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var buffer: [(URL, Int64)] = []
        var lastFlush = ContinuousClock.now

        func flush() {
            for (url, size) in buffer {
                cache[url] = size
                byURL[url]?.size = size
            }
            pendingCount -= buffer.count
            buffer.removeAll(keepingCapacity: true)
            lastFlush = .now
        }

        await withTaskGroup(of: (URL, Int64).self) { group in
            for url in byURL.keys {
                group.addTask { (url, FileSizer.size(of: url)) }
            }
            for await result in group {
                buffer.append(result)
                if ContinuousClock.now - lastFlush > .milliseconds(150) { flush() }
            }
        }
        flush()
        if node.size == nil { node.size = children.reduce(0) { $0 + ($1.size ?? 0) } }
    }

    /// Simülatör klasörlerinin UUID adları yerine cihaz adını ve iOS sürümünü göster.
    private func labelSimulators(_ nodes: [DiskNode]) {
        Task {
            let devices = await Task.detached { Simulators.list() }.value
            let byUDID = Dictionary(devices.map { ($0.udid, $0) }, uniquingKeysWith: { first, _ in first })
            for node in nodes {
                guard let device = byUDID[node.name] else { continue }
                node.label = "\(device.name) · \(device.runtime)" + (device.isAvailable ? "" : " · kullanılamıyor")
            }
        }
    }

    func remove(_ node: DiskNode) async {
        let outcome = await Trasher.remove([node.url], sizes: [node.url: node.size ?? 0])
        errors = outcome.failures
        guard outcome.removed.contains(node.url), let parent = node.parent else { return }
        parent.children?.removeAll { $0 === node }
        // Silinen boyutu tüm üst klasörlerden düş.
        let removed = node.size ?? 0
        var ancestor: DiskNode? = parent
        while let current = ancestor {
            if let size = current.size { current.size = max(0, size - removed) }
            cache[current.url] = nil
            ancestor = current.parent
        }
    }
}

@MainActor
@Observable
final class ShredderViewModel {
    struct Target: Identifiable, Hashable {
        let url: URL
        let size: Int64
        var id: URL { url }
        var safety: SafetyLevel { SafetyPolicy.level(for: url) }
    }

    var targets: [Target] = []
    var isShredding = false
    var message: String?
    var errors: [String] = []

    var totalSize: Int64 { targets.reduce(0) { $0 + $1.size } }

    func add(_ urls: [URL]) {
        let existing = Set(targets.map(\.url))
        for url in urls where !existing.contains(url) {
            targets.append(Target(url: url, size: FileSizer.size(of: url)))
        }
        message = nil
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Ekle"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func shred() async {
        isShredding = true
        let outcome = await Trasher.remove(
            targets.map(\.url), method: .shred, sizes: Dictionary(targets.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        )
        targets.removeAll { outcome.removed.contains($0.url) }
        errors = outcome.failures
        message = outcome.removed.isEmpty ? nil : "\(outcome.removed.count) öğe kalıcı olarak yok edildi."
        isShredding = false
    }
}

@MainActor
@Observable
final class MaintenanceViewModel {
    enum Status: Equatable { case idle, running, done, failed(String) }

    var statuses: [String: Status] = [:]
    private(set) var snapshots: [TimeMachineSnapshots.Snapshot] = []
    private(set) var purgeable: Int64 = 0
    private(set) var snapshotStatus: Status = .idle

    func status(of task: MaintenanceTask) -> Status { statuses[task.id] ?? .idle }

    func loadSnapshots() async {
        let (list, bytes) = await runDetached { (TimeMachineSnapshots.list(), TimeMachineSnapshots.purgeableBytes) }
        snapshots = list
        purgeable = bytes
    }

    func deleteSnapshots() async {
        snapshotStatus = .running
        do {
            try await TimeMachineSnapshots.delete(snapshots)
            snapshotStatus = .done
        } catch {
            snapshotStatus = .failed(error.localizedDescription)
        }
        await loadSnapshots()
    }

    func run(_ task: MaintenanceTask) async {
        statuses[task.id] = .running
        do {
            try await Maintenance.run(task)
            statuses[task.id] = .done
        } catch {
            statuses[task.id] = .failed(error.localizedDescription)
        }
    }
}
