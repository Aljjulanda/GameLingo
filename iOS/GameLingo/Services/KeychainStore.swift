import Foundation
import Security

enum KeychainStore {
    static func read(_ account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass:kSecClassGenericPassword,kSecAttrService:"dev.gamelingo.ios",kSecAttrAccount:account,kSecReturnData:true,kSecMatchLimit:kSecMatchLimitOne] as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LingoError.invalid("تعذرت قراءة Keychain (\(status))") }
        return result as? Data
    }
    static func write(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [kSecClass:kSecClassGenericPassword,kSecAttrService:"dev.gamelingo.ios",kSecAttrAccount:account]
        let status = SecItemUpdate(query as CFDictionary,[kSecValueData:data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData] = data; item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw LingoError.invalid("تعذر حفظ Keychain") }
        } else if status != errSecSuccess { throw LingoError.invalid("تعذر تحديث Keychain (\(status))") }
    }
    static func delete(_ account: String) {
        SecItemDelete([kSecClass:kSecClassGenericPassword,kSecAttrService:"dev.gamelingo.ios",kSecAttrAccount:account] as CFDictionary)
    }
    static func random(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0,count: count)
        guard SecRandomCopyBytes(kSecRandomDefault,count,&bytes) == errSecSuccess else { throw LingoError.invalid("تعذر إنشاء قيمة عشوائية آمنة") }
        return Data(bytes)
    }
}
