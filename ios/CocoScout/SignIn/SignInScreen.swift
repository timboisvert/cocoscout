import AuthenticationServices
import SwiftUI

/// The app's sign-in screens, designed for the phone (Tim, 2026-11-22,
/// direction A on https://claude.ai/artifact/X1sA6FoXBSPJseGxFzdExn): a pink
/// landing with Coco, then the steps on a white sheet that rises over it.
///
/// Coco comes in three sizes, always rising out of the top of something
/// (Tim's rule): the hero on the first-time landing, anchored to the bottom
/// of the screen; the card on Welcome back, exactly as wide as the card; and
/// the peek over a low sheet. When a step raises the sheet near the top
/// there's no room, and she steps off.
struct SignInScreen: View {
    @ObservedObject var model: SignInModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .bottom) {
                Tailwind.pink500.ignoresSafeArea()
                if model.screen == .landing {
                    Landing(model: model, width: width)
                        .transition(.opacity)
                } else {
                    StepSheet(model: model, height: geometry.size.height)
                        .transition(.move(edge: .bottom))
                }
                if model.busy {
                    ProgressView().controlSize(.large).tint(model.screen == .landing ? .white : Tailwind.pink500)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .tint(Tailwind.pink500)
        .animation(.spring(duration: 0.4), value: model.screen)
        .onAppear { model.prepareApple() }
    }
}

// MARK: The landing

/// The launch screen, with what to do on top (Tim, 2026-11-23, for 1.4.1):
/// the wordmark, the tagline, and the hero Coco are the launch screen itself
/// (LaunchBackdropView), so opening the app never shows anything between it
/// and this. First time, Get started rises onto it. Coming back, or a link
/// waiting, the card rises and Coco settles from the hero to the card's width,
/// head and shoulders over its top edge (Coco always rises out of the top of
/// something).
private struct Landing: View {
    @ObservedObject var model: SignInModel
    let width: CGFloat
    @State private var shown = false
    @Namespace private var cocoSpace

    var body: some View {
        let hasCard = model.known != nil || model.waiting != nil
        ZStack(alignment: .bottom) {
            LaunchBackdropView(showsCoco: !hasCard).ignoresSafeArea()

            if hasCard {
                // Coco where the launch screen has her (LaunchScreen.storyboard:
                // 108% of the screen's width, her feet 40 points below its
                // bottom), until she settles behind the card.
                GeometryReader { screen in
                    if !shown {
                        let heroWidth = screen.size.width * 1.08
                        let heroHeight = heroWidth * 768 / 721
                        coco
                            .frame(width: heroWidth, height: heroHeight)
                            .matchedGeometryEffect(id: "coco", in: cocoSpace)
                            .position(x: screen.size.width / 2, y: screen.size.height + 40 - heroHeight / 2)
                            // One Coco that moves, not two that crossfade.
                            .transition(.identity)
                    }
                }
                .ignoresSafeArea()

                let cardWidth = width - 40
                let imageHeight = cardWidth * 768 / 721
                let showing = cardWidth * 260 / 350
                VStack(spacing: -(imageHeight - showing)) {
                    if shown {
                        coco
                            .frame(width: cardWidth, height: imageHeight)
                            .matchedGeometryEffect(id: "coco", in: cocoSpace)
                            .transition(.identity)
                    }
                    Group {
                        if let known = model.known {
                            WelcomeBackCard(model: model, known: known)
                        } else if let waiting = model.waiting {
                            WaitingCard(model: model, waiting: waiting)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 22).fill(.white).shadow(color: .black.opacity(0.22), radius: 18, y: 10))
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            } else {
                Button { model.getStarted() } label: {
                    Text("Get started")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Tailwind.pink600)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                        .shadow(color: .black.opacity(0.2), radius: 15, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 24)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5).delay(0.15)) { shown = true }
        }
    }

    private var coco: some View {
        Image("LaunchLogo")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Coco, the CocoScout cat")
    }
}

