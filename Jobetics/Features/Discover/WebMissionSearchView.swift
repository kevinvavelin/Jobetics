import SwiftData
import SwiftUI

/// Finds missions for the freelancer: searches job APIs (and Google or Brave when the user adds a key),
/// parses each listing into rate, contract, location, skills match, and shows the details in the app.
struct WebMissionSearchView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(SafeBrowser.self) private var browser
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Mission> { $0.statusRaw == "lead" || $0.statusRaw == "negotiating" || $0.statusRaw == "quoted" })
    private var leads: [Mission]
    @AppStorage("leads.query") private var query = ""
    @AppStorage("leads.freelanceOnly") private var freelanceOnly = true
    @AppStorage(LeadSearchSettings.enabledKey) private var enabledRaw = LeadSearchSettings.defaultEnabled
    @State private var outcome: LeadSearchOutcome?
    @State private var isSearching = false
    @State private var withRateOnly = false
    @State private var savingLead: Mission?
    @State private var showsSettings = false

    private var skills: [String] { store.profile?.skills ?? [] }
    private var savedURLs: Set<URL> { Set((try? context.fetch(FetchDescriptor<Mission>()))?.compactMap(\.sourceURL) ?? []) }

    private var results: [LeadResult] {
        (outcome?.results ?? []).filter { !withRateOnly || $0.rate != nil }
    }

    var body: some View {
        List {
            Section { filters.listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)).listRowBackground(Color.clear) }

            if isSearching && outcome == nil {
                Section { ProgressView("Searching \(LeadSearchSettings.enabled(enabledRaw).map(\.name).formatted(.list(type: .and)))…").frame(maxWidth: .infinity) }
            } else if let outcome {
                Section {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(results) { lead in
                        NavigationLink {
                            LeadDetailView(lead: lead, skills: skills, isSaved: savedURLs.contains(lead.url)) { savingLead = save(lead) }
                        } label: {
                            LeadRow(lead: lead, match: lead.match(skills: skills), isSaved: savedURLs.contains(lead.url),
                                    targetDailyCents: RateCalculator.recommend(settings.settings.rateInputs).dailyRateCents)
                        }
                        .accessibilityIdentifier("lead-row")
                        .swipeActions(edge: .leading) {
                            Button("Save as lead", systemImage: "bookmark") { savingLead = save(lead) }.tint(Brand.blue)
                        }
                    }
                } header: {
                    if !results.isEmpty { Text("^[\(results.count) listing](inflect: true)") }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(outcome.failures.sorted { $0.key.name < $1.key.name }, id: \.key) { source, reason in
                            Label("\(source.name): \(reason)", systemImage: "exclamationmark.triangle").font(.caption)
                        }
                        Text("Listings from \(LeadSearchSettings.enabled(enabledRaw).map(\.name).formatted(.list(type: .and))). Apply opens the original listing. Only your search words are sent.")
                    }
                }
            }

            if !leads.isEmpty {
                Section("Your pipeline") {
                    ForEach(leads) { lead in
                        NavigationLink { MissionDetailView(mission: lead) } label: { MissionRow(mission: lead) }
                    }
                }
            }

            Section {
                ForEach(MissionBoard.all) { board in
                    Button {
                        if let url = board.url(for: query) { browser.open(url) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: board.symbol).foregroundStyle(.tint).frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(board.name).foregroundStyle(.primary)
                                Text(board.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
                PasteButton(payloadType: URL.self) { urls in
                    if let url = urls.first { savingLead = makeLead(url: url) }
                }
            } header: {
                Text("More boards")
            } footer: {
                Text("Malt, LinkedIn and Free-Work have no public search API: they open in the browser. Copy a listing's link and paste it to save it as a lead.")
            }
        }
        .navigationTitle("Find missions")
        .searchable(text: $query, prompt: "Skills, role, technology")
        .onSubmit(of: .search) { Task { await search() } }
        .refreshable { await search() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search sources", systemImage: "slider.horizontal.3") { showsSettings = true }
            }
        }
        .sheet(isPresented: $showsSettings, onDismiss: { Task { await search() } }) { NavigationStack { LeadSearchSettingsView() } }
        .sheet(item: $savingLead) { MissionEditorView(mission: $0) }
        .task {
            if query.isEmpty { query = skills.prefix(2).joined(separator: " ") }
            if outcome == nil { await search() }
        }
        .onChange(of: freelanceOnly) { Task { await search() } }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    filterChip("Freelance & contract", "briefcase", isOn: $freelanceOnly)
                    filterChip("With a rate", "eurosign", isOn: $withRateOnly)
                    ForEach(skills.prefix(4), id: \.self) { skill in
                        Button {
                            query = skill
                            Task { await search() }
                        } label: {
                            Text(skill).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .selectableCapsule(query.caseInsensitiveCompare(skill) == .orderedSame)
                    }
                }
                .padding(.horizontal)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(_ title: LocalizedStringKey, _ symbol: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { isOn.wrappedValue.toggle() }
        } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .selectableCapsule(isOn.wrappedValue)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let configuration = LeadSearchConfiguration(enabled: LeadSearchSettings.enabled(enabledRaw),
                                                    braveKey: KeychainStore.get(LeadSearchSettings.braveAccount),
                                                    googleKey: KeychainStore.get(LeadSearchSettings.googleAccount),
                                                    googleEngineID: KeychainStore.get(LeadSearchSettings.googleEngineAccount))
        let result = await LeadSearchService.search(query, skills: skills, freelanceOnly: freelanceOnly, configuration: configuration)
        withAnimation { outcome = result }
    }

    private func save(_ lead: LeadResult) -> Mission {
        let mission = LeadImport.mission(from: lead, context: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return mission
    }

    private func makeLead(url: URL) -> Mission {
        let mission = Mission(title: "", status: .lead, rateCents: 0, startDate: .now.addingTimeInterval(86_400 * 30),
                              endDate: .now.addingTimeInterval(86_400 * 120))
        mission.sourceURL = url
        mission.source = url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        context.insert(mission)
        return mission
    }
}

