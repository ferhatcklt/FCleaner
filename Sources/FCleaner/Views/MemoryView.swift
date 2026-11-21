import SwiftUI

private extension UInt64 {
    var formattedBytes: String { Int64(clamping: self).formattedBytes }
}

private enum MemoryColors {
    static let app = Color.blue
    static let wired = Color.orange
    static let compressed = Color.purple
    static let cached = Color.teal
}

struct MemoryView: View {
    @Bindable var vm: MemoryViewModel
    @State private var pendingQuit: AppMemoryUsage?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .memory, trailing: "\(vm.stats.used.formattedBytes) / \(vm.stats.total.formattedBytes)")

            VStack(spacing: 12) {
                MemoryCompositionCard(stats: vm.stats) { vm.isPurgeSheetPresented = true }
                if let report = vm.lastReport {
                    PurgeReportView(report: report, compact: true)
                        .padding(14)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
                if let message = vm.message {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)

            HStack(alignment: .firstTextBaseline) {
                Text("Uygulamalar").font(.headline)
                Text("Yalnızca sizin işlemleriniz; sistem işlemleri listelenmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SortControl(state: $vm.sort, keys: [.size, .name], sizeTitle: "Bellek")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            List(vm.sortedApps) { usage in
                row(usage)
            }
            .listStyle(.inset)
        }
        .navigationTitle(SidebarItem.memory.title)
        .toolbar {
            Button { vm.isPurgeSheetPresented = true } label: { Label("RAM'i Boşalt", systemImage: "wind") }
        }
        .sheet(isPresented: $vm.isPurgeSheetPresented) { PurgeSheet(vm: vm) }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .confirmationDialog(
            "\(pendingQuit?.name ?? "") kapatılsın mı?",
            isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } })
        ) {
            Button("Çık") {
                if let usage = pendingQuit { Task { await vm.quitSingle(usage) } }
            }
        } message: {
            Text("Uygulamaya normal Çık komutu gönderilir. Kaydedilmemiş belge varsa uygulama size sorar.")
        }
    }

    private func row(_ usage: AppMemoryUsage) -> some View {
        let fraction = Double(usage.footprint) / Double(max(vm.stats.total, 1))
        return HStack(spacing: 10) {
            if let bundle = usage.bundleURL {
                FileIcon(url: bundle, size: 22)
            } else {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(usage.name).lineLimit(1)
                if usage.processCount > 1 {
                    Text("\(usage.processCount) işlem").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fraction > 0.15 ? Color.red : fraction > 0.05 ? Color.orange : Color.accentColor)
                    .frame(width: max(2, 100 * min(fraction * 4, 1)))
            }
            .frame(width: 100, height: 6)
            Text(usage.footprint.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Button("Çık") { pendingQuit = usage }
                .controlSize(.small)
                .opacity(vm.quittableIDs.contains(usage.id) ? 1 : 0)
                .disabled(!vm.quittableIDs.contains(usage.id))
        }
        .padding(.vertical, 2)
    }
}

/// Kullanılan belleğin neye gittiğini gösteren çubuk ve açıklamalar.
private struct MemoryCompositionCard: View {
    let stats: MemoryStats
    let onPurge: () -> Void

    private var segments: [(String, UInt64, Color, String)] {
        [
            ("Uygulamalar", stats.app, MemoryColors.app, "Açık uygulamaların kullandığı bellek."),
            ("Sistem (kablolu)", stats.wired, MemoryColors.wired, "macOS çekirdeğinin ayırdığı, boşaltılamayan bellek."),
            ("Sıkıştırılmış", stats.compressed, MemoryColors.compressed, "Yer açmak için sıkıştırılmış uygulama belleği."),
            ("Önbellek", stats.cached, MemoryColors.cached, "Diskten okunan dosyaların önbelleği. Gerektiğinde anında boşaltılır; RAM boşaltma bunu temizler."),
        ]
    }

    private var pressure: (String, Color) {
        switch stats.pressure {
        case .low: ("Düşük", .green)
        case .medium: ("Orta", .orange)
        case .high: ("Yüksek", .red)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bellek baskısı: \(pressure.0)", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.headline)
                    .foregroundStyle(pressure.1)
                if stats.swapUsed > 0 {
                    Text("· Takas: \(stats.swapUsed.formattedBytes)")
                        .foregroundStyle(.secondary)
                        .help("RAM yetmediğinde diske yazılan bellek. Yüksekse Mac yavaşlar.")
                }
                Spacer()
                Button(action: onPurge) { Label("RAM'i Boşalt", systemImage: "wind") }
                    .buttonStyle(.borderedProminent)
            }

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments, id: \.0) { segment in
                        Rectangle()
                            .fill(segment.2)
                            .frame(width: max(0, proxy.size.width * Double(segment.1) / Double(max(stats.total, 1)) - 2))
                    }
                    Rectangle().fill(.quaternary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .animation(.easeInOut, value: stats)
            }
            .frame(height: 16)

