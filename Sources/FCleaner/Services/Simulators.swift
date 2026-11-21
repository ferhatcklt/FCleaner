import Foundation

struct SimulatorDevice: Sendable {
    let udid: String
    let name: String
    let runtime: String
    let isAvailable: Bool
    let isBooted: Bool
    let folder: URL
}

/// Xcode iOS Simülatörü cihazları. Cihaz klasörleri Finder'dan değil `simctl` ile silinir,
/// yoksa CoreSimulator'ın cihaz listesi bozulur.
enum Simulators {
    static let devicesDir = Paths.library("Developer/CoreSimulator/Devices")

    /// Simülatör cihazı olan bir Mac mi? (Xcode kurulu değilse bu klasör yoktur.)
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: devicesDir.path)
    }

    static func list() -> [SimulatorDevice] {
        // Xcode yoksa xcrun "geliştirici araçlarını yükle" penceresi açar; cihaz klasörü yoksa hiç çağırma.
        guard isInstalled else { return [] }
        guard let data = try? simctl(["list", "devices", "--json"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else { return [] }

        return runtimes.flatMap { runtimeID, devices in
            devices.compactMap { device -> SimulatorDevice? in
                guard let udid = device["udid"] as? String, let name = device["name"] as? String else { return nil }
                return SimulatorDevice(
                    udid: udid,
                    name: name,
                    runtime: runtimeName(runtimeID),
                    isAvailable: device["isAvailable"] as? Bool ?? true,
                    isBooted: (device["state"] as? String) == "Booted",
                    folder: devicesDir.appendingPathComponent(udid)
                )
            }
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-0" → "iOS 27.0"
    static func runtimeName(_ id: String) -> String {
        let raw = id.components(separatedBy: ".").last ?? id
        var parts = raw.components(separatedBy: "-")
        guard parts.count > 1 else { return raw }
        let platform = parts.removeFirst()
        return "\(platform) \(parts.joined(separator: "."))"
    }

    /// Klasör bir simülatör cihazına mı ait? (…/CoreSimulator/Devices/<UUID>)
    static func isDeviceFolder(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == devicesDir.standardizedFileURL.path
            && UUID(uuidString: url.lastPathComponent) != nil
    }

    static func delete(udid: String) throws {
        _ = try simctl(["delete", udid])
    }

    enum Failure: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { message } else { nil } }
    }

    @discardableResult
    private static func simctl(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed(message?.isEmpty == false ? message! : "simctl hata kodu \(process.terminationStatus)")
        }
        return data
    }
}
