import SwiftData
import SwiftUI

/// On iPhone, Profile is also the home of the business tools (invoices, quotes, accounting…),
/// which have their own sidebar entries on iPad.
struct ProfileView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<BillingDocument> { $0.kindRaw == "invoice" }) private var invoices: [BillingDocument]
    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            List {
                Section { header }

                Section("Business") {
                    NavigationLink { JobCalendarView() } label: { Label("Calendar", systemImage: "calendar") }
                    NavigationLink { BillingListView(kind: .invoice) } label: {
                        LabeledContent {
                            let due = invoices.filter { $0.status == .sent || $0.status == .overdue }.count
                            if due > 0 { Text("\(due) awaiting") }
                        } label: { Label("Invoices", systemImage: "doc.text.fill") }
                    }
                    NavigationLink { BillingListView(kind: .quote) } label: { Label("Quotes", systemImage: "doc.text.magnifyingglass") }
                    NavigationLink { AccountingView() } label: { Label("Accounting", systemImage: "chart.bar.xaxis") }
                    NavigationLink { PayoutsView() } label: { Label("Payouts", systemImage: "banknote.fill") }
                    NavigationLink { PortfolioView() } label: { Label("Portfolio", systemImage: "square.grid.2x2.fill") }
                }

                Section("Profile") {
                    NavigationLink { EditProfileView() } label: { Label("Edit profile & links", systemImage: "person.text.rectangle.fill") }
                    NavigationLink { JobAlertsView() } label: { Label("Job alerts", systemImage: "bell.badge.fill") }
                    Button { router.sheet = .focus } label: { Label("Focus timer", systemImage: "timer") }
                    NavigationLink { SearchView(embedded: true) } label: { Label("Search", systemImage: "magnifyingglass") }
                }

                if store.isFreelancer {
                    Section {
                        Picker(selection: Binding(get: { store.mode }, set: { store.mode = $0 })) {
                            ForEach(MarketplaceStore.Mode.allCases) { Text($0.title).tag($0) }
                        } label: {
                            Label("Mode", systemImage: "arrow.left.arrow.right")
                        }
                    } footer: {
                        Text("Freelancers can also hire: switch to Hiring to post jobs and see recommended candidates.")
                    }
                }

                if store.isAdmin {
                    Section("Administration") {
                        NavigationLink { ModerationQueueView() } label: { Label("Moderation queue", systemImage: "checkmark.shield.fill") }
                    }
                }

                Section("Privacy") {
                    Label("Your name, e-mail, phone and links are visible only to people you've both accepted.", systemImage: "hand.raised.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !LaunchOptions.isDemo {
                        Button("Sign out") { auth.signOut() }
                    }
                    Button("Delete account", role: .destructive) { confirmsDeletion = true }
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog("Delete your account?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task {
                        try? await store.deleteAccount()
                        auth.signOut()
                    }
                }
            } message: {
                Text("Your profile, contact details and messages will be permanently deleted. Invoices and portfolio stay in your iCloud.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            AnonymousAvatar(seed: store.me, symbol: store.profile?.discipline.symbol ?? "person.fill", size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.account?.displayName ?? "").font(.title3.bold())
                Text(store.profile?.handle ?? "").font(.subheadline).foregroundStyle(.secondary)
                Text("This is how others see you until you connect.").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let score = store.profile?.score {
                ScoreRing(score: score.overall, lineWidth: 6).frame(width: 58, height: 58)
            }
        }
        .padding(.vertical, 6)
    }
}

