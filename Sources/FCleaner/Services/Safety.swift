import Foundation
import LocalAuthentication
import Observation

/// Her dosyanın ne kadar güvenle silinebileceği.
enum SafetyLevel: Int, Comparable, Sendable {
    /// Silinmesi güvenli, sistem gerektiğinde yeniden oluşturur (önbellek, log, derleme artığı).
    case safe
    /// Silinebilir ama kullanıcı verisi olabilir; kullanıcı gözden geçirmeli.
    case review
    /// Silinirse geri dönülemez hasar oluşabilir; kilit açılmadan seçilemez ve silinemez.
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .safe: "Önerilen"
        case .review: "Gözden Geçir"
        case .critical: "Kritik"
        }
    }

    var icon: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .review: "exclamationmark.triangle.fill"
        case .critical: "lock.fill"
        }
    }
}

enum SafetyPolicy {
    /// Hiçbir koşulda (kilit açık olsa bile) silinemeyecek yollar.
    static let forbiddenPaths: Set<String> = [
        "/", "/Applications", "/Library", "/System", "/Users", "/usr", "/bin", "/sbin", "/private", "/opt", "/Volumes",
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/LaunchAgents",
        "/Library/LaunchDaemons", "/Library/Logs", "/Library/PrivilegedHelperTools",
        Paths.home.path, Paths.library.path,
        Paths.library("Caches").path, Paths.library("Logs").path, Paths.library("Application Support").path,
        Paths.library("Preferences").path, Paths.library("Containers").path, Paths.library("Group Containers").path,
        Paths.library("LaunchAgents").path, Paths.library("Keychains").path, Paths.library("Mobile Documents").path,
        Paths.home("Downloads").path, Paths.home("Documents").path, Paths.home("Desktop").path,
        Paths.home("Pictures").path, Paths.home("Movies").path, Paths.home("Music").path, Paths.home(".Trash").path,
    ]

    static let forbiddenPrefixes = [
        "/System/", "/usr/", "/bin/", "/sbin/", "/private/var/db/", "/private/etc/", "/var/db/", "/etc/",
    ]

    static func isForbidden(_ url: URL) -> Bool {
        // macOS "/private/var" ile "/var" yolunu birbirine çevirebildiği için her iki biçim de kontrol edilir.
        let forms = [url.standardizedFileURL, url.resolvingSymlinksInPath()]
        for form in forms {
            let components = form.pathComponents
            if isSystemPath(form.path) || components.count < 3 { return true }

            if components[1] == "Volumes" {
                // Diskin kendisi (/Volumes/<disk>) silinemez.
                if components.count == 3 { return true }
                // Başka bir macOS diskindeki sistem klasörleri de korunur (/Volumes/Mac/System, /Volumes/Mac/Users).
                if isSystemPath("/" + components.dropFirst(3).joined(separator: "/")) { return true }
            }

            if components[1] == "Users" {
                // Kullanıcı klasörlerinin kendisi ve başka kullanıcıların verileri silinemez; /Users/Shared içi serbest.
                if components.count == 3 { return true }
                let currentUser = Paths.home.standardizedFileURL.pathComponents.dropFirst(2).first
                if components[2] != currentUser && components[2] != "Shared" { return true }
            }
        }
        return false
    }

    private static func isSystemPath(_ path: String) -> Bool {
        forbiddenPaths.contains(path) || forbiddenPrefixes.contains(where: path.hasPrefix)
    }

    /// Silinirse geri dönülemez veri kaybına yol açabilecek konumlar.
    private static let criticalRoots: [(URL, String)] = [
        (Paths.library("Keychains"), "Anahtar Zinciri: kayıtlı parolalar ve sertifikalar"),
        (Paths.library("Mobile Documents"), "iCloud Drive dosyaları"),
        (Paths.library("Messages"), "iMessage geçmişi"),
        (Paths.library("Mail"), "E-posta arşivi"),
        (Paths.library("Photos"), "Fotoğraflar kitaplığı"),
        (Paths.library("Application Support/MobileSync/Backup"), "iPhone/iPad yedekleri"),
        (Paths.library("Application Support/AddressBook"), "Kişiler"),
        (Paths.library("Calendars"), "Takvimler"),
        (Paths.library("Developer/Xcode/Archives"), "Xcode arşivleri (yayınlanmış sürümlerin dSYM'leri)"),
        (Paths.library("Application Support/Google/Chrome"), "Chrome profili: parolalar, yer imleri"),
        (Paths.library("Application Support/Firefox"), "Firefox profili: parolalar, yer imleri"),
        (Paths.library("Application Support/BraveSoftware"), "Brave profili"),
        (Paths.library("Application Support/Microsoft Edge"), "Edge profili"),
        (Paths.library("Safari"), "Safari yer imleri ve geçmişi"),
        (Paths.home(".ssh"), "SSH anahtarları"),
        (Paths.home(".gnupg"), "GPG anahtarları"),
    ]

