import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var error: String?
    @State private var isSigningInWithGoogle = false
    @State private var showsEmailSignIn = false

    var body: some View {
        ZStack {
            BrandMesh(animated: true).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 34))
                        .accessibilityHidden(true)
                    Text("Jobetics").font(.system(size: 48, weight: .heavy, design: .rounded))
                    Text("Paid jobs. Fair clients. Your freelance business, in one place.")
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 14) {
                    feature("checkmark.seal.fill", "Every job is paid and checked for spam")
                    feature("eye.slash.fill", "Anonymous until you both accept contact")
                    feature("gauge.with.dots.needle.67percent", "A score that rewards reliability")
                    feature("doc.text.fill", "Quotes, invoices & accounting built in")
                }
                .padding(20)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        Group {
                            if isSigningInWithGoogle { ProgressView().tint(.black) } else { Text("Continue with Google") }
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(.white, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSigningInWithGoogle)

                    Button {
                        showsEmailSignIn = true
                    } label: {
                        Label("Continue with e-mail", systemImage: "envelope.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)

                if let error { Text(error).font(.footnote).foregroundStyle(.white) }

                Text("By continuing you accept the Terms and Community Guidelines.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal)
        }
        .sheet(isPresented: $showsEmailSignIn) { EmailSignInView() }
    }

    private func signInWithGoogle() async {
        error = nil
        isSigningInWithGoogle = true
        defer { isSigningInWithGoogle = false }
        do { try await auth.signInWithGoogle(using: webAuthenticationSession) }
        catch { self.error = AuthService.message(for: error) }
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(.subheadline.weight(.semibold)) } icon: {
            Image(systemName: symbol).foregroundStyle(Brand.gradient)
        }
    }
}

/// E-mail & password: sign in, create an account, or reset a forgotten password.
struct EmailSignInView: View {
    private enum Mode: Hashable { case signIn, createAccount }

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var notice: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Sign in").tag(Mode.signIn)
                        Text("Create account").tag(Mode.createAccount)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("E-mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                } footer: {
                    if mode == .createAccount {
                        Text("At least 6 characters. We'll send you an e-mail to confirm your address.")
                    }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger) }
                }
                if let notice {
                    Section { Label(notice, systemImage: "envelope.badge.fill") }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() } else {
                                Text(mode == .signIn ? "Sign in" : "Create account").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)

                    if mode == .signIn {
                        Button("Forgot password?") { Task { await resetPassword() } }
                            .frame(maxWidth: .infinity)
                            .disabled(isWorking)
                    }
                }
            }
            .navigationTitle(mode == .signIn ? "Sign in" : "Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .onChange(of: mode) { error = nil; notice = nil }
            .onAppear { focusedField = .email }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        error = nil
        notice = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn: try await auth.signIn(email: email, password: password)
            case .createAccount: try await auth.createAccount(email: email, password: password)
            }
            // Signing in swaps the root view to the app, which dismisses this sheet.
        } catch {
            self.error = AuthService.message(for: error)
        }
    }

    private func resetPassword() async {
        error = nil
        notice = nil
        guard email.contains("@") else {
            error = String(localized: "Enter your e-mail address first.")
            focusedField = .email
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.sendPasswordReset(to: email)
            notice = String(localized: "If an account exists for this address, you'll receive an e-mail to reset your password.")
        } catch {
            self.error = AuthService.message(for: error)
        }
    }
}

/// First launch after sign-in: choose a role and fill the required links.
struct ProfileSetupView: View {
    var body: some View {
        NavigationStack {
            EditProfileView()
                .navigationTitle("Create your profile")
        }
    }
}