/// Turns a parsed listing into a lead in the pipeline (client created or reused by name).
enum LeadImport {
    static func mission(from lead: LeadResult, context: ModelContext) -> Mission {
        let rate = lead.rate
        let mode: BillingMode = rate?.unit == .hour ? .hourly : .daily
        var cents = 0
        if let rate, rate.currency == "EUR" {
            cents = switch rate.unit {
            case .hour: rate.maxCents.map { ($0 + rate.minCents) / 2 } ?? rate.minCents
            default: rate.dailyCents
            }
        }
        let mission = Mission(title: lead.title, status: .lead, billingMode: mode, rateCents: cents,
                              startDate: .now.addingTimeInterval(86_400 * 21), endDate: .now.addingTimeInterval(86_400 * 111),
                              location: lead.isRemote ? .remote : .hybrid)
        mission.summary = lead.summary
        mission.source = lead.source.isWebSearch ? lead.location : lead.source.name
        mission.sourceURL = lead.url
        mission.symbol = "sparkle.magnifyingglass"
        mission.colorName = "purple"
        if !lead.company.isEmpty {
            let name = lead.company
            let existing = try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.name == name })).first
            mission.client = existing ?? {
                let client = Client(name: name)
                context.insert(client)
                return client
            }()
        }
        context.insert(mission)
        return mission
    }
}

