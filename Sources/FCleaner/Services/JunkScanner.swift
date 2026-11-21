import Foundation

enum JunkScanner {
    static func scan() async -> [JunkCategory] {
        let categories = await withTaskGroup(of: JunkCategory.self) { group in
            for kind in JunkCategory.Kind.allCases {
                group.addTask {
                    let items = items(for: kind).filter { !Exclusions.shared.contains($0.url) }
                    return JunkCategory(kind: kind, items: items.sorted { $0.size > $1.size })
                }
            }
            var result: [JunkCategory] = []
            for await category in group { result.append(category) }
            return result
        }
        let order = JunkCategory.Kind.allCases
        return categories
            .filter { !$0.items.isEmpty }
            .sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }

    static func items(for kind: JunkCategory.Kind) -> [CleanableItem] {
        let base = kind.baseSafety
        func children(_ dir: URL) -> [CleanableItem] { FileSizer.children(of: dir, base: base) }

        switch kind {
        case .userCaches:
            return children(Paths.library("Caches"))

        case .logs:
            return children(Paths.library("Logs"))

        case .developer:
            let childDirs = [
                "Developer/Xcode/DerivedData",
                "Developer/Xcode/iOS DeviceSupport",
                "Developer/Xcode/watchOS DeviceSupport",
                "Developer/Xcode/macOS DeviceSupport",
                "Developer/CoreSimulator/Caches",
            ].map(Paths.library)
            let wholeDirs = [".npm/_cacache", ".gradle/caches", ".cocoapods/repos", ".cache/pip", ".cache/yarn"].map(Paths.home)
            return childDirs.flatMap(children)
                + wholeDirs.map { CleanableItem(url: $0, size: FileSizer.size(of: $0), base: base) }.filter { $0.size > 0 }

        case .simulators:
            return Simulators.list().compactMap { device in
                let size = FileSizer.size(of: device.folder)
                guard size > 0 else { return nil }
                var notes = [device.runtime]
                if !device.isAvailable { notes.append("Kullanılamıyor: sistem dosyası silinmiş") }
                if device.isBooted { notes.append("Şu anda açık") }
                return CleanableItem(
                    url: device.folder,
                    size: size,
                    // Çalışmayan cihazlar işe yaramaz; diğerleri kullanıcıya sorulmalı.
                    base: device.isAvailable ? .review : .safe,
                    label: device.name,
                    note: notes.joined(separator: " · ")
                )
            }

        case .iosUpdates:
            return ["iTunes/iPhone Software Updates", "iTunes/iPad Software Updates"].map(Paths.library).flatMap(children)

        case .installers:
            let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
            return children(Paths.home("Downloads")).filter { extensions.contains($0.url.pathExtension.lowercased()) }

        case .mailDownloads:
            return children(Paths.library("Containers/com.apple.mail/Data/Library/Mail Downloads"))

        case .iosBackups:
            return children(Paths.library("Application Support/MobileSync/Backup"))

        case .trash:
            return children(Paths.home(".Trash"))
        }
    }
}
