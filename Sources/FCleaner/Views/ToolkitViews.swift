import SwiftUI
import UniformTypeIdentifiers

struct DiskAnalyzerView: View {
    @Bindable var vm: DiskAnalyzerViewModel
    @State private var pendingRemoval: DiskNode?
    @State private var selection: URL?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .diskAnalyzer, trailing: vm.root.size?.formattedBytes)
            pathBar
            HStack {
                SortControl(state: $vm.sort, dateTitle: "Değiştirilme")
                Spacer()
                if vm.isCalculating {
                    ProgressView().controlSize(.small)
                    Text("Boyutlar hesaplanıyor…").font(.caption).foregroundStyle(.secondary)
                }
                Button("Tümünü Kapat") { withAnimation(.snappy) { vm.collapseAll() } }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            ErrorBanner(errors: vm.errors)

            List(vm.visibleNodes, selection: $selection) { node in
                DiskNodeRow(node: node) {
                    withAnimation(.snappy(duration: 0.2)) { vm.toggle(node) }
                } onRemove: {
                    pendingRemoval = node
                } onFocus: {
                    vm.setRoot(node.url)
                }
                .tag(node.url)
            }
            .listStyle(.inset)
            .overlay {
                if vm.root.children?.isEmpty == true {
                    ContentUnavailableView("Klasör boş veya okunamıyor", systemImage: "folder")
                }
            }
            // Klavye: → klasörü açar, ← kapatır.
            .onKeyPress(.rightArrow) { setExpanded(true) }
            .onKeyPress(.leftArrow) { setExpanded(false) }
        }
        .navigationTitle(SidebarItem.diskAnalyzer.title)
        .toolbar {
            Menu {
                Button("Ev Klasörü") { vm.setRoot(Paths.home) }
                Button("Uygulamalar") { vm.setRoot(URL(fileURLWithPath: "/Applications")) }
                Button("Tüm Disk") { vm.setRoot(URL(fileURLWithPath: "/")) }
                Divider()
                Button("Klasör Seç…") { vm.chooseFolder() }
            } label: {
                Label("Konum", systemImage: "folder")
            }
            Button { vm.refresh() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
        }
        .onAppear { vm.startIfNeeded() }
        .confirmationDialog(
            "\(pendingRemoval?.name ?? "") Çöp Sepeti'ne taşınsın mı?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Çöp Sepeti'ne Taşı", role: .destructive) {
                if let node = pendingRemoval { Task { await vm.remove(node) } }
            }
        } message: {
            Text(pendingRemoval?.size.map { "\($0.formattedBytes) boşalacak." } ?? "")
        }
    }

    private func setExpanded(_ expanded: Bool) -> KeyPress.Result {
        guard let url = selection, let node = vm.visibleNodes.first(where: { $0.url == url }), node.isDirectory else {
            return .ignored
        }
        if node.isExpanded != expanded { withAnimation(.snappy(duration: 0.2)) { vm.toggle(node) } }
        return .handled
    }

    private var pathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let ancestors = vm.rootAncestors
                ForEach(Array(ancestors.enumerated()), id: \.offset) { index, url in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    let isLast = index == ancestors.count - 1
                    Button {
                        vm.setRoot(url)
                    } label: {
                        HStack(spacing: 4) {
                            FileIcon(url: url, size: 14)
                            Text(url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
                        }
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(isLast ? .semibold : .regular)
                    .foregroundStyle(isLast ? .primary : .secondary)
                    .disabled(isLast)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

private struct DiskNodeRow: View {
    let node: DiskNode
    let onToggle: () -> Void
    let onRemove: () -> Void
    let onFocus: () -> Void
    @State private var isHovered = false

    private var fraction: Double {
        guard let size = node.size, let total = node.parent?.size, total > 0 else { return 0 }
        return min(1, Double(size) / Double(total))
    }

    private var isExcluded: Bool {
        _ = Exclusions.shared.paths
        return Exclusions.shared.contains(node.url)
    }

    private var canRemove: Bool {
        !isExcluded && !SafetyPolicy.isForbidden(node.url) && ProtectionLock.shared.canSelect(node.safety)
    }

    private var barColor: Color {
        fraction > 0.5 ? .red : fraction > 0.2 ? .orange : .accentColor
    }

    var body: some View {
        HStack(spacing: 8) {
            // Girinti: her seviye için 18 pt.
            Color.clear.frame(width: CGFloat(max(node.depth - 1, 0)) * 18, height: 1)

            Group {
                if node.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                        .opacity(node.isDirectory ? 1 : 0)
                }
            }
            .frame(width: 12)

            FileIcon(url: node.url, size: 18)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if isExcluded {
                Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                    .help("Hariç tutuldu: FCleaner buna dokunmaz")
            }
            if let label = node.label {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
            if node.safety == .critical {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.red)
                    .help(SafetyPolicy.criticalReason(for: node.url) ?? "Kritik")
            }

            Spacer(minLength: 12)

            if isHovered {
                Button(action: onFocus) { Image(systemName: "scope") }
                    .buttonStyle(.borderless)
                    .help("Buradan analiz et")
                    .opacity(node.isDirectory ? 1 : 0)
                RevealButton(url: node.url)
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(!canRemove)
                    .help("Çöp Sepeti'ne taşı")
            }

            if let modified = node.modified {
                Text(modified.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 90, alignment: .trailing)
            }

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(barColor.opacity(0.8)).frame(width: max(2, 80 * fraction))
            }
            .frame(width: 80, height: 6)
            .opacity(node.size == nil ? 0 : 1)

            Text(node.size.map { $0.formattedBytes } ?? "…")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded(onToggle))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            if node.isDirectory { Button("Buradan Analiz Et", action: onFocus) }
            if isExcluded {
                Button("Hariç Tutmayı Kaldır") { Exclusions.shared.remove(node.url.standardizedFileURL.path) }
                    .disabled(!Exclusions.shared.paths.contains(node.url.standardizedFileURL.path))
            } else {
                Button("Hariç Tut") { Exclusions.shared.add(node.url) }
            }
            Divider()
            Button("Çöp Sepeti'ne Taşı…", role: .destructive, action: onRemove)
                .disabled(!canRemove)
        }
    }
}

