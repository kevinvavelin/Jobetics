import SwiftUI

struct JobsView: View {
    @Environment(AppRouter.self) private var router
    @State private var layout: Layout = .list

    enum Layout: String, CaseIterable { case list, calendar }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.jobsPath) {
            Group {
                switch layout {
                case .list: JobsListContent()
                case .calendar: JobCalendarView()
                }
            }
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Layout", selection: $layout) {
                        Label("List", systemImage: "list.bullet").tag(Layout.list)
                        Label("Calendar", systemImage: "calendar").tag(Layout.calendar)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post a job", systemImage: "plus") { router.sheet = .postJob }
                }
            }
            .navigationDestination(for: JobPost.self) { JobDetailView(job: $0) }
        }
    }
}

struct JobsListContent: View {
    @Environment(MarketplaceStore.self) private var store
    @State private var query = ""
    @State private var discipline: Discipline?

    private var jobs: [JobPost] {
        store.matchedJobs.filter { job in
            (discipline == nil || job.discipline == discipline)
                && (query.isEmpty || job.title.localizedStandardContains(query)
                    || job.skills.contains { $0.localizedStandardContains(query) })
        }
    }

    var body: some View {
        Group {
            if !store.isFreelancer {
                ContentUnavailableView {
                    Label("Jobs are for freelancers", systemImage: "lock.fill")
                } description: {
                    Text("Register as a freelancer in your profile (LinkedIn required) to browse and answer jobs. Anyone can post a job.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12, pinnedViews: .sectionHeaders) {
                        Section {
                            ForEach(jobs) { job in
                                NavigationLink(value: job) {
                                    JobCard(job: job, matchedSkills: Set(store.profile?.skills ?? []))
                                }
                                .buttonStyle(.plain)
                            }
                            if jobs.isEmpty {
                                ContentUnavailableView.search(text: query).padding(.top, 40)
                            }
                        } header: {
                            filters
                        }
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground))
                .searchable(text: $query, prompt: "Skills, titles…")
                .refreshable { await store.load() }
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(nil, title: String(localized: "All"), symbol: "square.grid.2x2")
                    ForEach(Discipline.allCases) { chip($0, title: $0.title, symbol: $0.symbol) }
                }
                .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(_ value: Discipline?, title: String, symbol: String) -> some View {
        let selected = discipline == value
        return Button {
            withAnimation(.snappy) { discipline = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : .primary)
        .glassEffect(selected ? .regular.tint(Brand.indigo).interactive() : .regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct JobCard: View {
    var job: JobPost
    var matchedSkills: Set<String> = []

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: job.discipline.symbol)
                    .font(.headline)
                    .foregroundStyle(job.discipline.tint)
                    .frame(width: 40, height: 40)
                    .background(job.discipline.tint.opacity(0.14), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if job.employer.reviewCount > 0 {
                            StarRating(value: job.employer.overall, size: .caption2)
                            Text("(\(job.employer.reviewCount))").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("New employer").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(job.budget.formatted)
                    .font(.title3.bold())
                    .foregroundStyle(Brand.gradient)
                Text(job.pricing == .hourly ? String(localized: "/ hour") : String(localized: "fixed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if job.isRemote {
                    Label("Remote", systemImage: "globe.europe.africa.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            FlowLayout {
                ForEach(job.skills.prefix(4), id: \.self) { skill in
                    SkillChip(text: skill, highlighted: matchedSkills.contains { $0.caseInsensitiveCompare(skill) == .orderedSame })
                }
            }
            HStack {
                Text(job.createdAt, format: .relative(presentation: .named))
                Spacer()
                Label("\(job.proposalCount)", systemImage: "person.2.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct JobDetailView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var job: JobPost
    @State private var showsProposal = false
    @State private var showsReport = false
    @State private var showsReview = false
    @State private var proposalSent = false

    private var isMine: Bool { job.ownerId == store.me }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(job.discipline.title, systemImage: job.discipline.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(job.discipline.tint)
                    Text(job.title).font(.largeTitle.bold())
                    HStack(alignment: .firstTextBaseline) {
                        Text(job.budget.formatted).font(.title.bold()).foregroundStyle(Brand.gradient)
                        Text(job.pricing.title).foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    StatTile(title: "Starts", value: job.startDate.formatted(.dateTime.day().month()), symbol: "play.circle.fill", tint: Brand.blue)
                    StatTile(title: "Due", value: job.dueDate.formatted(.dateTime.day().month()), symbol: "flag.checkered", tint: Brand.violet)
                    StatTile(title: "Proposals", value: job.proposalCount.formatted(), symbol: "person.2.fill", tint: .teal)
                    StatTile(title: "Location", value: job.isRemote ? String(localized: "Remote") : String(localized: "On site"), symbol: "mappin.and.ellipse", tint: .orange)
                }

                Card {
                    Text("About the job").font(.headline)
                    Text(job.summary).font(.body)
                    FlowLayout {
                        ForEach(job.skills, id: \.self) { SkillChip(text: $0, highlighted: store.profile?.skills.contains($0) == true) }
                    }
                }

                Card {
                    HStack {
                        Text("Employer reputation").font(.headline)
                        Spacer()
                        Text("\(job.employer.reviewCount) reviews").font(.caption).foregroundStyle(.secondary)
                    }
                    if job.employer.reviewCount == 0 {
                        Text("This employer hasn't been reviewed yet.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        MetricBar(title: "Clear brief", symbol: "text.page.fill", value: job.employer.clarity / 5,
                                  detail: job.employer.clarity.formatted(.number.precision(.fractionLength(1))))
                        MetricBar(title: "Communication", symbol: "bubble.left.and.bubble.right.fill", value: job.employer.communication / 5,
                                  detail: job.employer.communication.formatted(.number.precision(.fractionLength(1))))
                        MetricBar(title: "Pays on time", symbol: "eurosign.circle.fill", value: job.employer.payment / 5,
                                  detail: job.employer.payment.formatted(.number.precision(.fractionLength(1))), tint: Brand.positive)
                    }
                    Label("Employer identity is shared once you both accept contact.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    ShareLink(item: URL(string: "jobetics://jobs/\(job.id)")!, subject: Text(job.title))
                    if !isMine {
                        Button("Review employer", systemImage: "star.bubble") { showsReview = true }
                        Button("Report job", systemImage: "flag", role: .destructive) { showsReport = true }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isMine && store.isFreelancer {
                Button { showsProposal = true } label: {
                    Label(proposalSent ? "Proposal sent" : "Send a proposal", systemImage: proposalSent ? "checkmark" : "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: 400)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(proposalSent)
                .padding()
            }
        }
        .sheet(isPresented: $showsProposal) { ProposalSheet(job: job) { proposalSent = true } }
        .sheet(isPresented: $showsReport) {
            ReportSheet(kind: .job, targetId: job.id, ownerId: job.ownerId, excerpt: job.title + " — " + job.summary)
        }
        .sheet(isPresented: $showsReview) { ReviewEmployerView(job: job) }
    }
}

struct ProposalSheet: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var job: JobPost
    var onSent: () -> Void
    @State private var note = ""
    @State private var price: Double
    @State private var isSending = false
    @State private var error: String?

    init(job: JobPost, onSent: @escaping () -> Void) {
        self.job = job
        self.onSent = onSent
        _price = State(initialValue: job.budget.amount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Why are you a great fit? Share relevant work from your portfolio.", text: $note, axis: .vertical)
                        .lineLimit(6...12)
                } header: {
                    Text("Cover note")
                } footer: {
                    Text("Your name and contact details stay hidden until you both accept.")
                }
                Section(job.pricing == .hourly ? "Your hourly rate" : "Your price") {
                    TextField("Price", value: $price, format: .currency(code: job.budget.currency))
                        .keyboardType(.decimalPad)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger) }
                }
            }
            .navigationTitle("Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", role: .confirm) { send() }
                        .disabled(note.count < 20 || price <= 0 || isSending)
                }
            }
        }
    }

    private func send() {
        isSending = true
        Task {
            do {
                try await store.submitProposal(to: job, note: note, price: Money(price, currency: job.budget.currency))
                onSent()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }
}
