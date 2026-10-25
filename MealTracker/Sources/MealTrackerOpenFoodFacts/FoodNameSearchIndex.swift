import Foundation
import GRDB
import MealTrackerCore

public struct FoodSearchDocument: Sendable {
    public let id: String
    public let source: String
    public let names: [String: String]
    public let brand: String
    public let markets: [String]

    public init(id: String, source: String, names: [String: String], brand: String = "", markets: [String]) {
        self.id = id
        self.source = source
        self.names = names
        self.brand = brand
        self.markets = markets
    }
}

public struct FoodSearchCandidates: Sendable {
    public let ids: [String]
    public let correctedQuery: String?
}

/// Lightweight derived indexes. Call from a search actor, never from the UI actor.
public final class FoodNameSearchIndex: @unchecked Sendable {
    private let database: DatabaseQueue
    let supportsTrigrams: Bool

    public convenience init() throws { try self.init(database: DatabaseQueue()) }

    init(database: DatabaseQueue) throws {
        self.database = database
        supportsTrigrams = try database.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS search_documents(
                    id INTEGER PRIMARY KEY, food_id TEXT NOT NULL UNIQUE, source TEXT NOT NULL,
                    en TEXT NOT NULL, sv TEXT NOT NULL, de TEXT NOT NULL, other TEXT NOT NULL,
                    brand TEXT NOT NULL, search_text TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS search_document_source ON search_documents(source);
                CREATE TABLE IF NOT EXISTS search_markets(document_id INTEGER NOT NULL, market TEXT NOT NULL, PRIMARY KEY(market,document_id));
                CREATE VIRTUAL TABLE IF NOT EXISTS search_words USING fts5(
                    en,sv,de,other,brand,content='search_documents',content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2',prefix='2 3 4');
                CREATE VIRTUAL TABLE IF NOT EXISTS search_vocabulary USING fts5vocab(search_words,'row');
                """)
            // Older system SQLite builds can still use word/prefix search. The
            // bounded substring fallback below remains available without trigrams.
            do {
                try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS search_trigrams USING fts5(search_text,content='search_documents',content_rowid='id',tokenize='trigram')")
                return true
            } catch { return false }
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func terms(_ query: String) -> [String] {
        normalize(query).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func quoted(_ term: String) -> String { "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    public func replace(with documents: [FoodSearchDocument]) throws {
        try database.write { db in
            try reset(in: db)
            for document in documents {
                try Task.checkCancellation()
                try insert(document, in: db)
            }
            try finish(in: db)
        }
    }

    func reset(in db: Database) throws {
        try db.execute(sql: "DELETE FROM search_markets; DELETE FROM search_documents")
    }

    // External-content FTS tables use rebuild after the authoritative rows have
    // been replaced, so document, market and text indexes commit atomically.
    func insert(_ document: FoodSearchDocument, in db: Database) throws {
        let other = document.names.filter { !["en", "sv", "de"].contains($0.key) }.sorted { $0.key < $1.key }.map(\.value).joined(separator: " ")
        let values = [document.names["en"] ?? "", document.names["sv"] ?? "", document.names["de"] ?? "", other, document.brand].map(Self.normalize)
        try db.execute(sql: "INSERT INTO search_documents(food_id,source,en,sv,de,other,brand,search_text) VALUES (?,?,?,?,?,?,?,?)", arguments: StatementArguments([document.id, document.source] + values + [values.joined(separator: " ")]))
        let rowID = db.lastInsertedRowID
        for market in Set(document.markets) {
            try db.execute(sql: "INSERT INTO search_markets VALUES (?,?)", arguments: [rowID, market])
        }
    }

    func finish(in db: Database) throws {
        try db.execute(sql: "INSERT INTO search_words(search_words) VALUES('rebuild')")
        if supportsTrigrams { try db.execute(sql: "INSERT INTO search_trigrams(search_trigrams) VALUES('rebuild')") }
    }

    public func candidates(query: String, language: String, market: String?, source: String?, limit: Int, allowTypos: Bool = true) throws -> FoodSearchCandidates {
        try Task.checkCancellation()
        let limit = max(1, limit)
        let terms = Self.terms(query)
        return try database.read { db in
            var filters: [String] = []
            var filterArguments = StatementArguments()
            if let source { filters.append("d.source=?"); filterArguments += [source] }
            if let market { filters.append("d.id IN (SELECT document_id FROM search_markets WHERE market=?)"); filterArguments += [market] }
            let suffix = filters.isEmpty ? "" : " AND " + filters.joined(separator: " AND ")
            func fullText(_ expression: String) throws -> [String] {
                let weights = language == "sv" ? "bm25(2,8,2,1,3)" : language == "de" ? "bm25(2,2,8,1,3)" : "bm25(8,2,2,1,3)"
                var arguments: StatementArguments = [expression, weights]
                arguments += filterArguments
                arguments += [limit]
                return try String.fetchAll(db, sql: "SELECT d.food_id FROM search_words JOIN search_documents d ON d.id=search_words.rowid WHERE search_words MATCH ? AND rank MATCH ?\(suffix) ORDER BY rank LIMIT ?", arguments: arguments)
            }
            guard !terms.isEmpty else {
                guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return FoodSearchCandidates(ids: [], correctedQuery: nil)
                }
                let whereClause = filters.isEmpty ? "" : " WHERE " + filters.joined(separator: " AND ")
                var arguments = filterArguments; arguments += [limit]
                return FoodSearchCandidates(ids: try String.fetchAll(db, sql: "SELECT d.food_id FROM search_documents d\(whereClause) ORDER BY COALESCE(NULLIF(d.\(language == "sv" ? "sv" : language == "de" ? "de" : "en"),''),NULLIF(d.en,''),NULLIF(d.sv,''),d.other),d.food_id LIMIT ?", arguments: arguments), correctedQuery: nil)
            }
            var ids = try fullText(terms.map { Self.quoted($0) + "*" }.joined(separator: " AND "))
            try Task.checkCancellation()
            // Substrings are a fallback, not an unconditional scan of the catalog.
            if ids.count < min(20, limit), terms.allSatisfy({ $0.count >= 3 }) {
                var substringIDs: [String]
                if supportsTrigrams {
                    var arguments: StatementArguments = [terms.map(Self.quoted).joined(separator: " AND ")]
                    arguments += filterArguments; arguments += [limit]
                    substringIDs = try String.fetchAll(db, sql: "SELECT d.food_id FROM search_trigrams JOIN search_documents d ON d.id=search_trigrams.rowid WHERE search_trigrams MATCH ?\(suffix) ORDER BY rank LIMIT ?", arguments: arguments)
                } else {
                    var arguments = StatementArguments(terms.map { "%" + $0 + "%" })
                    arguments += filterArguments; arguments += [limit]
                    let conditions = Array(repeating: "d.search_text LIKE ?", count: terms.count).joined(separator: " AND ")
                    substringIDs = try String.fetchAll(db, sql: "SELECT d.food_id FROM search_documents d WHERE \(conditions)\(suffix) ORDER BY d.food_id LIMIT ?", arguments: arguments)
                }
                var seen = Set(ids)
                ids += substringIDs.filter { seen.insert($0).inserted }
            }
            if ids.count < min(20, limit), terms.count > 1 {
                var seen = Set(ids)
                ids += try fullText(terms.map { Self.quoted($0) + "*" }.joined(separator: " OR ")).filter { seen.insert($0).inserted }
            }
            if ids.isEmpty, allowTypos, terms.count == 1, let term = terms.first, (4...12).contains(term.count) {
                let variants = Self.spellingVariants(term)
                let placeholders = Array(repeating: "?", count: variants.count).joined(separator: ",")
                let suggestions = try String.fetchAll(db, sql: "SELECT term FROM search_vocabulary WHERE term IN (\(placeholders)) ORDER BY doc DESC,term LIMIT 5", arguments: StatementArguments(variants))
                for suggestion in suggestions {
                    try Task.checkCancellation()
                    let corrected = try fullText(Self.quoted(suggestion))
                    if !corrected.isEmpty { return FoodSearchCandidates(ids: corrected, correctedQuery: suggestion) }
                }
            }
            return FoodSearchCandidates(ids: Array(ids.prefix(limit)), correctedQuery: nil)
        }
    }

    private static func spellingVariants(_ word: String) -> [String] {
        let letters = Array(word)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzåäöüéß")
        var result = Set<String>()
        for index in letters.indices {
            var deleted = letters; deleted.remove(at: index); result.insert(String(deleted))
            if index + 1 < letters.count {
                var transposed = letters; transposed.swapAt(index, index + 1); result.insert(String(transposed))
            }
            for letter in alphabet {
                var replaced = letters; replaced[index] = letter; result.insert(String(replaced))
            }
        }
        for index in 0...letters.count {
            for letter in alphabet {
                var inserted = letters; inserted.insert(letter, at: index); result.insert(String(inserted))
            }
        }
        result.remove(word)
        return result.sorted()
    }
}
