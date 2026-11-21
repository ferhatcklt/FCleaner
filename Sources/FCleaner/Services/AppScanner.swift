import Foundation
import AppKit

enum AppScanner {
    static func installedApps() async -> [InstalledApp] {
        var seen = Set<String>()
        let bundles = applicationRoots().flatMap { appBundles(in: $0) }
            .filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }

        return await withTaskGroup(of: InstalledApp?.self) { group in
            for url in bundles {
                group.addTask {
                    let bundle = Bundle(url: url)
                    let bundleID = bundle?.bundleIdentifier
                    // Apple'ın kendi uygulamaları SIP ile korunur, listelemeye gerek yok.
                    if bundleID?.hasPrefix("com.apple.") == true { return nil }
                    let info = bundle?.infoDictionary
                    let name = (info?["CFBundleDisplayName"] as? String)
                        ?? (info?["CFBundleName"] as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    return InstalledApp(
                        url: url,
                        name: name,
                        bundleID: bundleID,
                        version: info?["CFBundleShortVersionString"] as? String,
                        size: FileSizer.size(of: url),
                        lastUsed: lastUsedDate(of: url)
                    )
                }
            }
            var apps: [InstalledApp] = []
            for await app in group { if let app { apps.append(app) } }
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Ana diskteki ve kullanıcının Applications klasörleri ile bağlı her diskin kökündeki Applications klasörü.
    /// "/Volumes/Macintosh HD" gibi "/"a bağlanan diskler aynı klasöre çıktığı için tekrarlar ayıklanır.
    static func applicationRoots() -> [URL] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let candidates = [URL(fileURLWithPath: "/Applications"), Paths.home("Applications")]
            + volumes.map { $0.appendingPathComponent("Applications") }

        var seen = Set<String>()
        return candidates.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
            return seen.insert(url.resolvingSymlinksInPath().path).inserted
        }
    }

    /// Klasördeki .app paketlerini alt klasörlerle birlikte bulur (ör. "Adobe Photoshop 2025/Adobe Photoshop 2025.app").
    /// Paketlerin ve kısayol klasörlerin içine girilmez.
    static func appBundles(in dir: URL, depth: Int = 0) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return contents.flatMap { url -> [URL] in
            if url.pathExtension == "app" { return [url] }
            guard depth < 3, let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isPackage != true, values.isSymbolicLink != true else { return [] }
            return appBundles(in: url, depth: depth + 1)
        }
    }

    /// Uygulamanın sistemde bıraktığı tüm dosyaları bulur: kullanıcı ve sistem Kitaplığı, yardımcı araçlar, geçici önbellekler.
    /// `otherBundleIDs`: diğer yüklü uygulamaların kimlikleri. Onlara ait dosyalar hiçbir zaman artık sayılmaz.
    static func leftovers(for app: InstalledApp, otherBundleIDs: Set<String> = []) -> [CleanableItem] {
        let libraryDirs = [
            "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
            "Saved Application State", "Logs", "Logs/DiagnosticReports", "HTTPStorages", "WebKit", "Cookies",
            "LaunchAgents", "Application Scripts", "Internet Plug-Ins", "PreferencePanes", "Services",
            "Application Support/CrashReporter",
        ]
        let systemDirs = [
            "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/Logs",
            "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
            "/Library/Internet Plug-Ins", "/Library/PreferencePanes",
        ].map { URL(fileURLWithPath: $0) }

        // /var/folders/<..>/C ve /T: uygulamaya özel geçici dosyalar ve önbellekler.
        let tempRoot = FileManager.default.temporaryDirectory.deletingLastPathComponent()
        let tempDirs = [tempRoot.appendingPathComponent("C"), tempRoot.appendingPathComponent("T")]

        let searchDirs = libraryDirs.map(Paths.library) + systemDirs + tempDirs

        let names = Set([app.url.deletingPathExtension().lastPathComponent.lowercased(), app.name.lowercased()])
        func matches(_ fileName: String) -> Bool {
            isLeftover(fileName, bundleID: app.bundleID, names: names, otherBundleIDs: otherBundleIDs)
        }

        var seen = Set<String>()
        var results: [CleanableItem] = []
        for dir in searchDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where matches(url.lastPathComponent) && !Exclusions.shared.contains(url) && seen.insert(url.path).inserted {
                results.append(CleanableItem(url: url, size: FileSizer.size(of: url), base: .safe))
            }
        }
        return results.sorted { $0.size > $1.size }
    }

    static func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func isLeftover(_ fileName: String, bundleID: String?, names: Set<String>, otherBundleIDs: Set<String>) -> Bool {
        let name = fileName.lowercased()
        let stem = (name as NSString).deletingPathExtension

        func references(_ id: String) -> Bool {
            name == id || stem == id || name.hasPrefix(id + ".") || name.hasSuffix("." + id) || name.contains("." + id + ".")
        }

        if let id = bundleID?.lowercased(), references(id) {
            // "com.jetbrains.intellij" kaldırılırken "com.jetbrains.intellij.ce" (başka bir yüklü uygulama) dosyaları eşleşmesin.
            let siblings = otherBundleIDs.map { $0.lowercased() }.filter { $0 != id && $0.hasPrefix(id + ".") }
            return !siblings.contains(where: references)
        }
        // İsimle eşleştirmede sadece birebir eşleşme kabul edilir (ör. "Notes" gibi genel isimler yüzünden).
        // Çökme raporları "Uygulama_2026-01-01-....ips" biçimindedir.
        return names.contains(stem) || names.contains { name.hasPrefix($0 + "_") || name.hasPrefix($0 + "-20") }
    }

    static func isRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
    }
}

enum LaunchItemScanner {
    static func scan() -> [LaunchItem] {
        let sources: [(URL, LaunchItem.Scope)] = [
            (Paths.library("LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .systemAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .systemDaemon),
        ]

        return sources.flatMap { dir, scope -> [LaunchItem] in
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "plist" }.compactMap { url in
                let plist = NSDictionary(contentsOf: url) as? [String: Any]
                let label = plist?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                if label.hasPrefix("com.apple.") { return nil }
                let program = plist?["Program"] as? String ?? (plist?["ProgramArguments"] as? [String])?.first
                return LaunchItem(
                    url: url,
                    label: label,
                    program: program,
                    scope: scope,
                    runAtLoad: plist?["RunAtLoad"] as? Bool ?? false
                )
            }
        }
    }

    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