            HStack(spacing: 18) {
                ForEach(segments, id: \.0) { segment in
                    legend(segment.0, segment.1, segment.2).help(segment.3)
                }
                legend("Boş", stats.free, Color.secondary.opacity(0.4))
                    .help("Hiç kullanılmayan bellek. macOS boş RAM'i israf sayar ve önbellek için kullanır; bu normaldir.")
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func legend(_ title: String, _ value: UInt64, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value.formattedBytes).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
    }
}

/// RAM boşaltma öncesi açıklama, isteğe bağlı uygulama kapatma ve sonuç raporu.
private struct PurgeSheet: View {
    @Bindable var vm: MemoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("RAM'i Boşalt", systemImage: "wind").font(.title2.bold())

            if case .running(let step) = vm.phase {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(step)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else if finished, let report = vm.lastReport {
                PurgeReportView(report: report, compact: false)
                HStack {
                    Spacer()
                    Button("Tamam") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                setup
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("macOS boştaki RAM'i, diskten okunan dosyaları hızlı açmak için önbellek olarak kullanır. Bu işlem o önbelleği temizler. **Hiçbir uygulama kapatılmaz** ve kaydedilmemiş işleriniz etkilenmez, aşağıdan siz seçmedikçe.")
                .fixedSize(horizontal: false, vertical: true)

            if !vm.quitCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("İsterseniz bu uygulamaları da kapatın").font(.headline)
                    ForEach(vm.quitCandidates) { usage in
                        HStack(spacing: 8) {
                            Toggle("", isOn: .membership(usage.id, in: $vm.appsToQuit))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                            if let bundle = usage.bundleURL { FileIcon(url: bundle, size: 18) }
                            Text(usage.name)
                            Spacer()
                            Text(Int64(clamping: usage.footprint).formattedBytes)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Seçtiklerinize normal Çık komutu gönderilir; kaydedilmemiş belge varsa uygulama size sorar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Label("Yönetici parolası istenir", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(vm.appsToQuit.isEmpty ? "Boşalt" : "Kapat ve Boşalt") {
                    Task {
                        await vm.purge()
                        finished = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// RAM boşaltma sonucunda ne olduğunu açıkça anlatır.
private struct PurgeReportView: View {
    let report: MemoryViewModel.PurgeReport
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(report.freed > 50_000_000 ? "\(report.freed.formattedBytes) boşaldı" : "Kullanılan bellek belirgin şekilde değişmedi")
                    .font(compact ? .headline : .title3.bold())
                Spacer()
                Text(report.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Kullanılan bellek").foregroundStyle(.secondary)
                    Text("\(report.before.used.formattedBytes) → \(report.after.used.formattedBytes)").monospacedDigit()
                }
                GridRow {
                    Text("Disk önbelleği").foregroundStyle(.secondary)
                    Text(report.purgeError == nil ? "\(report.cacheCleared.formattedBytes) temizlendi" : "temizlenmedi").monospacedDigit()
                }
                GridRow {
                    Text("Boş bellek").foregroundStyle(.secondary)
                    Text("\(report.before.free.formattedBytes) → \(report.after.free.formattedBytes)").monospacedDigit()
                }
            }
            .font(.callout)

            if report.closedApps.isEmpty {
                Label("Hiçbir uygulama kapatılmadı.", systemImage: "app.badge.checkmark")
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kapatılan uygulamalar").font(.callout.weight(.semibold))
                    ForEach(report.closedApps) { result in
                        Text("• \(result.name) (\(result.footprint.formattedBytes))").font(.callout)
                    }
                }
            }
            if !report.refusedApps.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kapanmayan uygulamalar").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                    ForEach(report.refusedApps) { result in
                        Text("• \(result.name): kaydedilmemiş belge olabilir, uygulamaya bakın").font(.callout)
                    }
                }
            }
            if let error = report.purgeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if !compact {
                Text("macOS boşalan alanı zamanla yeniden önbellek için kullanır. Bu normaldir ve Mac'i yavaşlatmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
