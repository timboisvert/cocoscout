import SwiftUI
import UIKit

/// Apple's awareness moment for Tap to Pay on iPhone (Apple 3.1, 3.2, 6.2):
/// a full-screen page shown once to each person who can sell with it, built
/// from Apple's Hero banner (its photograph, in TapToPayHero) and Apple's
/// own words (Marketing Guide, US, Sept 2026). "Get started" opens Tap to
/// Pay on iPhone's page; "Terms apply." opens Apple's full disclaimer.
@MainActor
enum TapToPaySplash {
    private static func shownKey(_ info: TapToPayInfo) -> String { "TapToPay.splashShown.\(info.userKey)" }

    /// Once per person on this iPhone, over whatever's showing.
    static func showIfNeeded(_ info: TapToPayInfo, over page: UIViewController, open: @escaping (String) -> Void) {
        let key = shownKey(info)
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        var screen: UIViewController?
        let view = SplashView(
            getStarted: { screen?.dismiss(animated: true) { open(info.settingsPath) } },
            notNow: { screen?.dismiss(animated: true) }
        )
        let hosting = UIHostingController(rootView: view)
        hosting.modalPresentationStyle = .fullScreen
        screen = hosting
        page.present(hosting, animated: true)
    }

    static let fullDisclaimer = """
    Tap to Pay on iPhone requires a supported payment app and the latest version of iOS. Update to the latest version by going to Settings > General > Software Update. Some contactless cards may not be accepted by your payment app. Transaction limits may apply. Tap to Pay on iPhone is not available in all markets. For Tap to Pay on iPhone countries and regions, see https://developer.apple.com/tap-to-pay/regions/.

    Apple Pay is a service provided by Apple Payments Services LLC, a subsidiary of Apple Inc. Neither Apple Inc. nor Apple Payments Services LLC is a bank. Any card used in Apple Pay is offered by the card issuer.

    The Contactless Indicator mark, consisting of four graduating arcs, is a trademark owned by and used with permission of EMVCo, LLC.
    """

    private struct SplashView: View {
        let getStarted: () -> Void
        let notNow: () -> Void
        @State private var showingTerms = false

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        Button(action: notNow) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Tailwind.gray700)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Not now")
                    }
                    Text("Tap to Pay\non iPhone")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color.black)
                        .fixedSize(horizontal: false, vertical: true)
                    Image("TapToPayHero")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    Text("Accept physical debit and credit cards as well as Apple Pay and other digital wallets. Right on your iPhone.")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.black)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        Button("Get started with Tap to Pay on iPhone", action: getStarted)
                            .buttonStyle(SharedButtonStyle(variant: .primary, size: .large, fullWidth: true))
                        Button("Not now", action: notNow)
                            .buttonStyle(SharedButtonStyle(variant: .secondary, size: .large, fullWidth: true))
                    }
                    Button("Terms apply.") { showingTerms = true }
                        .font(.system(size: 15))
                        .foregroundStyle(Tailwind.gray700)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color.white.ignoresSafeArea())
            .sheet(isPresented: $showingTerms) {
                ScrollView {
                    Text(TapToPaySplash.fullDisclaimer)
                        .font(.system(size: 14))
                        .foregroundStyle(Tailwind.gray700)
                        .padding(24)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}
