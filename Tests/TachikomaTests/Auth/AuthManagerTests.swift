import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Tachikoma

@Suite(.serialized)
struct AuthManagerTests {
    private func withIsolatedAuthState<T: Sendable>(
        _ body: @Sendable () async throws -> T,
    ) async rethrows
        -> T
    {
        try await TestEnvironmentMutex.shared.withLock {
            let originalProfileDirectory = TachikomaConfiguration.profileDirectoryName
            let isolatedProfileDirectory = ".tachikoma-auth-tests-\(UUID().uuidString)"
            let previousIgnoreEnvironment = TKAuthManager.shared.setIgnoreEnvironment(false)
            let previousIgnoreCredentialStore = TKAuthManager.shared.setIgnoreCredentialStore(false)
            let isolatedPath = NSString(string: "~/" + isolatedProfileDirectory).expandingTildeInPath

            TachikomaConfiguration.profileDirectoryName = isolatedProfileDirectory
            try? FileManager.default.removeItem(atPath: isolatedPath)

            defer {
                self.resetAuthEnv()
                TKAuthManager.shared.setIgnoreEnvironment(previousIgnoreEnvironment)
                TKAuthManager.shared.setIgnoreCredentialStore(previousIgnoreCredentialStore)
                TachikomaConfiguration.profileDirectoryName = originalProfileDirectory
                try? FileManager.default.removeItem(atPath: isolatedPath)
            }

            return try await body()
        }
    }

    private func resetAuthEnv() {
        unsetenv("XAI_API_KEY")
        unsetenv("X_AI_API_KEY")
        unsetenv("GROK_API_KEY")
        unsetenv("OPENAI_API_KEY")
        unsetenv("OPENAI_ACCESS_TOKEN")
        unsetenv("ANTHROPIC_API_KEY")
        unsetenv("ANTHROPIC_ACCESS_TOKEN")
        unsetenv("GEMINI_API_KEY")
        unsetenv("GOOGLE_API_KEY")
        unsetenv("OPENROUTER_API_KEY")
    }

    @Test
    func `env preferred over creds`() async throws {
        try await self.withIsolatedAuthState {
            self.resetAuthEnv()
            setenv("OPENAI_API_KEY", "env-key", 1)
            defer { unsetenv("OPENAI_API_KEY") }
            try TKAuthManager.shared.setCredential(key: "OPENAI_API_KEY", value: "cred-key")
            let auth = TKAuthManager.shared.resolveAuth(for: .openai)
            guard case let .bearer(token, _) = auth else {
                Issue.record("Expected bearer from env")
                return
            }
            #expect(token == "env-key")
        }
    }

    @Test
    func `grok alias env`() async {
        await self.withIsolatedAuthState {
            self.resetAuthEnv()
            setenv("X_AI_API_KEY", "alias-key", 1)
            unsetenv("XAI_API_KEY")
            unsetenv("GROK_API_KEY")
            defer { unsetenv("X_AI_API_KEY") }
            let auth = TKAuthManager.shared.resolveAuth(for: .grok)
            guard case let .bearer(token, _) = auth else {
                Issue.record("Expected bearer from alias env")
                return
            }
            #expect(token == "alias-key")
        }
    }

    @Test
    func `openrouter resolves env and credential keys as bearer auth`() async throws {
        try await self.withIsolatedAuthState {
            self.resetAuthEnv()
            try TKAuthManager.shared.setCredential(key: "OPENROUTER_API_KEY", value: "credential-openrouter-key")

            guard case let .bearer(credentialToken, _)? = TKAuthManager.shared.resolveAuth(for: .openrouter) else {
                Issue.record("Expected OpenRouter bearer auth from credentials")
                return
            }
            #expect(credentialToken == "credential-openrouter-key")

            setenv("OPENROUTER_API_KEY", "env-openrouter-key", 1)
            defer { unsetenv("OPENROUTER_API_KEY") }

            guard case let .bearer(envToken, _)? = TKAuthManager.shared.resolveAuth(for: .openrouter) else {
                Issue.record("Expected OpenRouter bearer auth from environment")
                return
            }
            #expect(envToken == "env-openrouter-key")
        }
    }

