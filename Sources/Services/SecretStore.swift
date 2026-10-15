import Foundation
import Security

/// Gizli değerleri kullanıcının Application Support klasöründe 0600 izinli tek dosyada tutar.
///
/// Neden anahtar zinciri değil: macOS'un eski (dosya tabanlı) anahtar zincirinde her kaydın
/// kendi erişim listesi vardır ve bu liste kaydı **oluşturan** kod kimliğine bağlıdır.
/// Uygulama yeniden imzalandığında ya da kayıt başka bir sürüm tarafından yazıldığında
/// “Her Zaman İzin Ver” kalıcı olmuyor ve her okumada yeniden soruluyordu.
/// Sorusuz çalışan veri koruma anahtar zinciri ise provisioning profile istiyor,
/// yerel derlemede kullanılamıyor (SecItemAdd → -34018).
///
/// Saklanan değerler (grok.com oturum çerezi, xAI anahtarları) hassasiyet olarak
/// Codex'in düz metin tuttuğu `~/.codex/auth.json` ile aynı sınıfta; dosya yalnızca
/// kullanıcı tarafından okunabilir.
enum SecretStore {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: String]?

    static var fileURL: URL {
        AppPaths.support.appendingPathComponent("secrets.json")
    }

    static func get(_ key: String) -> String? {
        let value = load()[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func set(_ key: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = load()
        if trimmed.isEmpty {
            values.removeValue(forKey: key)
        } else {
            values[key] = trimmed
        }
        save(values)
    }

    private static func load() -> [String: String] {
        lock.lock()
        if let cache {
            lock.unlock()
            return cache
        }
        lock.unlock()

        let values: [String: String]
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
        lock.lock(); cache = values; lock.unlock()
        return values
    }

    private static func save(_ values: [String: String]) {
        lock.lock(); cache = values; lock.unlock()
        guard let data = try? JSONEncoder().encode(values) else { return }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Eski anahtar zinciri kayıtları

    private static let legacyService = "dev.sungur.Hilal"
    /// Ara sürümde kullanılan toplu kayıt: içinde tüm değerlerin JSON sözlüğü var.
    private static let legacyBlobAccount = "secrets"
    /// İlk sürümlerdeki ayrı kayıtlar: her biri düz metin tek değer.
    private static let legacyPlainAccounts = [
        "xai.apiKey", "xai.managementKey", "xai.grokCookies", "xai.grokToken"
    ]

    private static var legacyAccounts: [String] {
        [legacyBlobAccount] + legacyPlainAccounts
    }

    /// Eski kayıtlardan hâlâ duran var mı? (Yalnızca öznitelik okur, soru sormaz.)
    static func legacyItemCount() -> Int {
        legacyAccounts.filter { account in
            var query = legacyQuery(account)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
        }.count
    }

    /// Eski kayıtları dosyaya taşır ve siler. Kayıt başına bir kez şifre sorabilir,
    /// bu yüzden yalnızca kullanıcı Ayarlar'dan açıkça istediğinde çalışır.
    @discardableResult
    static func importLegacyKeychainItems() -> (moved: Int, failed: Int) {
        var values = load()
        var moved = 0
        var failed = 0

        for account in legacyAccounts {
            var query = legacyQuery(account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            switch SecItemCopyMatching(query as CFDictionary, &item) {
            case errSecSuccess:
                if let data = item as? Data {
                    moved += absorb(data, account: account, into: &values)
                }
                SecItemDelete(legacyQuery(account) as CFDictionary)
            case errSecItemNotFound:
                break
            default:
                failed += 1
            }
        }

        if moved > 0 { save(values) }
        return (moved, failed)
    }

    /// Toplu kayıt JSON sözlüğü, ayrı kayıtlar düz metin taşır.
    private static func absorb(_ data: Data, account: String, into values: inout [String: String]) -> Int {
        if account == legacyBlobAccount {
            guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return 0 }
            var count = 0
            for (key, value) in decoded where !value.isEmpty {
                values[key] = value
                count += 1
            }
            return count
        }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return 0 }
        values[account] = text
        return 1
    }

    /// Eski kayıtları okumadan siler. Değerleri elle yeniden girecek kullanıcı için.
    @discardableResult
    static func discardLegacyKeychainItems() -> Int {
        legacyAccounts.filter { SecItemDelete(legacyQuery($0) as CFDictionary) == errSecSuccess }.count
    }

    private static func legacyQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account
        ]
    }
}
