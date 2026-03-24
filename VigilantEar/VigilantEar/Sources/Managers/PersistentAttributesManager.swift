//
//  DeviceIdentifier.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/7/26.
//


import Security
import Foundation

class PersistentAttributesManager {
    static let shared = PersistentAttributesManager()
    
    public var staticDeviceIdentifierFromKeychain: String {
        if let existing = loadFromKeychain() {
            return existing
        } else {
            let newID = UUID().uuidString
            saveToKeychain(newID)
            return newID
        }
    }
    
    private func saveToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: AppGlobals.vigilantEarKeystoreIdentifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock  // or .whenUnlocked, etc.
        ]
        
        // Delete any old one first (idempotent)
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: AppGlobals.vigilantEarKeystoreIdentifier,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }
}
