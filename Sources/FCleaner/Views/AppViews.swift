import SwiftUI

struct UninstallerView: View {
    @Bindable var vm: UninstallerViewModel
    @State private var confirm = false

    var body: some View {
        Group {
            if vm.isLoading {
                ScanningView(title: "Uygulamalar listeleniyor…")
            } else if !vm.hasLoaded {
                ScanPrompt(item: .uninstaller, description: "Yüklü uygulamaları boyutlarıyla listeler. Bir uygulamayı kaldırırken ayar, önbellek ve destek dosyalarını da bulur.", buttonTitle: "Uygulamaları Listele") {
                    Task { await vm.load() }
                }
            } else {
                HSplitView {
                    appList.frame(minWidth: 280, idealWidth: 320)
                    detail.frame(minWidth: 380)
                }
            }
        }
        .navigationTitle(SidebarItem.uninstaller.title)
        .confirmationDialog("\(vm.selectedApp?.name ?? "") kaldırılsın mı?", isPresented: $confirm) {
            Button("\(vm.removalSize.formattedBytes) Kaldır", role: .destructive) { Task { await vm.uninstall() } }
        } message: {
            Text("Uygulama ve seçili dosyaları Çöp Sepeti'ne taşınır.")
        }
    }

    private var appList: some View {
        List(vm.filteredApps, selection: $vm.selectedApp) { app in
            HStack(spacing: 10) {
                FileIcon(url: app.url, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).lineLimit(1)
                    Text(appSubtitle(app)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(app.size.formattedBytes).font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            .tag(app)
        }
        .searchable(text: $vm.searchText, placement: .sidebar, prompt: "Uygulama ara")
        .safeAreaInset(edge: .top) {
            SortControl(state: $vm.sort, dateTitle: "Son Kullanım")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }

    private func appSubtitle(_ app: InstalledApp) -> String {
        let used = app.lastUsed.map { "Son kullanım: \($0.formatted(.relative(presentation: .named)))" } ?? "Kullanım bilgisi yok"
        // Harici diskteki uygulamalar, ana diskteki kopyalarından ayırt edilebilsin diye disk adıyla gösterilir.
        let components = app.url.pathComponents
        let volume = components.count > 2 && components[1] == "Volumes" ? components[2] : nil
        return [volume, app.version, used].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var detail: some View {
        if let app = vm.selectedApp {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    FileIcon(url: app.url, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2.bold())
                        Text(app.bundleID ?? "Paket kimliği yok").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(app.url.tildePath).font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(16)

                if AppScanner.isRunning(app) {
                    Label("Uygulama şu anda çalışıyor. Kaldırmadan önce kapatın.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                ErrorBanner(errors: vm.errors)

                List {
                    Section("Uygulama") {
                        HStack {
                            FileIcon(url: app.url)
                            Text(app.url.lastPathComponent)
                            Spacer()
                            Text(app.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Section("Artık dosyalar (\(vm.leftovers.count))") {
                        if vm.leftovers.isEmpty {
                            Text("Artık dosya bulunamadı.").foregroundStyle(.secondary)
                        }
                        ForEach(vm.leftovers) { item in
                            FileRow(url: item.url, size: item.size, isOn: .membership(item.url, in: $vm.selectedLeftovers), safety: item.safety)
                        }
                    }
                }
                .listStyle(.inset)

                ActionBar(buttonTitle: "Kaldır", buttonIcon: "xmark.bin", action: { confirm = true }) {
                    Text("Toplam \(vm.removalSize.formattedBytes)").foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 10) {
                if let message = vm.message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                ErrorBanner(errors: vm.errors)
                Text("Kaldırmak için soldan bir uygulama seçin.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StartupView: View {
    @Bindable var vm: StartupViewModel
    @State private var pendingRemoval: LaunchItem?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .startup, trailing: "\(vm.items.count) öğe")
            HStack {
                Text("Silinen öğeler bir sonraki oturum açışta veya yeniden başlatmada devre dışı kalır.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Giriş Öğeleri Ayarları") { LaunchItemScanner.openLoginItemsSettings() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            ErrorBanner(errors: vm.errors)

            if vm.items.isEmpty {
                EmptyResultView(title: "Başlangıç öğesi yok", detail: "Üçüncü parti arka plan servisi bulunamadı.") { vm.load() }
            } else {
                List(vm.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.scope == .userAgent ? "person.circle" : "gearshape.2")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).lineLimit(1)
                            Text(item.program ?? item.url.tildePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if item.runAtLoad {
                            Text("Açılışta").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                        Text(item.scope.rawValue).font(.caption).foregroundStyle(.secondary)
                        RevealButton(url: item.url)
                        Button(role: .destructive) { pendingRemoval = item } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Çöp Sepeti'ne taşı")
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(SidebarItem.startup.title)
        .toolbar {
            Button { vm.load() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
        }
        .onAppear { if !vm.hasLoaded { vm.load() } }
        .confirmationDialog(
            "\(pendingRemoval?.label ?? "") kaldırılsın mı?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Çöp Sepeti'ne Taşı", role: .destructive) {
                if let item = pendingRemoval { Task { await vm.remove(item) } }
            }
        } message: {
            Text("Bu servise bağlı uygulama bazı özelliklerini kaybedebilir.")
        }
    }
}
