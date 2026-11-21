import SwiftUI

/// Menü çubuğu simgesine tıklayınca açılan küçük panel.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var disk = SystemInfo.disk()
    @State private var memory = MemoryMonitor.stats()
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        let junk = model.junk
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                Text("FCleaner").font(.headline)
                Spacer()
            }

            if let disk {
                meter(
                    title: "Disk",
                    detail: "\(disk.available.formattedBytes) boş",
                    fraction: Double(disk.used) / Double(max(disk.total, 1))
                )
            }
            meter(
                title: "Bellek",
                detail: "\(Int64(clamping: memory.used).formattedBytes) / \(Int64(clamping: memory.total).formattedBytes)",
                fraction: Double(memory.used) / Double(max(memory.total, 1))
            )

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                    Text("Flash Temizlik").font(.callout.weight(.semibold))
                    Spacer()
                    if junk.isScanning || junk.isCleaning { ProgressView().controlSize(.small) }
                }
                if let freed = junk.lastFreed {
                    Text("\(freed.formattedBytes) boşaltıldı.").font(.caption).foregroundStyle(.green)
                } else if junk.hasScanned {
                    Text("\(junk.safeSize.formattedBytes) güvenle temizlenebilir.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Önce tarayın; yalnızca güvenli öğeler temizlenir.").font(.caption).foregroundStyle(.secondary)
                }
                if !junk.hasScanned || junk.lastFreed != nil {
                    Button("Tara") { Task { await junk.scan() } }
                        .disabled(junk.isScanning || junk.isCleaning)
                } else {
                    Button("Temizle (\(junk.safeSize.formattedBytes))") { Task { await junk.flashClean() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(junk.safeSize == 0 || junk.isScanning || junk.isCleaning)
                }
            }

            Divider()

            HStack {
                Button("FCleaner'ı Aç") {
                    openWindow(id: AppSettings.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear(perform: startRefreshing)
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                disk = SystemInfo.disk()
                memory = MemoryMonitor.stats()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func meter(title: String, detail: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                Text(detail).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .accentColor)
        }
    }
}
