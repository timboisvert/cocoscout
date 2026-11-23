import LocalAuthentication
import SwiftUI

/// "Sign in with Face ID next time" (screen 10 on
/// https://claude.ai/artifact/X1sA6FoXBSPJseGxFzdExn): after someone signs
/// in here with a code or a password, a sheet rises over their first page
/// offering a passkey, so next time Face ID signs them in. Turn on Face ID
/// opens iOS's own sheet (PasskeyMaker); Not now isn't asked again for that
/// account on this iPhone, and the Account page's Add a passkey is always
/// there. Coco peeks over it, as over the email step.
@MainActor
enum PasskeyOffer {
    private static let declinedKey = "Passkeys.declined"
    private static let madeKey = "Passkeys.made"

    /// After a code or password sign-in, unless this account already said
    /// Not now, or already made one, on this iPhone.
    static func shouldOffer(after account: KnownAccount?) -> Bool {
        guard let account, ["code", "password"].contains(account.method) else { return false }
        let email = account.email.lowercased()
        return !list(declinedKey).contains(email) && !list(madeKey).contains(email)
    }

    static func remember(_ email: String, made: Bool) {
        let key = made ? madeKey : declinedKey
        UserDefaults.standard.set(Array(Set(list(key) + [email.lowercased()])), forKey: key)
    }

    private static func list(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// What unlocks a passkey on this iPhone, in words and as a symbol.
    static var unlock: (name: String, symbol: String, body: String) {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return ("Face ID", "faceid", "nobody else's face works")
        case .touchID: return ("Touch ID", "touchid", "nobody else's fingerprint works")
        default: return ("your passcode", "key.fill", "nobody without your passcode can use it")
        }
    }

    static func controller(for account: KnownAccount, onFinish: @escaping () -> Void) -> UIViewController {
        let screen = UIHostingController(rootView: PasskeyOfferSheet(account: account, onFinish: onFinish))
        screen.modalPresentationStyle = .overFullScreen
        screen.modalTransitionStyle = .crossDissolve
        screen.view.backgroundColor = .clear
        return screen
    }
}

private struct PasskeyOfferSheet: View {
    let account: KnownAccount
    let onFinish: () -> Void

    @State private var shown = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let unlock = PasskeyOffer.unlock
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.4 : 0).ignoresSafeArea()
                .onTapGesture { notNow() }
                .accessibilityHidden(true)
            if shown {
                VStack(spacing: -84) {
                    // The peek: 220 points wide, 150 showing over the sheet.
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(unlock.name == "your passcode" ? "Sign in with a passkey next time" : "Sign in with \(unlock.name) next time")
                            .font(Font(AppConfig.coustard(26)))
                            .foregroundStyle(Tailwind.gray900)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(account.method == "code" ? "No code to wait for." : "No password to type.") \(unlock.name == "your passcode" ? "Your passcode" : unlock.name) signs you in on this iPhone, and \(unlock.body).")
                            .font(.system(size: 16))
                            .foregroundStyle(Tailwind.gray500)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                        if let error {
                            Text(error)
                                .font(.system(size: 15))
                                .foregroundStyle(Tailwind.pink700)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Tailwind.pink50))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tailwind.pink200, lineWidth: 1))
                                .padding(.top, 16)
                        }
                        Spacer(minLength: 28)
                        Button(action: turnOn) {
                            HStack(spacing: 10) {
                                if busy {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: unlock.symbol).font(.system(size: 18, weight: .semibold)).accessibilityHidden(true)
                                }
                                Text(unlock.name == "your passcode" ? "Make a passkey" : "Turn on \(unlock.name)").font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Tailwind.pink500))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        Button("Not now", action: notNow)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tailwind.pink600)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(.top, 6)
                            .disabled(busy)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 374, alignment: .top)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(.white).ignoresSafeArea(edges: .bottom))
                }
                .transition(.move(edge: .bottom))
            }
        }
        .tint(Tailwind.pink500)
        .onAppear { withAnimation(.spring(duration: 0.4)) { shown = true } }
    }

    private func turnOn() {
        guard !busy else { return }
        busy = true
        error = nil
        PasskeyMaker.shared.make { outcome in
            busy = false
            switch outcome {
            case .added, .exists:
                PasskeyOffer.remember(account.email, made: true)
                // Next time Welcome back's Continue opens the passkey.
                KnownAccount(email: account.email, firstName: account.firstName, method: "passkey").save()
                close()
            case .canceled:
                break
            case .failed(let message):
                error = message
            }
        }
    }

    private func notNow() {
        guard !busy else { return }
        PasskeyOffer.remember(account.email, made: false)
        close()
    }

    private func close() {
        withAnimation(.spring(duration: 0.3)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
    }
}
