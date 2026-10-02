import XCTest
@testable import CLIProxyMenuBar

final class CodexQuotaTests: XCTestCase {
    func testQuotaShowsRemainingAndMissingWindowAsUnknown() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":42,"reset_at":2000000000}}}"#.utf8)
        let windows = try CodexQuotaClient.parseUsage(data)
        XCTAssertEqual(windows[0].remainingPercent, 58)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 2000000000))
        XCTAssertNil(windows[1].remainingPercent)
    }

    func testCreditsSortedByExpiryAndUnavailableCreditsExcluded() throws {
        let data = Data(#"{"applicable_available_count":"2","credits":[{"id":"later","status":"available","reset_type":"codex_rate_limits","expires_at":"2030-03-01T00:00:00Z"},{"id":"first","status":"available","reset_type":"codex_rate_limits","expires_at":"2030-01-02T00:00:00.000Z"},{"id":"expired","status":"available","reset_type":"codex_rate_limits","expires_at":"2020-01-01T00:00:00Z"},{"id":"used","status":"consumed","reset_type":"codex_rate_limits","expires_at":"2030-01-01T00:00:00Z"},{"id":"other","status":"available","reset_type":"other","expires_at":"2030-01-01T00:00:00Z"}]}"#.utf8)
        let result = try CodexQuotaClient.parseCredits(data, now: Date(timeIntervalSince1970: 1800000000))
        XCTAssertEqual(result.credits.map(\.id), ["first", "later"])
        XCTAssertEqual(result.count, 2)
    }

    func testApplicableZeroOverridesAvailableCount() throws {
        let result = try CodexQuotaClient.parseCredits(Data(#"{"available_count":3,"applicable_available_count":0}"#.utf8))
        XCTAssertEqual(result.count, 0)
    }

    func testInvalidPayloadDoesNotBecomeFullQuotaOrZeroCredits() {
        XCTAssertThrowsError(try CodexQuotaClient.parseUsage(Data("{}".utf8)))
        XCTAssertThrowsError(try CodexQuotaClient.parseCredits(Data("{}".utf8)))
    }
}
