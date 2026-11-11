import SwiftUI

/// Sign up or sign in with an email and a six-digit code. No password —
/// except for the App Review demo account, which can't receive mail (see
/// `Supabase.passwordAccounts`).
///
/// Both modes send the same code; the difference is that Sign up creates the
/// account on the spot and Sign in refuses an unknown address, so a typo can't
/// quietly become a second, empty account.
struct AuthSheet: View {
    enum Mode { case signUp, signIn }

    @ObservedObject var account: Account

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    @State private var mode: Mode
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var stage = Stage.email
    @State private var busy = false
    @State private var message: String?

    enum Stage { case email, code, password, done }

    init(account: Account, mode: Mode = .signUp) {
        _account = ObservedObject(wrappedValue: account)
        _mode = State(initialValue: mode)
    }

    private var title: String {
        switch stage {
        case .done: "You're in"
        default: mode == .signUp ? "Create your account" : "Sign in"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ClaySheetHeader(title: title) { dismiss() }
                .padding(.horizontal, Tokens.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch stage {
                    case .email: emailStage
                    case .code: codeStage
                    case .password: passwordStage
                    case .done: doneStage
                    }

                    if let message {
                        Text(message)
                            .textRole(.meta, color: Tokens.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Tokens.paper)
        .presentationDetents([.medium, .large])
        .claySheet()
    }

    /// The one field style: white, hairline, radius 14, ≥ 52 pt.
    private func fieldSurface<Content: View>(_ content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous)
                .strokeBorder(Tokens.hairline, lineWidth: 1))
    }

    private var emailStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .signUp
                 ? "Your borks only exist on this phone right now. Enter your email and we'll send a six-digit code — that's the whole sign-up. Your borks get backed up and follow you to every device."
                 : "Enter the email you signed up with and we'll send a six-digit code.")
                .textRole(.body, color: Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            fieldSurface(
                TextField("you@example.com", text: $email)
                    .textRole(.body, color: Tokens.ink)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            )

            primaryButton(busy ? "Sending…" : "Email me a code") {
                Task { await sendCode() }
            }
            .disabled(busy || !email.contains("@"))

            Text("No password to make up or lose — the code is the whole thing.")
                .textRole(.meta)
                .fixedSize(horizontal: false, vertical: true)

            Button(mode == .signUp ? "Already have an account? Sign in" : "New here? Sign up") {
                withAnimation(Motion.gentle) {
                    mode = mode == .signUp ? .signIn : .signUp
                }
                message = nil
            }
            .buttonStyle(.clayQuiet)
        }
    }

    private var codeStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check \(email) for a six-digit code.")
                .textRole(.body, color: Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            fieldSurface(
                TextField("123456", text: $code)
                    .font(Typo.mono(24))
                    .foregroundStyle(Tokens.ink)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
            )

            primaryButton(busy ? "Checking…" : "Continue") {
                Task { await verify() }
            }
            .disabled(busy || code.count < 6)

            Button("Use a different email") {
                stage = .email
                code = ""
                message = nil
            }
            .buttonStyle(.clayQuiet)
        }
    }

    private var passwordStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(email) signs in with a password.")
                .textRole(.body, color: Tokens.inkSecondary)

            fieldSurface(
                SecureField("Password", text: $password)
                    .textRole(.body, color: Tokens.ink)
                    .textContentType(.password)
            )

            primaryButton(busy ? "Checking…" : "Sign in") {
                Task { await signInWithPassword() }
            }
            .disabled(busy || password.isEmpty)

            Button("Use a different email") {
                stage = .email
                password = ""
                message = nil
            }
            .buttonStyle(.clayQuiet)
        }
    }

    private var doneStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(accent.deep)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.email ?? email)
                        .textRole(.cardTitle, color: Tokens.ink)
                    Text(mode == .signUp
                         ? "Account made. Your borks are backing up now."
                         : "Your borks are backing up now.")
                        .textRole(.meta)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .cardSurface()
            primaryButton("Done") { dismiss() }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.clayPrimary)
    }

    /// A wrong code or password is the likeliest failure, so it is named;
    /// a network problem gets `PlainError`'s sentence. The raw text is logged.
    private func plain(_ error: Error, doing: String, otherwise: String) -> String {
        #if DEBUG
        print("Auth failed (\(doing)):", error)
        #endif
        switch PlainError.kind(of: error) {
        case .offline, .timeout, .server: return PlainError.message(error, doing: doing)
        case .cancelled: return ""
        case .signedOut, .other: return otherwise
        }
    }

    private func sendCode() async {
        if Supabase.usesPassword(email) {
            withAnimation(Motion.gentle) { stage = .password }
            return
        }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await account.sendCode(to: email, createIfNew: mode == .signUp)
            withAnimation(Motion.gentle) { stage = .code }
        } catch where Supabase.isUnknownAccount(error) {
            message = "No account with that email yet. Tap Sign up and we'll make one."
        } catch {
            message = plain(error, doing: "send the code",
                            otherwise: "Couldn't send the code. Check the email and try again.")
        }
    }

    private func signInWithPassword() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            try await account.signIn(email: email, password: password)
            Haptics.success()
            withAnimation(Motion.gentle) { stage = .done }
        } catch {
            message = plain(error, doing: "sign you in",
                            otherwise: "That email and password don't match. Try again.")
        }
    }

    private func verify() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            try await account.verify(code: code, email: email)
            Haptics.success()
            withAnimation(Motion.gentle) { stage = .done }
        } catch {
            message = plain(error, doing: "check the code",
                            otherwise: "That code didn't work. Check it, or use a different email to get a new one.")
        }
    }
}
