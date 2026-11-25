import SwiftUI

struct MessagesView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.messagesPath) {
            List {
                ForEach(store.conversations) { conversation in
                    NavigationLink(value: conversation) { ConversationRow(conversation: conversation) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if store.conversations.isEmpty {
                    ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Send a proposal to start a conversation."))
                }
            }
            .navigationTitle("Messages")
            .navigationDestination(for: Conversation.self) { ChatView(conversation: $0) }
        }
        .task { await store.observeConversations() }
        .onChange(of: store.conversations) { _, list in
            guard let id = router.pendingConversationID, let match = list.first(where: { $0.id == id }) else { return }
            router.pendingConversationID = nil
            router.messagesPath = [match]
        }
    }
}

struct ConversationRow: View {
    @Environment(MarketplaceStore.self) private var store
    var conversation: Conversation

    var body: some View {
        let other = conversation.otherParticipant(than: store.me)
        let unread = conversation.unread[store.me] ?? 0
        HStack(spacing: 10) {
            // Messages-style unread indicator: a leading blue dot.
            Circle()
                .fill(unread > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            AnonymousAvatar(seed: other, symbol: other.hasPrefix("emp") ? "building.2.fill" : "person.fill", size: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.handles[other] ?? String(localized: "Member")).font(.headline).lineLimit(1)
                    Spacer()
                    Text(conversation.lastMessageAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(unread > 0 ? Brand.indigo : .secondary)
                }
                if let title = conversation.jobTitle {
                    Text(title).font(.caption.weight(.medium)).foregroundStyle(Brand.indigo).lineLimit(1)
                }
                HStack(alignment: .top) {
                    Text(conversation.lastMessage).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread > 0 ? Text("\(unread) unread") : Text(""))
    }
}

struct ChatView: View {
    @Environment(MarketplaceStore.self) private var store
    var conversation: Conversation
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var connection: Connection?
    @State private var contact: PrivateContact?
    @State private var notice: String?
    @State private var reported: ChatMessage?
    @State private var showsContact = false
    @State private var confirmsBlock = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool

    private var other: String { conversation.otherParticipant(than: store.me) }
    private var unlocked: Bool { connection?.isMutual == true }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    contactBanner.padding(.bottom, 8)
                    ForEach(messages) { message in
                        MessageBubble(message: message, isMine: message.senderId == store.me)
                            .id(message.id)
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
                                if message.senderId != store.me {
                                    Button("Report", systemImage: "flag", role: .destructive) { reported = message }
                                }
                            }
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(conversation.handles[other] ?? String(localized: "Chat"))
        .navigationSubtitle(conversation.jobTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    if unlocked { Button("Contact details", systemImage: "person.text.rectangle") { showsContact = true } }
                    Button("Report conversation", systemImage: "flag", role: .destructive) {
                        reported = messages.last { $0.senderId != store.me }
                    }
                    Button("Block", systemImage: "hand.raised.fill", role: .destructive) { confirmsBlock = true }
                }
            }
        }
        .task {
            connection = try? await store.backend.connection(with: other)
            for await list in store.backend.messages(in: conversation.id) { messages = list }
        }
        .sheet(item: $reported) { message in
            ReportSheet(kind: .message, targetId: message.id, ownerId: message.senderId, excerpt: message.text)
        }
        .sheet(isPresented: $showsContact) { PrivateContactSheet(contact: contact) }
        .confirmationDialog("Block this member?", isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { try? await store.block(other); dismiss() }
            }
        } message: {
            Text("They won't be able to message you, and this conversation will be hidden.")
        }
        .task(id: unlocked) { if unlocked { contact = try? await store.backend.contact(of: other) } }
    }

    @ViewBuilder private var contactBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .font(.title3)
                .foregroundStyle(unlocked ? AnyShapeStyle(Brand.positive) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(unlocked ? "Contact details unlocked" : "Contact details are private")
                    .font(.subheadline.weight(.semibold))
                Text(bannerDetail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let action = bannerAction {
                Button(action.0) { action.1() }
                    .buttonStyle(.gradientCapsule)
                    .controlSize(.small)
            } else if unlocked {
                Button("View") { showsContact = true }.buttonStyle(.glass).controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private var bannerDetail: String {
        guard let connection else { return String(localized: "Names, e-mails and phone numbers are shared only when you both accept.") }
        if connection.isMutual { return String(localized: "You can now see each other's name and contact details.") }
        return connection.acceptedBy.contains(store.me)
            ? String(localized: "Waiting for the other side to accept.")
            : String(localized: "They'd like to exchange contact details.")
    }

    private var bannerAction: (LocalizedStringKey, () -> Void)? {
        if let connection {
            if connection.isMutual || connection.acceptedBy.contains(store.me) { return nil }
            return ("Accept", { Task { self.connection = try? await store.backend.accept(connection) } })
        }
        return ("Request", { Task { self.connection = try? await store.backend.requestContact(with: other) } })
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.body.weight(.bold)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.gradientCapsule)
                    .buttonBorderShape(.circle)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.snappy, value: notice)
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            do {
                let redacted = try await store.send(text, in: conversation, contactUnlocked: unlocked)
                notice = redacted ? String(localized: "Contact details were hidden. They're shared once you both accept.") : nil
            } catch {
                draft = text
                notice = error.localizedDescription
            }
        }
    }
}

struct MessageBubble: View {
    var message: ChatMessage
    var isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(Self.linkified(message.text))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(isMine ? .white : .primary)
                    .background(isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                in: .rect(cornerRadius: 20, style: .continuous))
                HStack(spacing: 4) {
                    if message.wasRedacted { Image(systemName: "eye.slash.fill") }
                    Text(message.sentAt, format: .dateTime.hour().minute())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }

    /// Detects links so they're tappable; taps go through `SafeBrowser` → `LinkGuard`.
    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return attributed }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].link = url
            attributed[lower..<upper].underlineStyle = .single
        }
        return attributed
    }
}

struct PrivateContactSheet: View {
    var contact: PrivateContact?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let contact {
                    Section { Text(contact.displayName).font(.title3.bold()) }
                    Section("Contact") {
                        if let mail = URL(string: "mailto:\(contact.email)") { Link(destination: mail) { Label(contact.email, systemImage: "envelope.fill") } }
                        if let phone = contact.phone, let tel = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                            Link(destination: tel) { Label(phone, systemImage: "phone.fill") }
                        }
                    }
                    Section("Links") {
                        ForEach(contact.links, id: \.url) { link in
                            Link(destination: link.url) { Label(link.kind.title, systemImage: link.kind.symbol) }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
