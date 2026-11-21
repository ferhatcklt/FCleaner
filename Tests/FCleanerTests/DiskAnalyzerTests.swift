import Testing
import Foundation
@testable import FCleaner

@Suite struct DiskAnalyzerTests {
    @Test func rootAncestorsStopAtSlash() {
        let ancestors = DiskAnalyzerViewModel.ancestors(of: URL(fileURLWithPath: "/Users/test/Library"))
        #expect(ancestors.map(\.path) == ["/", "/Users", "/Users/test", "/Users/test/Library"])
        #expect(DiskAnalyzerViewModel.ancestors(of: URL(fileURLWithPath: "/")).map(\.path) == ["/"])
    }
}
