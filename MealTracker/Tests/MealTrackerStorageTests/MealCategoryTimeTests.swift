import Foundation
import Testing
import MealTrackerDiary

struct MealCategoryTimeTests {
    @Test(arguments: [
        ("2026-01-01T00:00:00Z", "UTC", MealCategory.breakfast),
        ("2026-01-01T10:59:59Z", "UTC", .breakfast),
        ("2026-01-01T11:00:00Z", "UTC", .lunch),
        ("2026-01-01T16:59:59Z", "UTC", .lunch),
        ("2026-01-01T17:00:00Z", "UTC", .dinner),
        ("2026-01-01T23:59:59Z", "UTC", .dinner),
        ("2026-01-01T10:00:00Z", "Europe/Stockholm", .lunch),
        ("2026-07-01T15:00:00Z", "Europe/Stockholm", .dinner)
    ])
    func categoryUsesLocalTime(timestamp: String, zone: String, expected: MealCategory) throws {
        let date = try #require(ISO8601DateFormatter().date(from: timestamp))
        #expect(try DiaryTime.category(date, zoneID: zone) == expected)
    }
}