struct ShredderView: View {
    @Bindable var vm: ShredderViewModel
    @State private var confirm = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .shredder)
            Label(
                "Parçalanan dosyalar Çöp Sepeti'ne gitmez ve geri getirilemez. Not: SSD'lerde (tüm modern Mac'ler) üzerine yazma fiziksel silmeyi garanti etmez; en güçlü koruma FileVault'un açık olmasıdır.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if let message = vm.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            ErrorBanner(errors: vm.errors)

            if vm.targets.isEmpty {
                dropZone
            } else {
                List {
                    ForEach(vm.targets) { target in
                        HStack(spacing: 10) {
                            FileIcon(url: target.url)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.url.lastPathComponent).lineLimit(1)
                                Text(target.url.deletingLastPathComponent().tildePath)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            SafetyBadge(level: target.safety)
                            Text(target.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                            Button { vm.targets.removeAll { $0 == target } } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
            }

            ActionBar(
                buttonTitle: "Kalıcı Olarak Parçala",
                buttonIcon: "scissors",
                disabled: vm.targets.isEmpty,
                isWorking: vm.isShredding,
                action: { confirm = true }
            ) {
                Button("Dosya Ekle…") { vm.choose() }
                Text("\(vm.targets.count) öğe · \(vm.totalSize.formattedBytes)").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(SidebarItem.shredder.title)
        .confirmationDialog("Bu öğeler kalıcı olarak yok edilsin mi?", isPresented: $confirm) {
            Button("Parçala (geri alınamaz)", role: .destructive) { Task { await vm.shred() } }
        } message: {
            Text("\(vm.targets.count) öğe, \(vm.totalSize.formattedBytes). Bu işlem geri alınamaz.")
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "scissors")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text("Dosyaları buraya sürükleyin").font(.title3.bold())
            Button("Dosya Seç…") { vm.choose() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
        )
        .padding(16)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in vm.add([url]) }
            }
        }
        return true
    }
}

struct MaintenanceView: View {
    @Bindable var vm: MaintenanceViewModel
    @State private var confirmSnapshots = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(item: .maintenance)
                Text("Kilit simgeli işlemler macOS'un yönetici parolası penceresini açar. Parolanız FCleaner'a iletilmez.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                snapshotCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(Maintenance.tasks) { task in
                        card(task)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(SidebarItem.maintenance.title)
        .task { await vm.loadSnapshots() }
        .confirmationDialog("\(vm.snapshots.count) yerel anlık görüntü silinsin mi?", isPresented: $confirmSnapshots) {
            Button("Hepsini Sil", role: .destructive) { Task { await vm.deleteSnapshots() } }
        } message: {
            Text("Time Machine yedekleriniz (harici disk veya ağ) etkilenmez. Yalnızca bu Mac'te tutulan, son birkaç saate geri dönmeye yarayan yerel kopyalar silinir.")
        }
    }

    private var snapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundStyle(.tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Machine Yerel Anlık Görüntüleri").font(.headline)
                    Text("macOS bunları yer gerektiğinde kendisi siler, ama o zamana kadar diskte \"boşaltılabilir\" alan olarak yer tutarlar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 16) {
                Label(vm.snapshots.isEmpty ? "Anlık görüntü yok" : "\(vm.snapshots.count) anlık görüntü", systemImage: "square.stack.3d.up")
                Label("Boşaltılabilir alan: \(vm.purgeable.formattedBytes)", systemImage: "internaldrive")
                    .help("Anlık görüntüler ve iCloud önbellekleri dahil, macOS'un gerektiğinde boşaltabileceği toplam alan.")
                Spacer()
                switch vm.snapshotStatus {
                case .running: ProgressView().controlSize(.small)
                case .done: Label("Silindi", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption).lineLimit(2)
                case .idle: EmptyView()
                }
                Button("Hepsini Sil…") { confirmSnapshots = true }
                    .disabled(vm.snapshots.isEmpty || vm.snapshotStatus == .running)
            }
            .font(.callout)
            if !vm.snapshots.isEmpty {
                Text(vm.snapshots.prefix(6).compactMap { $0.date?.formatted(date: .abbreviated, time: .shortened) }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func card(_ task: MaintenanceTask) -> some View {
        let status = vm.status(of: task)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: task.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                Text(task.title).font(.headline)
                if task.needsAdmin {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).help("Yönetici parolası gerekir")
                }
                Spacer()
            }
            Text(task.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                switch status {
                case .idle: EmptyView()
                case .running: ProgressView().controlSize(.small)
                case .done: Label("Tamamlandı", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption).lineLimit(2)
                }
                Spacer()
                Button("Çalıştır") { Task { await vm.run(task) } }
                    .disabled(status == .running)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
