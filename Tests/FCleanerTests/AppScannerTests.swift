import Testing
import Foundation
@testable import FCleaner

@Suite struct AppScannerTests {
    @Test func appBundlesInSubfolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fcleaner-apps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Top.app/Contents/Helper.app", "Adobe Photoshop 2025/Adobe Photoshop 2025.app", "XAMPP/xamppfiles/manager-osx.app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let names = Set(AppScanner.appBundles(in: root).map(\.lastPathComponent))
        #expect(names == ["Top.app", "Adobe Photoshop 2025.app", "manager-osx.app"])
    }

    @Test func applicationRootsAreUnique() {
        let roots = AppScanner.applicationRoots().map { $0.resolvingSymlinksInPath().path }
        #expect(roots.contains("/Applications"))
        #expect(Set(roots).count == roots.count)
    }

    @Test func leftoversSkipSiblingApps() {
        let others: Set<String> = ["com.jetbrains.intellij.ce", "com.google.Chrome.canary"]
        let names: Set<String> = ["intellij idea"]
        #expect(AppScanner.isLeftover("com.jetbrains.intellij.plist", bundleID: "com.jetbrains.intellij", names: names, otherBundleIDs: others))
        #expect(AppScanner.isLeftover("com.jetbrains.intellij.savedState", bundleID: "com.jetbrains.intellij", names: names, otherBundleIDs: others))
        #expect(!AppScanner.isLeftover("com.jetbrains.intellij.ce.plist", bundleID: "com.jetbrains.intellij", names: names, otherBundleIDs: others))
        #expect(!AppScanner.isLeftover("com.google.Chrome.canary", bundleID: "com.google.Chrome", names: [], otherBundleIDs: others))
        #expect(AppScanner.isLeftover("com.google.Chrome", bundleID: "com.google.Chrome", names: [], otherBundleIDs: others))
    }
}
