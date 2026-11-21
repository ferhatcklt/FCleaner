import Testing
import Foundation
@testable import FCleaner

@Suite struct SimulatorTests {
    @Test func simulatorRuntimeNames() {
        #expect(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-27-0") == "iOS 27.0")
        #expect(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.watchOS-12-1") == "watchOS 12.1")
    }

    @Test func simulatorDeviceFolder() {
        #expect(Simulators.isDeviceFolder(Simulators.devicesDir.appendingPathComponent("0E4A6B1C-2D3F-4A5B-8C7D-9E0F1A2B3C4D")))
        #expect(!Simulators.isDeviceFolder(Simulators.devicesDir.appendingPathComponent("device_set.plist")))
        #expect(!Simulators.isDeviceFolder(Simulators.devicesDir))
    }
}