    @Test
    @MainActor
    func `validate success mock`() async throws {
        let session = URLSession.mock(status: 200)
        let req = try URLRequest(url: #require(URL(string: "https://api.openai.com/v1/models")))
        let result = await HTTP.perform(request: req, timeoutSeconds: 5, session: session)
        switch result {
        case .success: break
        default: Issue.record("Expected success")
        }
    }

    @Test
    @MainActor
    func `validate failure mock`() async throws {
        let session = URLSession.mock(status: 401)
        let req = try URLRequest(url: #require(URL(string: "https://api.openai.com/v1/models")))
        let result = await HTTP.perform(request: req, timeoutSeconds: 5, session: session)
        switch result {
        case let .failure(reason):
            #expect(reason.contains("401"))
        default:
            Issue.record("Expected failure")
        }
    }

    @Test
    @MainActor
    func `o auth token exchange uses form encoding`() async throws {
        OAuthMockURLProtocol.reset()
        let config = OAuthConfig(
            prefix: "TEST",
            authorize: "https://example.com/auth",
            token: "https://example.com/token",
            clientId: "client-id",
            scope: "scope",
            redirect: "https://example.com/callback",
            extraAuthorize: [:],
            extraToken: [:],
            betaHeader: nil,
            pkce: PKCE(),
        )
        let result = await OAuthTokenExchanger.exchange(
            config: config,
            code: "abc123",
            pkce: config.pkce,
            timeout: 5,
            session: .oauthMock(),
        )
        guard case .success = result else {
            Issue.record("Expected success but got \(result)")
            return
        }

        let request = try #require(OAuthMockURLProtocol.lastRequest, "No request captured")

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let bodyString = String(data: OAuthMockURLProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        let items = URLComponents(string: "https://example.com?\(bodyString)")?.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(params["grant_type"] == "authorization_code")
        #expect(params["client_id"] == "client-id")
        #expect(params["code"] == "abc123")
        #expect(params["redirect_uri"] == "https://example.com/callback")
        #expect(params["code_verifier"] == config.pkce.verifier)
    }

    @Test
    @MainActor
    func `o auth token exchange uses JSON encoding and state when required`() async throws {
        OAuthMockURLProtocol.reset()
        let config = OAuthConfig(
            prefix: "TEST",
            authorize: "https://example.com/auth",
            token: "https://example.com/token",
            clientId: "client-id",
            scope: "scope",
            redirect: "https://example.com/callback",
            extraAuthorize: [:],
            extraToken: [:],
            betaHeader: nil,
            tokenEncoding: .json,
            requiresStateInTokenExchange: true,
            pkce: PKCE(),
        )
        let result = await OAuthTokenExchanger.exchange(
            config: config,
            code: "abc123",
            state: "state123",
            pkce: config.pkce,
            timeout: 5,
            session: .oauthMock(),
        )
        guard case .success = result else {
            Issue.record("Expected success but got \(result)")
            return
        }

        let request = try #require(OAuthMockURLProtocol.lastRequest, "No request captured")

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(OAuthMockURLProtocol.lastBody, "No request body captured")
        let json = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            "Expected JSON request body",
        )

        #expect(json["grant_type"] as? String == "authorization_code")
        #expect(json["client_id"] as? String == "client-id")
        #expect(json["code"] as? String == "abc123")
        #expect(json["state"] as? String == "state123")
        #expect(json["redirect_uri"] as? String == "https://example.com/callback")
        #expect(json["code_verifier"] as? String == config.pkce.verifier)
    }
}

// MARK: - URLSession mocking

@MainActor
private final class AuthMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode: Int = 200

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: self.request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: nil,
        )!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Data())
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLSession {
    @MainActor
    fileprivate static func mock(status: Int) -> URLSession {
        AuthMockURLProtocol.statusCode = status
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @MainActor
    fileprivate static func oauthMock() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@MainActor
private final class OAuthMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func reset() {
        self.lastRequest = nil
        self.lastBody = nil
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        OAuthMockURLProtocol.lastRequest = self.request
        if let body = self.request.httpBody {
            OAuthMockURLProtocol.lastBody = body
        } else if let stream = self.request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else { break }
            }
            OAuthMockURLProtocol.lastBody = data
        }
        let body: [String: Any] = [
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": 3600,
        ]
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: self.request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"],
        )!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: data)
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
