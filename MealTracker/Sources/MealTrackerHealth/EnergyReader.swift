import Foundation

public enum HealthAvailability: String, Sendable { case available, unavailable }
public enum EnergyKind: String, CaseIterable, Sendable { case active, resting }
public enum EnergyCoverage: Equatable, Sendable { case unknown, complete, truncated(start: Date) }
public struct EnergyWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let timeZoneID: String
    public let isSoFar: Bool
    public init(start: Date, end: Date, timeZoneID: String, isSoFar: Bool) throws {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, start < end, TimeZone(identifier:timeZoneID) != nil else { throw EnergyError.invalidWindow }
        self.start=start; self.end=end; self.timeZoneID=timeZoneID; self.isSoFar=isSoFar
    }
    public static func day(containing date: Date, timeZone: TimeZone, now: Date) throws -> EnergyWindow {
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=timeZone
        guard date.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite, let interval=calendar.dateInterval(of:.day,for:date), interval.start < now else { throw EnergyError.invalidWindow }
        let today=calendar.isDate(date,inSameDayAs:now)
        return try EnergyWindow(start:interval.start,end:today ? now : interval.end,timeZoneID:timeZone.identifier,isSoFar:today)
    }
}
public struct EnergySample: Equatable, Sendable {
    public let kcal: Double
    public let coverage: EnergyCoverage
    public init(kcal: Double, coverage: EnergyCoverage = .unknown) throws {
        guard kcal.isFinite, kcal >= 0 else { throw EnergyError.invalidValue }; self.kcal=kcal;self.coverage=coverage
    }
}
public struct EnergyValue: Equatable, Sendable {
    public let kcal: Double
    public let window: EnergyWindow
    public let fetchedAt: Date
    public let coverage: EnergyCoverage
    public init(kcal: Double, window: EnergyWindow, fetchedAt: Date, coverage: EnergyCoverage) throws {
        guard kcal.isFinite,kcal >= 0,fetchedAt.timeIntervalSince1970.isFinite else { throw EnergyError.invalidValue }
        self.kcal=kcal;self.window=window;self.fetchedAt=fetchedAt;self.coverage=coverage
    }
}
public enum EnergyReadState: Equatable, Sendable {
    case notRequested, loading, noReadableData, value(EnergyValue), error(String), stale(EnergyValue,error:String)
    public var previousValue: EnergyValue? { switch self { case .value(let v),.stale(let v,_):return v;default:return nil } }
}
public enum EnergyError: Error, Equatable { case unavailable, invalidWindow, invalidValue, authorizationRequestFailed }
public struct NutritionEntry: Equatable, Sendable {
    public let id: UUID
    public let revision: Int64
    public let date: Date
    public let foodName: String
    public let energyKcal: Double
    public let proteinGrams: Double
    public let carbohydrateGrams: Double
    public let fatGrams: Double

    public init(id: UUID, revision: Int64, date: Date, foodName: String, energyKcal: Double, proteinGrams: Double, carbohydrateGrams: Double, fatGrams: Double) throws {
        let values = [energyKcal, proteinGrams, carbohydrateGrams, fatGrams]
        guard revision >= 0, date.timeIntervalSince1970.isFinite, !foodName.isEmpty,
              values.allSatisfy({ $0.isFinite && $0 >= 0 }), values.contains(where: { $0 > 0 }) else {
            throw EnergyError.invalidValue
        }
        self.id = id
        self.revision = revision
        self.date = date
        self.foodName = foodName
        self.energyKcal = energyKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
    }
}
public protocol HealthEnergyGateway: Sendable {
    var availability: HealthAvailability { get }
    /// Called only by the user's explicit Connect action. Completion is not proof of read access.
    func requestReadAuthorization() async throws
    func cumulativeEnergy(_ kind: EnergyKind, window: EnergyWindow) async throws -> EnergySample?
    func saveNutrition(_ entry: NutritionEntry) async throws
}

/// In-memory read model. No Health data is written to disk or sent to the network.
@MainActor public final class EnergyReader {
    private let gateway: any HealthEnergyGateway
    private let clock: @Sendable () -> Date
    private var requested=false
    private var generation: UInt64=0
    public private(set) var active: EnergyReadState = .notRequested
    public var availability: HealthAvailability { gateway.availability }
    public init(gateway: any HealthEnergyGateway, clock: @escaping @Sendable () -> Date = {Date()}) { self.gateway=gateway;self.clock=clock }
    public func connect() async throws {
        guard availability == .available else { active = .error("unavailable");throw EnergyError.unavailable }
        do { try await gateway.requestReadAuthorization();try Task.checkCancellation();requested=true }
        catch { active = .error("authorizationRequestFailed");throw error }
    }
    public func saveNutrition(_ entry: NutritionEntry) async throws {
        guard requested else { throw EnergyError.authorizationRequestFailed }
        try await gateway.saveNutrition(entry)
    }
    public func refresh(day: Date, timeZone: TimeZone) async {
        guard requested else { return }
        generation &+= 1; let current=generation
        let priorActive=active.previousValue
        let window: EnergyWindow
        do { window=try .day(containing:day,timeZone:timeZone,now:clock()) }
        catch { active = .error("invalidWindow");return }
        // Retain stale values only for the same calendar day and time zone.
        let previousActive = priorActive.flatMap { $0.window.start == window.start && $0.window.timeZoneID == window.timeZoneID ? $0 : nil }
        active = .loading
        let result=await read(.active,window:window,previous:previousActive)
        guard current == generation else { return }
        active=result
    }
    private func read(_ kind: EnergyKind,window: EnergyWindow,previous: EnergyValue?) async -> EnergyReadState {
        do {
            let value=try await gateway.cumulativeEnergy(kind,window:window);try Task.checkCancellation()
            guard let value else { return .noReadableData }
            return .value(try EnergyValue(kcal:value.kcal,window:window,fetchedAt:clock(),coverage:value.coverage))
        } catch is CancellationError { return Self.failure(previous,error:"cancelled") }
        catch { return Self.failure(previous,error:"readFailed") }
    }
    private static func failure(_ previous: EnergyValue?,error:String) -> EnergyReadState { previous.map { .stale($0,error:error) } ?? .error(error) }
}
