import Testing
import Foundation
@testable import FCleaner

@Suite struct TrasherTests {
    @Test @MainActor func trasherRefusesWhenLocked() async throws {
        let dir = Paths.library("Keychains/__fcleaner_test_does_not_exist__")
        let outcome = await Trasher.remove([dir])
        #expect(outcome.removed.isEmpty)
        #expect(outcome.failures.first?.contains("kilitli") == true)
    }

    @Test @MainActor func trasherRefusesForbidden() async {
        let outcome = await Trasher.remove([Paths.home("Documents")])
        #expect(outcome.removed.isEmpty)
        #expect(outcome.failures.count == 1)
    }

    @Test func shredderDoesNotFollowSymlinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("fcleaner-shred-\(UUID().uuidString)")
        let target = root.appendingPathComponent("target")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let precious = target.appendingPathComponent("precious.txt")
        try Data("keep me".utf8).write(to: precious)
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? fm.removeItem(at: root) }

        try Shredder.shred(link)

        #expect(!fm.fileExists(atPath: link.path))
        #expect(try String(contentsOf: precious, encoding: .utf8) == "keep me")
    }

    @Test @MainActor func cancelStopsDetachedWork() async {
        let started = Date()
        let task = Task {
            await runDetached { () -> Int in
                var count = 0
                while !Task.isCancelled && Date().timeIntervalSince(started) < 5 { count += 1 }
                return count
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value
        #expect(Date().timeIntervalSince(started) < 2)
    }
}