private struct WelcomeBackCard: View {
    @ObservedObject var model: SignInModel
    let known: KnownAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // A name saved before the server stopped sending addresses as names isn't one.
                Text(known.firstName.flatMap { $0.contains("@") ? nil : $0 }.map { "Welcome back, \($0)" } ?? "Welcome back")
                    .font(Font(AppConfig.coustard(26)))
                    .foregroundStyle(Tailwind.gray900)
                Text(verbatim: known.email)
                    .font(.system(size: 15))
                    .foregroundStyle(Tailwind.gray500)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let waiting = model.waiting {
                WaitingNote(text: waiting)
            }
            if let error = model.error { Banner(text: error, error: true) }
            PrimaryButton(title: "Continue", faceID: ["password", "passkey"].contains(known.method)) { model.continueAsKnown() }
            Button("Use a different email") { model.useDifferentEmail() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Tailwind.pink600)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

private struct WaitingCard: View {
    @ObservedObject var model: SignInModel
    let waiting: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WaitingNote(text: waiting)
            PrimaryButton(title: "Sign in to see it") { model.getStarted() }
        }
        .padding(16)
    }
}

/// What a link that came in while signed out is waiting to show.
private struct WaitingNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Tailwind.pink600)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tailwind.gray900)
                Text("Sign in and it opens right after.").font(.system(size: 14)).foregroundStyle(Tailwind.gray500)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tailwind.pink50))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tailwind.pink200, lineWidth: 1))
    }
}

// MARK: The sheet

private struct StepSheet: View {
    @ObservedObject var model: SignInModel
    let height: CGFloat

    var body: some View {
        let low = model.screen.sheetIsLow
        VStack(spacing: low ? -84 : 0) {
            if low {
                // The peek: 220 points wide, 150 showing over the sheet.
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220)
                    .accessibilityHidden(true)
            }
            sheet
                .frame(height: low ? height - 150 : height - 50)
                .frame(maxWidth: .infinity)
                .background(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(.white).ignoresSafeArea(edges: .bottom))
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var sheet: some View {
        switch model.screen {
        case .email: EmailStep(model: model)
        case .addEmail: AddEmailStep(model: model)
        case .password, .connect: PasswordStep(model: model)
        case .code: CodeStep(model: model)
        case .create: NameStep(model: model)
        case .landing: EmptyView()
        }
    }
}

private struct EmailStep: View {
    @ObservedObject var model: SignInModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    CircleButton(systemImage: "xmark", label: "Close") { model.closeSheet() }
                }
                StepTitle(title: "What's your email?",
                          lede: "Use the address your organizations know you by. We'll sign you in, or set you up if you're new.")
                Notices(model: model)
                Field(text: $model.email, prompt: "you@example.com", focused: $focused)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit { model.continueWithEmail() }
                    .accessibilityLabel("Email address")
                    .padding(.top, 22)
                PrimaryButton(title: "Continue") { model.continueWithEmail() }
                    .padding(.top, 14)
                OrRule().padding(.vertical, 22)
                VStack(spacing: 12) {
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
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(model.appleNonce == nil)

                    Button { model.continueWithGoogle() } label: {
                        HStack(spacing: 10) {
                            Image("GoogleG").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                            Text("Continue with Google").font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(Tailwind.gray900)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tailwind.gray300, lineWidth: 1.5))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                Terms().padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct AddEmailStep: View {
    @ObservedObject var model: SignInModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let name = model.provider ?? "Apple"
                StepTitle(title: "Add your email address",
                          lede: "\(name) kept your address private. Enter the one organizations know you by, so your invitations, contracts, and tickets find you. We'll send it a code.")
                    .padding(.top, 24)
                Notices(model: model)
                Field(text: $model.email, prompt: "you@example.com", focused: $focused)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit { model.addEmail() }
                    .accessibilityLabel("Email address")
                    .padding(.top, 22)
                PrimaryButton(title: "Continue") { model.addEmail() }
                    .padding(.top, 14)
                LinkButton(title: "Start over") { model.startOver() }
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
        .onAppear { focused = true }
    }
}

private struct PasswordStep: View {
    @ObservedObject var model: SignInModel
    @FocusState private var focused: Bool
    @State private var showing = false

