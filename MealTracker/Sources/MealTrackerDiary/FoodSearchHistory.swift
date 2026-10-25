import Foundation
import GRDB
import MealTrackerCore

public struct FoodSearchPreference: Sendable {
    public let food: CatalogueFood
    public let lastUsed: Date?
    public let isFavorite: Bool
    public let lastSelectedForQuery: Date?

    public func isRecentlyUsed(now: Date = Date()) -> Bool {
        guard let lastUsed else { return false }
        return lastUsed >= now.addingTimeInterval(-30 * 24 * 60 * 60)
    }

    public func priority(now: Date = Date()) -> Int {
        if lastSelectedForQuery != nil { return 3 }
        if isFavorite { return 2 }
        return isRecentlyUsed(now: now) ? 1 : 0
    }
}

/// Private search-to-food associations, favorites, and successful diary additions.
public final class FoodSearchHistory: Sendable {
    private let store: DiaryStore

    public init(store: DiaryStore) { self.store = store }

    private static func key(_ id: FoodID) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(id), as: UTF8.self)
    }

    public static func normalizedQuery(_ query: String, language: String) -> String {
        query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: language))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func recordUse(_ db: Database, food: CatalogueFood, date: Date) throws {
        try db.execute(sql: """
            INSERT INTO food_search_history(food_id,payload,last_used) VALUES (?,?,?)
            ON CONFLICT(food_id) DO UPDATE SET
                payload=CASE WHEN excluded.last_used >= COALESCE(last_used,0) THEN excluded.payload ELSE payload END,
                last_used=MAX(COALESCE(last_used,0),excluded.last_used)
            """, arguments: [try key(food.id), try JSONEncoder().encode(food), date.timeIntervalSince1970])
    }

    public func recordSelection(food: CatalogueFood, query: String, language: String, now: Date = Date()) throws {
        let query = Self.normalizedQuery(query, language: language)
        guard !query.isEmpty else { return }
        try store.writer.write { db in
            let id = try Self.key(food.id)
            try db.execute(sql: "INSERT INTO food_search_history(food_id,payload) VALUES (?,?) ON CONFLICT(food_id) DO UPDATE SET payload=excluded.payload",
                           arguments: [id, try JSONEncoder().encode(food)])
            try db.execute(sql: "INSERT INTO food_search_queries VALUES (?,?,?,?) ON CONFLICT(query,language,food_id) DO UPDATE SET last_selected=excluded.last_selected",
                           arguments: [query, language, id, now.timeIntervalSince1970])
        }
    }

    public func setFavorite(_ favorite: Bool, food: CatalogueFood) throws {
        try store.writer.write { db in
            try db.execute(sql: "INSERT INTO food_search_history(food_id,payload,favorite) VALUES (?,?,?) ON CONFLICT(food_id) DO UPDATE SET payload=excluded.payload,favorite=excluded.favorite",
                           arguments: [try Self.key(food.id), try JSONEncoder().encode(food), favorite])
        }
    }

    public func preferences(query: String, language: String) throws -> [FoodID: FoodSearchPreference] {
        try store.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT h.payload,h.last_used,h.favorite,q.last_selected
                FROM food_search_history h LEFT JOIN food_search_queries q
                ON h.food_id=q.food_id AND q.query=? AND q.language=?
                """, arguments: [Self.normalizedQuery(query, language: language), language])
            return try Dictionary(uniqueKeysWithValues: rows.map { row in
                let food = try JSONDecoder().decode(CatalogueFood.self, from: row["payload"])
                let used: Double? = row["last_used"]
                let selected: Double? = row["last_selected"]
                return (food.id, FoodSearchPreference(food: food, lastUsed: used.map(Date.init(timeIntervalSince1970:)), isFavorite: row["favorite"], lastSelectedForQuery: selected.map(Date.init(timeIntervalSince1970:))))
            })
        }
    }
}

extension FoodSearchHistory {
    /// A cheap connection-local change counter invalidates cached decoded history
    /// after diary, favorite, overlay or personal-food writes (including rollback).
    public func revision() throws -> Int64 {
        try store.writer.read { try Int64.fetchOne($0, sql: "SELECT total_changes()") ?? 0 }
    }

    public func selectionDates(query: String, language: String) throws -> [FoodID: Date] {
        let query = Self.normalizedQuery(query, language: language)
        guard !query.isEmpty else { return [:] }
        return try store.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT food_id,last_selected FROM food_search_queries WHERE query=? AND language=?", arguments: [query, language])
            return try Dictionary(uniqueKeysWithValues: rows.map { row in
                let key: String = row["food_id"]
                let timestamp: Double = row["last_selected"]
                return (try JSONDecoder().decode(FoodID.self, from: Data(key.utf8)), Date(timeIntervalSince1970: timestamp))
            })
        }
    }
}
