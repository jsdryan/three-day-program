import Foundation

// 直接打 Supabase REST：Email 驗證碼登入、讀 prefs、寫 sessions
struct AuthSession: Codable {
    var access: String
    var refresh: String
    var expires: Date
    var uid: String
    var email: String
}

enum SupaError: LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return code == 0 ? msg : "連線錯誤（\(code)）：\(msg)"
        }
    }
}

final class Supa {
    static let shared = Supa()
    private let base = Config.supabaseURL
    private let key = Config.supabaseKey

    private func request(_ path: String, method: String = "GET", token: String? = nil,
                         body: Any? = nil, headers: [String: String] = [:]) async throws -> Data {
        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "apikey")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (obj?["msg"] ?? obj?["message"] ?? obj?["error_description"] ?? obj?["error"]) as? String
            throw SupaError.http(code, msg ?? String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // 寄驗證碼到信箱（只給已經在網頁登入過的帳號，不會新開帳號）
    func sendCode(email: String) async throws {
        _ = try await request("/auth/v1/otp", method: "POST", body: ["email": email, "create_user": false])
    }

    func verify(email: String, code: String) async throws -> AuthSession {
        let data = try await request("/auth/v1/verify", method: "POST",
                                     body: ["type": "email", "email": email, "token": code])
        return try Supa.parseSession(data, email: email)
    }

    func refreshed(_ s: AuthSession) async throws -> AuthSession {
        if s.expires.timeIntervalSinceNow > 120 { return s }
        let data = try await request("/auth/v1/token?grant_type=refresh_token", method: "POST",
                                     body: ["refresh_token": s.refresh])
        return try Supa.parseSession(data, email: s.email)
    }

    private static func parseSession(_ data: Data, email: String) throws -> AuthSession {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = o["access_token"] as? String,
              let refresh = o["refresh_token"] as? String,
              let user = o["user"] as? [String: Any],
              let uid = user["id"] as? String else {
            throw SupaError.http(0, "登入回應看不懂")
        }
        let exp = (o["expires_in"] as? Double) ?? 3600
        return AuthSession(access: access, refresh: refresh, expires: Date().addingTimeInterval(exp),
                           uid: uid, email: (user["email"] as? String) ?? email)
    }

    func loadSnapshot(_ s: AuthSession) async throws -> Snapshot? {
        let data = try await request("/rest/v1/prefs?select=data&user_id=eq.\(s.uid)", token: s.access)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let d = rows.first?["data"] as? [String: Any],
              let w = d["watch"] else { return nil }
        let wd = try JSONSerialization.data(withJSONObject: w)
        return try JSONDecoder().decode(Snapshot.self, from: wd)
    }

    func saveSession(_ s: AuthSession, record: [String: Any]) async throws {
        let row: [String: Any] = ["id": record["id"]!, "user_id": s.uid, "t": record["t"]!, "data": record]
        _ = try await request("/rest/v1/sessions", method: "POST", token: s.access, body: row,
                              headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }
}