    var body: some View {
        let connecting = model.screen == .connect
        let name = model.provider ?? "Apple"
        PinnedStep(model: model, button: connecting ? "Connect and sign in" : "Sign in", action: model.submitPassword,
                   footnote: connecting ? nil : "iOS offers to save it, so Face ID can sign you in next time.") {
            StepTitle(title: connecting ? "Connect your \(name) account" : "Enter your password",
                      lede: connecting ? "You already have a CocoScout account at this address. Enter its password once, and \(name) signs you in from then on." : nil)
            AccountChip(email: model.email) { model.startOver() }
                .padding(.top, 16)
            Notices(model: model)
            // The address rides along unseen, so AutoFill files the password under it.
            TextField("", text: .constant(model.email))
                .textContentType(.username)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            ZStack(alignment: .trailing) {
                Field(text: $model.password, prompt: "Your password", focused: $focused, secure: !showing)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { model.submitPassword() }
                    .accessibilityLabel("Password")
                Button { showing.toggle() } label: {
                    Image(systemName: showing ? "eye.slash" : "eye").foregroundStyle(Tailwind.gray500).frame(width: 44, height: 44)
                }
                .accessibilityLabel(showing ? "Hide password" : "Show password")
                .padding(.trailing, 6)
            }
            .padding(.top, 20)
            if !model.superadmin {
                LinkButton(title: "Email me a code instead", leading: true) { model.sendCode() }
                    .padding(.top, 8)
                if !connecting {
                    Text("Forgot it? A code signs you in without it.")
                        .font(.system(size: 14))
                        .foregroundStyle(Tailwind.gray500)
                }
            }
        }
        .onAppear { focused = true }
    }
}

private struct CodeStep: View {
    @ObservedObject var model: SignInModel
    @FocusState private var focused: Bool

    var body: some View {
        PinnedStep(model: model, button: "Continue", action: model.submitCode, buttonEnabled: model.code.count == 6,
                   footnote: "Continues by itself once all six are in.") {
            StepTitle(title: "Check your email",
                      lede: "We sent a 6-digit code to \(model.email). It works for \(model.codeLifetime).")
            Notices(model: model)
            CodeBoxes(code: $model.code, focused: $focused) { model.submitCode() }
                .padding(.top, 28)
            Text("The code fills in from the email on its own on most iPhones.")
                .font(.system(size: 14))
                .foregroundStyle(Tailwind.gray500)
                .padding(.top, 14)
            LinkButton(title: "Send a new code", leading: true) { model.sendCode() }
                .padding(.top, 8)
        }
        .onAppear { focused = true }
    }
}

private struct NameStep: View {
    @ObservedObject var model: SignInModel
    @FocusState private var focusedFirst: Bool
    @FocusState private var focusedLast: Bool

    var body: some View {
        PinnedStep(model: model, button: "Create account", action: model.createAccount, footnote: "Free to join · No card needed") {
            StepTitle(title: "What should we call you?",
                      lede: "Your name is used on cast lists, messages, and contracts, so use the name you perform or work under.")
            Notices(model: model)
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(label: "First name") {
                    Field(text: $model.firstName, prompt: "", focused: $focusedFirst)
                        .textContentType(.givenName)
                        .submitLabel(.next)
                        .onSubmit { focusedLast = true }
                }
                LabeledField(label: "Last name") {
                    Field(text: $model.lastName, prompt: "", focused: $focusedLast)
                        .textContentType(.familyName)
                        .submitLabel(.done)
                        .onSubmit { model.createAccount() }
                }
            }
            .padding(.top, 24)
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Tailwind.pink600)
                Text(verbatim: "\(model.email) is confirmed").font(.system(size: 14)).foregroundStyle(Tailwind.gray700)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tailwind.gray50))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tailwind.gray200, lineWidth: 1))
            .padding(.top, 18)
        }
        .onAppear { if model.firstName.isEmpty { focusedFirst = true } else { focusedLast = model.lastName.isEmpty } }
    }
}

/// A step on the raised sheet: back at the top, the step's content, and its
/// one button pinned at the bottom, where a thumb reaches it.
private struct PinnedStep<Content: View>: View {
    @ObservedObject var model: SignInModel
    let button: String
    let action: () -> Void
    var buttonEnabled = true
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CircleButton(systemImage: "chevron.left", label: "Back") { model.startOver() }
                .padding(.leading, -4)
                .padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.top, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            PrimaryButton(title: button, action: action)
                .opacity(buttonEnabled ? 1 : 0.45)
                .disabled(!buttonEnabled)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 13))
                    .foregroundStyle(Tailwind.gray500)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

// MARK: Pieces

