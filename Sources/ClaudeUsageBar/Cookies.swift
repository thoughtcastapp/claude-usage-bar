import Foundation
import SQLite3

struct ClaudeCookie: Sendable {
    let name: String
    let value: String
}

enum CookiesError: Error, CustomStringConvertible {
    case dbOpenFailed(String)
    case prepareFailed(String)
    case noCookies
    case sessionKeyMissing
    case orgUUIDMissing
    case decodeFailed
    case underlying(Error)

    var description: String {
        switch self {
        case .dbOpenFailed(let m): return "Cannot open Cookies db: \(m)"
        case .prepareFailed(let m): return "SQLite prepare failed: \(m)"
        case .noCookies: return "No cookies returned for *.claude.ai"
        case .sessionKeyMissing: return "sessionKey cookie missing"
        case .orgUUIDMissing: return "lastActiveOrg cookie missing"
        case .decodeFailed: return "Failed to decode cookie payload as UTF-8"
        case .underlying(let e): return "\(e)"
        }
    }
}

struct CookieJar: Sendable {
    let cookies: [ClaudeCookie]
    let sessionKey: String
    let orgUUID: String

    var headerValue: String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

enum Cookies {
    private static let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Claude/Cookies").path
    }()

    static func load() throws -> CookieJar {
        let raw = try readRawRows()
        let password = try Keychain.claudeSafeStoragePassword()
        let key = try Crypto.deriveKey(
            password: password,
            salt: Data("saltysalt".utf8),
            iterations: 1003,
            keyLength: 16
        )
        let iv = Data(repeating: 0x20, count: 16)

        var resolved: [ClaudeCookie] = []
        resolved.reserveCapacity(raw.count)

        for row in raw {
            let value: String
            if !row.value.isEmpty {
                value = row.value
            } else {
                guard let decrypted = try? decrypt(row.encryptedValue, key: key, iv: iv) else {
                    continue
                }
                value = decrypted
            }
            resolved.append(ClaudeCookie(name: row.name, value: value))
        }

        guard !resolved.isEmpty else { throw CookiesError.noCookies }

        guard let session = resolved.first(where: { $0.name == "sessionKey" })?.value else {
            throw CookiesError.sessionKeyMissing
        }
        guard let orgRaw = resolved.first(where: { $0.name == "lastActiveOrg" })?.value else {
            throw CookiesError.orgUUIDMissing
        }
        let org = orgRaw.removingPercentEncoding ?? orgRaw

        return CookieJar(cookies: resolved, sessionKey: session, orgUUID: org)
    }

    private struct RawRow {
        let name: String
        let value: String
        let encryptedValue: Data
    }

    private static func readRawRows() throws -> [RawRow] {
        // Read-only URI mode lets us coexist with running Claude.app which holds the lock.
        let uri = "file:" + dbPath + "?mode=ro&immutable=1"

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(
            uri,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        )
        guard openResult == SQLITE_OK, let db else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw CookiesError.dbOpenFailed(msg)
        }
        defer { sqlite3_close(db) }

        // Strict host_key match — `LIKE '%claude.ai'` would also match `evil-claude.ai`.
        let sql = """
            SELECT name, value, encrypted_value FROM cookies
            WHERE host_key = 'claude.ai'
               OR host_key = '.claude.ai'
               OR host_key LIKE '%.claude.ai'
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw CookiesError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [RawRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let value = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let encLen = sqlite3_column_bytes(stmt, 2)
            let encData: Data
            if encLen > 0, let ptr = sqlite3_column_blob(stmt, 2) {
                encData = Data(bytes: ptr, count: Int(encLen))
            } else {
                encData = Data()
            }
            rows.append(RawRow(name: name, value: value, encryptedValue: encData))
        }
        return rows
    }

    private static func decrypt(_ encrypted: Data, key: Data, iv: Data) throws -> String {
        guard encrypted.count > 3 else { throw CryptoError.payloadTooShort }
        let prefix = encrypted.prefix(3)
        let body: Data
        if prefix == Data("v10".utf8) || prefix == Data("v11".utf8) {
            body = encrypted.dropFirst(3)
        } else {
            body = encrypted
        }
        guard !body.isEmpty, body.count % 16 == 0 else { throw CryptoError.payloadTooShort }

        let decrypted = try Crypto.aes128CBCDecrypt(ciphertext: body, key: key, iv: iv)
        let unpadded = try Crypto.stripPKCS7Padding(decrypted)
        // Modern Chromium prepends a SHA-256 host hash (32 bytes) before the actual cookie value.
        guard unpadded.count >= 32 else { throw CryptoError.payloadTooShort }
        let payload = unpadded.dropFirst(32)
        guard let text = String(data: payload, encoding: .utf8) else {
            throw CookiesError.decodeFailed
        }
        return text
    }
}
