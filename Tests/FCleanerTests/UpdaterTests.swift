import Testing
import Foundation
@testable import FCleaner

@Suite struct UpdaterTests {
    @Test func versionComparison() {
        #expect(Updater.isVersion("0.2.0", newerThan: "0.1.0"))
        #expect(Updater.isVersion("0.10.0", newerThan: "0.9.3"))
        #expect(Updater.isVersion("1.0", newerThan: "0.9.9"))
        #expect(!Updater.isVersion("0.1.0", newerThan: "0.1.0"))
        #expect(!Updater.isVersion("0.1", newerThan: "0.1.0"))
        #expect(!Updater.isVersion("0.0.9", newerThan: "0.1.0"))
    }
}
