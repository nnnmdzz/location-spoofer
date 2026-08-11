import XCTest
@testable import PaopaoLocationSpoofer

final class CertificateAuthorityStoreTests: XCTestCase {
    private let validAuthority = CertificateAuthority(certPEM: "valid-cert", keyPEM: "valid-key")

    func testEnsureCreatesOnceThenReusesValidKeychainPair() throws {
        let keychain = InMemoryCertificateAuthorityKeychain()
        var generations = 0
        let store = makeStore(keychain: keychain) {
            generations += 1
            return self.validAuthority
        }

        XCTAssertEqual(try store.ensure(), validAuthority)
        XCTAssertEqual(try store.ensure(), validAuthority)
        XCTAssertEqual(keychain.stored, validAuthority)
        XCTAssertEqual(generations, 1)
    }

    func testEnsureMigratesValidLegacyPairThenDeletesLegacyFiles() throws {
        let directory = try makeLegacyDirectory(authority: validAuthority)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = InMemoryCertificateAuthorityKeychain()
        let store = makeStore(directory: directory, keychain: keychain) {
            XCTFail("A valid legacy pair must be migrated instead of regenerated")
            return self.validAuthority
        }

        XCTAssertEqual(try store.ensure(), validAuthority)
        XCTAssertEqual(keychain.stored, validAuthority)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-cert.pem").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-key.pem").path))
    }

    func testFailedKeychainMigrationPreservesLegacyFiles() throws {
        let directory = try makeLegacyDirectory(authority: validAuthority)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = InMemoryCertificateAuthorityKeychain()
        keychain.shouldFailSave = true
        let store = makeStore(directory: directory, keychain: keychain) { self.validAuthority }

        XCTAssertThrowsError(try store.ensure())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-cert.pem").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-key.pem").path))
    }

    func testInvalidKeychainPairFallsBackToLegacyPair() throws {
        let directory = try makeLegacyDirectory(authority: validAuthority)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = InMemoryCertificateAuthorityKeychain()
        keychain.stored = CertificateAuthority(certPEM: "invalid-cert", keyPEM: "invalid-key")
        let store = makeStore(directory: directory, keychain: keychain) { self.validAuthority }

        XCTAssertEqual(try store.ensure(), validAuthority)
        XCTAssertEqual(keychain.stored, validAuthority)
    }

    func testValidKeychainPairRetriesCleanupOfLegacyFiles() throws {
        let directory = try makeLegacyDirectory(authority: validAuthority)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = InMemoryCertificateAuthorityKeychain()
        keychain.stored = validAuthority
        let store = makeStore(directory: directory, keychain: keychain) {
            XCTFail("A valid Keychain pair must not be regenerated")
            return self.validAuthority
        }

        XCTAssertEqual(try store.ensure(), validAuthority)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-cert.pem").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-key.pem").path))
    }

    func testInvalidLegacyFilesAreRemovedOnlyAfterReplacementIsPersisted() throws {
        let invalidAuthority = CertificateAuthority(certPEM: "invalid-cert", keyPEM: "invalid-key")
        let directory = try makeLegacyDirectory(authority: invalidAuthority)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = InMemoryCertificateAuthorityKeychain()
        let store = makeStore(directory: directory, keychain: keychain) { self.validAuthority }

        XCTAssertEqual(try store.ensure(), validAuthority)
        XCTAssertEqual(keychain.stored, validAuthority)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-cert.pem").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-key.pem").path))
    }

    func testFailedReplacementPersistencePreservesInvalidLegacyFiles() throws {
        let invalidAuthority = CertificateAuthority(certPEM: "invalid-cert", keyPEM: "invalid-key")
        let directory = try makeLegacyDirectory(authority: invalidAuthority)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = InMemoryCertificateAuthorityKeychain()
        keychain.shouldFailSave = true
        let store = makeStore(directory: directory, keychain: keychain) { self.validAuthority }

        XCTAssertThrowsError(try store.ensure())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-cert.pem").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ca-key.pem").path))
    }

    func testResetRemovesKeychainAndLegacyAuthority() throws {
        let directory = try makeLegacyDirectory(authority: validAuthority)
        let keychain = InMemoryCertificateAuthorityKeychain()
        keychain.stored = validAuthority
        let store = makeStore(directory: directory, keychain: keychain) { self.validAuthority }

        try store.reset()

        XCTAssertNil(keychain.stored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testResetFailurePreservesKeychainAuthority() {
        let keychain = InMemoryCertificateAuthorityKeychain()
        keychain.stored = validAuthority
        keychain.shouldFailRemove = true
        let store = makeStore(keychain: keychain) { self.validAuthority }

        XCTAssertThrowsError(try store.reset())
        XCTAssertEqual(keychain.stored, validAuthority)
    }

    private func makeStore(
        directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
        keychain: InMemoryCertificateAuthorityKeychain,
        generator: @escaping () throws -> CertificateAuthority
    ) -> CertificateAuthorityStore {
        CertificateAuthorityStore(
            directory: directory,
            keychain: keychain,
            generator: generator,
            validator: { $0 == self.validAuthority }
        )
    }

    private func makeLegacyDirectory(authority: CertificateAuthority) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try authority.certPEM.write(to: directory.appendingPathComponent("ca-cert.pem"), atomically: true, encoding: .utf8)
        try authority.keyPEM.write(to: directory.appendingPathComponent("ca-key.pem"), atomically: true, encoding: .utf8)
        return directory
    }
}

private enum CertificateAuthorityStoreTestError: Error {
    case saveFailed
    case removeFailed
}

private final class InMemoryCertificateAuthorityKeychain: CertificateAuthorityKeychain {
    var stored: CertificateAuthority?
    var shouldFailSave = false
    var shouldFailRemove = false

    func load() throws -> CertificateAuthority? { stored }

    func save(_ authority: CertificateAuthority) throws {
        guard !shouldFailSave else { throw CertificateAuthorityStoreTestError.saveFailed }
        stored = authority
    }

    func remove() throws {
        guard !shouldFailRemove else { throw CertificateAuthorityStoreTestError.removeFailed }
        stored = nil
    }
}
