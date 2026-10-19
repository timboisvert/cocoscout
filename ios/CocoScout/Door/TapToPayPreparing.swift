import Combine
import SwiftUI
import UIKit

/// "Getting Tap to Pay on iPhone ready" over a sale whose reader isn't
/// connected yet (Apple 5.7), with the configuration's progress when the
/// SDK reports it (3.9.1). Shown only when getting ready takes longer than
/// a moment, and gone the moment it's ready or fails.
@MainActor
enum TapToPayPreparing {
    /// Runs `work`, showing the screen over `page` if it takes over 300 ms
    /// (Apple's checkout video asks for it past 300 ms).
    static func around<T>(_ page: UIViewController?, _ work: () async -> T) async -> T {
        let model = Model()
        let showing = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let page else { return }
            let screen = UIHostingController(rootView: PreparingView(model: model))
            screen.modalPresentationStyle = .overFullScreen
            screen.view.backgroundColor = .clear
            topmost(page).present(screen, animated: true)
            model.screen = screen
        }
        TapToPaySetup.shared.preparingListener = { state in
            if case .preparing(let progress) = state { model.progress = progress }
        }
        let result = await work()
        showing.cancel()
        TapToPaySetup.shared.preparingListener = nil
        if let screen = model.screen { await screen.dismissAsync() }
        return result
    }

    private static func topmost(_ page: UIViewController) -> UIViewController {
        var top = page
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    @MainActor
    final class Model: ObservableObject {
        @Published var progress: Float = 0
        var screen: UIViewController?
    }

    private struct PreparingView: View {
        @ObservedObject var model: Model

        var body: some View {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Getting Tap to Pay on iPhone ready")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tailwind.gray900)
                    ProgressView(value: Double(model.progress))
                        .tint(Tailwind.pink500)
                    Text(model.progress > 0 ? "\(Int(model.progress * 100))%. Tap to Pay on iPhone will be ready in a moment." : "Tap to Pay on iPhone will be ready in a moment.")
                        .font(.system(size: 14))
                        .foregroundStyle(Tailwind.gray700)
                }
                .padding(20)
                .frame(maxWidth: 340)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .padding(24)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension UIViewController {
    func dismissAsync() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            dismiss(animated: true) { done.resume() }
        }
    }
}
