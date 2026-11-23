import AuthenticationServices
import SwiftUI

/// The app's own sign-in screens (sign-in plan phase 3), worded like the
/// website's /signin steps: the email address first, with Continue with Apple
/// and Continue with Google below an "or" (Tim, 2026-11-22: "email's the more
/// important sign in"), then Password, Code, Create your account, Connect
/// once, and Add your email address, whichever the server names next.
struct SignInScreen: View {
    @ObservedObject var model: SignInModel
    @FocusState private var focused: Field?

    enum Field { case email, password, code, firstName, lastName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("CocoScout")
                    .font(Font(AppConfig.coustard(30)))
                    .foregroundStyle(Tailwind.pink500)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(Font(AppConfig.coustard(26)))
                        .foregroundStyle(Tailwind.gray900)
                    Text(lede)
                        .font(.system(size: 16))
                        .foregroundStyle(Tailwind.gray500)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = model.error {
                    Banner(text: error, error: true)
                } else if let notice = model.notice {
                    Banner(text: notice, error: false)
                }

                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .tint(Tailwind.pink500)
        .foregroundStyle(Tailwind.gray900)
        .background(Color.white)
        .disabled(model.busy)
        .overlay {
            if model.busy {
                ProgressView().controlSize(.large).tint(Tailwind.pink500)
            }
        }
        .onAppear {
            model.prepareApple()
            SavedPasswords.shared.offer { email, password in model.signIn(email: email, password: password) }
        }
    }

    // MARK: Each screen

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .start: start
        case .password, .connect: passwordStep
        case .code: codeStep
        case .create: createStep
        case .addEmail: addEmailStep
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField(label: "Email address") {
                TextField("", text: $model.email, prompt: Text(verbatim: "you@example.com").foregroundStyle(Tailwind.gray500))
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($focused, equals: .email)
                    .onSubmit { model.continueWithEmail() }
            }
            Button("Continue") { model.continueWithEmail() }
                .buttonStyle(SharedButtonStyle(variant: .primary, size: .large, fullWidth: true))

