import Foundation
import MealTrackerCore
import MealTrackerDiary
import MealTrackerLocalization
import MealTrackerOpenFoodFacts
import MealTrackerHealth

func appError(_ error: Error, copy: AppCopy? = nil) -> String {
    let copy = copy ?? AppCopy(language: AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "sv") ?? .sv)
    if let error = error as? OFFError {
        switch error {
        case .busy: return copy.text("offBusy")
        case .invalidBarcode: return copy.text("barcodeError")
        case .notFound: return copy.text("offNotFound")
        case .rateLimited: return copy.text("offRateLimited")
        case .timeout: return copy.text("offTimeout")
        default: return copy.text("offError")
        }
    }
    if error is EnergyError { return copy.text("energyError") }
    if error is ShareImportError { return copy.text("sharedInvalid") }
    if let error = error as? DiaryError {
        switch error {
        case .staleRevision: return copy.text("conflictError")
        case .futureRequiresConfirmation: return copy.text("futureConfirm")
        case .invalidInput: return copy.text("quantityError")
        default: return copy.text("storageError")
        }
    }
    if let error = error as? CoreError {
        switch error {
        case .invalidDecimal, .invalidQuantity: return copy.text("quantityError")
        case .missingConversion, .missingYield: return copy.text("conversionError")
        default: return copy.text("nutritionError")
        }
    }
    if (error as NSError).domain == NSURLErrorDomain { return copy.text("networkError") }
    return copy.text("storageError")
}