    private static let criticalKeywords = [
        "1password", "bitwarden", "keepass", "dashlane", "enpass", "lastpass",
        "wallet", "electrum", "exodus", "ledger live", "metamask",
    ]

    private static let criticalExtensions: Set<String> = [
        "keychain", "keychain-db", "kdbx", "p12", "pfx", "photoslibrary", "wallet",
    ]

    /// Kritikse nedenini döndürür.
    static func criticalReason(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        for (root, reason) in criticalRoots where path == root.path || path.hasPrefix(root.path + "/") {
            // Mail eklerinin önbelleği kritik değil.
            if path.contains("/Mail Downloads") { continue }
            return reason
        }
        // Kritik bir klasörü içeren üst klasör de kritiktir (ör. MobileSync içinde iPhone yedekleri var).
        if let (_, reason) = criticalRoots.first(where: { $0.0.path.hasPrefix(path + "/") }) {
            return "İçinde kritik veri var: \(reason)"
        }
        if criticalExtensions.contains(url.pathExtension.lowercased()) {
            return "Parola, sertifika veya fotoğraf kitaplığı dosyası"
        }
        let lower = path.lowercased()
        // Uygulama paketinin kendisi veri değildir; kaldırılması kilit gerektirmez.
        if url.pathExtension != "app", !lower.contains("/caches/"), let keyword = criticalKeywords.first(where: lower.contains) {
            return "Parola yöneticisi / kripto cüzdan verisi (\(keyword))"
        }
        // Apple'ın kendi uygulamalarının verileri ve ayarları.
        let name = url.lastPathComponent.lowercased()
        let parent = url.deletingLastPathComponent().path
        let appleDataDirs = [
            Paths.library("Containers").path, Paths.library("Group Containers").path, Paths.library("Preferences").path,
        ]
        if appleDataDirs.contains(parent) && (name.hasPrefix("com.apple.") || name.contains(".com.apple.") || name.hasPrefix("group.com.apple.")) {
            return "macOS sistem uygulaması verisi"
        }
        return nil
    }

    /// Dosyanın güvenlik seviyesi. `base`, dosyanın bulunduğu kategoriye göre beklenen seviyedir; politika bunu sadece yükseltebilir.
    static func level(for url: URL, base: SafetyLevel = .review) -> SafetyLevel {
        if isForbidden(url) || criticalReason(for: url) != nil { return .critical }
        return base
    }
}

/// Kritik dosyaların kilidi. Touch ID veya Mac parolasıyla açılır, 5 dakika sonra kendiliğinden kilitlenir.
@MainActor
@Observable
final class ProtectionLock {
    static let shared = ProtectionLock()
    static let unlockDuration: TimeInterval = 5 * 60

    private(set) var isUnlocked = false
    private(set) var unlockedUntil: Date?
    private var relockTask: Task<Void, Never>?

    @discardableResult
    func unlock() async -> Bool {
        if isUnlocked { return true }
        let context = LAContext()
        context.localizedCancelTitle = "Vazgeç"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "kritik dosyaların silinmesine izin vermek"
            )
            if ok { startUnlockedPeriod() }
            return ok
        } catch {
            return false
        }
    }

    func lock() {
        relockTask?.cancel()
        isUnlocked = false
        unlockedUntil = nil
    }

    private func startUnlockedPeriod() {
        isUnlocked = true
        unlockedUntil = Date().addingTimeInterval(Self.unlockDuration)
        relockTask?.cancel()
        relockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.unlockDuration))
            guard !Task.isCancelled else { return }
            self?.lock()
        }
    }

    /// Kilitliyken kritik öğelerin seçilmesini engellemek için.
    func canSelect(_ level: SafetyLevel) -> Bool { level != .critical || isUnlocked }
}
