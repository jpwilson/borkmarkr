import SwiftUI

/// Sign in with an email and a six-digit code. No password — except for the
/// App Review demo account, which can't receive mail (see
/// `Supabase.passwordAccounts`).
struct AuthSheet: View {
    @ObservedObject var account: Account

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var stage = Stage.email
    @State private var busy = false
    @State private var message: String?

    enum Stage { case email, code, password, done }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch stage {
                    case .email: emailStage
                    case .code: codeStage
                    case .password: passwordStage
                    case .done: doneStage
                    }

                    if let message {
                        Text(message)
                            .font(Typo.ui(12.5))
                            .foregroundStyle(Tokens.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
            }
            .background(Tokens.paper)
            .navigationTitle(stage == .done ? "You're in" : "Back up your borks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .done ? "Done" : "Not now") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }

    private var emailStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Right now your borks only exist on this phone. Sign in and they're backed up and on every device you use.")
                .font(Typo.ui(14))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("you@example.com", text: $email)
                .font(Typo.ui(16))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .cardSurface(radius: 16)

            primaryButton(busy ? "Sending…" : "Email me a code") {
                Task { await sendCode() }
            }
            .disabled(busy || !email.contains("@"))

            Text("We'll email you a six-digit code. No password to remember or lose.")
                .font(Typo.ui(12))
                .foregroundStyle(Tokens.inkFaint)
        }
    }

    private var codeStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check \(email) for a six-digit code.")
                .font(Typo.ui(14))
                .foregroundStyle(Tokens.inkSecondary)

            TextField("123456", text: $code)
                .font(Typo.mono(24))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding(16)
                .cardSurface(radius: 16)

            primaryButton(busy ? "Checking…" : "Sign in") {
                Task { await verify() }
            }
            .disabled(busy || code.count < 6)

            Button("Use a different email") {
                stage = .email
                code = ""
                message = nil
            }
            .font(Typo.ui(13, .semibold))
        }
    }

    private var passwordStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(email) signs in with a password.")
                .font(Typo.ui(14))
                .foregroundStyle(Tokens.inkSecondary)

            SecureField("Password", text: $password)
                .font(Typo.ui(16))
                .textContentType(.password)
                .padding(14)
                .cardSurface(radius: 16)

            primaryButton(busy ? "Checking…" : "Sign in") {
                Task { await signInWithPassword() }
            }
            .disabled(busy || password.isEmpty)

            Button("Use a different email") {
                stage = .email
                password = ""
                message = nil
            }
            .font(Typo.ui(13, .semibold))
        }
    }

    private var doneStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(accent.base)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? email)
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(Tokens.ink)
                    Text("Your borks are backing up now.")
                        .font(Typo.ui(12.5))
                        .foregroundStyle(Tokens.inkMeta)
                }
            }
            primaryButton("Done") { dismiss() }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.ui(15.5, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func sendCode() async {
        if Supabase.usesPassword(email) {
            withAnimation(Motion.gentle) { stage = .password }
            return
        }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await account.sendCode(to: email)
            withAnimation(Motion.gentle) { stage = .code }
        } catch {
            message = error.localizedDescription
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
            message = error.localizedDescription
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
            message = error.localizedDescription
        }
    }
}