struct LeadRow: View {
    var lead: LeadResult
    var match: Double
    var isSaved: Bool
    var targetDailyCents: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanyLogo(url: lead.logoURL, name: lead.company.isEmpty ? lead.location : lead.company)
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.title).font(.headline).lineLimit(2)
                Text([lead.company, lead.location].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if let rate = lead.rate {
                        OutlineCapsule(text: rate.formatted, gradient: rateGradient(rate))
                    }
                    if lead.contract == .freelance {
                        OutlineCapsule(text: String(localized: "Freelance"))
                    }
                    if match > 0 {
                        Text(match, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(match >= 0.5 ? Brand.positive : .secondary)
                            + Text(" match").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let posted = lead.postedAt { Text(posted, format: .relative(presentation: .named)) }
                    Text("· \(lead.source.name)")
                    if isSaved { Text("· Saved").foregroundStyle(.tint) }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Green when the listing pays at least the freelancer's target daily rate.
    private func rateGradient(_ rate: ParsedRate) -> LinearGradient {
        guard rate.currency == "EUR", targetDailyCents > 0 else { return Brand.gradient }
        return Brand.gradient(for: rate.dailyCents >= targetDailyCents ? Brand.positive : Brand.warning)
    }
}

struct CompanyLogo: View {
    var url: URL?
    var name: String
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().padding(4).background(.white)
            } else {
                ClientMonogram(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct LeadDetailView: View {
    @Environment(SafeBrowser.self) private var browser
    @Environment(SettingsStore.self) private var settings
    var lead: LeadResult
    var skills: [String]
    var isSaved: Bool
    var onSave: () -> Void
    @State private var saved = false

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    CompanyLogo(url: lead.logoURL, name: lead.company.isEmpty ? lead.location : lead.company, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lead.title).font(.title3.bold())
                        if !lead.company.isEmpty { Text(lead.company).font(.headline).foregroundStyle(.secondary) }
                    }
                }
                .padding(.vertical, 4)
                HStack(spacing: 10) {
                    Button { browser.open(lead.url) } label: {
                        Label("Apply on \(lead.source.isWebSearch ? lead.location : lead.source.name)", systemImage: "arrow.up.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.gradientCapsule)
                    Button {
                        onSave()
                        saved = true
                    } label: {
                        Label(isSaved || saved ? "Saved" : "Save as lead", systemImage: isSaved || saved ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.glass)
                    .disabled(isSaved || saved)
                }
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }

            Section("At a glance") {
                if let rate = lead.rate {
                    LabeledContent("Rate", value: rate.formatted)
                    if rate.currency == "EUR" {
                        let target = RateCalculator.recommend(settings.settings.rateInputs).dailyRateCents
                        LabeledContent("Per day (approx.)") {
                            Text(Money(cents: rate.dailyCents).formatted)
                                .foregroundStyle(rate.dailyCents >= target ? Brand.positive : Brand.warning)
                        }
                    }
                } else {
                    LabeledContent("Rate", value: String(localized: "Not stated"))
                }
                LabeledContent("Contract", value: lead.contract.title)
                LabeledContent("Location", value: lead.isRemote ? String(localized: "Remote · \(lead.location)") : lead.location)
                if let posted = lead.postedAt {
                    LabeledContent("Posted", value: posted.formatted(.relative(presentation: .named)))
                }
                let match = lead.match(skills: skills)
                if !skills.isEmpty {
                    LabeledContent("Matches your skills", value: match.formatted(.percent.precision(.fractionLength(0))))
                }
            }

            if !lead.tags.isEmpty {
                Section("Skills") {
                    FlowLayout {
                        ForEach(lead.tags, id: \.self) { tag in
                            SkillChip(text: tag, highlighted: skills.contains { $0.caseInsensitiveCompare(tag) == .orderedSame || tag.localizedCaseInsensitiveContains($0) })
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Description") {
                Text(lead.details.isEmpty ? lead.summary : lead.details)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            Section {
                Button { browser.open(lead.source.homepage) } label: {
                    Label("Listing from \(lead.source.name)", systemImage: "link")
                }
            } footer: {
                Text("Details are parsed from the listing and may be incomplete. Check the original before applying.")
            }
        }
        .navigationTitle(lead.company.isEmpty ? lead.title : lead.company)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: lead.url, subject: Text(lead.title)) { Label("Share", systemImage: "square.and.arrow.up") }
            }
        }
    }
}

// MARK: - Settings

enum LeadSearchSettings {
    static let enabledKey = "leads.providers.v1"
    static let defaultEnabled = "remotive,jobicy,himalayas,brave,google"
    static let braveAccount = "brave.apiKey"
    static let googleAccount = "google.apiKey"
    static let googleEngineAccount = "google.cx"

    static func enabled(_ raw: String) -> Set<LeadSource> {
        Set(raw.split(separator: ",").compactMap { LeadSource(rawValue: String($0)) })
    }
}

struct LeadSearchSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LeadSearchSettings.enabledKey) private var enabledRaw = LeadSearchSettings.defaultEnabled
    @State private var braveKey = KeychainStore.get(LeadSearchSettings.braveAccount) ?? ""
    @State private var googleKey = KeychainStore.get(LeadSearchSettings.googleAccount) ?? ""
    @State private var googleEngine = KeychainStore.get(LeadSearchSettings.googleEngineAccount) ?? ""

    var body: some View {
        Form {
            Section {
                ForEach(LeadSource.allCases.filter { !$0.needsAPIKey }) { source in toggle(source) }
            } header: {
                Text("Job boards")
            } footer: {
                Text("Free public APIs, no account needed. Mostly remote and international listings.")
            }

            Section {
                toggle(.google)
                SecureField("API key", text: $googleKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Search engine ID (cx)", text: $googleEngine).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Google Programmable Search")
            } footer: {
                Text("Searches Malt, Free-Work, LinkedIn Jobs and more across the web. Create a key and a search engine at programmablesearchengine.google.com.")
            }

            Section {
                toggle(.brave)
                SecureField("API key", text: $braveKey).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Brave Search")
            } footer: {
                Text("Independent web search with a free tier: api-dashboard.search.brave.com. Keys are stored in your Keychain, on this device only.")
            }
        }
        .navigationTitle("Search sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", role: .confirm) {
                    KeychainStore.set(braveKey.trimmingCharacters(in: .whitespaces), for: LeadSearchSettings.braveAccount)
                    KeychainStore.set(googleKey.trimmingCharacters(in: .whitespaces), for: LeadSearchSettings.googleAccount)
                    KeychainStore.set(googleEngine.trimmingCharacters(in: .whitespaces), for: LeadSearchSettings.googleEngineAccount)
                    dismiss()
                }
            }
        }
    }

    private func toggle(_ source: LeadSource) -> some View {
        Toggle(source.name, isOn: Binding(
            get: { LeadSearchSettings.enabled(enabledRaw).contains(source) },
            set: { on in
                var set = LeadSearchSettings.enabled(enabledRaw)
                if on { set.insert(source) } else { set.remove(source) }
                enabledRaw = LeadSource.allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
            }))
    }
}

