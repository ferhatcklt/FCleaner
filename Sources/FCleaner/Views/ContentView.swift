import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Bindable private var updater = Updater.shared

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(SidebarItem.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(SidebarItem.allCases.filter { $0.group == group }) { item in
                            Label(item.title, systemImage: item.icon).tag(item)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    ProtectionLockView()
                    HStack(spacing: 6) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text("FCleaner \(updater.currentVersion) · Açık Kaynak")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
            }
        } detail: {
            detail
        }
        .sheet(isPresented: $updater.isSheetPresented) {
            UpdateSheet(updater: updater)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .dashboard {
        case .dashboard: DashboardView()
        case .junk: JunkView(vm: model.junk)
        case .largeFiles: LargeFilesView(vm: model.largeFiles)
        case .duplicates: DuplicatesView(vm: model.duplicates)
        case .history: HistoryView()
        case .uninstaller: UninstallerView(vm: model.uninstaller)
        case .startup: StartupView(vm: model.startup)
        case .memory: MemoryView(vm: model.memory)
        case .diskAnalyzer: DiskAnalyzerView(vm: model.diskAnalyzer)
        case .shredder: ShredderView(vm: model.shredder)
        case .maintenance: MaintenanceView(vm: model.maintenance)
        }
    }
}

/// Kenar çubuğunun altındaki koruma kilidi göstergesi.
struct ProtectionLockView: View {
    private var lock: ProtectionLock { .shared }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: lock.isUnlocked ? "lock.open.fill" : "lock.fill")
                .foregroundStyle(lock.isUnlocked ? .orange : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(lock.isUnlocked ? "Koruma kapalı" : "Koruma açık")
                    .font(.callout.weight(.semibold))
                if let until = lock.unlockedUntil, lock.isUnlocked {
                    Text("Kilitlenme: \(until, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kritik dosyalar kilitli")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(lock.isUnlocked ? "Kilitle" : "Aç") {
                if lock.isUnlocked { lock.lock() } else { Task { await lock.unlock() } }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            (lock.isUnlocked ? Color.orange : Color.green).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .help("Kritik dosyalar (parolalar, iCloud, yedekler, sistem uygulaması verileri) bu kilit açılmadan silinemez. Kilit Touch ID veya Mac parolanızla açılır ve 5 dakika sonra kendiliğinden kapanır.")
    }
}
