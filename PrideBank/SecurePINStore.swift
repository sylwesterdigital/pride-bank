import CryptoKit
import Foundation
import Security

final class SecurePINStore {
    private let service = "xyz.mojoworks.pridebank"
    private let account = "member-pin-v1"

    var hasPIN: Bool {
        readRecord() != nil
    }

    func save(pin: String) throws {
        let salt = randomBytes(count: 16)
        let digest = hash(pin: pin, salt: salt)
        var payload = Data([1])
        payload.append(salt)
        payload.append(digest)

        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: payload
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PINStoreError.keychain(status)
        }
    }

    func verify(pin: String) -> Bool {
        guard let payload = readRecord(), payload.count == 49, payload.first == 1 else { return false }
        let salt = payload.subdata(in: 1..<17)
        let expected = payload.subdata(in: 17..<49)
        let candidate = hash(pin: pin, salt: salt)
        return constantTimeEqual(candidate, expected)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func readRecord() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func hash(pin: String, salt: Data) -> Data {
        var material = Data()
        material.append(salt)
        material.append(Data(pin.utf8))
        return Data(SHA256.hash(data: material))
    }

    private func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes)
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

enum PINStoreError: Error {
    case keychain(OSStatus)
}
