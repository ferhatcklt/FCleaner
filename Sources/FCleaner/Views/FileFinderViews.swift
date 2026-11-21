import SwiftUI

struct LargeFilesView: View {
    @Bindable var vm: LargeFilesViewModel
    @State private var confirm = false

    var body: some View {
        Group {
            if vm.isScanning {
                ScanningView(title: "Büyük dosyalar aranıyor…", detail: "\(vm.scannedCount) dosya tarandı", onCancel: vm.cancel)
            } else if !vm.hasScanned {
                VStack(spacing: 0) {
                    ScanPrompt(item: .largeFiles, description: "Ev klasörünüzde (Kitaplık hariç) seçtiğiniz boyuttan büyük dosyaları bulur.") { vm.scan() }
                    thresholdPicker.padding(.bottom, 40)
                }
            } else {
                results
            }
        }
        .navigationTitle(SidebarItem.largeFiles.title)
        .confirmationDialog("Seçili dosyalar Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button("\(vm.selectedSize.formattedBytes) Taşı", role: .destructive) { Task { await vm.removeSelected() } }
        }
    }

    private var thresholdPicker: some View {
        Picker("En küçük boyut", selection: $vm.minSize) {
            ForEach(LargeFilesViewModel.thresholds, id: \.self) { Text($0.formattedBytes).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 360)
    }

    private var results: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .largeFiles, trailing: "\(vm.files.count) dosya")
            HStack {
                thresholdPicker
                Button("Yeniden Tara") { vm.scan() }
                Spacer()
                SortControl(state: $vm.sort, dateTitle: "Değiştirilme")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            ErrorBanner(errors: vm.errors)

            if vm.files.isEmpty {
                EmptyResultView(title: "Büyük dosya yok", detail: "Bu boyutun üstünde dosya bulunamadı.")
            } else {
                List(vm.sortedFiles) { file in
                    FileRow(
                        url: file.url,
                        size: file.size,
                        isOn: .membership(file.url, in: $vm.selected),
                        subtitle: subtitle(for: file),
                        safety: file.safety
                    )
                }
                .listStyle(.inset)
            }

            ActionBar(buttonTitle: "Çöp Sepeti'ne Taşı", disabled: vm.selected.isEmpty, action: { confirm = true }) {
                Text("\(vm.selected.count) dosya · \(vm.selectedSize.formattedBytes)").foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(for file: LargeFile) -> String {
        let folder = file.url.deletingLastPathComponent().tildePath
        guard let date = file.modified else { return folder }
        return "\(folder) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct DuplicatesView: View {
    @Bindable var vm: DuplicatesViewModel
    @State private var confirm = false

    var body: some View {
        Group {
            if vm.isScanning {
                ScanningView(title: "Kopya dosyalar aranıyor…", detail: vm.status, onCancel: vm.cancel)
            } else if !vm.hasScanned {
                ScanPrompt(item: .duplicates, description: "Ev klasörünüzdeki 1 MB'tan büyük dosyaları içeriklerine (SHA-256) göre karşılaştırır. İsim farklı olsa bile birebir aynı olanları bulur.") { vm.scan() }
            } else {
                results
            }
        }
        .navigationTitle(SidebarItem.duplicates.title)
        .confirmationDialog("Seçili kopyalar Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button("\(vm.selectedSize.formattedBytes) Taşı", role: .destructive) { Task { await vm.removeSelected() } }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .duplicates, trailing: "\(vm.totalWasted.formattedBytes) israf")
            HStack {
                Button("En eskiler hariç hepsini seç") { vm.selectAllButOldest() }
                Button("Seçimi temizle") { vm.selected = [] }
                Spacer()
                SortControl(state: $vm.sort, keys: [.size, .name])
                Button("Yeniden Tara") { vm.scan() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            ErrorBanner(errors: vm.errors)

            if vm.groups.isEmpty {
                EmptyResultView(title: "Kopya dosya yok", detail: "Birebir aynı dosya bulunamadı.")
            } else {
                List {
                    ForEach(vm.sortedGroups) { group in
                        Section {
                            ForEach(group.files, id: \.self) { url in
                                FileRow(
                                    url: url,
                                    size: group.size,
                                    isOn: .membership(url, in: $vm.selected),
                                    disabled: !vm.canSelect(url, in: group),
                                    safety: SafetyPolicy.level(for: url)
                                )
                            }
                        } header: {
                            Text("\(group.files.count) kopya · her biri \(group.size.formattedBytes)")
                        }
                    }
                }
                .listStyle(.inset)
            }

            ActionBar(buttonTitle: "Çöp Sepeti'ne Taşı", disabled: vm.selected.isEmpty, action: { confirm = true }) {
                Text("\(vm.selected.count) dosya · \(vm.selectedSize.formattedBytes)").foregroundStyle(.secondary)
            }
        }
    }
}
