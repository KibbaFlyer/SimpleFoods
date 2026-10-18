#if os(iOS)
import Foundation
import HealthKit

public final class NativeHealthEnergyGateway: HealthEnergyGateway, @unchecked Sendable {
    private let store: HKHealthStore
    public var availability: HealthAvailability { HKHealthStore.isHealthDataAvailable() ? .available : .unavailable }
    public init() { store=HKHealthStore() }
    public func requestReadAuthorization() async throws {
        guard availability == .available else { throw EnergyError.unavailable }
        guard let active=HKQuantityType.quantityType(forIdentifier:.activeEnergyBurned) else {
            throw EnergyError.unavailable
        }
        let nutritionTypes = Set([
            HKQuantityTypeIdentifier.dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal
        ].compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            store.requestAuthorization(toShare:nutritionTypes,read:[active]) { success,error in
                if let error { continuation.resume(throwing:error) }
                else if !success { continuation.resume(throwing:EnergyError.authorizationRequestFailed) }
                else { continuation.resume() }
            }
        }
    }
    public func saveNutrition(_ entry: NutritionEntry) async throws {
        guard availability == .available,
              let foodType = HKObjectType.correlationType(forIdentifier: .food) else {
            throw EnergyError.unavailable
        }
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: entry.foodName,
            HKMetadataKeySyncIdentifier: "mealtracker.meal.\(entry.id.uuidString)",
            HKMetadataKeySyncVersion: NSNumber(value: entry.revision),
            HKMetadataKeyWasUserEntered: true
        ]
        let values: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), entry.energyKcal),
            (.dietaryProtein, .gram(), entry.proteinGrams),
            (.dietaryCarbohydrates, .gram(), entry.carbohydrateGrams),
            (.dietaryFatTotal, .gram(), entry.fatGrams)
        ]
        let samples = values.compactMap { identifier, unit, value -> HKQuantitySample? in
            guard value > 0, let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: entry.date, end: entry.date)
        }
        guard !samples.isEmpty else { throw EnergyError.invalidValue }
        let correlation = HKCorrelation(type: foodType, start: entry.date, end: entry.date, objects: Set(samples), metadata: metadata)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(correlation) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: EnergyError.authorizationRequestFailed) }
            }
        }
    }
    public func cumulativeEnergy(_ kind: EnergyKind, window: EnergyWindow) async throws -> EnergySample? {
        guard availability == .available else { throw EnergyError.unavailable }
        let operation=QueryOperation<EnergySample?>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard operation.install(continuation) else { return }
                let type=HKQuantityType.quantityType(forIdentifier:.activeEnergyBurned)!
                var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:window.timeZoneID)!
                var interval=DateComponents();interval.calendar=calendar;interval.timeZone=calendar.timeZone;interval.day=1
                let predicate=HKQuery.predicateForSamples(withStart:window.start,end:window.end,options:[])
                let query=HKStatisticsCollectionQuery(quantityType:type,quantitySamplePredicate:predicate,options:.cumulativeSum,anchorDate:window.start,intervalComponents:interval)
                query.initialResultsHandler = { _,collection,error in
                    if let error { operation.finish(.failure(error));return }
                    guard let quantity=collection?.statistics(for:window.start)?.sumQuantity() else { operation.finish(.success(nil));return }
                    do { operation.finish(.success(try EnergySample(kcal:quantity.doubleValue(for:.largeCalorie()),coverage:.unknown))) }
                    catch { operation.finish(.failure(error)) }
                }
                operation.start(execute: { self.store.execute(query) }, stop: { self.store.stop(query) })
            }
        },onCancel:{ operation.cancel() })
    }
}

#endif
