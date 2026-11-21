import Foundation

struct MaintenanceTask: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let command: String
    let needsAdmin: Bool
}

enum Maintenance {
    /// Disk önbelleğini boşaltır. Uygulamaları kapatmaz; Bellek sayfasından raporlu olarak çalıştırılır.
    static let purge = MaintenanceTask(
        id: "ram", title: "RAM'i Boşalt",
        detail: "Diskten okunan dosyaların bellekteki önbelleğini temizler (purge).",
        icon: "memorychip", command: "/usr/sbin/purge", needsAdmin: true
    )

    static let tasks: [MaintenanceTask] = [
        MaintenanceTask(
            id: "dns", title: "DNS Önbelleğini Temizle",
            detail: "Siteler açılmıyor veya yanlış adrese gidiyorsa işe yarar.",
            icon: "network", command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", needsAdmin: true
        ),
        MaintenanceTask(
            id: "spotlight", title: "Spotlight'ı Yeniden Dizinle",
            detail: "Arama sonuçları eksik veya hatalıysa dizini sıfırdan oluşturur. Birkaç saat sürebilir.",
            icon: "magnifyingglass", command: "/usr/bin/mdutil -E /", needsAdmin: true
        ),
        MaintenanceTask(
            id: "launchservices", title: "\"Birlikte Aç\" Menüsünü Onar",
            detail: "Launch Services veritabanını yeniden oluşturur; çift kayıtları ve silinmiş uygulamaları temizler.",
            icon: "list.bullet.rectangle",
            command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
            needsAdmin: false
        ),
        MaintenanceTask(
            id: "quicklook", title: "Quick Look Önbelleğini Sıfırla",
            detail: "Dosya önizlemeleri ve küçük resimler hatalı görünüyorsa.",
            icon: "eye", command: "/usr/bin/qlmanage -r cache && /usr/bin/qlmanage -r", needsAdmin: false
        ),
        MaintenanceTask(
            id: "fonts", title: "Yazı Tipi Önbelleğini Temizle",
            detail: "Bozuk görünen yazı tipleri için. Değişiklik yeniden oturum açınca geçerli olur.",
            icon: "textformat", command: "/usr/bin/atsutil databases -removeUser", needsAdmin: false
        ),
        MaintenanceTask(
            id: "dock", title: "Dock'u Yeniden Başlat",
            detail: "Donan veya hatalı görünen Dock ve Mission Control için.",
            icon: "dock.rectangle", command: "/usr/bin/killall Dock", needsAdmin: false
        ),
        MaintenanceTask(
            id: "finder", title: "Finder'ı Yeniden Başlat",
            detail: "Yanıt vermeyen Finder pencereleri için.",
            icon: "macwindow", command: "/usr/bin/killall Finder", needsAdmin: false
        ),
    ]

    enum Failure: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { message } else { nil } }
    }

    static func run(_ task: MaintenanceTask) async throws {
        try await Task.detached(priority: .userInitiated) {
            if task.needsAdmin {
                // macOS'un kendi yönetici parolası penceresini gösterir; parola FCleaner'a hiç ulaşmaz.
                let escaped = task.command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")
                var error: NSDictionary?
                script?.executeAndReturnError(&error)
                if let error {
                    throw Failure.failed(error[NSAppleScript.errorMessage] as? String ?? "İşlem iptal edildi")
                }
            } else {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", task.command]
                let pipe = Pipe()
                process.standardError = pipe
                process.standardOutput = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    throw Failure.failed(output.isEmpty ? "Çıkış kodu \(process.terminationStatus)" : output)
                }
            }
        }.value
    }
}

/// Time Machine'in ana diskte tuttuğu yerel anlık görüntüler. macOS yer gerektiğinde bunları kendisi siler,
/// ama o zamana kadar "boşaltılabilir" olarak onlarca GB tutabilirler.
enum TimeMachineSnapshots {
    struct Snapshot: Identifiable, Hashable, Sendable {
        /// tmutil'in beklediği tarih kimliği, ör. "2026-11-20-101112".
        let id: String
        let date: Date?
    }

    static func list() -> [Snapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(data: data, encoding: .utf8) ?? "")
    }

    /// "com.apple.TimeMachine.2026-11-20-101112.local" satırlarından tarih kimliklerini çıkarır.
    static func parse(_ output: String) -> [Snapshot] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return output.split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("com.apple.TimeMachine."), text.hasSuffix(".local") else { return nil }
            let id = String(text.dropFirst("com.apple.TimeMachine.".count).dropLast(".local".count))
            return Snapshot(id: id, date: formatter.date(from: id))
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Diskte macOS'un gerektiğinde boşaltabileceği alan (anlık görüntüler ve iCloud önbellekleri dahil).
    static var purgeableBytes: Int64 {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacity,
              let important = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return max(0, important - Int64(available))
    }

    static func delete(_ snapshots: [Snapshot]) async throws {
        // Tarih kimlikleri yalnızca rakam ve tire içerir; komuta başka bir şey karışmasın diye yine de süzülür.
        let ids = snapshots.map(\.id).filter { $0.allSatisfy { $0.isNumber || $0 == "-" } }
        guard !ids.isEmpty else { return }
        let command = ids.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: "; ")
        try await Maintenance.run(MaintenanceTask(
            id: "timemachine", title: "Time Machine anlık görüntülerini sil", detail: "",
            icon: "clock.arrow.circlepath", command: command, needsAdmin: true
        ))
    }
}