struct EditProfileView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var isFreelancer = true
    @State private var discipline: Discipline = .design
    @State private var headline = ""
    @State private var skills = ""
    @State private var links: [ProfileLinkKind: String] = [:]
    @State private var errors: [ProfileLinkKind: String] = [:]
    @State private var saveError: String?
    @State private var isSaving = false

    private var requiredKinds: [ProfileLinkKind] {
        guard isFreelancer else { return [] }
        return [.linkedin] + (discipline.requiredLink.map { [$0] } ?? [])
    }

    var body: some View {
        Form {
            Section {
                TextField("Full name", text: $name).textContentType(.name)
                TextField("Phone (optional)", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
            } header: {
                Text("Private")
            } footer: {
                Text("Only shared with people after you both accept a contact request.")
            }

            Section("Public profile") {
                Toggle("I'm a freelancer", isOn: $isFreelancer)
                if isFreelancer {
                    Picker("Discipline", selection: $discipline) {
                        ForEach(Discipline.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Headline", text: $headline)
                    TextField("Skills, comma separated", text: $skills, axis: .vertical)
                }
            }

            Section {
                ForEach(ProfileLinkKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(kind.title, systemImage: kind.symbol)
                            if requiredKinds.contains(kind) {
                                Text("Required").font(.caption2.weight(.semibold)).foregroundStyle(Brand.indigo)
                            }
                        }
                        .font(.subheadline)
                        TextField(kind.placeholder, text: Binding(get: { links[kind] ?? "" }, set: { links[kind] = $0; errors[kind] = nil }))
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let error = errors[kind] {
                            Text(error).font(.caption).foregroundStyle(Brand.danger)
                        }
                    }
                }
            } header: {
                Text("Links")
            } footer: {
                Text("LinkedIn is required for every freelancer. Designers add Behance, developers GitHub, consultants their website and advisors their X account. Links are verified and stay private until you connect.")
            }

            if let saveError {
                Section { Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger) }
            }
        }
        .navigationTitle("Edit profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", role: .confirm, action: save).disabled(isSaving || name.isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let account = store.account else { return }
        name = account.displayName
        phone = account.phone ?? ""
        isFreelancer = account.isFreelancer
        discipline = account.discipline ?? .design
        headline = store.profile?.headline ?? ""
        skills = store.profile?.skills.joined(separator: ", ") ?? ""
        for link in account.links { links[link.kind] = link.url.absoluteString }
    }

    private func save() {
        errors = [:]
        var validated: [ProfileLink] = []
        for kind in ProfileLinkKind.allCases {
            let text = links[kind]?.trimmingCharacters(in: .whitespaces) ?? ""
            if text.isEmpty {
                if requiredKinds.contains(kind) { errors[kind] = String(localized: "\(kind.title) is required.") }
                continue
            }
            switch LinkGuard.validateProfileLink(text, kind: kind) {
            case .success(let url): validated.append(ProfileLink(kind: kind, url: url))
            case .failure(let error): errors[kind] = error.localizedDescription
            }
        }
        guard errors.isEmpty else { return }

        let base = store.account ?? UserAccount(id: store.me, displayName: name, email: "", phone: nil, isFreelancer: isFreelancer,
                                                discipline: nil, links: [], jobAlertSkills: [], createdAt: .now)
        var account = base
        account.displayName = name
        account.phone = phone.isEmpty ? nil : phone
        account.isFreelancer = isFreelancer
        account.discipline = isFreelancer ? discipline : nil
        account.links = validated

        var profile = store.profile ?? PublicProfile(id: store.me, discipline: discipline, headline: "", skills: [], yearsOfExperience: 0,
                                                     hourlyRate: nil, region: TimeZone.current.identifier.split(separator: "/").first.map(String.init) ?? "",
                                                     signals: .newcomer, completedJobs: 0, verifiedLinks: [], isAvailable: true)
        profile.discipline = discipline
        profile.headline = headline
        profile.skills = skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        isSaving = true
        Task {
            do {
                try await store.save(account: account, profile: profile)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct JobAlertsView: View {
    @Environment(MarketplaceStore.self) private var store
    @State private var skills: [String] = []
    @State private var newSkill = ""
    @State private var notifyMessages = true

    var body: some View {
        Form {
            Section {
                ForEach(skills, id: \.self) { Text($0) }
                    .onDelete { skills.remove(atOffsets: $0) }
                TextField("Add a skill to watch", text: $newSkill)
                    .onSubmit {
                        let s = newSkill.trimmingCharacters(in: .whitespaces)
                        if !s.isEmpty { skills.append(s) }
                        newSkill = ""
                    }
            } header: {
                Text("Notify me about new jobs matching")
            } footer: {
                Text("You'll get a push notification as soon as a matching job is published and approved.")
            }
            Section {
                Toggle("New messages", isOn: $notifyMessages)
            }
        }
        .navigationTitle("Job alerts")
        .onAppear { skills = store.account?.jobAlertSkills ?? [] }
        .onDisappear {
            guard var account = store.account, let profile = store.profile, account.jobAlertSkills != skills else { return }
            account.jobAlertSkills = skills
            Task { try? await store.save(account: account, profile: profile) }
        }
    }
}
