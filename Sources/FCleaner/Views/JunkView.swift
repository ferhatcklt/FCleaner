import SwiftUI

struct JunkView: View {
    @Bindable var vm: JunkViewModel
    @State private var expanded: Set<String> = []
    @State private var confirmClean = false

    var body: some View {
        Group {
            if vm.isScanning {
                ScanningView(title: "Sistem çöpü taranıyor…")
            } else if !vm.hasScanned {
                ScanPrompt(item: .junk, description: "Uygulama önbelleklerini, log dosyalarını, Xcode artıklarını, eski kurulum dosyalarını ve Çöp Sepeti'ni tarar. Seçtikleriniz Çöp Sepeti'ne taşınır.") {
                    Task { await vm.scan() }
                }
            } else {
                results
            }
        }
        .navigationTitle(SidebarItem.junk.title)
        .toolbar {
            if vm.hasScanned && !vm.isScanning && !vm.isCleaning {
                Button { vm.selectRecommended() } label: { Label("Önerilenleri Seç", systemImage: "checkmark.shield") }
                Button { Task { await vm.scan() } } label: { Label("Yeniden Tara", systemImage: "arrow.clockwise") }
            }
        }
        .confirmationDialog("Seçili öğeler temizlensin mi?", isPresented: $confirmClean) {
            Button("\(vm.selectedSize.formattedBytes) Temizle", role: .destructive) { Task { await vm.clean() } }
        } message: {
            Text("Öğeler Çöp Sepeti'ne taşınır, geri alınabilir. Çöp Sepeti kategorisi seçiliyse o dosyalar kalıcı olarak silinir. Kilitli (kritik) öğeler atlanır.")
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .junk, trailing: vm.totalSize.formattedBytes)
            if let freed = vm.lastFreed {
                Label("\(freed.formattedBytes) alan boşaltıldı", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            HStack {
                SortControl(state: $vm.sort)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            ErrorBanner(errors: vm.errors)

            if vm.categories.isEmpty {
                EmptyResultView(title: "Her şey temiz", detail: "Temizlenecek bir şey bulunamadı.") {
                    Task { await vm.scan() }
                }
            } else {
                List {
                    ForEach(vm.categories) { category in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expanded.contains(category.id) },
                            set: { if $0 { expanded.insert(category.id) } else { expanded.remove(category.id) } }
                        )) {
                            ForEach(category.items.sorted(vm.sort, size: \.size, name: { $0.label ?? $0.name }, date: \.modified)) { item in
                                FileRow(
                                    url: item.url,
                                    size: item.size,
                                    isOn: .membership(item.url, in: $vm.selected),
                                    subtitle: item.note,
                                    safety: item.safety,
                                    title: item.label
                                )
                            }
                        } label: {
                            categoryRow(category)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }

            ActionBar(
                buttonTitle: "Temizle",
                disabled: vm.selected.isEmpty,
                isWorking: vm.isCleaning,
                action: { confirmClean = true }
            ) {
                Text("\(vm.selected.count) öğe seçildi · \(vm.selectedSize.formattedBytes)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func categoryRow(_ category: JunkCategory) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { vm.isCategorySelected(category) },
                set: { vm.setCategory(category, selected: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(category.deletesPermanently ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).font(.headline)
                Text(category.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if category.kind.baseSafety == .critical || category.items.contains(where: { $0.safety == .critical }) {
                SafetyBadge(level: .critical)
            } else {
                SafetyBadge(level: category.kind.baseSafety)
            }
            Text("\(category.items.count) öğe").font(.caption).foregroundStyle(.secondary)
            Text(category.totalSize.formattedBytes)
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
