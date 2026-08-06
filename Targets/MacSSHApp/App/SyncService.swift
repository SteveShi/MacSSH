import Foundation
import CryptoKit

struct EncryptionHelper {
    private static func deriveKey(password: String, salt: String) -> SymmetricKey {
        let passwordData = password.data(using: .utf8) ?? Data()
        let saltData = salt.data(using: .utf8) ?? Data()
        var hasher = SHA256()
        hasher.update(data: passwordData)
        hasher.update(data: saltData)
        let digest = hasher.finalize()
        return SymmetricKey(data: Data(digest))
    }

    static func encrypt(text: String, password: String) throws -> String {
        let plainData = text.data(using: .utf8) ?? Data()
        let salt = "MacSSHSyncSalt"
        let key = deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(plainData, using: key)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Encryption failed")])
        }
        return "MACSSH_ENC:" + combined.base64EncodedString()
    }

    static func decrypt(encryptedText: String, password: String) throws -> String {
        guard encryptedText.hasPrefix("MACSSH_ENC:") else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Not encrypted or invalid prefix")])
        }
        let base64Part = String(encryptedText.dropFirst("MACSSH_ENC:".count))
        guard let combinedData = Data(base64Encoded: base64Part) else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid base64 payload")])
        }
        let salt = "MacSSHSyncSalt"
        let key = deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid utf8 decrypted data")])
        }
        return decryptedString
    }
}

struct GistSyncResponse: Codable {
    let id: String
    let html_url: String?
    let files: [String: GistFile]
}

struct GistFile: Codable {
    let filename: String?
    let type: String?
    let language: String?
    let raw_url: String?
    let size: Int?
    let truncated: Bool?
    let content: String?
}

enum GistSyncService {
    static func upload(token: String, gistId: String?, connections: [SSHConnection], password: String? = nil) async throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(connections)
        var contentString = String(data: data, encoding: .utf8) ?? ""
        if contentString.isEmpty {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to convert connections data to string")])
        }
        if let password, !password.isEmpty {
            contentString = try EncryptionHelper.encrypt(text: contentString, password: password)
        }

        let urlString: String
        let method: String
        if let id = gistId, !id.isEmpty {
            urlString = "https://api.github.com/gists/\(id)"
            method = "PATCH"
        } else {
            urlString = "https://api.github.com/gists"
            method = "POST"
        }

        guard let url = URL(string: urlString) else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid Gist URL")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MacSSH-App", forHTTPHeaderField: "User-Agent")

        var bodyJSON: [String: Any] = [
            "description": "MacSSH Server Configurations Sync",
            "files": [
                "connections.json": [
                    "content": contentString
                ]
            ]
        ]
        
        if gistId == nil || gistId!.isEmpty {
            bodyJSON["public"] = false
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyJSON, options: [])

        let (resData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseString = String(data: resData, encoding: .utf8) ?? "No detail"
            throw NSError(domain: "MacSSH", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub Gist API error (status \(statusCode)): \(responseString)"])
        }

        let decoder = JSONDecoder()
        let gistResponse = try decoder.decode(GistSyncResponse.self, from: resData)
        return gistResponse.id
    }

    static func download(token: String, gistId: String) async throws -> Data {
        guard !gistId.isEmpty else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Gist ID is empty")])
        }
        guard let url = URL(string: "https://api.github.com/gists/\(gistId)") else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid Gist URL")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MacSSH-App", forHTTPHeaderField: "User-Agent")

        let (resData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "MacSSH", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub Gist API error (status \(statusCode))"])
        }

        let gistResponse = try JSONDecoder().decode(GistSyncResponse.self, from: resData)
        guard let file = gistResponse.files["connections.json"],
              let content = file.content,
              let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "connections.json file not found in Gist")])
        }

        return contentData
    }
}

enum DropboxSyncService {
    static func upload(token: String, connections: [SSHConnection], password: String? = nil) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(connections)
        var uploadData = data
        if let password, !password.isEmpty {
            guard let contentString = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to convert connections data to string")])
            }
            let encryptedString = try EncryptionHelper.encrypt(text: contentString, password: password)
            guard let encryptedData = encryptedString.data(using: .utf8) else {
                throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to convert encrypted data to Data")])
            }
            uploadData = encryptedData
        }

        guard let url = URL(string: "https://content.dropboxapi.com/2/files/upload") else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid Dropbox URL")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let apiArg: [String: Any] = [
            "path": "/connections.json",
            "mode": "overwrite",
            "autorename": false,
            "mute": true,
            "strict_conflict": false
        ]
        let apiArgData = try JSONSerialization.data(withJSONObject: apiArg, options: [])
        guard let apiArgString = String(data: apiArgData, encoding: .utf8) else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to construct Dropbox-API-Arg")])
        }
        request.setValue(apiArgString, forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = uploadData

        let (resData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseString = String(data: resData, encoding: .utf8) ?? "No detail"
            throw NSError(domain: "MacSSH", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Dropbox API error (status \(statusCode)): \(responseString)"])
        }
    }

    static func download(token: String) async throws -> Data {
        guard let url = URL(string: "https://content.dropboxapi.com/2/files/download") else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid Dropbox URL")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let apiArg: [String: Any] = [
            "path": "/connections.json"
        ]
        let apiArgData = try JSONSerialization.data(withJSONObject: apiArg, options: [])
        guard let apiArgString = String(data: apiArgData, encoding: .utf8) else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to construct Dropbox-API-Arg")])
        }
        request.setValue(apiArgString, forHTTPHeaderField: "Dropbox-API-Arg")

        let (resData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseString = String(data: resData, encoding: .utf8) ?? "No detail"
            throw NSError(domain: "MacSSH", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Dropbox API error (status \(statusCode)): \(responseString)"])
        }

        return resData
    }
}
