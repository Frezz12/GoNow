import Foundation
import UIKit

final class DeviceIdentityProvider: @unchecked Sendable {
    private let keychain: KeychainStore

    init(keychain: KeychainStore) { self.keychain = keychain }

    func payload() throws -> DevicePayload {
        let id: String
        if let existing = try keychain.readString(account: "device-id") { id = existing }
        else {
            id = UUID().uuidString
            try keychain.saveString(id, account: "device-id")
        }
        return DevicePayload(deviceId: id, deviceName: UIDevice.current.name, platform: "ios")
    }
}
