import AppCore
import Foundation
import LocalAuthentication
import Observation
import Security

/// 가리기/휴지통 접근 제어 게이트.
/// Touch ID(또는 암호 폴백)로 잠금 해제하며, 앱 재시작 시 초기화된다(메모리에만 유지).
@MainActor
@Observable
public final class PrivacyGate {
    public private(set) var unlockedThisSession = false

    public init() {}

    /// 생체 인증(불가 시 기기 암호 폴백) 요청.
    @discardableResult
    public func unlock(reason: String) async -> Bool {
        if unlockedThisSession { return true }
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            unlockedThisSession = success
            return success
        } catch {
            return false
        }
    }

    public func lock() {
        unlockedThisSession = false
    }
}

/// API 키 등 비밀 값을 위한 Keychain 저장소.
public struct KeychainStore: Sendable {
    let service: String

    public init(service: String = "com.seolhwarim.sonnetcreate") {
        self.service = service
    }

    public func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
