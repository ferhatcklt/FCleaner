import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Genel", systemImage: "gearshape") }
            ExclusionSettings()
                .tabItem { Label("Hariç Tutulanlar", systemImage: "eye.slash") }
        }
        .frame(width: 540, height: 380)
    }
}

private struct GeneralSettings: View {
    @Bindable private var updater = Updater.shared
    @AppStorage(AppSettings.showMenuBarKey) private var showMenuBar = true

    var body: some View {
        Form {
            Section {
                Toggle("Menü çubuğunda göster", isOn: $showMenuBar)
                Text("Açıkken pencere kapatıldığında FCleaner menü çubuğunda çalışmaya devam eder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Güncellemeleri otomatik denetle", isOn: $updater.automaticallyChecks)
                HStack {
                    Text("Yüklü sürüm: \(updater.currentVersion)")
                    Spacer()
                    Button("Şimdi Denetle") { Task { await updater.check(userInitiated: true) } }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExclusionSettings: View {
    private var exclusions: Exclusions { .shared }
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bu klasör ve dosyalar taramalarda gösterilmez ve FCleaner tarafından hiçbir koşulda silinmez. Listelerde bir öğeye sağ tıklayıp \"Bunu Hariç Tut\" diyerek de ekleyebilirsiniz.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(exclusions.paths, id: \.self, selection: $selection) { path in
                HStack(spacing: 8) {
                    FileIcon(url: URL(fileURLWithPath: path), size: 18)
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .listStyle(.bordered)
            .overlay {
                if exclusions.paths.isEmpty {
                    Text("Hariç tutulan öğe yok").foregroundStyle(.secondary)
                }
            }

            HStack {
                Button { choose() } label: { Image(systemName: "plus") }
                Button {
                    if let selection { exclusions.remove(selection) }
                    selection = nil
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding(20)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Hariç Tut"
        if panel.runModal() == .OK { panel.urls.forEach(exclusions.add) }
    }
}
