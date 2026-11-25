import CoreTransferable
import PassKit
import SwiftUI
import UniformTypeIdentifiers

/// The freelancer's business card: a QR code anyone can scan with their Camera to add the contact,
/// a vCard to send by Messages, WhatsApp or AirDrop, and an Apple Wallet pass.
struct MyCardView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var pass: PKPass?
    @State private var walletError: String?
    @State private var isCreatingPass = false

    private var card: ContactCard {
        let s = settings.settings
        let linkedIn = store.account?.links.first { $0.kind == .linkedin }?.url.absoluteString ?? ""
        return ContactCard(fullName: s.legalName.isEmpty ? (store.account?.displayName ?? "") : s.legalName,
                           organization: s.tradeName, title: s.jobTitle, email: s.email, phone: s.phone,
                           website: s.website, linkedIn: linkedIn)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                cardFace
                VStack(spacing: 12) {
                    if WalletPassService.isAvailable {
                        AddToWalletButton { Task { await addToWallet() } }
                            .frame(height: 48)
                            .disabled(isCreatingPass)
                    }
                    ShareLink(item: VCardFile(card: card), preview: SharePreview(card.fullName, image: Image(systemName: "person.crop.rectangle"))) {
                        Label("Share contact card", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.gradientCapsule)
                    .controlSize(.large)
                    HStack {
                        Button {
                            if let url = SocialShare.whatsAppURL(text: shareText) { openURL(url) }
                        } label: { Label("WhatsApp", systemImage: "bubble.left.and.text.bubble.right.fill").frame(maxWidth: .infinity) }
                        Button {
                            if let url = SocialShare.linkedInComposeURL(text: shareText) { openURL(url) }
                        } label: { Label("LinkedIn", systemImage: "person.crop.square.fill").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                if let walletError {
                    Label(walletError, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Scanning the QR code with an iPhone or Android camera offers to add you to their contacts. No app needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !settings.settings.isComplete {
                    NavigationLink("Complete your details") { BusinessSettingsView() }
                }
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My card")
        .sheet(item: Binding(get: { pass.map(IdentifiedPass.init) }, set: { pass = $0?.pass })) { item in
            AddPassSheet(pass: item.pass).ignoresSafeArea()
        }
    }

    private var shareText: String {
        [card.fullName, card.title, card.email, card.phone, card.website].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var cardFace: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(card.fullName).font(.title2.bold())
                if !card.title.isEmpty { Text(card.title).font(.subheadline).opacity(0.85) }
                if !card.organization.isEmpty { Text(card.organization).font(.caption).opacity(0.7) }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            if let image = QRCode.image(for: card.vCard) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(14)
                    .background(.white, in: .rect(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel("QR code with your contact card")
            }
            HStack(spacing: 16) {
                if !card.email.isEmpty { Label(card.email, systemImage: "envelope.fill") }
                if !card.phone.isEmpty { Label(card.phone, systemImage: "phone.fill") }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background { BrandMesh() }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .shadow(color: Brand.blue.opacity(0.25), radius: 24, y: 12)
    }

    private func addToWallet() async {
        isCreatingPass = true
        walletError = nil
        defer { isCreatingPass = false }
        do { pass = try await WalletPassService.makePass(for: card) } catch { walletError = error.localizedDescription }
    }
}

/// vCard file for ShareLink: Messages, WhatsApp, Mail and AirDrop all understand it.
struct VCardFile: Transferable {
    var card: ContactCard

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .vCard) { Data($0.card.vCard.utf8) }
            .suggestedFileName { "\($0.card.fullName).vcf" }
    }
}

private struct IdentifiedPass: Identifiable {
    var pass: PKPass
    var id: String { pass.serialNumber }
}

struct AddToWalletButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

struct AddPassSheet: UIViewControllerRepresentable {
    var pass: PKPass

    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