/// Boards without a public API, opened in the in-app browser.
nonisolated struct MissionBoard: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var symbol: String
    var detail: String
    /// `{q}` is replaced by the encoded query.
    var template: String

    func url(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: template.replacingOccurrences(of: "{q}", with: encoded))
    }

    static let all: [MissionBoard] = [
        MissionBoard(name: "Malt", symbol: "m.circle.fill", detail: String(localized: "Freelance marketplace, France & Europe"),
                     template: "https://www.malt.fr/s?q={q}"),
        MissionBoard(name: "LinkedIn", symbol: "person.crop.square.fill", detail: String(localized: "Freelance & contract jobs"),
                     template: "https://www.linkedin.com/jobs/search/?keywords={q}&f_JT=C"),
        MissionBoard(name: "Free-Work", symbol: "laptopcomputer", detail: String(localized: "IT missions in France"),
                     template: "https://www.free-work.com/fr/tech-it/jobs?query={q}&contracts=contractor"),
        MissionBoard(name: "Welcome to the Jungle", symbol: "leaf.fill", detail: String(localized: "Startups and scale-ups"),
                     template: "https://www.welcometothejungle.com/fr/jobs?query={q}"),
        MissionBoard(name: "Codeur.com", symbol: "chevron.left.forwardslash.chevron.right", detail: String(localized: "Freelance projects in France"),
                     template: "https://www.codeur.com/projects?q={q}"),
    ]
}
