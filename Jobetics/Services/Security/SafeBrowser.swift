import SafariServices
import SwiftUI

/// Routes every link through `LinkGuard`, then opens it **inside** the app with
/// `SFSafariViewController` (cookies isolated from the app, Safari's own phishing protection).
@Observable
final class SafeBrowser {
    struct Presentation: Identifiable {
        let id = UUID()
        let assessment: LinkGuard.Assessment
        var confirmed: Bool
    }

    var presentation: Presentation?

    func open(_ url: URL) {
        var target = url
        // Upgrade plain HTTP to HTTPS when possible, as Safari would with HTTPS-by-default.
        if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            target = components.url ?? url
        }
        let assessment = LinkGuard.assess(target)
        presentation = Presentation(assessment: assessment, confirmed: assessment.level == .trusted)
    }

    var openURLAction: OpenURLAction {
        OpenURLAction { [weak self] url in
            // Let the app handle its own deep links and mail/phone links normally.
            if url.scheme == "jobetics" || url.scheme == "mailto" || url.scheme == "tel" { return .systemAction }
            self?.open(url)
            return .handled
        }
    }
}

struct SafeBrowserModifier: ViewModifier {
    @Bindable var browser: SafeBrowser

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, browser.openURLAction)
            .sheet(item: $browser.presentation) { presentation in
                if presentation.confirmed {
                    SafariView(url: presentation.assessment.url)
                        .ignoresSafeArea()
                        .presentationDetents([.large])
                } else {
                    LinkWarningView(assessment: presentation.assessment) {
                        browser.presentation?.confirmed = true
                    } onCancel: {
                        browser.presentation = nil
                    }
                    .presentationDetents([.medium, .large])
                }
            }
    }
}

extension View {
    func safeBrowsing(_ browser: SafeBrowser) -> some View { modifier(SafeBrowserModifier(browser: browser)) }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Brand.indigo)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct LinkWarningView: View {
    let assessment: LinkGuard.Assessment
    var onContinue: () -> Void
    var onCancel: () -> Void

    private var isBlocked: Bool { assessment.level == .blocked }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: isBlocked ? "hand.raised.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(isBlocked ? Brand.danger : Brand.warning)
                        .symbolEffect(.bounce, options: .nonRepeating)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text(isBlocked ? "Link blocked" : "Check this link")
                            .font(.title2.bold())
                        Text(assessment.host.isEmpty ? assessment.url.absoluteString : assessment.host)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(assessment.reasons, id: \.self) { reason in
                            Label {
                                Text(reason.explanation)
                            } icon: {
                                Image(systemName: reason.level == .blocked ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(reason.level == .blocked ? Brand.danger : Brand.warning)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text(isBlocked ? "Close" : "Go back to safety").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    if !isBlocked {
                        Button("Open anyway", role: .destructive, action: onContinue)
                            .buttonStyle(.glass)
                    }
                }
                .padding()
            }
        }
    }
}
