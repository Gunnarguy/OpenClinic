import Foundation
import Security

enum SMARTCredentialStoreError: Error, LocalizedError {
    case saveFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case serializationFailed
    case deserializationFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status \(status)."
        case .readFailed(let status):
            return "Keychain read failed with status \(status)."
        case .deleteFailed(let status):
            return "Keychain delete failed with status \(status)."
        case .serializationFailed:
            return "Failed to serialize token response."
        case .deserializationFailed:
            return "Failed to deserialize token response."
        }
    }
}

protocol SMARTCredentialStore: Sendable {
    func saveTokenResponse(_ tokenResponse: SMARTTokenResponse, baseURL: URL, clientID: String) throws
    func readTokenResponse(baseURL: URL, clientID: String) throws -> SMARTTokenResponse?
    func deleteTokenResponse(baseURL: URL, clientID: String) throws
}

struct KeychainSMARTCredentialStore: SMARTCredentialStore {
    static let shared = KeychainSMARTCredentialStore()

    private init() {}

    private func makeService(clientID: String) -> String {
        return "com.openclinic.smart.\(clientID)"
    }

    private func makeAccount(baseURL: URL) -> String {
        return baseURL.absoluteString
    }

    func saveTokenResponse(_ tokenResponse: SMARTTokenResponse, baseURL: URL, clientID: String) throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(tokenResponse) else {
            throw SMARTCredentialStoreError.serializationFailed
        }

        let service = makeService(clientID: clientID)
        let account = makeAccount(baseURL: baseURL)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            let attributesToUpdate: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus != errSecSuccess {
                throw SMARTCredentialStoreError.saveFailed(status: updateStatus)
            }
        } else if status != errSecSuccess {
            throw SMARTCredentialStoreError.saveFailed(status: status)
        }
    }

    func readTokenResponse(baseURL: URL, clientID: String) throws -> SMARTTokenResponse? {
        let service = makeService(clientID: clientID)
        let account = makeAccount(baseURL: baseURL)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        } else if status != errSecSuccess {
            throw SMARTCredentialStoreError.readFailed(status: status)
        }

        guard let data = result as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let tokenResponse = try? decoder.decode(SMARTTokenResponse.self, from: data) else {
            throw SMARTCredentialStoreError.deserializationFailed
        }

        return tokenResponse
    }

    func deleteTokenResponse(baseURL: URL, clientID: String) throws {
        let service = makeService(clientID: clientID)
        let account = makeAccount(baseURL: baseURL)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SMARTCredentialStoreError.deleteFailed(status: status)
        }
    }
}

final class InMemorySMARTCredentialStore: SMARTCredentialStore, @unchecked Sendable {
    private var store: [String: SMARTTokenResponse] = [:]
    private let lock = NSLock()

    func saveTokenResponse(_ tokenResponse: SMARTTokenResponse, baseURL: URL, clientID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(clientID)|\(baseURL.absoluteString)"
        store[key] = tokenResponse
    }

    func readTokenResponse(baseURL: URL, clientID: String) throws -> SMARTTokenResponse? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(clientID)|\(baseURL.absoluteString)"
        return store[key]
    }

    func deleteTokenResponse(baseURL: URL, clientID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(clientID)|\(baseURL.absoluteString)"
        store.removeValue(forKey: key)
    }
}
