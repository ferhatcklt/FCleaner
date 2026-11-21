import Foundation
import AppKit
import Security
import Observation

/// GitHub Releases üzerinden güncelleme denetler ve kurar.
///
/// Güvenlik: indirilen uygulama, yalnızca şu an çalışan FCleaner ile aynı geliştirici
/// (Team ID) tarafından imzalanmışsa ve paket kimliği aynıysa kurulur.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()
    static let repository = "ferhatcklt/FCleaner"
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    struct Release: Equatable {
        let version: String
        let notes: String
        let pageURL: URL
        let assetURL: URL?
        let publishedAt: Date?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    var isSheetPresented = false

    var automaticallyChecks: Bool {
        get { access(keyPath: \.automaticallyChecks); return UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { withMutation(keyPath: \.automaticallyChecks) { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") } }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Bu kopya kendini güncelleyemiyorsa nedeni; güncelleyebiliyorsa nil.
    var installBlocker: String? {
        let app = Bundle.main.bundleURL
        if app.pathExtension != "app" {
            return "Geliştirme modunda çalışıyor; güncelleme sayfası tarayıcıda açılacak."
        }
        if Self.runningTeamIdentifier() == nil {
            return "Bu kopya bir geliştirici sertifikasıyla imzalanmamış; güncellemeyi sayfadan indirin."
        }
        // İndirilen uygulama yerinden taşınmadan açılırsa macOS onu salt okunur geçici bir konumdan çalıştırır.
        if app.path.contains("/AppTranslocation/") {
            return "FCleaner indirildiği yerden çalışıyor. Kendini güncelleyebilmesi için Uygulamalar klasörüne taşıyıp oradan açın."
        }
        if !FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) {
            return "FCleaner'ın bulunduğu klasöre yazılamıyor; güncellemeyi sayfadan indirin."
        }
        return nil
    }

    var canInstallUpdates: Bool { installBlocker == nil }

    // MARK: Denetleme

    func checkOnLaunch() {
        guard automaticallyChecks else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.checkInterval else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        if case .installing = state { return }
        state = .checking
        if userInitiated { isSheetPresented = true }
        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            if Self.isVersion(release.version, newerThan: currentVersion) {
                state = .available(release)
                // Otomatik denetimde kullanıcıyı bölmeyiz; Genel Bakış'ta bir bant gösterilir.
            } else {
                state = .upToDate
            }
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FCleaner/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw UpdateError.message("Henüz yayınlanmış bir sürüm yok.") }
        guard status == 200 else { throw UpdateError.message("GitHub yanıt vermedi (HTTP \(status)).") }

        struct Payload: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let body: String?
            let html_url: URL
            let published_at: Date?
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        let version = payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return Release(
            version: version,
            notes: payload.body ?? "",
            pageURL: payload.html_url,
            assetURL: payload.assets.first { $0.name.hasSuffix(".zip") }?.browser_download_url,
            publishedAt: payload.published_at
        )
    }

    // MARK: Kurulum

    func install() async {
        guard let release = availableRelease else { return }
        guard canInstallUpdates, let assetURL = release.assetURL else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        do {
            let currentApp = Bundle.main.bundleURL
            // Değişim atomik olsun diye geçici klasör uygulamayla aynı diskte açılır.
            let workDir = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: currentApp, create: true
            )
            defer { try? FileManager.default.removeItem(at: workDir) }

            state = .installing("İndiriliyor…")
            let (downloaded, response) = try await URLSession.shared.download(from: assetURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.message("İndirme başarısız oldu.") }
            let zip = workDir.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)

            state = .installing("Açılıyor…")
            let extracted = workDir.appendingPathComponent("extracted")
            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.message("Arşivde uygulama bulunamadı.")
            }

            state = .installing("İmza doğrulanıyor…")
            try Self.verify(newApp, version: release.version)

            state = .installing("Kuruluyor…")
            _ = try FileManager.default.replaceItemAt(currentApp, withItemAt: newApp)
            relaunch(currentApp)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func relaunch(_ app: URL) {
        // Bu süreç kapandıktan sonra yeni sürümü açar.
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(app.path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: Doğrulama

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
    }

    /// İndirilen paket: geçerli imzalı, aynı Team ID, aynı paket kimliği ve beklenen sürüm olmalı.
    private static func verify(_ app: URL, version: String) throws {
        guard let team = runningTeamIdentifier() else {
            throw UpdateError.message("Bu kopya imzasız; güncelleme elle indirilmeli.")
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.message("İndirilen uygulama okunamadı.")
        }
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            throw UpdateError.message("İmza gereksinimi oluşturulamadı.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateError.message("İmza doğrulanamadı: indirilen dosya FCleaner geliştiricisine ait değil. Kurulum iptal edildi.")
        }
        let info = Bundle(url: app)?.infoDictionary
        guard Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.message("Paket kimliği eşleşmiyor. Kurulum iptal edildi.")
        }
        guard (info?["CFBundleShortVersionString"] as? String) == version else {
            throw UpdateError.message("İndirilen sürüm beklenenle eşleşmiyor.")
        }
    }

    private static func runningTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: Yardımcılar

    /// "0.10.0" > "0.9.3" gibi sayısal karşılaştırma.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw UpdateError.message("\(URL(fileURLWithPath: tool).lastPathComponent) başarısız oldu.")
            }
        }.value
    }
}
