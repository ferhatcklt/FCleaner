import Testing
import Foundation
@testable import FCleaner

@Suite struct MemoryMonitorTests {
    @Test func statsAreConsistent() {
        let stats = MemoryMonitor.stats()
        #expect(stats.total == ProcessInfo.processInfo.physicalMemory)
        #expect(stats.used > 0 && stats.used <= stats.total)
        #expect(stats.app + stats.wired + stats.compressed + stats.cached + stats.free <= stats.total + stats.total / 10)
    }

    @Test func appUsageIncludesOwnProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let usage = MemoryMonitor.appUsage()
        let own = usage.first { $0.pids.contains(pid) }
        #expect(own != nil)
        #expect((own?.footprint ?? 0) > 1_000_000)
    }

    @Test func helpersGroupUnderParentApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(MemoryMonitor.outermostAppBundle(in: helper) == "/Applications/Google Chrome.app")
        #expect(MemoryMonitor.outermostAppBundle(in: "/usr/sbin/cfprefsd") == nil)
    }
}
