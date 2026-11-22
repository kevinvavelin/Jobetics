import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AuthService.self) private var auth
    @State private var error: String?

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

                SignInWithAppleButton(.continue) { request in
                    auth.prepare(request)
                } onCompletion: { result in
                    Task {
                        do { try await auth.complete(result) } catch { self.error = error.localizedDescription }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(.capsule)
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
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(.subheadline.weight(.semibold)) } icon: {
            Image(systemName: symbol).foregroundStyle(Brand.gradient)
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
