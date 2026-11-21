import Testing
import Foundation
@testable import FCleaner

@Suite struct HistoryTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fcleaner-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test @MainActor func recordsPersistAndRestore() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("docs/report.pdf")
        let trashed = dir.appendingPathComponent("trash/report.pdf")
        try FileManager.default.createDirectory(at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: trashed)

        let logFile = dir.appendingPathComponent("history.json")
        let log = DeletionLog(fileURL: logFile)
        log.record([DeletionLog.Entry(date: Date(), originalPath: original.path, trashedPath: trashed.path, size: 3, method: .trash)])

        // Yeniden açınca kayıt duruyor.
        let reopened = DeletionLog(fileURL: logFile)
        #expect(reopened.entries.count == 1)
        let entry = try #require(reopened.entries.first)
        #expect(entry.canRestore)

        try reopened.restore(entry)
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: trashed.path))
        #expect(reopened.entries.isEmpty)
    }

    @Test @MainActor func restoreRefusesToOverwrite() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.txt")
        let trashed = dir.appendingPathComponent("trashed-a.txt")
        try Data("new".utf8).write(to: original)
        try Data("old".utf8).write(to: trashed)

        let log = DeletionLog(fileURL: dir.appendingPathComponent("history.json"))
        log.record([DeletionLog.Entry(date: Date(), originalPath: original.path, trashedPath: trashed.path, size: nil, method: .trash)])
        #expect(throws: DeletionLog.RestoreError.self) { try log.restore(log.entries[0]) }
        #expect(try String(contentsOf: original, encoding: .utf8) == "new")
    }

    @Test @MainActor func permanentDeletionsCannotBeRestored() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = DeletionLog(fileURL: dir.appendingPathComponent("history.json"))
        log.record([DeletionLog.Entry(date: Date(), originalPath: "/tmp/x", trashedPath: nil, size: 1, method: .shred)])
        #expect(!log.entries[0].canRestore)
    }
}

@Suite struct ExclusionTests {
    @Test func containsChildrenOfExcludedFolders() throws {
        let defaults = try #require(UserDefaults(suiteName: "fcleaner-tests-\(UUID().uuidString)"))
        let exclusions = Exclusions(defaults: defaults)
        exclusions.add(URL(fileURLWithPath: "/Users/test/Projects"))
        #expect(exclusions.contains(URL(fileURLWithPath: "/Users/test/Projects")))
        #expect(exclusions.contains(URL(fileURLWithPath: "/Users/test/Projects/app/build")))
        #expect(!exclusions.contains(URL(fileURLWithPath: "/Users/test/ProjectsOld")))

        // Kalıcı: aynı ayarlarla yeniden oluşturulunca liste duruyor.
        #expect(Exclusions(defaults: defaults).paths == ["/Users/test/Projects"])
        exclusions.remove("/Users/test/Projects")
        #expect(!exclusions.contains(URL(fileURLWithPath: "/Users/test/Projects/app")))
    }

    @Test @MainActor func trasherSkipsExcludedItems() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fcleaner-excluded-\(UUID().uuidString).txt")
        try Data("keep".utf8).write(to: file)
        Exclusions.shared.add(file)
        defer {
            Exclusions.shared.remove(file.standardizedFileURL.path)
            try? FileManager.default.removeItem(at: file)
        }
        let outcome = await Trasher.remove([file], method: .permanent)
        #expect(outcome.removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}

@Suite struct TimeMachineTests {
    @Test func parsesSnapshotList() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-20-101112.local
        com.apple.TimeMachine.2026-11-21-083000.local
        """
        let snapshots = TimeMachineSnapshots.parse(output)
        #expect(snapshots.map(\.id) == ["2026-11-21-083000", "2026-11-20-101112"])
        #expect(snapshots.allSatisfy { $0.date != nil })
        #expect(TimeMachineSnapshots.parse("Snapshots for disk /:\n").isEmpty)
    }
}
