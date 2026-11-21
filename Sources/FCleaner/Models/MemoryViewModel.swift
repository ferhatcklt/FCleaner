import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class MemoryViewModel {
    struct QuitResult: Identifiable, Equatable {
        let name: String
        let footprint: UInt64
        let closed: Bool
        var id: String { name }
    }

    struct PurgeReport: Equatable {
        let before: MemoryStats
        let after: MemoryStats
        let quitResults: [QuitResult]
        let purgeError: String?
        let date: Date

        var freed: UInt64 { before.used > after.used ? before.used - after.used : 0 }
        var cacheCleared: UInt64 { before.cached > after.cached ? before.cached - after.cached : 0 }
        var closedApps: [QuitResult] { quitResults.filter(\.closed) }
        var refusedApps: [QuitResult] { quitResults.filter { !$0.closed } }
    }

    enum Phase: Equatable {
        case idle
        case running(String)
    }

    private(set) var stats = MemoryMonitor.stats()
    private(set) var apps: [AppMemoryUsage] = []
    /// Normal "Çık" komutuyla kapatılabilecek uygulamalar (Dock'taki uygulamalar; FCleaner ve Finder hariç).
    private(set) var quittableIDs: Set<String> = []
    var sort = SortState()
    var appsToQuit: Set<String> = []
    var isPurgeSheetPresented = false
    private(set) var phase: Phase = .idle
    private(set) var lastReport: PurgeReport?
    var message: String?
    private var refreshTask: Task<Void, Never>?

    var sortedApps: [AppMemoryUsage] {
        apps.sorted(sort, size: { Int64($0.footprint) }, name: \.name, date: { _ in nil })
    }

    /// RAM boşaltırken kapatılması önerilebilecek, en çok bellek kullanan uygulamalar.
    var quitCandidates: [AppMemoryUsage] {
        Array(apps.filter { quittableIDs.contains($0.id) }.sorted { $0.footprint > $1.footprint }.prefix(8))
    }

    // MARK: Canlı izleme

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        let (newStats, newApps) = await runDetached { (MemoryMonitor.stats(), MemoryMonitor.appUsage()) }
        stats = newStats
        apps = newApps
        quittableIDs = Set(newApps.filter { !runningApplications(for: $0).isEmpty }.map(\.id))
    }

    // MARK: Uygulama kapatma

    private func runningApplications(for usage: AppMemoryUsage) -> [NSRunningApplication] {
        guard let bundle = usage.bundleURL?.resolvingSymlinksInPath().path else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != ownPID
                && $0.bundleIdentifier != "com.apple.finder"
                && $0.bundleURL?.resolvingSymlinksInPath().path == bundle
        }
    }

    /// Uygulamaya normal "Çık" komutunu gönderir (zorla kapatmaz) ve kapanmasını en fazla 8 sn bekler.
    /// Kaydedilmemiş belge varsa uygulama kullanıcıya sorar; kapanmazsa false döner.
    private func quit(_ usage: AppMemoryUsage) async -> Bool {
        let running = runningApplications(for: usage)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<32 {
            if running.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return running.allSatisfy(\.isTerminated)
    }

    func quitSingle(_ usage: AppMemoryUsage) async {
        let closed = await quit(usage)
        message = closed
            ? "\(usage.name) kapatıldı, \(Int64(usage.footprint).formattedBytes) serbest kaldı."
            : "\(usage.name) kapanmadı. Kaydedilmemiş bir belge olabilir; uygulamaya bakın."
        await refresh()
    }

    // MARK: RAM boşaltma

    func purge() async {
        guard phase == .idle else { return }
        let before = MemoryMonitor.stats()
        var results: [QuitResult] = []

        for usage in apps.filter({ appsToQuit.contains($0.id) }) {
            phase = .running("\(usage.name) kapatılıyor…")
            results.append(QuitResult(name: usage.name, footprint: usage.footprint, closed: await quit(usage)))
        }

        phase = .running("Disk önbelleği temizleniyor…")
        var purgeError: String?
        do {
            try await Maintenance.run(Maintenance.purge)
        } catch {
            purgeError = "Disk önbelleği temizlenemedi: \(error.localizedDescription)"
        }

        phase = .running("Sonuç ölçülüyor…")
        try? await Task.sleep(for: .seconds(1))
        lastReport = PurgeReport(
            before: before,
            after: MemoryMonitor.stats(),
            quitResults: results,
            purgeError: purgeError,
            date: Date()
        )
        appsToQuit = []
        phase = .idle
        await refresh()
    }
}
