import SwiftUI

struct HistoryView: View {
    private var log: DeletionLog { .shared }
    @State private var confirmClear = false
    @State private var error: String?

    private var days: [(Date, [DeletionLog.Entry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: log.entries) { calendar.startOfDay(for: $0.date) }
        return grouped.sorted { $0.key > $1.key }
    }

    private var totalSize: Int64 { log.entries.reduce(0) { $0 + ($1.size ?? 0) } }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(item: .history, trailing: log.entries.isEmpty ? nil : "\(totalSize.formattedBytes) boşaltıldı")
            Text("Çöp Sepeti'ne taşınanlar, Çöp Sepeti boşaltılana kadar buradan eski yerlerine geri yüklenebilir.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            if let error {
                ErrorBanner(errors: [error])
            }

            if log.entries.isEmpty {
                ContentUnavailableView(
                    "Henüz bir şey silinmedi",
                    systemImage: "clock",
                    description: Text("FCleaner'ın sildiği her şey burada listelenir.")
                )
            } else {
                List {
                    ForEach(days, id: \.0) { day, entries in
                        Section(day.formatted(date: .complete, time: .omitted)) {
                            ForEach(entries) { entry in row(entry) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(SidebarItem.history.title)
        .toolbar {
            Button { confirmClear = true } label: { Label("Geçmişi Temizle", systemImage: "trash.slash") }
                .disabled(log.entries.isEmpty)
        }
        .confirmationDialog("Silme geçmişi temizlensin mi?", isPresented: $confirmClear) {
            Button("Geçmişi Temizle", role: .destructive) { log.clear() }
        } message: {
            Text("Yalnızca kayıtlar silinir; Çöp Sepeti'ndeki dosyalar yerinde kalır ama buradan geri yüklenemez.")
        }
    }

    private func row(_ entry: DeletionLog.Entry) -> some View {
        let original = URL(fileURLWithPath: entry.originalPath)
        return HStack(spacing: 10) {
            FileIcon(url: entry.trashedPath.map(URL.init(fileURLWithPath:)) ?? original)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                Text(original.deletingLastPathComponent().tildePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(entry.method.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(entry.method == .trash ? Color.secondary : Color.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(entry.size.map(\.formattedBytes) ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
            if entry.canRestore {
                Button("Geri Yükle") {
                    do {
                        try log.restore(entry)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .controlSize(.small)
            } else {
                Color.clear.frame(width: 72, height: 1)
            }
        }
        .padding(.vertical, 2)
    }
}