private struct StepTitle: View {
    let title: String
    let lede: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Font(AppConfig.coustard(30)))
                .foregroundStyle(Tailwind.gray900)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let lede {
                Text(lede)
                    .font(.system(size: 16))
                    .foregroundStyle(Tailwind.gray500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Notices: View {
    @ObservedObject var model: SignInModel

    var body: some View {
        if let error = model.error {
            Banner(text: error, error: true).padding(.top, 16)
        } else if let notice = model.notice {
            Banner(text: notice, error: false).padding(.top, 16)
        }
    }
}

private struct Field: View {
    @Binding var text: String
    let prompt: String
    var focused: FocusState<Bool>.Binding
    var secure = false

    var body: some View {
        let promptText = Text(verbatim: prompt).foregroundStyle(Tailwind.gray500)
        Group {
            if secure {
                SecureField("", text: $text, prompt: promptText)
            } else {
                TextField("", text: $text, prompt: promptText)
            }
        }
        .focused(focused)
        .font(.system(size: 17))
        .foregroundStyle(Tailwind.gray900)
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused.wrappedValue ? Tailwind.pink500 : Tailwind.gray300, lineWidth: 1.5))
        .background(RoundedRectangle(cornerRadius: 18).fill(focused.wrappedValue ? Tailwind.pink50 : .clear).padding(-4))
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(Tailwind.gray700)
            content
        }
    }
}

/// Six boxes over one hidden field, so the code can be typed, pasted, or
/// filled in by iOS from the email.
private struct CodeBoxes: View {
    @Binding var code: String
    var focused: FocusState<Bool>.Binding
    let complete: () -> Void

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused(focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel("6-digit code")
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(6))
                    if digits != value { code = digits }
                    if digits.count == 6 { complete() }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let characters = Array(code)
                    let current = index == characters.count && focused.wrappedValue
                    Text(index < characters.count ? String(characters[index]) : "")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Tailwind.gray900)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(RoundedRectangle(cornerRadius: 14).fill(index < characters.count ? Tailwind.gray50 : .white))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(current ? Tailwind.pink500 : Tailwind.gray300, lineWidth: 1.5))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}

private struct AccountChip: View {
    let email: String
    let change: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Signing in as").font(.system(size: 13)).foregroundStyle(Tailwind.gray500)
                Text(verbatim: email).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tailwind.gray900)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Change", action: change)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tailwind.pink600)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tailwind.gray50))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tailwind.gray200, lineWidth: 1))
    }
}

private struct PrimaryButton: View {
    let title: String
    var faceID = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if faceID { Image(systemName: "faceid").font(.system(size: 18, weight: .semibold)).accessibilityHidden(true) }
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tailwind.pink500))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct LinkButton: View {
    let title: String
    var leading = false
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Tailwind.pink600)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: leading ? .leading : .center)
    }
}

private struct CircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tailwind.gray900)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(red: 0.95, green: 0.96, blue: 0.96)))
        }
        .accessibilityLabel(label)
    }
}

private struct OrRule: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Tailwind.gray200).frame(height: 1)
            Text("or").font(.system(size: 14)).foregroundStyle(Tailwind.gray500)
            Rectangle().fill(Tailwind.gray200).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct Terms: View {
    var body: some View {
        let terms = AppConfig.url("/terms").absoluteString
        let privacy = AppConfig.url("/privacy").absoluteString
        Text(.init("By continuing you agree to the [Terms of Service](\(terms)) and [Privacy Policy](\(privacy))."))
            .font(.system(size: 12))
            .foregroundStyle(Tailwind.gray500)
            .tint(Tailwind.gray500)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
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
            .background(RoundedRectangle(cornerRadius: 12).fill(error ? Tailwind.pink50 : Tailwind.gray50))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(error ? Tailwind.pink200 : Tailwind.gray200, lineWidth: 1))
    }
}

/// The sign-in screens over the whole app while nobody's signed in
/// (AppShell). It can't be swiped away: there's nothing behind it to use.
final class SignInViewController: UIHostingController<SignInScreen> {
    let model: SignInModel

    init(onSignedIn: @escaping (URL) -> Void) {
        model = SignInModel(onSignedIn: onSignedIn)
        super.init(rootView: SignInScreen(model: model))
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
        view.backgroundColor = AppConfig.pink
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
