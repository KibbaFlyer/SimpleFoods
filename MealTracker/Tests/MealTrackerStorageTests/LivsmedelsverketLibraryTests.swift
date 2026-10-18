import Foundation
import XCTest
import MealTrackerCatalog

private final class LivsmedelsverketURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let headers: [String: String]
        let data: Data
    }

    private static let lock = NSLock()
    private static var stubs: [Stub] = []
    private(set) static var requests: [URLRequest] = []

    static func prepare(_ newStubs: [Stub]) {
        lock.lock()
        stubs = newStubs
        requests = []
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let stub = Self.stubs.removeFirst()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LivsmedelsverketLibraryTests: XCTestCase {
    private func databaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("livsmedelsverket.sqlite")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LivsmedelsverketURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testSyncIdentifiesClientRetriesRateLimitAndImportsValidatedFood() async throws {
        let index = Data(#"{"_meta":{"totalRecords":1},"livsmedel":[{"nummer":1,"version":"v1","namn":"Testmat"}]}"#.utf8)
        let nutrients = Data(#"[{"euroFIRkod":"ENERC","varde":100,"enhet":"kcal","vardetypkod":null},{"euroFIRkod":"PROT","varde":10,"enhet":"g","vardetypkod":null}]"#.utf8)
        LivsmedelsverketURLProtocol.prepare([
            .init(status: 429, headers: ["Retry-After": "1"], data: Data()),
            .init(status: 200, headers: [:], data: index),
            .init(status: 200, headers: [:], data: nutrients)
        ])
        let library = try LivsmedelsverketLibrary(
            databaseURL: databaseURL(),
            session: session(),
            userAgent: "SimpleFoods/Test",
            sleep: { _ in }
        )

        let report = await library.sync()

        XCTAssertEqual(report.available, 1)
        XCTAssertEqual(report.changed, 1)
        XCTAssertEqual(report.failed, 0)
        let foods = try await library.foods()
        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(LivsmedelsverketURLProtocol.recordedRequests().count, 3)
        XCTAssertTrue(LivsmedelsverketURLProtocol.recordedRequests().allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == "SimpleFoods/Test"
        })
    }

    func testSyncRejectsOversizedIndexResponse() async throws {
        LivsmedelsverketURLProtocol.prepare([
            .init(status: 200, headers: [:], data: Data(repeating: 0x20, count: 2_000_001))
        ])
        let library = try LivsmedelsverketLibrary(
            databaseURL: databaseURL(),
            session: session(),
            sleep: { _ in }
        )

        let report = await library.sync()

        XCTAssertEqual(report.available, 0)
        XCTAssertEqual(report.changed, 0)
        XCTAssertEqual(report.failed, 1)
    }
}
