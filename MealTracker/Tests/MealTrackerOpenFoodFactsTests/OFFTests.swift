import XCTest
import GRDB
@testable import MealTrackerOpenFoodFacts

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var seconds: Double = 1000
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970:seconds) }
    func advance() { lock.lock(); seconds += 100; lock.unlock() }
}
private actor Server {
    var responses: [OFFResponse]; var calls = 0
    init(_ responses: [OFFResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> OFFResponse { calls += 1; XCTAssertEqual(request.httpMethod,"GET"); XCTAssertTrue(request.url!.path.contains("/api/v3/product/")); XCTAssertNotNil(request.value(forHTTPHeaderField:"User-Agent")); if responses.isEmpty { throw URLError(.notConnectedToInternet) }; return responses.removeFirst() }
}
final class OFFTests: XCTestCase {
    let code = "3017620422003"
    func data(_ rev: Int = 1, timestamp: Int = 100, unit: String = "g", energyUnit: String = "kcal") -> Data {
        Data("""
        {"status":"success","product":{"code":"3017620422003","rev":\(rev),"last_modified_t":\(timestamp),"product_name_en":"Synthetic product","nutrition_data_per":"100g","product_quantity_unit":"\(unit)","countries_tags":["en:sweden"],"origins_tags":["en:italy"],"nutriments":{"energy-kcal_100g":100,"energy-kcal_unit":"\(energyUnit)","proteins_100g":0,"proteins_unit":"g","carbohydrates_100g":20,"carbohydrates_unit":"g","fat_100g":10,"fat_unit":"g"}}}
        """.utf8)
    }
    private func library(_ server: Server) throws -> (OFFLibrary, URL) { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("off.sqlite"); return (try OFFLibrary(databaseURL: url, transport: { try await server.send($0) }, clock: { Date(timeIntervalSince1970:1000) }, sleep: { _ in }), url) }
    func testBarcodeValidationAndEquivalence() throws {
        XCTAssertEqual(try Barcode("012345678905").equivalents,["012345678905","0012345678905"])
        XCTAssertThrowsError(try Barcode("3017620422004")); XCTAssertThrowsError(try Barcode(" 3017620422003")); XCTAssertEqual(try Barcode("0012345678905").value,"0012345678905")
    }
    func testLocalFirstAndOfflineCache() async throws {
        let server = Server([.init(data:data())]); let (store,_) = try library(server)
        let product = try await store.lookup(barcode:code); XCTAssertEqual(product.food?.salesCountries,["SE"]); XCTAssertEqual(product.food?.ingredientOrigins,["IT"])
        XCTAssertEqual(product.food?.profile.nutrients["protein"]?.status.rawValue,"knownZero")
        _ = try await store.lookup(barcode:code); let calls = await server.calls; XCTAssertEqual(calls,1)
        let report = await store.sync(); XCTAssertEqual(report.failedCount,1); let cached = try await store.cached(barcode:code); XCTAssertEqual(cached?.revision,"1")
    }
    func testUnchangedAndChangedImmutableRevisions() async throws {
        let server = Server([.init(data:data()),.init(data:data()),.init(data:data(2,timestamp:200))]); let (store,url) = try library(server)
        _ = try await store.lookup(barcode:code); let unchanged = await store.sync(); XCTAssertFalse(unchanged.items[0].changed)
        let changed = await store.sync(); XCTAssertTrue(changed.items[0].changed)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);let db = try DatabaseQueue(path:url.path); let count = try await db.read { try Int.fetchOne($0,sql:"SELECT COUNT(*) FROM off_revision") }; XCTAssertEqual(count,2)
    }
    func testMalformedFutureAndOutOfOrderDoNotReplaceCache() async throws {
        let server = Server([.init(data:data(2,timestamp:200)),.init(data:data(1,timestamp:100)),.init(data:data(3,timestamp:2000)),.init(data:Data("{}".utf8))]); let (store,_) = try library(server)
        _ = try await store.lookup(barcode:code)
        for _ in 0..<3 { let report = await store.sync(); XCTAssertEqual(report.failedCount,1) }
        let cached = try await store.cached(barcode:code); XCTAssertEqual(cached?.revision,"2"); XCTAssertEqual(cached?.lastSuccessfulCheck,Date(timeIntervalSince1970:1000))
    }
    func testAmbiguousVolumeAndUnsupportedNutrientUnit() async throws {
        let (volume,_) = try library(Server([.init(data:data(unit:"ml"))])); let a = try await volume.lookup(barcode:code); XCTAssertNil(a.food)
        let (unit,_) = try library(Server([.init(data:data(energyUnit:"kJ"))])); let b = try await unit.lookup(barcode:code); XCTAssertNil(b.food)
    }
    func testApproximateNutritionIsAcceptedAndMarked() async throws {
        let approximate = String(data:data(),encoding:.utf8)!
            .replacingOccurrences(of:"\"proteins_100g\":0",with:"\"proteins_modifier\":\"~\",\"proteins_100g\":0")
        let (store,_) = try library(Server([.init(data:Data(approximate.utf8))]))
        let product = try await store.lookup(barcode:code)
        XCTAssertNotNil(product.food)
        XCTAssertTrue(product.hasApproximateNutrition)
    }
    func testPreparedNutritionIsAccepted() async throws {
        var prepared = String(data:data(),encoding:.utf8)!
            .replacingOccurrences(of:"\"nutrition_data_per\":\"100g\"",with:"\"nutrition_data_prepared_per\":\"100g\"")
        for key in ["energy-kcal", "proteins", "carbohydrates", "fat"] {
            prepared = prepared
                .replacingOccurrences(of:"\"\(key)_100g\"",with:"\"\(key)_prepared_100g\"")
                .replacingOccurrences(of:"\"\(key)_unit\"",with:"\"\(key)_prepared_unit\"")
        }
        let (store,_) = try library(Server([.init(data:Data(prepared.utf8))]))
        let product = try await store.lookup(barcode:code)
        XCTAssertNotNil(product.food)
        XCTAssertEqual(product.food?.profile.preparation,"prepared")
    }
    func testPurgeRemovesCachedProduct() async throws {
        let (store,url) = try library(Server([.init(data:data(energyUnit:"kJ"))]))
        let entry = OFFNameEntry(barcode:code,names:["en":"Synthetic product"],markets:["SE"])
        let database = try DatabaseQueue(path:url.path)
        try database.write {
            try $0.execute(
                sql:"INSERT OR REPLACE INTO off_name_index VALUES (?,?,?,?)",
                arguments:[code,try JSONEncoder().encode(entry),"synthetic product","|SE|"]
            )
        }
        let unsupported = try await store.lookup(barcode:code)
        XCTAssertNil(unsupported.food)
        let indexedBeforePurge = try await store.name(barcode:code)
        XCTAssertNotNil(indexedBeforePurge)
        try await store.purgeCachedProduct(barcode:code)
        let cached = try await store.cached(barcode:code)
        XCTAssertNil(cached)
        let products = try await store.cachedProducts()
        XCTAssertTrue(products.isEmpty)
        let indexedAfterPurge = try await store.name(barcode:code)
        XCTAssertNil(indexedAfterPurge)
    }
    func testRateLimitStopsFurtherRequestsUntilRetry() async throws {
        let server = Server([.init(data:data()),.init(data:Data(),status:429,retryAfter:"120")]); let (store,_) = try library(server)
        _ = try await store.lookup(barcode:code); _ = await store.sync(); _ = await store.sync(); let calls = await server.calls; XCTAssertEqual(calls,2)
    }
    func testSameSourceRevisionHasDistinctImmutableFoodRevision() async throws {
        let server = Server([.init(data:data()), .init(data:data(timestamp:200))]); let (store,_) = try library(server)
        let a = try await store.lookup(barcode:code); _ = await store.sync(); let b = try await store.cached(barcode:code)
        XCTAssertEqual(a.revision,b?.revision); XCTAssertNotEqual(a.food?.revision,b?.food?.revision)
    }
    func testUnsupportedSchemaRefused() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("off.sqlite")
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);let db = try DatabaseQueue(path:url.path); try db.write { try $0.execute(sql:"PRAGMA user_version=99") }
        XCTAssertThrowsError(try OFFLibrary(databaseURL:url))
    }
    func testInvalidFractionAndBooleanMetadata() async throws {
        for text in ["true", "1.5"] {
            let invalid = String(data:data(),encoding:.utf8)!.replacingOccurrences(of:"\"rev\":1",with:"\"rev\":\(text)")
            let (store,_) = try library(Server([.init(data:Data(invalid.utf8))]))
            do { _ = try await store.lookup(barcode:code); XCTFail("Invalid metadata accepted") } catch { }
            let cached = try await store.cached(barcode:code); XCTAssertNil(cached)
        }
    }

    func testPartialSyncContinuesAfterHTTPFailure() async throws {
        let other = "012345678905"
        let otherData = Data(String(data:data(),encoding:.utf8)!.replacingOccurrences(of:code,with:other).utf8)
        let server = Server([.init(data:data()),.init(data:otherData),.init(data:Data(),status:503),.init(data:data(2,timestamp:200))])
        let (store,_) = try library(server); _ = try await store.lookup(barcode:code); _ = try await store.lookup(barcode:other)
        let report = await store.sync(); XCTAssertEqual(report.items.count,2); XCTAssertEqual(report.failedCount,1); XCTAssertTrue(report.items.contains { $0.changed })
    }

    func testFailureRecordsAttemptWithoutAdvancingSuccess() async throws {
        let clock = TestClock(); let server = Server([.init(data:data()),.init(data:Data(),status:503)])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("off.sqlite")
        let store = try OFFLibrary(databaseURL:url,transport:{ try await server.send($0) },clock:{ clock.now() },sleep:{ _ in })
        _ = try await store.lookup(barcode:code); clock.advance(); _ = await store.sync()
        let cached = try await store.cached(barcode:code)
        XCTAssertEqual(cached?.lastAttempt,Date(timeIntervalSince1970:1100)); XCTAssertEqual(cached?.lastSuccessfulCheck,Date(timeIntervalSince1970:1000))
    }
    func testUnknownCountryRetainedRawOnlyAndSameVersionChangedValues() async throws {
        let initial = String(data:data(),encoding:.utf8)!.replacingOccurrences(of:"en:sweden",with:"en:unreviewed-region")
        let changed = initial.replacingOccurrences(of:"energy-kcal_100g\":100",with:"energy-kcal_100g\":200")
        let server = Server([.init(data:Data(initial.utf8)),.init(data:Data(changed.utf8))]); let (store,_) = try library(server)
        let a = try await store.lookup(barcode:code); XCTAssertEqual(a.food?.salesCountries,[])
        let report = await store.sync(); XCTAssertTrue(report.items[0].changed)
        let b = try await store.cached(barcode:code); XCTAssertNotEqual(a.food?.revision,b?.food?.revision); XCTAssertEqual(a.revision,b?.revision)
    }

    func testRestartEnumeratesOfflineCacheAndExplicitRefresh() async throws {
        let server = Server([.init(data:data()),.init(data:data(2,timestamp:200))]); let (store,url) = try library(server)
        _ = try await store.lookup(barcode:code); let refreshed = try await store.refresh(barcode:code); XCTAssertEqual(refreshed.revision,"2")
        let reopened = try OFFLibrary(databaseURL:url,transport:{ _ in throw URLError(.notConnectedToInternet) },sleep:{ _ in })
        let all = try await reopened.cachedProducts(); XCTAssertEqual(all.map(\.barcode),[code]); XCTAssertEqual(all.first?.revision,"2")
    }

    func testCurrentV3StructuredNutritionUsesDirectDeclaredValue() async throws {
        var envelope = try JSONSerialization.jsonObject(with:data()) as! [String:Any]
        var product = envelope["product"] as! [String:Any]
        product["nutrition"] = ["aggregated_set":["preparation":"as_sold","per":"100g","nutrients":["energy-kcal":["value":125,"value_computed":999,"unit":"kcal","source":"packaging","source_per":"100g"],"proteins":["value":2,"unit":"g","source":"packaging","source_per":"100g"],"carbohydrates":["value":20,"unit":"g","source":"packaging","source_per":"100g"],"fat":["value":10,"unit":"g","source":"packaging","source_per":"100g"],"salt":["value":0.1,"unit":"g","source":"packaging","source_per":"100g","modifier":"<"]]]]
        envelope["product"] = product
        let (store,_) = try library(Server([.init(data:try JSONSerialization.data(withJSONObject:envelope))]))
        let result = try await store.lookup(barcode:code)
        XCTAssertEqual(result.food?.profile.nutrients["energy.declared"]?.value?.canonicalString,"125")
        XCTAssertEqual(result.food?.profile.nutrients["salt.equivalent"]?.status.rawValue,"unknown")
    }

    func testFoodRequiresEveryExplicitMacroAndMapsCarbohydrates() async throws {
        let required: [(String, String)] = [
            ("energy-kcal_100g", "energy-kcal_unit"),
            ("proteins_100g", "proteins_unit"),
            ("carbohydrates_100g", "carbohydrates_unit"),
            ("fat_100g", "fat_unit")
        ]
        for (valueKey, unitKey) in required {
            var envelope = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
            var product = envelope["product"] as! [String: Any]
            var nutriments = product["nutriments"] as! [String: Any]
            nutriments.removeValue(forKey: valueKey)
            nutriments.removeValue(forKey: unitKey)
            product["nutriments"] = nutriments
            envelope["product"] = product

            let (store, _) = try library(Server([.init(data: try JSONSerialization.data(withJSONObject: envelope))]))
            let productResult = try await store.lookup(barcode: code)
            XCTAssertNil(productResult.food, "Missing \(valueKey) must exclude the food")
        }

        let (store, _) = try library(Server([.init(data: data())]))
        let product = try await store.lookup(barcode: code)
        XCTAssertEqual(product.food?.profile.nutrients["carbohydrate.euAvailable"]?.value?.canonicalString, "20")
        XCTAssertEqual(product.food?.profile.nutrients["carbohydrate.euAvailable"]?.status, .known)
    }

}
