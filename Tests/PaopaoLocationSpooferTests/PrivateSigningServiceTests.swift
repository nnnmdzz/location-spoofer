import XCTest
@testable import PaopaoLocationSpoofer

final class PrivateSigningServiceTests: XCTestCase {
    func testCreateURLJobUsesV2BearerContractAndCompleteOptions() async throws {
        let transport = RecordingPrivateSigningTransport(response: """
        {"job_id":"00000000-0000-4000-8000-000000000001","status":"queued","signing_mode":"split"}
        """)
        let client = PrivateSigningClient(
            configuration: PrivateUpdateConfiguration(
                workerURL: URL(string: "https://signer.example.com")!,
                personalToken: "request-token"
            ),
            transport: transport
        )
        let options = PrivateSigningOptions(
            signingMode: .split,
            targetBundleIdentifier: "com.example.clone",
            profileID: "personal-main",
            keychainAccessGroups: ["TEAM.com.example.clone", "TEAM.com.example.legacy"],
            embeddedBundlePolicy: .requireAll,
            entitlementPolicy: .stripUnsupported
        )

        let job = try await client.createURLJob(
            sourceURL: URL(string: "https://downloads.example/App.ipa")!,
            options: options
        )

        XCTAssertEqual(job.jobID, "00000000-0000-4000-8000-000000000001")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v2/sign/jobs")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer request-token")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["source_url"] as? String, "https://downloads.example/App.ipa")
        XCTAssertEqual(payload["signing_mode"] as? String, "split")
        XCTAssertEqual(payload["target_bundle_id"] as? String, "com.example.clone")
        XCTAssertEqual(payload["profile_id"] as? String, "personal-main")
        XCTAssertEqual(payload["embedded_bundle_policy"] as? String, "require_all")
        XCTAssertEqual(payload["entitlement_policy"] as? String, "strip_unsupported")
    }

    func testUploadSessionUsesEightMiBPartsBeforeCreatingJob() async throws {
        let responses = [
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000002\",\"part_size\":8388608,\"max_bytes\":104857600,\"expires_at\":\"2026-08-12T00:00:00Z\"}",
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000002\",\"part_number\":1,\"etag\":\"etag-1\"}",
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000002\",\"status\":\"completed\",\"filename\":\"Local.ipa\"}",
            "{\"job_id\":\"00000000-0000-4000-8000-000000000003\",\"status\":\"queued\",\"signing_mode\":\"split\"}",
        ]
        let transport = RecordingPrivateSigningTransport(responses: responses)
        let client = PrivateSigningClient(
            configuration: PrivateUpdateConfiguration(
                workerURL: URL(string: "https://signer.example.com")!,
                personalToken: "request-token"
            ),
            transport: transport
        )
        let bytes = Data("fake-ipa!".utf8)

        let job = try await client.uploadAndCreateJob(
            filename: "Local.ipa",
            data: bytes,
            options: PrivateSigningOptions()
        )

        XCTAssertEqual(job.jobID, "00000000-0000-4000-8000-000000000003")
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/v2/uploads",
            "/v2/uploads/00000000-0000-4000-8000-000000000002/parts/1",
            "/v2/uploads/00000000-0000-4000-8000-000000000002/complete",
            "/v2/sign/jobs",
        ])
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Content-Length"), "9")
    }

    func testUploadRejectsUnsafeWorkerPartSizeBeforeReadingOrSendingParts() async throws {
        for invalidPartSize in [0, PrivateSigningClient.maximumPartBytes + 1] {
            let transport = RecordingPrivateSigningTransport(response: """
            {"upload_id":"00000000-0000-4000-8000-000000000004","part_size":\(invalidPartSize),"max_bytes":104857600,"expires_at":"2026-08-12T00:00:00Z"}
            """)
            let client = PrivateSigningClient(
                configuration: PrivateUpdateConfiguration(
                    workerURL: URL(string: "https://signer.example.com")!,
                    personalToken: "request-token"
                ),
                transport: transport
            )

            do {
                _ = try await client.uploadAndCreateJob(
                    filename: "Local.ipa",
                    data: Data("fake-ipa".utf8),
                    options: PrivateSigningOptions()
                )
                XCTFail("unsafe part size should be rejected")
            } catch PrivateSigningClientError.invalidResponse {
                XCTAssertEqual(transport.requests.count, 1)
            }
        }
    }

    func testHistoryFollowsEveryCursorPage() async throws {
        let transport = RecordingPrivateSigningTransport(responses: [
            "{\"jobs\":[{\"job_id\":\"00000000-0000-4000-8000-000000000010\",\"status\":\"completed\"}],\"next_cursor\":\"page-2\"}",
            "{\"jobs\":[{\"job_id\":\"00000000-0000-4000-8000-000000000011\",\"status\":\"failed\"}],\"next_cursor\":null}",
        ])
        let client = PrivateSigningClient(
            configuration: PrivateUpdateConfiguration(
                workerURL: URL(string: "https://signer.example.com")!,
                personalToken: "request-token"
            ),
            transport: transport
        )

        let jobs = try await client.history()

        XCTAssertEqual(jobs.map(\.jobID), [
            "00000000-0000-4000-8000-000000000010",
            "00000000-0000-4000-8000-000000000011",
        ])
        XCTAssertEqual(transport.requests[1].url?.query, "cursor=page-2")
    }
}

private final class RecordingPrivateSigningTransport: PrivateSigningTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [String]

    init(response: String) {
        responses = [response]
    }

    init(responses: [String]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let payload = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }
}
