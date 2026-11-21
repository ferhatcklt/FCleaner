import SwiftUI
import AppKit

@main
struct FCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage(AppSettings.showMenuBarKey) private var showMenuBar = true

    var body: some Scene {
        Window("FCleaner", id: AppSettings.mainWindowID) {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Güncellemeleri Denetle…") {
                    Task { await Updater.shared.check(userInitiated: true) }
                }
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

enum AppSettings {
    static let showMenuBarKey = "showMenuBar"
    static let mainWindowID = "main"

    static var showMenuBar: Bool {
        UserDefaults.standard.object(forKey: showMenuBarKey) as? Bool ?? true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` ile Info.plist olmadan başlatıldığında da normal bir uygulama gibi davransın.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in Updater.shared.checkOnLaunch() }
    }

    /// Menü çubuğu simgesi açıksa pencere kapatılınca uygulama arka planda çalışmaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !AppSettings.showMenuBar }
}

/// Tüm modüllerin durumunu tutar; bölümler arasında geçerken tarama sonuçları kaybolmaz.
@MainActor
@Observable
final class AppModel {
    var selection: SidebarItem? = .dashboard
    let junk = JunkViewModel()
    let largeFiles = LargeFilesViewModel()
    let duplicates = DuplicatesViewModel()
    let uninstaller = UninstallerViewModel()
    let startup = StartupViewModel()
    let diskAnalyzer = DiskAnalyzerViewModel()
    let shredder = ShredderViewModel()
    let maintenance = MaintenanceViewModel()
    let memory = MemoryViewModel()
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, junk, largeFiles, duplicates, history, uninstaller, startup, memory, diskAnalyzer, shredder, maintenance

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case cleanup = "Temizlik"
        case apps = "Uygulamalar"
        case toolkit = "Araç Takımı"
    }

    var group: Group {
        switch self {
        case .dashboard, .junk, .largeFiles, .duplicates, .history: .cleanup
        case .uninstaller, .startup: .apps
        case .memory, .diskAnalyzer, .shredder, .maintenance: .toolkit
        }
    }

    var title: String {
        switch self {
        case .dashboard: "Genel Bakış"
        case .junk: "Sistem Çöpü"
        case .largeFiles: "Büyük Dosyalar"
        case .duplicates: "Kopya Dosyalar"
        case .history: "Silme Geçmişi"
        case .uninstaller: "Uygulama Kaldırıcı"
        case .startup: "Başlangıç Öğeleri"
        case .memory: "Bellek"
        case .diskAnalyzer: "Disk Analizcisi"
        case .shredder: "Dosya Parçalayıcı"
        case .maintenance: "Bakım"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .junk: "trash.circle"
        case .largeFiles: "doc.zipper"
        case .duplicates: "doc.on.doc"
        case .history: "clock"
        case .uninstaller: "xmark.app"
        case .startup: "power.circle"
        case .memory: "memorychip"
        case .diskAnalyzer: "chart.pie"
        case .shredder: "scissors"
        case .maintenance: "wrench.and.screwdriver"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Disk ve bellek durumu"
        case .junk: "Önbellekler, loglar, geliştirici artıkları"
        case .largeFiles: "Yer kaplayan büyük dosyaları bul"
        case .duplicates: "Birebir aynı dosyaları bul"
        case .history: "Silinenleri gör, Çöp Sepeti'ndekileri geri yükle"
        case .uninstaller: "Uygulamaları tüm verileriyle birlikte sil"
        case .startup: "Açılışta çalışan arka plan servisleri"
        case .memory: "RAM'i neyin kullandığını gör ve boşalt"
        case .diskAnalyzer: "Hangi klasör ne kadar yer kaplıyor"
        case .shredder: "Dosyaları geri getirilemez şekilde yok et"
        case .maintenance: "DNS, Spotlight ve sistem onarımları"
        }
    }
}
