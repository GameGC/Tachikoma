#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import Testing
@testable import Tachikoma

@Suite(.serialized)
struct CredentialLoadingTests {
    @Test
    func `OAuth tokens are not loaded as OpenAI API keys`() async throws {
        try await self.withIsolatedCredentials(
            """
            OPENAI_ACCESS_TOKEN=access-token
            OPENAI_REFRESH_TOKEN=refresh-token
            OPENAI_ACCESS_EXPIRES=4102444800
            """,
        ) {
            let config = TachikomaConfiguration(loadFromEnvironment: true)
            #expect(config.getAPIKey(for: .openai) == nil)
        }
    }

    @Test
    func `OpenAI API key credential is preferred over OAuth token noise`() async throws {
        try await self.withIsolatedCredentials(
            """
            OPENAI_ACCESS_TOKEN=access-token
            OPENAI_API_KEY=api-key
            OPENAI_REFRESH_TOKEN=refresh-token
            """,
        ) {
            let config = TachikomaConfiguration(loadFromEnvironment: true)
            #expect(config.getAPIKey(for: .openai) == "api-key")
        }
    }

    @Test
    func `Absolute profile path credentials load without HOME`() async throws {
        #if !os(Windows)
        try await TestEnvironmentMutex.shared.withLock {
            let originalProfileDirectory = TachikomaConfiguration.profileDirectoryName
            let profilePath = FileManager.default.temporaryDirectory
                .appendingPathComponent("tachikoma-absolute-credentials-\(UUID().uuidString)")
                .path
            let credentialPath = "\(profilePath)/credentials"
            let savedEnvironment = self.unsetOpenAIEnvironment() + [("HOME", getenv("HOME").map { String(cString: $0) })]

            TachikomaConfiguration.profileDirectoryName = profilePath
            try FileManager.default.createDirectory(atPath: profilePath, withIntermediateDirectories: true)
            try "OPENAI_API_KEY=absolute-api-key\n".write(toFile: credentialPath, atomically: true, encoding: .utf8)
            unsetenv("HOME")

            defer {
                self.restoreEnvironment(savedEnvironment)
                TachikomaConfiguration.profileDirectoryName = originalProfileDirectory
                try? FileManager.default.removeItem(atPath: profilePath)
            }

            let config = TachikomaConfiguration(loadFromEnvironment: true)
            #expect(config.getAPIKey(for: .openai) == "absolute-api-key")
        }
        #endif
    }

    private func withIsolatedCredentials<T: Sendable>(
        _ credentials: String,
        _ body: @Sendable () throws -> T,
    ) async throws
        -> T
    {
        try await TestEnvironmentMutex.shared.withLock {
            let originalProfileDirectory = TachikomaConfiguration.profileDirectoryName
            let profileDirectory = ".tachikoma-credential-tests-\(UUID().uuidString)"
            let homeDirectory = try #require(ProcessInfo.processInfo.environment["HOME"])
            let profilePath = "\(homeDirectory)/\(profileDirectory)"
            let credentialPath = "\(profilePath)/credentials"
            let savedEnvironment = self.unsetOpenAIEnvironment()

            TachikomaConfiguration.profileDirectoryName = profileDirectory
            try FileManager.default.createDirectory(atPath: profilePath, withIntermediateDirectories: true)
            try credentials.write(toFile: credentialPath, atomically: true, encoding: .utf8)

            defer {
                self.restoreEnvironment(savedEnvironment)
                TachikomaConfiguration.profileDirectoryName = originalProfileDirectory
                try? FileManager.default.removeItem(atPath: profilePath)
            }

            return try body()
        }
    }

    private func unsetOpenAIEnvironment() -> [(String, String?)] {
        let keys = ["OPENAI_API_KEY", "OPENAI_ACCESS_TOKEN", "OPENAI_REFRESH_TOKEN", "OPENAI_ACCESS_EXPIRES"]
        let saved = keys.map { key in
            (key, getenv(key).map { String(cString: $0) })
        }
        keys.forEach { unsetenv($0) }
        return saved
    }

    private func restoreEnvironment(_ saved: [(String, String?)]) {
        for (key, value) in saved {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}
