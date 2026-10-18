import XCTest
import MealTrackerCore
import MealTrackerCatalog
import MealTrackerDiary
import GRDB
import CryptoKit

final class StorageTests:XCTestCase {
    func databaseURL()->URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("diary.sqlite") }
    func draft()throws->MealDraft {
        let catalogue=try CatalogueRepository.bundledDevelopment()
        let profile = try NutritionProfile(
            profileRevision: "test-r1",
            basis: NutritionBasis(quantity: DecimalAmount("100"), unit: .g),
            preparation: "test",
            density: nil,
            nutrients: [
                Nutrient.energy.rawValue: NutrientValue(status: .known, value: DecimalAmount("100"), unit: .kcal),
                Nutrient.protein.rawValue: NutrientValue(status: .known, value: DecimalAmount("10"), unit: .g)
            ],
            portions: [],
            provenanceRef: "test"
        )
        let food = CatalogueFood(
            id: .personal(UUID()), revision: "1", kind: "ingredient", lifecycle: "active",
            names: ["sv": "Testmat"], salesCountries: [], manufacturingCountries: [],
            ingredientOrigins: [], barcodes: [], profile: profile, provenanceRef: "test"
        )
        return MealDraft(eatenAt:Date(timeIntervalSince1970:1_700_000_000),zoneID:"Europe/Stockholm",components:[try MealComponent(food:food,generationID:catalogue.generationID,displayName:catalogue.displayName(food,language:"sv"),language:"sv",quantity:LoggedQuantity(amount:try DecimalAmount("100"),unit:.grams))])
    }
    func testCatalogueActiveMarketBarcodeRetained()throws {
        let catalogue=try CatalogueRepository.bundledDevelopment();XCTAssertTrue(catalogue.fixtureOnly)
        let foods=try catalogue.search(query:"");XCTAssertTrue(foods.isEmpty)
        XCTAssertTrue(try catalogue.search(query:"",market:"XX").isEmpty)
    }
    func testRestartSnapshotsDraftsHistoryIdempotency()throws {
        let url=databaseURL();let draft=try draft();let operation=UUID()
        let original:MealEvent
        do { let store=try DiaryStore(databaseURL:url);try store.saveDraft(draft);original=try store.save(draft,operationID:operation);XCTAssertEqual(try store.save(draft,operationID:operation),original) }
        let restarted=try DiaryStore(databaseURL:url)
        XCTAssertEqual(try restarted.events(localDate:original.localDate),[original]);XCTAssertNil(try restarted.loadDraft(id:draft.id))
        var changed=draft;changed.category = .dinner
        XCTAssertThrowsError(try restarted.save(changed,operationID:operation)) { XCTAssertEqual($0 as? DiaryError,.operationConflict) }
        XCTAssertThrowsError(try restarted.save(changed,operationID:UUID()))
        let edit=try restarted.save(changed,operationID:UUID(),expectedRevision:1);XCTAssertEqual(edit.revision,2);XCTAssertEqual(edit.categoryMode,"manual");XCTAssertEqual(edit.components,original.components)
        let deleted=try restarted.delete(id:edit.id,operationID:UUID(),expectedRevision:2);XCTAssertEqual(deleted.revision,3);XCTAssertTrue(try restarted.events(localDate:edit.localDate).isEmpty);XCTAssertEqual(try restarted.history(id:edit.id).count,3)
        let db=try DatabaseQueue(path:url.path);XCTAssertEqual(try db.read { try String.fetchOne($0,sql:"SELECT state FROM export_intents") },"disabled")
    }
    func testRollbackAndFutureDraft()throws {
        let url=databaseURL();let store=try DiaryStore(databaseURL:url);var draft=try draft();try store.saveDraft(draft)
        XCTAssertThrowsError(try store.save(draft,operationID:UUID(),injectFailureBeforeCommit:true))
        XCTAssertTrue(try store.events(localDate:DiaryTime.localDate(draft.eatenAt,zoneID:draft.zoneID)).isEmpty)
        XCTAssertEqual(try DiaryStore(databaseURL:url).loadDraft(id:draft.id),draft)
        draft.eatenAt=Date().addingTimeInterval(3600)
        XCTAssertThrowsError(try store.save(draft,operationID:UUID())) { XCTAssertEqual($0 as? DiaryError,.futureRequiresConfirmation) }
        XCTAssertNoThrow(try store.save(draft,operationID:UUID(),confirmFuture:true))
    }
    func testTimeWindowsAndDSTDays()throws {
        let format=ISO8601DateFormatter()
        for (hour,expected) in [(4,MealCategory.snack),(5,.breakfast),(10,.breakfast),(11,.lunch),(14,.lunch),(15,.snack),(16,.snack),(17,.dinner),(20,.dinner),(21,.snack)] { let date=try XCTUnwrap(format.date(from:String(format:"2026-01-01T%02d:00:00Z",hour)));XCTAssertEqual(try DiaryTime.category(date,zoneID:"UTC"),expected) }
        let spring=try XCTUnwrap(format.date(from:"2026-03-29T12:00:00Z"));let fall=try XCTUnwrap(format.date(from:"2026-10-25T12:00:00Z"))
        XCTAssertEqual(try DiaryTime.dayInterval(containing:spring,zoneID:"Europe/Stockholm").duration,23*3600)
        XCTAssertEqual(try DiaryTime.dayInterval(containing:fall,zoneID:"Europe/Stockholm").duration,25*3600)
    }
    func testChecksumSchemaAndUnknownMigrationFailClosed()throws {
        let source=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MealTrackerCatalog/Resources/DevelopmentPack")
        let copy=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at:source,to:copy)
        try Data("tamper".utf8).write(to:copy.appendingPathComponent("attribution.json"))
        XCTAssertThrowsError(try CatalogueRepository(packDirectory:copy))
        let manifest=copy.appendingPathComponent("manifest.json");var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:manifest)) as? [String:Any]);json["schemaVersion"]=999;try JSONSerialization.data(withJSONObject:json).write(to:manifest)
        XCTAssertThrowsError(try CatalogueRepository(packDirectory:copy))
        let url=databaseURL();_ = try DiaryStore(databaseURL:url)
        let db=try DatabaseQueue(path:url.path);try db.write { try $0.execute(sql:"INSERT INTO grdb_migrations VALUES ('future-v99')") }
        XCTAssertThrowsError(try DiaryStore(databaseURL:url))
        XCTAssertEqual(try db.read { try Int.fetchOne($0,sql:"SELECT count(*) FROM grdb_migrations") },4)
    }
    func testConcurrentSameOperationOneRevision()throws {
        let store=try DiaryStore(databaseURL:databaseURL());let draft=try draft();let operation=UUID()
        let lock=NSLock();var failures=[Error]()
        DispatchQueue.concurrentPerform(iterations:12) { _ in do { _ = try store.save(draft,operationID:operation) } catch { lock.lock();failures.append(error);lock.unlock() } }
        XCTAssertTrue(failures.isEmpty);XCTAssertEqual(try store.history(id:draft.id).count,1)
    }
    func testLatestEventCanBeReadForConflictResolution() throws {
        let store = try DiaryStore(databaseURL: databaseURL())
        let draft = try draft()
        let saved = try store.save(draft, operationID: UUID())

        XCTAssertEqual(try store.event(id: draft.id), saved)

        var changed = draft
        changed.category = .dinner
        let updated = try store.save(changed, operationID: UUID(), expectedRevision: saved.revision)
        XCTAssertEqual(try store.event(id: draft.id), updated)
    }
    func testInvalidDateAndQuantityReject()throws {
        XCTAssertThrowsError(try DiaryTime.localDate(Date(timeIntervalSince1970:.infinity),zoneID:"UTC"))
        XCTAssertThrowsError(try LoggedQuantity(amount:DecimalAmount("1"),unit:.grams,portionID:"extra").consumed())
    }

    func testRehashedSQLCurrentTamperingRejected()throws {
        let source=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MealTrackerCatalog/Resources/DevelopmentPack")
        let copy=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at:source,to:copy)
        let database=copy.appendingPathComponent("catalogue.sqlite")
        do { let db=try DatabaseQueue(path:database.path);try db.write { try $0.execute(sql:"UPDATE metadata SET value='\"00000000-0000-4000-8000-000000000003\"' WHERE key='generationID'") } }
        let manifest=copy.appendingPathComponent("manifest.json");var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:manifest)) as? [String:Any]);var files=try XCTUnwrap(json["files"] as? [String:String]);files["catalogue.sqlite"]=SHA256.hash(data:try Data(contentsOf:database)).map { String(format:"%02x",$0) }.joined();json["files"]=files
        try JSONSerialization.data(withJSONObject:json).write(to:manifest)
        XCTAssertThrowsError(try CatalogueRepository(packDirectory:copy))
    }

}
