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

import SwiftUI
import UIKit

/// Reports from the view's own scene so errors also appear above presented sheets.
struct ErrorBannerReporter: UIViewRepresentable {
    let message: String?

    func makeUIView(context: Context) -> ReporterView { ReporterView() }
    func updateUIView(_ view: ReporterView, context: Context) {
        view.message = message
        view.reportIfNeeded()
    }

    final class ReporterView: UIView {
        var message: String?
        private var reportedMessage: String?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportIfNeeded()
        }

        func reportIfNeeded() {
            guard let message else { reportedMessage = nil; return }
            guard message != reportedMessage, let scene = window?.windowScene else { return }
            reportedMessage = message
            Task { @MainActor in ErrorBannerPresenter.show(message, in: scene) }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Color.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.red.opacity(0.6)))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .shadow(radius: 6, y: 3)
        .accessibilityAction(.escape, dismiss)
    }
}

/// Only the banner receives touches; the rest of the app remains interactive.
private final class ErrorBannerWindow: UIWindow {
    weak var bannerView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let bannerView,
              bannerView.bounds.contains(bannerView.convert(point, from: self)) else { return nil }
        return super.hitTest(point, with: event)
    }
}

@MainActor
private enum ErrorBannerPresenter {
    private struct Presentation {
        let window: UIWindow
        let message: String
        let shownAt: Date
        let dismissal: Task<Void, Never>
    }
    private static var presentations: [String: Presentation] = [:]

    private static func dismiss(_ key: String) {
        guard let presentation = presentations.removeValue(forKey: key) else { return }
        presentation.dismissal.cancel()
        presentation.window.isHidden = true
    }

    static func show(_ message: String, in scene: UIWindowScene) {
        let key = scene.session.persistentIdentifier
        if let current = presentations[key], current.message == message,
           Date().timeIntervalSince(current.shownAt) < 0.5 { return }
        presentations[key]?.dismissal.cancel()
        presentations[key]?.window.isHidden = true
        let window = ErrorBannerWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let container = UIViewController()
        container.view.backgroundColor = .clear
        let controller = UIHostingController(rootView: ErrorBanner(message: message) {
            dismiss(key)
        })
        controller.sizingOptions = .intrinsicContentSize
        controller.view.backgroundColor = .clear
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            controller.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor, constant: 16),
            controller.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor, constant: -16)
        ])
        controller.didMove(toParent: container)
        window.bannerView = controller.view
        window.rootViewController = container
        // Showing without making this window key preserves the current keyboard focus.
        window.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
        let dismissal = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            dismiss(key)
        }
        presentations[key] = Presentation(window: window, message: message, shownAt: Date(), dismissal: dismissal)
    }
}

extension View {
    func temporaryErrorBanner(_ message: String?) -> some View {
        background(ErrorBannerReporter(message: message).frame(width: 0, height: 0))
    }
}