            HStack(spacing: 12) {
                Rectangle().fill(Tailwind.gray200).frame(height: 1)
                Text("or").font(.system(size: 14)).foregroundStyle(Tailwind.gray500)
                Rectangle().fill(Tailwind.gray200).frame(height: 1)
            }
            .padding(.vertical, 4)
            .accessibilityHidden(true)

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = model.appleNonceDigest
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
                        return model.appleFailed()
                    }
                    model.finishApple(token: token,
                                      authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                                      firstName: credential.fullName?.givenName,
                                      lastName: credential.fullName?.familyName)
                case .failure:
                    model.appleFailed()
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(model.appleNonce == nil)

            Button { model.continueWithGoogle() } label: {
                HStack(spacing: 10) {
                    Image("GoogleG").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                    Text("Continue with Google").font(.system(size: 17, weight: .medium))
                }
                .foregroundStyle(Tailwind.gray900)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tailwind.gray300, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountRow(email: model.email) { model.startOver() }
            // The address rides along unseen, so AutoFill files the password under it.
            TextField("", text: .constant(model.email))
                .textContentType(.username)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            LabeledField(label: "Password") {
                SecureField("", text: $model.password, prompt: Text("Your password").foregroundStyle(Tailwind.gray500))
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focused, equals: .password)
                    .onSubmit { model.submitPassword() }
            }
            Button(model.screen == .connect ? "Connect and sign in" : "Sign in") { model.submitPassword() }
                .buttonStyle(SharedButtonStyle(variant: .primary, size: .large, fullWidth: true))
            if !model.superadmin {
                LinkButton(text: "Email me a code instead") { model.sendCode() }
            }
        }
        .onAppear { focused = .password }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountRow(email: model.email) { model.startOver() }
            LabeledField(label: "6-digit code") {
                TextField("", text: $model.code, prompt: Text("123456").foregroundStyle(Tailwind.gray500))
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .focused($focused, equals: .code)
                    .onChange(of: model.code) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { model.code = digits }
                        if digits.count == 6 { model.submitCode() }
                    }
            }
            Button("Continue") { model.submitCode() }
                .buttonStyle(SharedButtonStyle(variant: .primary, size: .large, fullWidth: true))
            LinkButton(text: "Send a new code") { model.sendCode() }
        }
        .onAppear { focused = .code }
    }

    private var createStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountRow(email: model.email) { model.startOver() }
            LabeledField(label: "First name") {
                TextField("", text: $model.firstName)
                    .textContentType(.givenName)
                    .submitLabel(.next)
                    .focused($focused, equals: .firstName)
                    .onSubmit { focused = .lastName }
            }
            LabeledField(label: "Last name") {
                TextField("", text: $model.lastName)
                    .textContentType(.familyName)
                    .submitLabel(.done)
                    .focused($focused, equals: .lastName)
                    .onSubmit { model.createAccount() }
            }
            Button("Create account") { model.createAccount() }
                .buttonStyle(SharedButtonStyle(variant: .primary, size: .large, fullWidth: true))
            Text("Free to join · No card needed")
                .font(.system(size: 14))
                .foregroundStyle(Tailwind.gray500)
                .frame(maxWidth: .infinity)
        }
        .onAppear { focused = model.firstName.isEmpty ? .firstName : nil }
    }

    private var addEmailStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField(label: "Email address") {
                TextField("", text: $model.email, prompt: Text(verbatim: "you@example.com").foregroundStyle(Tailwind.gray500))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($focused, equals: .email)
                    .onSubmit { model.addEmail() }
            }
            Button("Continue") { model.addEmail() }
                .buttonStyle(SharedButtonStyle(variant: .primary, size: .large, fullWidth: true))
            LinkButton(text: "Start over") { model.startOver() }
        }
        .onAppear { focused = .email }
    }

    // MARK: Words

    private var title: String {
        let name = model.provider ?? "Apple"
        return switch model.screen {
        case .start: "Sign in or create an account"
        case .password: "Enter your password"
        case .code: "Enter your code"
        case .create: "Create your account"
        case .connect: "Connect your \(name) account"
        case .addEmail: "Add your email address"
        }
    }

    private var lede: String {
        let name = model.provider ?? "Apple"
        switch model.screen {
        case .start:
            return "Your calendar, cast messages, contracts and pay, and the door scanner when you're working it. Enter your email address to sign in or to create your account."
        case .password:
            return "Your calendar, cast messages, contracts, and pay are waiting in there."
        case .code:
            return "We sent a 6-digit code to \(model.email). It works for \(model.codeLifetime)."
        case .create:
            let base = "Enter your name the way organizations should see it on cast lists, messages, and contracts."
            return model.provider == nil ? base : "\(base) \(name) signs you in from now on."
        case .connect:
            return "You already have a CocoScout account at this address. Enter its password once, and \(name) signs you in from then on."
        case .addEmail:
            return "\(name) kept your address private. Enter the one organizations know you by, so your invitations, contracts, and tickets find you. We'll send it a code."
        }
    }
}

// MARK: Pieces

private struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Tailwind.gray700)
            field
                .font(.system(size: 17))
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tailwind.gray300, lineWidth: 1))
        }
    }
}

/// The address the step is for, with Change to go back (shared/auth/_account_row).
private struct AccountRow: View {
    let email: String
    let change: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Account").font(.system(size: 12, weight: .medium)).foregroundStyle(Tailwind.gray500)
                Text(email).font(.system(size: 16)).foregroundStyle(Tailwind.gray900).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Change", action: change)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Tailwind.pink600)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 6).fill(Tailwind.gray50))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tailwind.gray200, lineWidth: 1))
    }
}

private struct LinkButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(text, action: action)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Tailwind.pink600)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// shared/auth/_notice: pink for something that went wrong, gray to know.
private struct Banner: View {
    let text: String
    let error: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(error ? Tailwind.pink700 : Tailwind.gray700)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 6).fill(error ? Tailwind.pink50 : Tailwind.gray50))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(error ? Tailwind.pink200 : Tailwind.gray200, lineWidth: 1))
    }
}

/// The sign-in screens over the whole app while nobody's signed in
/// (AppShell). It can't be swiped away: there's nothing behind it to use.
final class SignInViewController: UIHostingController<SignInScreen> {
    init(onSignedIn: @escaping (URL) -> Void) {
        super.init(rootView: SignInScreen(model: SignInModel(onSignedIn: onSignedIn)))
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
        view.backgroundColor = .white
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
