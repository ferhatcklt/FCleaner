import Foundation
import Observation

/// Ağır işi ana iş parçacığı dışında çalıştırır. `Task.detached` iptali kendiliğinden devralmadığı
/// için çağıran görev iptal edildiğinde içteki görev de iptal edilir.
func runDetached<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
    let task = Task.detached(priority: .userInitiated, operation: work)
    return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
}

@MainActor
@Observable
final class JunkViewModel {
    var categories: [JunkCategory] = []
    var sort = SortState()
    var selected: Set<URL> = []
    var isScanning = false
    var isCleaning = false
    var hasScanned = false
    var lastFreed: Int64?
    var errors: [String] = []

    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    /// Flash Temizlik'in temizleyeceği, silinmesi güvenli öğelerin toplamı.
    var safeSize: Int64 { categories.reduce(0) { $0 + $1.safeSize } }
    var selectedSize: Int64 {
        categories.flatMap(\.items).filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func scan() async {
        // Temizlik sürerken kategoriler değiştirilmez; temizlik döngüsü onlar üzerinde çalışıyor.
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        lastFreed = nil
        errors = []
        categories = await runDetached { await JunkScanner.scan() }
        selectRecommended()
        isScanning = false
        hasScanned = true
    }

    /// Sadece "Önerilen" seviyesindeki öğeleri seçer.
    func selectRecommended() {
        selected = Set(categories.flatMap(\.items).filter { $0.safety == .safe }.map(\.url))
    }

    /// Tek tıkla temizlik: yalnızca güvenli öğeler.
    func flashClean() async {
        if !hasScanned { await scan() }
        selectRecommended()
        await clean()
    }

    func isCategorySelected(_ category: JunkCategory) -> Bool {
        let selectable = category.items.filter { ProtectionLock.shared.canSelect($0.safety) }
        return !selectable.isEmpty && selectable.allSatisfy { selected.contains($0.url) }
    }

    func setCategory(_ category: JunkCategory, selected isOn: Bool) {
        let urls = category.items.filter { ProtectionLock.shared.canSelect($0.safety) }.map(\.url)
        if isOn { selected.formUnion(urls) } else { selected.subtract(urls) }
    }

    func clean() async {
        guard !isCleaning, !isScanning else { return }
        isCleaning = true
        var freed: Int64 = 0
        var failures: [String] = []
        // Her await sonrasında dizi değişmiş olabileceğinden kategoriye indeksle değil kimliğiyle erişilir.
        for kind in categories.map(\.kind) {
            guard let category = categories.first(where: { $0.kind == kind }) else { continue }
            let chosen = category.items.filter { selected.contains($0.url) }
            guard !chosen.isEmpty else { continue }
            let outcome = await Trasher.remove(
                chosen.map(\.url),
                method: category.deletesPermanently ? .permanent : .trash,
                sizes: Dictionary(chosen.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
            )
            freed += chosen.filter { outcome.removed.contains($0.url) }.reduce(0) { $0 + $1.size }
            failures += outcome.failures
            if let index = categories.firstIndex(where: { $0.kind == kind }) {
                categories[index].items.removeAll { outcome.removed.contains($0.url) }
            }
            selected.subtract(outcome.removed)
        }
        categories.removeAll { $0.items.isEmpty }
        lastFreed = freed
        errors = failures
        isCleaning = false
    }
}

@MainActor
@Observable
final class LargeFilesViewModel {
    static let thresholds: [Int64] = [50, 100, 500, 1024].map { $0 * 1024 * 1024 }

    var files: [LargeFile] = []
    var sort = SortState()
    var sortedFiles: [LargeFile] {
        files.sorted(sort, size: \.size, name: \.url.lastPathComponent, date: \.modified)
    }
    var selected: Set<URL> = []
    var minSize: Int64 = 100 * 1024 * 1024
    var isScanning = false
    var hasScanned = false
    var scannedCount = 0
    var errors: [String] = []
    private var task: Task<Void, Never>?

    var selectedSize: Int64 { files.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size } }

    func scan() {
        task?.cancel()
        isScanning = true
        scannedCount = 0
        selected = []
        let minSize = minSize
        task = Task {
            let result = await runDetached {
                LargeFileScanner.scan(minSize: minSize) { count in
                    Task { @MainActor in self.scannedCount = count }
                }
            }
            // İptal edildiyse ya da yeni bir tarama başladıysa yarım sonucu gösterme.
            guard !Task.isCancelled else { return }
            files = result
            isScanning = false
            hasScanned = true
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    func removeSelected() async {
        let sizes = Dictionary(files.filter { selected.contains($0.url) }.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        let outcome = await Trasher.remove(Array(selected), sizes: sizes)
        files.removeAll { outcome.removed.contains($0.url) }
        selected.subtract(outcome.removed)
        errors = outcome.failures
    }
}

@MainActor
@Observable
final class DuplicatesViewModel {
    var groups: [DuplicateGroup] = []
    var sort = SortState()
    var sortedGroups: [DuplicateGroup] {
        groups.sorted(sort, size: \.wastedSize, name: { $0.files.first?.lastPathComponent ?? "" }, date: { _ in nil })
    }
    var selected: Set<URL> = []
    var isScanning = false
    var hasScanned = false
    var status = ""
    var errors: [String] = []
    private var task: Task<Void, Never>?

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wastedSize } }
    var selectedSize: Int64 {
        groups.reduce(0) { sum, group in sum + group.size * Int64(group.files.filter { selected.contains($0) }.count) }
    }

    func scan() {
        task?.cancel()
        isScanning = true
        status = "Dosyalar listeleniyor…"
        task = Task {
            let result = await runDetached {
                DuplicateScanner.scan(minSize: 1024 * 1024) { message in
                    Task { @MainActor in self.status = message }
                }
            }
            guard !Task.isCancelled else { return }
            groups = result
            selectAllButOldest()
            isScanning = false
            hasScanned = true
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    /// Her gruptaki en eski dosya korunur, diğerleri seçilir.
    func selectAllButOldest() {
        selected = Set(groups.flatMap { $0.files.dropFirst() }.filter { SafetyPolicy.level(for: $0) != .critical })
    }

    /// Bir grubun tüm kopyalarının seçilmesine izin verilmez; en az biri kalmalı.
    func canSelect(_ url: URL, in group: DuplicateGroup) -> Bool {
        selected.contains(url) || group.files.filter { !selected.contains($0) }.count > 1
    }

    func removeSelected() async {
        var sizes: [URL: Int64] = [:]
        for group in groups { for file in group.files where selected.contains(file) { sizes[file] = group.size } }
        let outcome = await Trasher.remove(Array(selected), sizes: sizes)
        for index in groups.indices {
            groups[index].files.removeAll { outcome.removed.contains($0) }
        }
        groups.removeAll { $0.files.count < 2 }
        selected.subtract(outcome.removed)
        errors = outcome.failures
    }
}

@MainActor
@Observable
final class UninstallerViewModel {
    var apps: [InstalledApp] = []
    var selectedApp: InstalledApp? {
        didSet { if oldValue != selectedApp { loadLeftovers() } }
    }
    var leftovers: [CleanableItem] = []
    var selectedLeftovers: Set<URL> = []
    var searchText = ""
    var isLoading = false
    var hasLoaded = false
    var message: String?
    var errors: [String] = []

    var sort = SortState(key: .name, ascending: true)

    var filteredApps: [InstalledApp] {
        let matching = searchText.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return matching.sorted(sort, size: \.size, name: \.name, date: \.lastUsed)
    }

    var removalSize: Int64 {
        (selectedApp?.size ?? 0) + leftovers.filter { selectedLeftovers.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func load() async {
        isLoading = true
        apps = await Task.detached(priority: .userInitiated) { await AppScanner.installedApps() }.value
        isLoading = false
        hasLoaded = true
    }

    private func loadLeftovers() {
        leftovers = []
        selectedLeftovers = []
        message = nil
        errors = []
        guard let app = selectedApp else { return }
        Task {
            let others = Set(apps.filter { $0.url != app.url }.compactMap(\.bundleID))
            let found = await Task.detached { AppScanner.leftovers(for: app, otherBundleIDs: others) }.value
            guard selectedApp == app else { return }
            leftovers = found
            selectedLeftovers = Set(found.filter { $0.safety != .critical }.map(\.url))
        }
    }

    func uninstall() async {
        guard let app = selectedApp else { return }
        var sizes = [app.url: app.size]
        for item in leftovers where selectedLeftovers.contains(item.url) { sizes[item.url] = item.size }
        let outcome = await Trasher.remove([app.url] + Array(selectedLeftovers), sizes: sizes)
        errors = outcome.failures
        if outcome.removed.contains(app.url) {
            message = "\(app.name) Çöp Sepeti'ne taşındı."
            apps.removeAll { $0.url == app.url }
            selectedApp = nil
        } else {
            leftovers.removeAll { outcome.removed.contains($0.url) }
            selectedLeftovers.subtract(outcome.removed)
        }
    }
}

@MainActor
@Observable
final class StartupViewModel {
    var items: [LaunchItem] = []
    var hasLoaded = false
    var errors: [String] = []

    func load() {
        items = LaunchItemScanner.scan()
        hasLoaded = true
    }

    func remove(_ item: LaunchItem) async {
        let outcome = await Trasher.remove([item.url])
        items.removeAll { outcome.removed.contains($0.url) }
        errors = outcome.failures
    }
}
