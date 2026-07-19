import XCTest
@testable import GoNow

final class GoNowAuthenticationTests: XCTestCase {
    func testEmailValidation() {
        XCTAssertNil(AuthValidation.email("user@example.com"))
        XCTAssertNotNil(AuthValidation.email("not-an-email"))
    }

    func testPasswordAndConfirmationValidation() {
        XCTAssertNotNil(AuthValidation.password("short"))
        XCTAssertNil(AuthValidation.password("StrongPassword123"))
        XCTAssertNotNil(AuthValidation.matchingPasswords("first", "second"))
    }

    func testDecodesSuccessAndErrorEnvelopes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let success = """
        {"data":{"id":"00000000-0000-0000-0000-000000000001","email":"user@example.com","displayName":"Николай","username":"nikolay_26","emailVerified":false,"createdAt":"2026-07-16T12:00:00Z"}}
        """
        let user = try decoder.decode(APIEnvelope<CurrentUser>.self, from: Data(success.utf8)).data
        XCTAssertEqual(user.email, "user@example.com")
        let failure = """
        {"error":{"code":"INVALID_CREDENTIALS","message":"Неверный email или пароль","requestId":"00000000-0000-0000-0000-000000000001"}}
        """
        let error = try decoder.decode(APIErrorEnvelope.self, from: Data(failure.utf8)).error
        XCTAssertEqual(error.code, "INVALID_CREDENTIALS")
    }

    func testInMemoryTokenStoreSavesAndDeletes() throws {
        let store = InMemoryTokenStore()
        let tokens = TokenSet(accessToken: "access", refreshToken: "refresh", accessTokenExpiresAt: Date())
        try store.save(tokens)
        XCTAssertEqual(try store.read()?.accessToken, "access")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testOnlyAuthenticationFailuresInvalidateTheSession() {
        XCTAssertTrue(APIError.unauthorized.invalidatesSession)
        XCTAssertTrue(APIError.server(APIErrorBody(
            code: "SESSION_REVOKED",
            message: "",
            fields: nil,
            requestId: "request"
        )).invalidatesSession)
        XCTAssertFalse(APIError.transport("offline").invalidatesSession)
        XCTAssertFalse(APIError.invalidResponse.invalidatesSession)
    }

    func testUsernameNormalizationAndValidation() {
        XCTAssertEqual(UsernameRules.normalize(" @Nikolay_26 "), "nikolay_26")
        XCTAssertNil(UsernameRules.validationMessage("nikolay_26"))
        XCTAssertNotNil(UsernameRules.validationMessage("26nikolay"))
        XCTAssertNotNil(UsernameRules.validationMessage("николай"))
        XCTAssertNotNil(UsernameRules.validationMessage("admin"))
    }

    func testRegistrationPayloadContainsChosenUsername() throws {
        let payload = RegisterPayload(
            email: "user@example.com",
            password: "StrongPassword123",
            displayName: "Николай",
            username: "nikolay_26",
            device: DevicePayload(deviceId: "test", deviceName: "iPhone", platform: "ios")
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        XCTAssertEqual(object["username"] as? String, "nikolay_26")
        XCTAssertFalse((object["username"] as? String)?.hasPrefix("user_") ?? true)
    }
}

private final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var value: TokenSet?
    func save(_ tokens: TokenSet) throws { value = tokens }
    func read() throws -> TokenSet? { value }
    func delete() throws { value = nil }
}
