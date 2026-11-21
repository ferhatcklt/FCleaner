import SwiftUI
import AppKit

extension Int64 {
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension URL {
    var tildePath: String { (path as NSString).abbreviatingWithTildeInPath }
}

extension Binding where Value == Bool {
    /// Bir kümedeki elemanın varlığını Bool olarak bağlar (onay kutuları için).
    static func membership<T: Hashable>(_ element: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(element) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(element) } else { set.wrappedValue.remove(element) }
            }
        )
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct FileRow: View {
    let url: URL
    let size: Int64
    @Binding var isOn: Bool
    var subtitle: String?
    var disabled = false
    var safety: SafetyLevel?
    var title: String?

    private var lock: ProtectionLock { .shared }
    private var isLocked: Bool { safety == .critical && !lock.isUnlocked }
    /// `paths` okunarak hariç tutma listesindeki değişiklikler izlenir.
    private var isExcluded: Bool {
        _ = Exclusions.shared.paths
        return Exclusions.shared.contains(url)
    }

    var body: some View {
        if !isExcluded { row }
    }

    private var row: some View {
        HStack(spacing: 10) {
            if isLocked {
                // Kritik dosya: onay kutusu yerine kilit; tıklanınca kimlik doğrulama istenir.
                Button { Task { await lock.unlock() } } label: {
                    Image(systemName: "lock.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .frame(width: 16)
                .help("Kritik dosya. Seçmek için kilidi açın.")
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(disabled)
            }
            FileIcon(url: url)
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(safety == .critical ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let safety { SafetyBadge(level: safety) }
            Text(size.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            RevealButton(url: url)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .opacity(isLocked ? 0.75 : 1)
        .contextMenu {
            Button("Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Bunu Hariç Tut") {
                isOn = false
                Exclusions.shared.add(url)
            }
        }
    }

    private var detailText: String {
        if safety == .critical, let reason = SafetyPolicy.criticalReason(for: url) { return "Kritik: \(reason)" }
        return subtitle ?? url.deletingLastPathComponent().tildePath
    }
}

struct SafetyBadge: View {
    let level: SafetyLevel

    private var color: Color {
        switch level {
        case .safe: .green
        case .review: .orange
        case .critical: .red
        }
    }

    var body: some View {
        Label(level.title, systemImage: level.icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

struct RevealButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "arrow.right.circle")
        }
        .buttonStyle(.borderless)
        .help("Finder'da göster")
    }
}

/// Liste altındaki özet + ana eylem çubuğu.
struct ActionBar<Leading: View>: View {
    let buttonTitle: String
    var buttonIcon = "trash"
    var disabled = false
    var isWorking = false
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer()
            if isWorking { ProgressView().controlSize(.small) }
            Button(action: action) {
                Label(buttonTitle, systemImage: buttonIcon)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(disabled || isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// Henüz tarama yapılmamış bir bölümün karşılama ekranı.
struct ScanPrompt: View {
    let item: SidebarItem
    let description: String
    var buttonTitle = "Taramayı Başlat"
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: item.icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(item.title).font(.title.bold())
                Text(description)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button(action: action) {
                Text(buttonTitle).padding(.horizontal, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ScanningView: View {
    let title: String
    var detail: String?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(title).font(.headline)
            if let detail { Text(detail).foregroundStyle(.secondary).monospacedDigit() }
            if let onCancel { Button("İptal", action: onCancel) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyResultView: View {
    let title: String
    var detail = ""
    var rescan: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "checkmark.seal")
        } description: {
            Text(detail)
        } actions: {
            if let rescan { Button("Yeniden Tara", action: rescan) }
        }
    }
}

/// Silme sırasında oluşan hataları gösterir.
struct ErrorBanner: View {
    let errors: [String]

    var body: some View {
        if !errors.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(errors, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("\(errors.count) öğe silinemedi", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

struct SectionHeader: View {
    let item: SidebarItem
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.title2.bold())
                Text(item.subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            if let trailing {
                Text(trailing).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - Sıralama

enum SortKey: String, CaseIterable, Identifiable {
    case size = "Boyut"
    case name = "Ad"
    case date = "Tarih"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .size: "internaldrive"
        case .name: "textformat"
        case .date: "calendar"
        }
    }

    /// Her anahtar için en mantıklı varsayılan yön: boyut ve tarihte büyük/yeni önce, adda A→Z.
    var defaultAscending: Bool { self == .name }
}

struct SortState: Equatable {
    var key: SortKey = .size
    var ascending = false

    mutating func select(_ newKey: SortKey) {
        if newKey == key {
            ascending.toggle()
        } else {
            key = newKey
            ascending = newKey.defaultAscending
        }
    }
}

extension Array {
    func sorted(
        _ state: SortState,
        size: (Element) -> Int64,
        name: (Element) -> String,
        date: (Element) -> Date?
    ) -> [Element] {
        sorted { a, b in
            let inOrder: Bool
            switch state.key {
            case .size:
                inOrder = size(a) < size(b)
            case .name:
                inOrder = name(a).localizedStandardCompare(name(b)) == .orderedAscending
            case .date:
                inOrder = (date(a) ?? .distantPast) < (date(b) ?? .distantPast)
            }
            return state.ascending ? inOrder : !inOrder
        }
    }
}

/// Boyut / Ad / Tarih seçici. Aynı anahtara tekrar tıklamak yönü tersine çevirir.
struct SortControl: View {
    @Binding var state: SortState
    var keys: [SortKey] = SortKey.allCases
    var dateTitle = "Tarih"
    var sizeTitle = "Boyut"

    var body: some View {
        HStack(spacing: 2) {
            Text("Sırala:").font(.callout).foregroundStyle(.secondary).padding(.trailing, 4)
            ForEach(keys) { key in
                let isActive = state.key == key
                Button {
                    withAnimation(.snappy) { state.select(key) }
                } label: {
                    HStack(spacing: 3) {
                        Text(key == .date ? dateTitle : key == .size ? sizeTitle : key.rawValue)
                        if isActive {
                            Image(systemName: state.ascending ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .font(.callout.weight(isActive ? .semibold : .regular))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isActive ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: Capsule())
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
