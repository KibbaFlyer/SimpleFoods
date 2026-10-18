import XCTest
@testable import MealTrackerHealth

private actor FakeState {
    var requests=0;var reads=0
    var active:EnergySample?,resting:EnergySample?
    var fails=false;var saved:[NutritionEntry]=[]
    init(active:EnergySample?=nil,resting:EnergySample?=nil) { self.active=active;self.resting=resting }
    func authorize() { requests += 1 }
    func read(_ kind:EnergyKind) throws -> EnergySample? { reads += 1;if fails { throw EnergyError.unavailable };return kind == .active ? active:resting }
    func fail() { fails=true }
    func save(_ entry:NutritionEntry) { saved.append(entry) }
}
private struct FakeGateway:HealthEnergyGateway {
    let state:FakeState
    var availability:HealthAvailability { .available }
    func requestReadAuthorization() async throws { await state.authorize() }
    func cumulativeEnergy(_ kind:EnergyKind,window:EnergyWindow) async throws -> EnergySample? { try await state.read(kind) }
    func saveNutrition(_ entry:NutritionEntry) async throws { await state.save(entry) }
}
@MainActor final class EnergyTests:XCTestCase {
    private let zone=TimeZone(identifier:"Europe/Stockholm")!
    private func date(_ text:String) -> Date { ISO8601DateFormatter().date(from:text)! }
    func testExplicitConnectionOnly() async throws {
        let state=FakeState();let now=date("2026-10-11T10:00:00Z");let reader=EnergyReader(gateway:FakeGateway(state:state),clock:{now})
        await reader.refresh(day:now,timeZone:zone);XCTAssertEqual(reader.active,.notRequested)
        let requests=await state.requests;let reads=await state.reads;XCTAssertEqual(requests,0);XCTAssertEqual(reads,0)
        try await reader.connect();let after=await state.requests;XCTAssertEqual(after,1)
    }
    func testNutritionWriteRequiresConnectionAndForwardsValidEntry() async throws {
        let state=FakeState();let now=date("2026-10-11T10:00:00Z");let reader=EnergyReader(gateway:FakeGateway(state:state),clock:{now})
        let entry=try NutritionEntry(id:UUID(),revision:1,date:now,foodName:"Lunch",energyKcal:500,proteinGrams:20,carbohydrateGrams:50,fatGrams:15)
        do { try await reader.saveNutrition(entry);XCTFail() } catch { XCTAssertEqual(error as? EnergyError,.authorizationRequestFailed) }
        try await reader.connect();try await reader.saveNutrition(entry)
        let saved=await state.saved;XCTAssertEqual(saved,[entry])
    }
    func testNilIsNotZeroOrDenial() async throws {
        let state=FakeState(active:nil,resting:try EnergySample(kcal:0));let now=date("2026-10-11T10:00:00Z");let reader=EnergyReader(gateway:FakeGateway(state:state),clock:{now})
        try await reader.connect();await reader.refresh(day:now,timeZone:zone)
        XCTAssertEqual(reader.active,.noReadableData);if case .value(let value)=reader.resting { XCTAssertEqual(value.kcal,0) } else { XCTFail() };XCTAssertNil(reader.total)
    }
    func testTodaySoFarAndMatchingTotal() async throws {
        let state=FakeState(active:try EnergySample(kcal:120),resting:try EnergySample(kcal:300));let now=date("2026-10-11T10:00:00Z");let reader=EnergyReader(gateway:FakeGateway(state:state),clock:{now})
        try await reader.connect();await reader.refresh(day:now,timeZone:zone)
        XCTAssertEqual(reader.total?.kcal,420);XCTAssertEqual(reader.total?.window.end,now);XCTAssertEqual(reader.total?.window.isSoFar,true);XCTAssertEqual(reader.total?.coverage,.unknown)
    }
    func testDifferentCoverageDoesNotProduceTotal() async throws {
        let now=date("2026-10-11T10:00:00Z");let state=FakeState(active:try EnergySample(kcal:10,coverage:.complete),resting:try EnergySample(kcal:20,coverage:.truncated(start:now.addingTimeInterval(-10))))
        let reader=EnergyReader(gateway:FakeGateway(state:state),clock:{now});try await reader.connect();await reader.refresh(day:now,timeZone:zone);XCTAssertNil(reader.total)
    }
    func testErrorKeepsStaleOriginalTimestamp() async throws {
        let now=date("2026-10-11T10:00:00Z");let state=FakeState(active:try EnergySample(kcal:10),resting:try EnergySample(kcal:20));let reader=EnergyReader(gateway:FakeGateway(state:state),clock:{now})
        try await reader.connect();await reader.refresh(day:now,timeZone:zone);await state.fail();await reader.refresh(day:now,timeZone:zone)
        if case .stale(let previous,let error)=reader.active { XCTAssertEqual(previous.fetchedAt,now);XCTAssertEqual(previous.kcal,10);XCTAssertEqual(error,"readFailed") } else { XCTFail() };XCTAssertNil(reader.total)
    }
    func testDifferentDayFailureDoesNotReusePreviousDay() async throws {
        let now=date("2026-10-11T10:00:00Z")
        let state=FakeState(active:try EnergySample(kcal:10),resting:try EnergySample(kcal:20))
        let reader=EnergyReader(gateway:FakeGateway(state:state),clock:{now})
        try await reader.connect();await reader.refresh(day:now,timeZone:zone)
        await state.fail();await reader.refresh(day:date("2026-10-10T10:00:00Z"),timeZone:zone)
        XCTAssertEqual(reader.active,.error("readFailed"));XCTAssertEqual(reader.resting,.error("readFailed"));XCTAssertNil(reader.total)
    }
    func testDSTDaysUseCalendarNot86400() throws {
        let now=date("2027-01-01T12:00:00Z")
        let spring=try EnergyWindow.day(containing:date("2026-03-29T12:00:00Z"),timeZone:zone,now:now)
        let autumn=try EnergyWindow.day(containing:date("2026-10-25T12:00:00Z"),timeZone:zone,now:now)
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start),23*3600);XCTAssertEqual(autumn.end.timeIntervalSince(autumn.start),25*3600);XCTAssertFalse(autumn.isSoFar)
    }
    func testNegativeNonfiniteAndFutureWindowRejected() throws {
        XCTAssertThrowsError(try EnergySample(kcal:-1));XCTAssertThrowsError(try EnergySample(kcal:.nan));XCTAssertThrowsError(try EnergySample(kcal:.infinity))
        XCTAssertThrowsError(try EnergyWindow.day(containing:date("2026-10-12T10:00:00Z"),timeZone:zone,now:date("2026-10-11T10:00:00Z")))
    }
    func testCancellationBeforeInstallDoesNotStartQuery() async {
        let operation=QueryOperation<Int>();operation.cancel();var started=false
        do { let _:Int=try await withCheckedThrowingContinuation { continuation in
            guard operation.install(continuation) else { return };operation.start(execute:{started=true},stop:{})
        };XCTFail() } catch is CancellationError { } catch { XCTFail() }
        XCTAssertFalse(started)
    }
    func testCallbackThenCancelResumesAndStopsExactlyOnce() async throws {
        let operation=QueryOperation<Int>();var stops=0
        let result:Int=try await withCheckedThrowingContinuation { continuation in
            _=operation.install(continuation)
            operation.start(execute:{operation.finish(.success(42));operation.cancel()},stop:{stops += 1})
        }
        XCTAssertEqual(result,42);XCTAssertEqual(stops,1)
    }
    func testCancelDuringExecuteStopsAfterQueryStarted() async {
        let operation=QueryOperation<Int>();var stops=0
        do { let _:Int=try await withCheckedThrowingContinuation { continuation in
            _=operation.install(continuation)
            operation.start(execute:{operation.cancel()},stop:{stops += 1})
            operation.finish(.success(42))
        };XCTFail() } catch is CancellationError { } catch { XCTFail() }
        XCTAssertEqual(stops,1)
    }

}
