import SwiftUI

/// "Güncellemeleri Denetle…" penceresi.
struct UpdateSheet: View {
    @Bindable var updater: Updater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(.title3.bold())
                    Text("Yüklü sürüm: \(updater.currentVersion)").foregroundStyle(.secondary)
                }
            }

            content

            Divider()
            HStack {
                Toggle("Güncellemeleri otomatik denetle", isOn: $updater.automaticallyChecks)
                    .toggleStyle(.checkbox)
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var headline: String {
        switch updater.state {
        case .idle, .checking: "Güncellemeler denetleniyor…"
        case .upToDate: "FCleaner güncel"
        case .available(let release): "FCleaner \(release.version) hazır"
        case .installing: "Güncelleniyor"
        case .failed: "Güncelleme denetlenemedi"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking:
            ProgressView().frame(maxWidth: .infinity)
        case .upToDate:
            Label("En son sürümü kullanıyorsunuz.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                if let date = release.publishedAt {
                    Text("Yayın tarihi: \(date.formatted(date: .long, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(notes(release.notes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                if let blocker = updater.installBlocker {
                    Label(blocker, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .installing(let step):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(step)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch updater.state {
        case .available(let release):
            Button("Sürüm Sayfası") { NSWorkspace.shared.open(release.pageURL) }
            Button(updater.canInstallUpdates ? "Şimdi Güncelle" : "İndirme Sayfasını Aç") { Task { await updater.install() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .installing:
            EmptyView()
        case .failed:
            Button("Tekrar Dene") { Task { await updater.check(userInitiated: true) } }
            Button("Kapat") { dismiss() }.keyboardShortcut(.defaultAction)
        default:
            Button("Kapat") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }

    private func notes(_ markdown: String) -> AttributedString {
        let text = markdown.isEmpty ? "Sürüm notu yok." : markdown
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Genel Bakış'ın üstünde, yeni sürüm olduğunda görünen bant.
struct UpdateBanner: View {
    let updater: Updater

    var body: some View {
        if let release = updater.availableRelease {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FCleaner \(release.version) yayınlandı").font(.headline)
                    Text("Şu an \(updater.currentVersion) sürümünü kullanıyorsunuz.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Ayrıntılar") { updater.isSheetPresented = true }
                Button("Güncelle") {
                    updater.isSheetPresented = true
                    Task { await updater.install() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
