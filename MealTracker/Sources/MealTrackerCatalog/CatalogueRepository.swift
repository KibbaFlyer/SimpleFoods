import Foundation
import CryptoKit
import GRDB
import MealTrackerCore

public enum CatalogueError: Error { case unsupportedSchema, checksumMismatch, invalidPack, notFound }
public struct CatalogueManifest: Decodable, Sendable {
    public let schemaVersion: Int
    public let minimumReaderVersion: Int
    public let generationID: UUID
    public let packID: String
    public let packVersion: String
    public let calculationVersion: String
    public let fixtureOnly: Bool
    public let mode: String
    public let files: [String:String]
    public let currentRecordCount: Int
    public let retainedRevisionCount: Int
}
/// Immutable D02 reader. It never writes public source files or queries the network.
public final class CatalogueRepository: @unchecked Sendable {
    private let database: DatabaseQueue
    public let manifest: CatalogueManifest
    public let attribution: Data
    public let provenance: [String:Provenance]
    public let evidence: [String:FixtureEvidence]
    public var generationID: UUID { manifest.generationID }
    public var fixtureOnly: Bool { manifest.fixtureOnly }
    public init(packDirectory: URL) throws {
        let decoder = JSONDecoder()
        manifest = try decoder.decode(CatalogueManifest.self, from: Data(contentsOf: packDirectory.appendingPathComponent("manifest.json")))
        guard manifest.schemaVersion == 1, manifest.minimumReaderVersion <= 1 else { throw CatalogueError.unsupportedSchema }
        // This bounded reader accepts only explicitly synthetic development material.
        guard manifest.fixtureOnly, manifest.mode == "development" else { throw CatalogueError.invalidPack }
        let required = Set(["catalogue.sqlite", "catalogue.normalized.json", "attribution.json", "diff.json"])
        guard Set(manifest.files.keys) == required else { throw CatalogueError.invalidPack }
        for (name, expected) in manifest.files {
            let data = try Data(contentsOf: packDirectory.appendingPathComponent(name))
            guard SHA256.hash(data: data).map({ String(format:"%02x", $0) }).joined() == expected else { throw CatalogueError.checksumMismatch }
        }
        attribution = try Data(contentsOf: packDirectory.appendingPathComponent("attribution.json"))
        let fixture = try decoder.decode(CatalogueFixture.self, from: Data(contentsOf: packDirectory.appendingPathComponent("catalogue.normalized.json")))
        try fixture.validate()
        guard fixture.provenance.values.allSatisfy({ $0.providerID == "mealtracker.synthetic" && $0.reviewStatus == "syntheticOnly" && $0.sourceURL == nil }) else { throw CatalogueError.invalidPack }
        provenance=fixture.provenance;evidence=fixture.evidence ?? [:]
        guard fixture.packID == manifest.packID, fixture.packVersion == manifest.packVersion,fixture.calculationVersion == manifest.calculationVersion,fixture.generationID == manifest.generationID, fixture.foods.count == manifest.currentRecordCount, fixture.retainedRevisions.count == manifest.retainedRevisionCount else { throw CatalogueError.invalidPack }
        var configuration = Configuration(); configuration.readonly = true
        database = try DatabaseQueue(path: packDirectory.appendingPathComponent("catalogue.sqlite").path, configuration: configuration)
        try database.read { db in
            guard try Int.fetchOne(db, sql:"PRAGMA user_version") == 1, try String.fetchOne(db, sql:"PRAGMA quick_check") == "ok" else { throw CatalogueError.unsupportedSchema }
            let generation = try String.fetchOne(db,sql:"SELECT value FROM metadata WHERE key='generationID'")
            guard let generation, try decoder.decode(UUID.self,from:Data(generation.utf8)) == fixture.generationID else { throw CatalogueError.invalidPack }
            let current = try String.fetchAll(db,sql:"SELECT record_json FROM food_revision WHERE current=1").map { try decoder.decode(CatalogueFood.self,from:Data($0.utf8)) }
            guard current.count == fixture.foods.count, current.allSatisfy({ fixture.foods.contains($0) }) else { throw CatalogueError.invalidPack }
            let rows = try String.fetchAll(db, sql:"SELECT record_json FROM food_revision")
            guard rows.count == fixture.foods.count + fixture.retainedRevisions.count else { throw CatalogueError.invalidPack }
            let expected = fixture.foods + fixture.retainedRevisions
            for row in try Row.fetchAll(db,sql:"SELECT * FROM food_revision") {
                let raw: String = row["record_json"]
                let food = try decoder.decode(CatalogueFood.self,from:Data(raw.utf8))
                guard case let .catalogue(namespace,recordID) = food.id else { throw CatalogueError.invalidPack }
                let storedNamespace:String=row["namespace"], storedID:String=row["record_id"], revision:String=row["revision"], lifecycle:String=row["lifecycle"], hash:String=row["record_sha256"]
                let isCurrent:Int=row["current"]
                let digest=SHA256.hash(data:Data(raw.utf8)).map { String(format:"%02x",$0) }.joined()
                guard expected.contains(food),storedNamespace == namespace,storedID == recordID,revision == food.revision,lifecycle == food.lifecycle,hash == digest,(isCurrent == 1 ? fixture.foods : fixture.retainedRevisions).contains(food) else { throw CatalogueError.invalidPack }
            }
            let metadata:[String:Data] = ["schemaVersion":try JSONEncoder().encode(fixture.schemaVersion),"packID":try JSONEncoder().encode(fixture.packID),"packVersion":try JSONEncoder().encode(fixture.packVersion),"calculationVersion":try JSONEncoder().encode(fixture.calculationVersion),"fixtureOnly":try JSONEncoder().encode(fixture.fixtureOnly)]
            for (key,value) in metadata { guard let stored=try String.fetchOne(db,sql:"SELECT value FROM metadata WHERE key=?",arguments:[key]),Data(stored.utf8) == value else { throw CatalogueError.invalidPack } }
        }
    }
    public static func bundledDevelopment() throws -> CatalogueRepository {
        guard let url = Bundle.module.url(forResource:"DevelopmentPack", withExtension:nil) else { throw CatalogueError.notFound }
        return try CatalogueRepository(packDirectory:url)
    }
    public func displayName(_ food: CatalogueFood, language: String) -> String { food.names[language] ?? food.names["en"] ?? food.names.sorted(by:{$0.key < $1.key}).first?.value ?? "Unknown food" }
    public func search(query: String, language: String = "en", market: String? = nil) throws -> [CatalogueFood] {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        let locale = Locale(identifier: language)
        let ranked: [(food: CatalogueFood, name: String, rank: Int)] = try current(market: market).compactMap { food in
            let name = displayName(food, language: language)
            guard let rank = FoodSearchRanking.rank(displayName: name, searchableNames: food.names.values, query: query, locale: locale) else { return nil }
            return (food: food, name: name, rank: rank)
        }
        return ranked.sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            return left.name.compare(right.name, options: [.caseInsensitive, .diacriticInsensitive, .numeric], range: nil, locale: locale) == .orderedAscending
        }.map(\.food)
    }
    public func barcodeMatches(_ barcode: String, market: String? = nil) throws -> [CatalogueFood] { try current(market:market).filter { $0.barcodes.contains(barcode) } }
    public func retainedFood(id: FoodID, revision: String) throws -> CatalogueFood {
        try database.read { db in
            for row in try String.fetchAll(db, sql:"SELECT record_json FROM food_revision WHERE revision = ?", arguments:[revision]) { let food = try JSONDecoder().decode(CatalogueFood.self, from:Data(row.utf8)); if food.id == id { return food } }
            throw CatalogueError.notFound
        }
    }
    private func current(market: String?) throws -> [CatalogueFood] {
        try database.read { db in try String.fetchAll(db,sql:"SELECT record_json FROM food_revision WHERE current=1 AND lifecycle='active'").map { try JSONDecoder().decode(CatalogueFood.self,from:Data($0.utf8)) }.filter { market == nil || market == "all" || $0.salesCountries.contains(market!) } }
    }
}
