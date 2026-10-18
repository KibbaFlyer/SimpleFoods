import Foundation
import GRDB
import MealTrackerCore

/// One serialized private writer. Every event revision, operation receipt, change
/// sequence and disabled export intent commits in one SQLite transaction.
public final class DiaryStore: @unchecked Sendable {
    let writer: DatabaseQueue
    private var encoder: JSONEncoder { let value=JSONEncoder();value.outputFormatting=[.sortedKeys];value.dateEncodingStrategy = .custom { date, encoder in try DiaryTime.validate(date);var container=encoder.singleValueContainer();try container.encode(Int64((date.timeIntervalSince1970*1_000_000).rounded())) };return value }
    private var decoder: JSONDecoder { let value=JSONDecoder();value.dateDecodingStrategy = .custom { decoder in let ticks=try decoder.singleValueContainer().decode(Int64.self);let date=Date(timeIntervalSince1970:Double(ticks)/1_000_000);try DiaryTime.validate(date);return date };return value }
    public let diaryIdentity: UUID
    public init(databaseURL:URL)throws {
        let directory=databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var excluded=directory;var values=URLResourceValues();values.isExcludedFromBackup=true;try excluded.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:directory.path)
        #endif
        writer=try DatabaseQueue(path:databaseURL.path)
        var migrator=DatabaseMigrator()
        migrator.registerMigration("private-v1") { db in
            try db.execute(sql:"""
            CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE events(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,local_date TEXT NOT NULL,deleted INTEGER NOT NULL,payload BLOB NOT NULL);
            CREATE TABLE event_history(id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(id,revision));
            CREATE TABLE drafts(id TEXT PRIMARY KEY,payload BLOB NOT NULL);
            CREATE TABLE operations(id TEXT PRIMARY KEY,request BLOB NOT NULL,result BLOB NOT NULL);
            CREATE TABLE changes(sequence INTEGER PRIMARY KEY AUTOINCREMENT,event_id TEXT NOT NULL,revision INTEGER NOT NULL,reason TEXT NOT NULL);
            CREATE TABLE export_intents(event_id TEXT PRIMARY KEY,revision INTEGER NOT NULL,state TEXT NOT NULL CHECK(state='disabled'),reason TEXT NOT NULL);
            """)
            try db.execute(sql:"INSERT INTO metadata VALUES ('diaryIdentity',?)",arguments:[UUID().uuidString])
        }
        migrator.registerMigration("private-v2-personal") { db in
            try db.execute(sql:"""
            ALTER TABLE drafts ADD COLUMN saved_at INTEGER NOT NULL DEFAULT 0;
            CREATE TABLE personal_overlays(target TEXT PRIMARY KEY,revision INTEGER NOT NULL,payload BLOB NOT NULL);
            CREATE TABLE overlay_history(target TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(target,revision));
            CREATE TABLE personal_foods(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,hidden INTEGER NOT NULL,payload BLOB NOT NULL);
            CREATE TABLE personal_food_history(id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(id,revision));
            CREATE TABLE personal_operations(id TEXT PRIMARY KEY,request BLOB NOT NULL,result BLOB NOT NULL);
            """)
        }
        migrator.registerMigration("private-v3-saved-meals") { db in
            try db.execute(sql:"""
            CREATE TABLE saved_meals(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,deleted INTEGER NOT NULL,payload BLOB NOT NULL);
            CREATE TABLE saved_meal_history(id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(id,revision));
            CREATE TABLE saved_meal_operations(id TEXT PRIMARY KEY,request BLOB NOT NULL,result BLOB NOT NULL);
            """)
        }
        let unknown = try writer.read { db -> Bool in
            guard try db.tableExists("grdb_migrations") else { return false };return try String.fetchAll(db,sql:"SELECT identifier FROM grdb_migrations").contains { !["private-v1","private-v2-personal","private-v3-saved-meals"].contains($0) }
        };guard !unknown else { throw DiaryError.invalidInput }
        try migrator.migrate(writer)
        diaryIdentity=try writer.read { db in guard let value=try String.fetchOne(db,sql:"SELECT value FROM metadata WHERE key='diaryIdentity'"),let id=UUID(uuidString:value) else { throw DiaryError.invalidInput };return id }
        #if os(iOS)
        for path in [databaseURL.path,databaseURL.path+"-wal",databaseURL.path+"-shm"] where FileManager.default.fileExists(atPath:path) { try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:path) }
        #endif
    }
    public func saveDraft(_ draft:MealDraft)throws { let data=try encoder.encode(draft);try writer.write { db in try db.execute(sql:"INSERT INTO drafts(id,payload,saved_at) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,saved_at=excluded.saved_at",arguments:[draft.id.uuidString,data,Int64((Date().timeIntervalSince1970*1_000_000).rounded())]) } }
    public func deleteDraft(id:UUID)throws { try writer.write { try $0.execute(sql:"DELETE FROM drafts WHERE id=?",arguments:[id.uuidString]) } }
    public func receipt(operationID:UUID)throws->MealEvent? { try writer.read { db in try Data.fetchOne(db,sql:"SELECT result FROM operations WHERE id=?",arguments:[operationID.uuidString]).map { try decodeEvent($0) } } }
    public func loadDraft(id:UUID)throws->MealDraft? { try writer.read { db in try Data.fetchOne(db,sql:"SELECT payload FROM drafts WHERE id=?",arguments:[id.uuidString]).map { try decoder.decode(MealDraft.self,from:$0) } } }
    public func drafts()throws->[MealDraft] { try writer.read { db in try Data.fetchAll(db,sql:"SELECT payload FROM drafts ORDER BY saved_at DESC,id").map { try decoder.decode(MealDraft.self,from:$0) } } }

    public func createSavedMeal(_ draft: SavedMealDraft, operationID: UUID, now: Date = Date()) throws -> SavedMeal {
        struct Request: Encodable { let command = "createSavedMeal"; let draft: SavedMealDraft }
        let request = try encoder.encode(Request(draft: draft))
        return try writer.write { db in
            if let result = try savedMealReceipt(db, id: operationID, request: request) { return result }
            try DiaryTime.validate(now)
            let result = SavedMeal(id: UUID(), revision: 1, draft: draft, createdAt: now, updatedAt: now)
            try commitSavedMeal(db, meal: result, operationID: operationID, request: request)
            return try decodeSavedMeal(encoder.encode(result))
        }
    }

    public func updateSavedMeal(id: UUID, draft: SavedMealDraft, expectedRevision: Int64, operationID: UUID, now: Date = Date()) throws -> SavedMeal {
        struct Request: Encodable { let command = "updateSavedMeal"; let id: UUID; let draft: SavedMealDraft; let expectedRevision: Int64 }
        let request = try encoder.encode(Request(id: id, draft: draft, expectedRevision: expectedRevision))
        return try writer.write { db in
            if let result = try savedMealReceipt(db, id: operationID, request: request) { return result }
            try DiaryTime.validate(now)
            guard let old = try currentSavedMeal(db, id: id) else { throw DiaryError.notFound }
            guard old.revision == expectedRevision, old.deletedAt == nil else { throw DiaryError.staleRevision }
            let result = SavedMeal(id: id, revision: try next(old.revision), draft: draft, createdAt: old.createdAt, updatedAt: now)
            try commitSavedMeal(db, meal: result, operationID: operationID, request: request)
            return try decodeSavedMeal(encoder.encode(result))
        }
    }

    public func deleteSavedMeal(id: UUID, expectedRevision: Int64, operationID: UUID, now: Date = Date()) throws -> SavedMeal {
        struct Request: Encodable { let command = "deleteSavedMeal"; let id: UUID; let expectedRevision: Int64 }
        let request = try encoder.encode(Request(id: id, expectedRevision: expectedRevision))
        return try writer.write { db in
            if let result = try savedMealReceipt(db, id: operationID, request: request) { return result }
            try DiaryTime.validate(now)
            guard let old = try currentSavedMeal(db, id: id) else { throw DiaryError.notFound }
            guard old.revision == expectedRevision, old.deletedAt == nil else { throw DiaryError.staleRevision }
            let draft = try SavedMealDraft(name: old.name, tags: old.tags, servingsProduced: old.servingsProduced, ingredients: old.ingredients)
            let result = SavedMeal(id: id, revision: try next(old.revision), draft: draft, createdAt: old.createdAt, updatedAt: now, deletedAt: now)
            try commitSavedMeal(db, meal: result, operationID: operationID, request: request)
            return try decodeSavedMeal(encoder.encode(result))
        }
    }

    /// Returns the latest revision, including a deleted saved meal.
    public func savedMeal(id: UUID) throws -> SavedMeal? { try writer.read { try currentSavedMeal($0, id: id) } }
    public func savedMeals() throws -> [SavedMeal] { try writer.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM saved_meals WHERE deleted=0 ORDER BY id").map { try decodeSavedMeal($0) } } }
    public func savedMealHistory(id: UUID) throws -> [SavedMeal] { try writer.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM saved_meal_history WHERE id=? ORDER BY revision", arguments: [id.uuidString]).map { try decodeSavedMeal($0) } } }
    /// Returns the latest persisted version, including a deleted event.
    /// Callers can use this to distinguish a harmless revision-only refresh from
    /// a real concurrent edit before deciding whether to retry a save.
    public func event(id: UUID) throws -> MealEvent? {
        try writer.read { db in try current(db, id: id) }
    }
    public func events(localDate:String)throws->[MealEvent] { try writer.read { db in try Data.fetchAll(db,sql:"SELECT payload FROM events WHERE local_date=? AND deleted=0",arguments:[localDate]).map { try decodeEvent($0) }.sorted { $0.eatenAt < $1.eatenAt } } }
    public func history(id:UUID)throws->[MealEvent] { try writer.read { db in try Data.fetchAll(db,sql:"SELECT payload FROM event_history WHERE id=? ORDER BY revision",arguments:[id.uuidString]).map { try decodeEvent($0) } } }
    public func save(_ draft:MealDraft,operationID:UUID,expectedRevision:Int64?=nil,confirmFuture:Bool=false,now:Date=Date(),injectFailureBeforeCommit:Bool=false)throws->MealEvent {
        struct Request:Encodable { let draft:MealDraft;let expectedRevision:Int64?;let confirmFuture:Bool }
        let request=try encoder.encode(Request(draft:draft,expectedRevision:expectedRevision,confirmFuture:confirmFuture))
        if draft.eatenAt > now && !confirmFuture {
            if let previous=try writer.read({ try receipt($0,id:operationID,request:request) }) { return previous }
            try saveDraft(draft);throw DiaryError.futureRequiresConfirmation
        }
        return try writer.write { db in
            if let result=try receipt(db,id:operationID,request:request) { return result }
            try DiaryTime.validate(draft.eatenAt);try DiaryTime.validate(now)
            guard draft.eatenAt <= now || confirmFuture else { throw DiaryError.futureRequiresConfirmation }
            guard !draft.components.isEmpty,Set(draft.components.map(\.id)).count == draft.components.count else { throw DiaryError.invalidInput }
            let old=try current(db,id:draft.id)
            guard old?.revision == expectedRevision,old?.deletedAt == nil else { throw DiaryError.staleRevision }
            let revision=try next(old?.revision)
            let computed=try NutritionCalculator.aggregate(draft.components.map { try NutritionCalculator.calculate(profile:$0.food.profile,quantity:$0.quantity.consumed()) })
            let totals=try Dictionary(uniqueKeysWithValues:computed.nutrients.map { ($0.key.rawValue,try StoredNutrientTotal($0.value)) })
            let zone=try DiaryTime.calendar(zoneID:draft.zoneID).timeZone
            let event=MealEvent(schemaVersion:1,id:draft.id,diaryIdentity:diaryIdentity,revision:revision,eatenAt:draft.eatenAt,zoneID:draft.zoneID,utcOffsetSeconds:zone.secondsFromGMT(for:draft.eatenAt),localDate:try DiaryTime.localDate(draft.eatenAt,zoneID:draft.zoneID),category:try draft.category ?? DiaryTime.category(draft.eatenAt,zoneID:draft.zoneID),categoryMode:draft.category == nil ? "automatic":"manual",components:draft.components,totals:totals,calculationVersion:NutritionCalculator.calculationVersion,createdAt:old?.createdAt ?? now,updatedAt:now,deletedAt:nil)
            try commit(db,event:event,operationID:operationID,request:request,reason:"save")
            try db.execute(sql:"DELETE FROM drafts WHERE id=?",arguments:[draft.id.uuidString])
            if injectFailureBeforeCommit { throw DiaryError.injectedFailure };return try decodeEvent(encoder.encode(event))
        }
    }
    public func delete(id:UUID,operationID:UUID,expectedRevision:Int64,now:Date=Date())throws->MealEvent {
        struct Request:Encodable { let deleteID:UUID;let expectedRevision:Int64 }
        let request=try encoder.encode(Request(deleteID:id,expectedRevision:expectedRevision))
        return try writer.write { db in
            if let result=try receipt(db,id:operationID,request:request) { return result }
            guard let old=try current(db,id:id) else { throw DiaryError.notFound }
            guard old.revision == expectedRevision,old.deletedAt == nil else { throw DiaryError.staleRevision }
            let event=MealEvent(schemaVersion:old.schemaVersion,id:id,diaryIdentity:diaryIdentity,revision:try next(old.revision),eatenAt:old.eatenAt,zoneID:old.zoneID,utcOffsetSeconds:old.utcOffsetSeconds,localDate:old.localDate,category:old.category,categoryMode:old.categoryMode,components:old.components,totals:old.totals,calculationVersion:old.calculationVersion,createdAt:old.createdAt,updatedAt:now,deletedAt:now)
            try commit(db,event:event,operationID:operationID,request:request,reason:"delete");return try decodeEvent(encoder.encode(event))
        }
    }
    private func decodeEvent(_ data:Data)throws->MealEvent { let event=try decoder.decode(MealEvent.self,from:data);guard event.schemaVersion == 1 else { throw DiaryError.invalidInput };return event }
    private func decodeSavedMeal(_ data: Data) throws -> SavedMeal {
        let meal = try decoder.decode(SavedMeal.self, from: data)
        _ = try SavedMealDraft(name: meal.name, tags: meal.tags, servingsProduced: meal.servingsProduced, ingredients: meal.ingredients)
        guard meal.schemaVersion == 1, meal.revision > 0 else { throw DiaryError.invalidInput }
        try DiaryTime.validate(meal.createdAt)
        try DiaryTime.validate(meal.updatedAt)
        if let deletedAt = meal.deletedAt { try DiaryTime.validate(deletedAt) }
        return meal
    }
    private func next(_ old:Int64?)throws->Int64 { guard old != Int64.max else { throw DiaryError.revisionOverflow };return (old ?? 0)+1 }
    private func current(_ db:Database,id:UUID)throws->MealEvent? { try Data.fetchOne(db,sql:"SELECT payload FROM events WHERE id=?",arguments:[id.uuidString]).map { try decodeEvent($0) } }
    private func currentSavedMeal(_ db: Database, id: UUID) throws -> SavedMeal? { try Data.fetchOne(db, sql: "SELECT payload FROM saved_meals WHERE id=?", arguments: [id.uuidString]).map { try decodeSavedMeal($0) } }
    private func receipt(_ db:Database,id:UUID,request:Data)throws->MealEvent? { guard try Int.fetchOne(db,sql:"SELECT count(*) FROM personal_operations WHERE id=?",arguments:[id.uuidString]) == 0 else { throw DiaryError.operationConflict };guard let row=try Row.fetchOne(db,sql:"SELECT request,result FROM operations WHERE id=?",arguments:[id.uuidString]) else { return nil };let original:Data=row["request"];guard original == request else { throw DiaryError.operationConflict };return try decodeEvent(row["result"]) }
    private func commit(_ db:Database,event:MealEvent,operationID:UUID,request:Data,reason:String)throws {
        let data=try encoder.encode(event)
        try db.execute(sql:"INSERT INTO events VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,local_date=excluded.local_date,deleted=excluded.deleted,payload=excluded.payload",arguments:[event.id.uuidString,event.revision,event.localDate,event.deletedAt == nil ? 0:1,data])
        try db.execute(sql:"INSERT INTO event_history VALUES (?,?,?)",arguments:[event.id.uuidString,event.revision,data])
        try db.execute(sql:"INSERT INTO operations VALUES (?,?,?)",arguments:[operationID.uuidString,request,data])
        try db.execute(sql:"INSERT INTO changes(event_id,revision,reason) VALUES (?,?,?)",arguments:[event.id.uuidString,event.revision,reason])
        try db.execute(sql:"INSERT INTO export_intents VALUES (?,?,'disabled',?) ON CONFLICT(event_id) DO UPDATE SET revision=excluded.revision,reason=excluded.reason",arguments:[event.id.uuidString,event.revision,event.components.contains(where:{$0.fixtureOnly}) ? "fixtureIneligible":"allSourcesDisabled"])
    }
    private func savedMealReceipt(_ db: Database, id: UUID, request: Data) throws -> SavedMeal? {
        guard try Int.fetchOne(db, sql: "SELECT count(*) FROM operations WHERE id=?", arguments: [id.uuidString]) == 0,
              try Int.fetchOne(db, sql: "SELECT count(*) FROM personal_operations WHERE id=?", arguments: [id.uuidString]) == 0 else { throw DiaryError.operationConflict }
        guard let row = try Row.fetchOne(db, sql: "SELECT request,result FROM saved_meal_operations WHERE id=?", arguments: [id.uuidString]) else { return nil }
        let original: Data = row["request"]
        guard original == request else { throw DiaryError.operationConflict }
        return try decodeSavedMeal(row["result"])
    }
    private func commitSavedMeal(_ db: Database, meal: SavedMeal, operationID: UUID, request: Data) throws {
        let data = try encoder.encode(meal)
        try db.execute(sql: "INSERT INTO saved_meals VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,deleted=excluded.deleted,payload=excluded.payload", arguments: [meal.id.uuidString, meal.revision, meal.deletedAt == nil ? 0 : 1, data])
        try db.execute(sql: "INSERT INTO saved_meal_history VALUES (?,?,?)", arguments: [meal.id.uuidString, meal.revision, data])
        try db.execute(sql: "INSERT INTO saved_meal_operations VALUES (?,?,?)", arguments: [operationID.uuidString, request, data])
    }
}
