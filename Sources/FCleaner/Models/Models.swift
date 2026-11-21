import Foundation

/// Silinebilecek tek bir dosya veya klasör.
struct CleanableItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let safety: SafetyLevel
    let modified: Date?
    /// Dosya adı yerine gösterilecek ad (ör. simülatör cihazının adı).
    var label: String?
    /// Yol yerine gösterilecek açıklama.
    var note: String?
    var id: URL { url }

    init(url: URL, size: Int64, base: SafetyLevel = .review, label: String? = nil, note: String? = nil) {
        self.url = url
        self.size = size
        self.label = label
        self.note = note
        self.safety = SafetyPolicy.level(for: url, base: base)
        self.modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    var name: String { url.lastPathComponent }
}

struct JunkCategory: Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case userCaches, logs, developer, simulators, iosUpdates, installers, mailDownloads, iosBackups, trash

        /// Kategoriden beklenen güvenlik seviyesi (politika tek tek dosyalar için yükseltebilir).
        var baseSafety: SafetyLevel {
            switch self {
            case .userCaches, .logs, .developer, .iosUpdates: .safe
            case .simulators, .installers, .mailDownloads, .trash: .review
            case .iosBackups: .critical
            }
        }
    }

    let kind: Kind
    var items: [CleanableItem]

    var id: String { kind.rawValue }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var safeSize: Int64 { items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size } }

    /// Çöp Sepeti zaten çöpte olduğu için kalıcı olarak silinir; diğer her şey Çöp Sepeti'ne taşınır.
    var deletesPermanently: Bool { kind == .trash }

    var title: String {
        switch kind {
        case .userCaches: "Uygulama Önbellekleri"
        case .logs: "Log Dosyaları"
        case .developer: "Geliştirici Artıkları"
        case .simulators: "iOS Simülatörleri"
        case .iosUpdates: "iOS Yazılım Güncellemeleri"
        case .iosBackups: "iPhone/iPad Yedekleri"
        case .installers: "Kurulum Dosyaları"
        case .mailDownloads: "Mail Ekleri"
        case .trash: "Çöp Sepeti"
        }
    }

    var icon: String {
        switch kind {
        case .userCaches: "archivebox"
        case .logs: "doc.text"
        case .developer: "hammer"
        case .simulators: "iphone.gen3"
        case .iosUpdates: "iphone.and.arrow.forward"
        case .iosBackups: "externaldrive.badge.icloud"
        case .installers: "shippingbox"
        case .mailDownloads: "envelope"
        case .trash: "trash"
        }
    }

    var detail: String {
        switch kind {
        case .userCaches: "Uygulamaların geçici önbellekleri. Silinirse gerektiğinde yeniden oluşturulur."
        case .logs: "Uygulama ve sistem günlük kayıtları."
        case .simulators: "Xcode'un sanal cihazları. Kullanılamayanlar güvenle silinir; diğerlerinde simülatördeki test uygulamaları ve verileri gider."
        case .developer: "Xcode DerivedData, cihaz destek dosyaları, simülatör, npm ve Gradle önbellekleri."
        case .iosUpdates: "Cihaz güncellemesi için indirilmiş .ipsw dosyaları. Gerekirse yeniden indirilir."
        case .iosBackups: "Yerel cihaz yedekleri. Silinirse geri getirilemez; kilit açılmadan silinemez."
        case .installers: "İndirilenler klasöründeki .dmg, .pkg ve .xip kurulum dosyaları."
        case .mailDownloads: "Mail uygulamasında açılan eklerin yerel kopyaları."
        case .trash: "Çöp Sepeti'ndeki dosyalar kalıcı olarak silinir."
        }
    }
}

struct LargeFile: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let modified: Date?
    var id: URL { url }
    var safety: SafetyLevel { SafetyPolicy.level(for: url, base: .review) }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let size: Int64
    var files: [URL]
    var wastedSize: Int64 { size * Int64(max(files.count - 1, 0)) }
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    var size: Int64
    /// Spotlight'ın kaydettiği son açılma tarihi.
    let lastUsed: Date?
    var id: URL { url }
}

struct LaunchItem: Identifiable, Hashable, Sendable {
    enum Scope: String, Sendable {
        case userAgent = "Kullanıcı Ajanı"
        case systemAgent = "Sistem Ajanı"
        case systemDaemon = "Sistem Servisi"
    }

    let url: URL
    let label: String
    let program: String?
    let scope: Scope
    let runAtLoad: Bool
    var id: URL { url }
}
