import SwiftUI
import AppKit

/// Tam Disk Erişimi kurulumunu hızlandırır: Sistem Ayarları'nı doğru sayfada açar, yanına
/// FCleaner simgesinin listeye sürüklenebildiği yüzen bir pencere koyar ve izin verildiği anda bunu algılar.
@MainActor
@Observable
final class FullDiskAccessHelper {
    static let shared = FullDiskAccessHelper()

    private(set) var isGranted = SystemInfo.hasFullDiskAccess
    private var panel: NSPanel?
    private var pollTask: Task<Void, Never>?

    /// İzin yalnızca paketlenmiş .app'e verilebilir; `swift run` ile çalışırken izin Terminal'e gider.
    var isRunningFromBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var appURL: URL { Bundle.main.bundleURL }

    func start() {
        SystemInfo.openFullDiskAccessSettings()
        showPanel()
        startPolling()
    }

    func refresh() {
        isGranted = SystemInfo.hasFullDiskAccess
    }

    func closePanel() {
        pollTask?.cancel()
        panel?.close()
        panel = nil
    }

    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if SystemInfo.hasFullDiskAccess {
                    withAnimation { self.isGranted = true }
                    NSApp.activate(ignoringOtherApps: true)
                    return
                }
            }
        }
    }

    private func showPanel() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let size = NSSize(width: 340, height: 300)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Tam Disk Erişimi"
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // Simge sürüklenirken pencerenin kaymaması için arka plandan taşıma kapalı; pencere başlık çubuğundan taşınır.
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: FullDiskAccessGuide(helper: self))

        // Sistem Ayarları penceresinin yanına, ekranın sağ alt köşesine yerleştir.
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

struct FullDiskAccessGuide: View {
    let helper: FullDiskAccessHelper
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            if helper.isGranted {
                granted
            } else if !helper.isRunningFromBundle {
                notBundled
            } else {
                instructions
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 340, height: 300)
    }

    private var instructions: some View {
        VStack(spacing: 14) {
            Text("FCleaner'ı listeye sürükleyin")
                .font(.headline)

            // Sürüklenebilir uygulama simgesi.
            VStack(spacing: 6) {
                DraggableFileIcon(url: helper.appURL)
                    .frame(width: 72, height: 72)
                    .scaleEffect(pulse ? 1.06 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("FCleaner").font(.callout.weight(.medium))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
                    .foregroundStyle(.tint)
            )
            .help("Bu simgeyi Sistem Ayarları'ndaki Tam Disk Erişimi listesine sürükleyin")
            .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 4) {
                step(1, "Simgeyi açılan listeye bırakın")
                step(2, "FCleaner'ın yanındaki anahtarı açın")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                ProgressView().controlSize(.small)
                Text("İzin bekleniyor…").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Ayarları Aç") { SystemInfo.openFullDiskAccessSettings() }
                    .controlSize(.small)
            }
        }
    }

    private var granted: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: helper.isGranted)
            Text("Tam Disk Erişimi verildi").font(.title3.bold())
            Text("Artık tüm klasörler taranabilir. Bazı durumlarda değişikliğin tamamen geçerli olması için yeniden başlatmak gerekir.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Yeniden Başlat") { helper.relaunch() }
                Button("Tamam") { helper.closePanel() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var notBundled: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Geliştirme modunda çalışıyor").font(.headline)
            Text("`swift run` ile açılan FCleaner'a izin verilemez; izin Terminal'e gider. Önce `./scripts/build-app.sh` ile paketleyip build/FCleaner.app'i açın.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Kapat") { helper.closePanel() }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.tint))
            Text(text).font(.callout)
        }
    }
}

/// Finder'daki gibi gerçek bir dosya sürüklemesi başlatan simge.
/// SwiftUI'nin `onDrag`'i yüzen panellerde pencereyi taşıyabildiği için AppKit sürükleme oturumu kullanılır.
struct DraggableFileIcon: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.url = url
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.url = url
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var url: URL? { didSet { needsDisplay = true } }
        private var icon: NSImage? { url.map { NSWorkspace.shared.icon(forFile: $0.path) } }

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            icon?.draw(in: bounds)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let url, let icon else { return }
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .link, .generic] : []
        }
    }
}
