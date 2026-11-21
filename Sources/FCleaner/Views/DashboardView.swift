import SwiftUI
import Combine

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var disk = SystemInfo.disk()
    @State private var memory = SystemInfo.memory()
    private var fullDiskAccess: FullDiskAccessHelper { .shared }

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                UpdateBanner(updater: .shared)
                if !fullDiskAccess.isGranted { fullDiskAccessBanner }

                HStack(spacing: 16) {
                    if let disk {
                        UsageCard(
                            title: "Disk",
                            icon: "internaldrive",
                            used: disk.used,
                            total: disk.total,
                            footer: "\(disk.available.formattedBytes) boş"
                        )
                    }
                    UsageCard(
                        title: "Bellek",
                        icon: "memorychip",
                        used: Int64(memory.used),
                        total: Int64(memory.total),
                        footer: "\(Int64(memory.total - memory.used).formattedBytes) boş · Ayrıntılar →"
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { model.selection = .memory }
                    .help("RAM'i neyin kullandığını gör")
                }

                smartScanCard

                Text("Araçlar").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(SidebarItem.allCases.filter { $0 != .dashboard }) { item in
                        ToolCard(item: item) { model.selection = item }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Genel Bakış")
        .onReceive(timer) { _ in
            memory = SystemInfo.memory()
            disk = SystemInfo.disk()
        }
        .onAppear { fullDiskAccess.refresh() }
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tam Disk Erişimi önerilir").font(.headline)
                Text("Mail ekleri ve bazı uygulama kapsayıcıları bu izin olmadan taranamaz. Hızlı Kurulum ile simgeyi sürükleyip bırakmanız yeterli.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Hızlı Kurulum") { fullDiskAccess.start() }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var smartScanCard: some View {
        let junk = model.junk
        let items = junk.categories.flatMap(\.items)
        func size(_ level: SafetyLevel) -> Int64 { items.filter { $0.safety == level }.reduce(0) { $0 + $1.size } }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Flash Temizlik").font(.title3.bold())
                    if junk.isScanning {
                        Text("Sistem taranıyor…").foregroundStyle(.secondary)
                    } else if junk.isCleaning {
                        Text("Temizleniyor…").foregroundStyle(.secondary)
                    } else if let freed = junk.lastFreed {
                        Text("\(freed.formattedBytes) alan boşaltıldı.").foregroundStyle(.green)
                    } else if junk.hasScanned {
                        Text("\(junk.safeSize.formattedBytes) güvenle temizlenebilir.").foregroundStyle(.secondary)
                    } else {
                        Text("Tek tıkla yalnızca silinmesi güvenli olan önbellek, log ve geliştirici artıklarını temizler.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if junk.isScanning || junk.isCleaning {
                    ProgressView().controlSize(.small)
                } else if !junk.hasScanned {
                    Button("Tara") { Task { await junk.scan() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Ayrıntılar") { model.selection = .junk }
                    Button("Flash Temizle") { Task { await junk.flashClean() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(junk.safeSize == 0)
                }
            }

            if junk.hasScanned && !junk.isScanning {
                HStack(spacing: 10) {
                    SafetySummary(level: .safe, size: size(.safe), note: "Flash Temizlik bunları siler")
                    SafetySummary(level: .review, size: size(.review), note: "Ayrıntılardan seçebilirsiniz")
                    SafetySummary(level: .critical, size: size(.critical), note: "Kilit açılmadan silinmez")
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SafetySummary: View {
    let level: SafetyLevel
    let size: Int64
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SafetyBadge(level: level)
            Text(size.formattedBytes).font(.title3.weight(.semibold)).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct UsageCard: View {
    let title: String
    let icon: String
    let used: Int64
    let total: Int64
    let footer: String

    private var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    private var tint: Color { fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .accentColor }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: fraction)
                Text("\(Int(fraction * 100))%").font(.headline).monospacedDigit()
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon).font(.headline)
                Text("\(used.formattedBytes) / \(total.formattedBytes)").monospacedDigit()
                Text(footer).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ToolCard: View {
    let item: SidebarItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quaternary.opacity(0.5)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
