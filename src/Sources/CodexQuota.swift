import Foundation

struct CodexQuotaWindow {
    let name: String
    let remainingPercent: Double?
    let resetsAt: Date?
}

struct CodexResetCredit: Equatable {
    let id: String
    let expiresAt: Date
}

struct CodexQuotaSnapshot {
    let windows: [CodexQuotaWindow]
    let credits: [CodexResetCredit]
    let availableCount: Int?
    let creditsError: String?
}

/// Reads the same provider endpoints as CLIProxyAPI's management dashboard.
/// Quota requests do not wake the local backend or modify OAuth credentials.
final class CodexQuotaClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://chatgpt.com/backend-api/wham/")!

    init(session: URLSession = .shared) { self.session = session }

    func fetch(account: AuthAccount) async throws -> CodexQuotaSnapshot {
        let usage = try await request(account: account, path: "usage")
        let windows = try Self.parseUsage(usage)
        do {
            let data = try await request(account: account, path: "rate-limit-reset-credits")
            let parsed = try Self.parseCredits(data)
            return CodexQuotaSnapshot(windows: windows, credits: parsed.credits,
                                      availableCount: parsed.count, creditsError: nil)
        } catch {
            return CodexQuotaSnapshot(windows: windows, credits: [], availableCount: nil,
                                      creditsError: error.localizedDescription)
        }
    }

    func reset(account: AuthAccount) async throws {
        // The provider chooses the credit. Its API does not accept a credit ID.
        // Never retry this write automatically or generate a second redemption ID.
        let body = try JSONSerialization.data(withJSONObject: ["redeem_request_id": UUID().uuidString])
        _ = try await request(account: account, path: "rate-limit-reset-credits/consume", body: body)
    }

    private func request(account: AuthAccount, path: String, body: Data? = nil) async throws -> Data {
        let authData = try Data(contentsOf: account.filePath)
        guard let auth = try JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let token = auth["access_token"] as? String, !token.isEmpty,
              auth["disabled"] as? Bool != true else {
            throw QuotaError("Account unavailable. Reconnect Codex in Settings.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 20
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-tui/0.149.1", forHTTPHeaderField: "User-Agent")
        if let accountID = auth["account_id"] as? String, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QuotaError("Invalid provider response.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw QuotaError("Authorization failed. Reconnect Codex in Settings.")
            }
            throw QuotaError("Codex request failed (HTTP \(http.statusCode)). Refresh before trying again.")
        }
        return data
    }

    static func parseUsage(_ data: Data) throws -> [CodexQuotaWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rate = root["rate_limit"] as? [String: Any] else {
            throw QuotaError("Quota data unavailable in provider response.")
        }
        return [("Session", "primary_window"), ("Weekly", "secondary_window")].map { name, key in
            let window = rate[key] as? [String: Any]
            let used = number(window?["used_percent"])
            return CodexQuotaWindow(name: name,
                remainingPercent: used.map { max(0, min(100, 100 - $0)) },
                resetsAt: number(window?["reset_at"]).map { Date(timeIntervalSince1970: $0) })
        }
    }

    static func parseCredits(_ data: Data, now: Date = Date()) throws -> (credits: [CodexResetCredit], count: Int?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["credits"] != nil || root["available_count"] != nil || root["applicable_available_count"] != nil else {
            throw QuotaError("Invalid reset credits response.")
        }
        let credits = (root["credits"] as? [[String: Any]] ?? []).compactMap { item -> CodexResetCredit? in
            guard item["status"] as? String == "available",
                  item["reset_type"] as? String == "codex_rate_limits",
                  let expiry = date(item["expires_at"]), expiry > now else { return nil }
            return CodexResetCredit(id: item["id"] as? String ?? "", expiresAt: expiry)
        }.sorted { $0.expiresAt < $1.expiresAt }
        let count = number(root["applicable_available_count"]) ?? number(root["available_count"])
        return (credits, count.flatMap { Int(exactly: max(0, $0).rounded(.towardZero)) })
    }

    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let value = value as? NSNumber { parsed = value.doubleValue }
        else if let value = value as? String { parsed = Double(value) }
        else { parsed = nil }
        return parsed.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) { return Date(timeIntervalSince1970: seconds) }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

struct QuotaError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
