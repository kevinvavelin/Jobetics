import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            Group {
                if store.mode == .hiring { EmployerHomeView() } else { FreelancerHomeView() }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .toolbar {
                if store.isFreelancer {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Mode", selection: Binding(get: { store.mode }, set: { store.mode = $0 })) {
                                ForEach(MarketplaceStore.Mode.allCases) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Label("Mode", systemImage: store.mode == .hiring ? "person.2.fill" : "person.fill")
                        }
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Focus", systemImage: "timer") { router.sheet = .focus }
                }
            }
            .navigationDestination(for: JobPost.self) { JobDetailView(job: $0) }
            .refreshable { await store.load() }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let first = store.account?.displayName.split(separator: " ").first.map(String.init) ?? ""
        let base = switch hour {
        case 5..<12: String(localized: "Good morning")
        case 12..<18: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
        return first.isEmpty ? base : "\(base), \(first)"
    }
}

// MARK: - Freelancer

struct FreelancerHomeView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(FocusTimer.self) private var focus
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: #Predicate<BillingDocument> { $0.kindRaw == "invoice" }) private var invoices: [BillingDocument]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query(filter: #Predicate<Project> { !$0.isArchived }) private var projects: [Project]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) { MotivationCard(); stats }
                        if let profile = store.profile { ScoreCard(score: profile.score, signals: profile.signals) }
                    }
                } else {
                    MotivationCard()
                    if let profile = store.profile { ScoreCard(score: profile.score, signals: profile.signals) }
                    stats
                }
                UpNextSection()
                matchedJobs
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var stats: some View {
        let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let earned = ledger.filter { $0.kind == .income && $0.date >= monthStart }.reduce(0) { $0 + $1.amountCents }
        let outstanding = invoices.filter { $0.status == .sent || $0.status == .overdue }.reduce(0) { $0 + $1.total.cents }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(title: "Earned this month", value: Money(cents: earned).formatted, symbol: "eurosign.circle.fill", tint: Brand.positive)
            StatTile(title: "Awaiting payment", value: Money(cents: outstanding).formatted, symbol: "hourglass", tint: Brand.warning)
            StatTile(title: "Active projects", value: projects.count.formatted(), symbol: "folder.fill", tint: Brand.blue)
            StatTile(title: "Focus today", value: "\(focus.completedToday)/\(focus.settings.dailyGoal)", symbol: "timer", tint: Brand.violet)
        }
    }

    @ViewBuilder private var matchedJobs: some View {
        if !store.matchedJobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Matched for you") {
                    NavigationLink("See all") { JobsListContent() }
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.matchedJobs.prefix(6)) { job in
                            NavigationLink(value: job) {
                                JobCard(job: job, matchedSkills: Set(store.profile?.skills ?? []))
                                    .frame(width: 300)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
}

struct MotivationCard: View {
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))

            Text(Motivation.line())
                .font(.title2.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Gauge(value: focus.dailyProgress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.white)
                Text("\(focus.completedToday) of \(focus.settings.dailyGoal) focus sessions")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { BrandMesh(animated: !LaunchOptions.isScreenshotRun) }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ScoreCard: View {
    var score: FreelancerScore
    var signals: ScoreSignals

    var body: some View {
        NavigationLink {
            ScoreDetailView(score: score, signals: signals)
        } label: {
            Card {
                HStack(alignment: .center, spacing: 20) {
                    ScoreRing(score: score.overall, lineWidth: 12)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Freelancer score")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(score.tier.title, systemImage: score.tier.symbol)
                            .font(.title3.bold())
                            .foregroundStyle(Brand.gradient)
                        Text(ScoreDetailView.headline(for: score))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Divider()
                VStack(spacing: 14) {
                    MetricBar(title: "Responsiveness", symbol: "bolt.fill", value: score.responsiveness,
                              detail: ScoreDetailView.replyTime(signals.medianResponseMinutes), tint: Brand.cyan)
                    MetricBar(title: "On time for meetings", symbol: "calendar.badge.checkmark", value: score.punctuality,
                              detail: ScoreDetailView.ratio(signals.meetingsAttended, signals.meetingsTotal), tint: Brand.blue)
                    MetricBar(title: "Delivered on time", symbol: "shippingbox.fill", value: score.delivery,
                              detail: ScoreDetailView.ratio(signals.deliveredOnTime, signals.deliveredTotal), tint: Brand.indigo)
                    MetricBar(title: "Client rating", symbol: "star.fill", value: score.satisfaction,
                              detail: signals.averageRating.formatted(.number.precision(.fractionLength(1))) + " ★", tint: Brand.violet)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct UpNextSection: View {
    @Query(filter: #Predicate<Meeting> { $0.onTime == nil }, sort: \Meeting.date) private var meetings: [Meeting]
    @Query(sort: \BoardTask.dueDate) private var tasks: [BoardTask]

    private var upcomingTasks: [BoardTask] {
        tasks.filter { $0.status != .done && $0.dueDate != nil }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Up next")
            Card(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(meetings.filter { $0.date > .now }.prefix(2)) { meeting in
                        row(symbol: "video.fill", tint: Color.named(meeting.project?.colorName ?? ""), title: meeting.title,
                            subtitle: meeting.project?.clientName ?? "",
                            trailing: Text(meeting.date, format: .relative(presentation: .named)))
                        Divider().padding(.leading, 60)
                    }
                    ForEach(upcomingTasks) { task in
                        row(symbol: task.status.symbol, tint: Color.named(task.project?.colorName ?? ""), title: task.title,
                            subtitle: task.project?.name ?? "",
                            trailing: Text(task.dueDate ?? .now, format: .dateTime.day().month(.abbreviated)))
                        if task.id != upcomingTasks.last?.id { Divider().padding(.leading, 60) }
                    }
                }
            }
        }
    }

    private func row(symbol: String, tint: Color, title: String, subtitle: String, trailing: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            trailing.font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Employer

struct EmployerHomeView: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var candidates: [String: [PublicProfile]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "eye.slash.fill")
                            .font(.title2)
                            .foregroundStyle(Brand.gradient)
                        Text("Candidates are anonymous: you see skills and reputation. Names and contact details are shared only when you both accept.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.myJobs.isEmpty {
                    ContentUnavailableView {
                        Label("No jobs posted yet", systemImage: "briefcase")
                    } description: {
                        Text("Post a paid job and we'll recommend matching freelancers.")
                    } actions: {
                        Button("Post a job") { router.sheet = .postJob }.buttonStyle(.glassProminent)
                    }
                }

                ForEach(store.myJobs) { job in
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink(value: job) { PostedJobRow(job: job) }.buttonStyle(.plain)
                        if let list = candidates[job.id], !list.isEmpty {
                            Text("Recommended candidates")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 12) {
                                    ForEach(list) { CandidateCard(profile: $0, job: job).frame(width: 290) }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button { router.sheet = .postJob } label: {
                Label("Post a job", systemImage: "plus").font(.headline).padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.bottom, 8)
        }
        .task(id: store.myJobs.map(\.id)) {
            for job in store.myJobs where candidates[job.id] == nil {
                candidates[job.id] = (try? await store.backend.candidates(for: job, limit: 6)) ?? []
            }
        }
    }
}

struct PostedJobRow: View {
    var job: JobPost

    var body: some View {
        Card {
            HStack(alignment: .top) {
                Image(systemName: job.discipline.symbol)
                    .foregroundStyle(job.discipline.tint)
                    .frame(width: 40, height: 40)
                    .background(job.discipline.tint.opacity(0.14), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title).font(.headline).lineLimit(2)
                    Text("\(job.budget.formatted) · \(job.status.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(job.proposalCount, format: .number).font(.title2.bold())
                    Text("proposals").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CandidateCard: View {
    @Environment(MarketplaceStore.self) private var store
    @Environment(AppRouter.self) private var router
    var profile: PublicProfile
    var job: JobPost
    @State private var requested = false

    var body: some View {
        Card {
            HStack(spacing: 12) {
                AnonymousAvatar(seed: profile.id, symbol: profile.discipline.symbol, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.handle).font(.headline)
                    Text(profile.region).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ScoreRing(score: profile.score.overall, lineWidth: 5)
                    .frame(width: 48, height: 48)
            }
            Text(profile.headline)
                .font(.subheadline)
                .lineLimit(2, reservesSpace: true)
            FlowLayout {
                ForEach(profile.skills.prefix(5), id: \.self) { skill in
                    SkillChip(text: skill, highlighted: job.skills.contains { $0.caseInsensitiveCompare(skill) == .orderedSame })
                }
            }
            HStack(spacing: 10) {
                ForEach(profile.verifiedLinks, id: \.self) { kind in
                    Label(kind.title, systemImage: "checkmark.seal.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.positive)
                }
                Spacer()
                if let rate = profile.hourlyRate {
                    Text("\(rate.formatted)/h").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Message", systemImage: "bubble.left.fill") {
                    Task {
                        let handles = [store.me: String(localized: "Employer"), profile.id: profile.handle]
                        if let c = try? await store.backend.startConversation(with: profile.id, handles: handles, job: job) {
                            router.tab = .messages
                            router.messagesPath = [c]
                        }
                    }
                }
                .buttonStyle(.glass)
                Spacer()
                Button(requested ? "Requested" : "Request contact", systemImage: requested ? "checkmark" : "person.badge.key.fill") {
                    Task {
                        _ = try? await store.backend.requestContact(with: profile.id)
                        requested = true
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(requested)
            }
            .controlSize(.small)
            .font(.caption.weight(.semibold))
        }
    }
}

// MARK: - Score detail

struct ScoreDetailView: View {
    var score: FreelancerScore
    var signals: ScoreSignals

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ScoreRing(score: score.overall, lineWidth: 18).frame(width: 200, height: 200)
                    Label(score.tier.title, systemImage: score.tier.symbol).font(.title2.bold()).foregroundStyle(Brand.gradient)
                    Text(Self.headline(for: score)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            Section("What it's made of") {
                tip("Responsiveness", "bolt.fill", score.responsiveness, "25%",
                    String(localized: "Median reply time: \(Self.replyTime(signals.medianResponseMinutes)). Replying within 30 minutes gives the full score."))
                tip("On time for meetings", "calendar.badge.checkmark", score.punctuality, "20%",
                    String(localized: "\(signals.meetingsAttended) of \(signals.meetingsTotal) meetings joined on time."))
                tip("Delivered on time", "shippingbox.fill", score.delivery, "25%",
                    String(localized: "\(signals.deliveredOnTime) of \(signals.deliveredTotal) milestones delivered by the due date."))
                tip("Client rating", "star.fill", score.satisfaction, "20%",
                    String(localized: "\(signals.averageRating.formatted(.number.precision(.fractionLength(1)))) average from \(signals.ratingCount) reviews."))
                tip("Profile completeness", "person.text.rectangle.fill", score.completeness, "10%",
                    String(localized: "Add your links, skills and portfolio to reach 100%."))
            }
            Section {
                Text("Scores are calculated by Jobetics from verified activity: message timestamps, meeting check-ins, delivered milestones and client reviews. New freelancers start from a fair baseline that adjusts as they complete jobs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Your score")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tip(_ title: LocalizedStringKey, _ symbol: String, _ value: Double, _ weight: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0))).font(.headline.monospacedDigit())
            }
            Gauge(value: value) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(Brand.gradient)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            Text("Weight: \(weight)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    static func headline(for score: FreelancerScore) -> String {
        switch score.tier {
        case .topRated: String(localized: "Clients love working with you. Keep it up!")
        case .trusted: String(localized: "You're a reliable pro. A few more five-star jobs to reach Top Rated.")
        case .established: String(localized: "Solid start. Reply faster and deliver on time to climb.")
        case .rising: String(localized: "Complete your profile and your first jobs to grow your score.")
        }
    }

    static func replyTime(_ minutes: Double) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    static func ratio(_ a: Int, _ b: Int) -> String {
        guard b > 0 else { return "–" }
        return (Double(a) / Double(b)).formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Bottom accessory

struct NextUpAccessory: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Meeting> { $0.onTime == nil }, sort: \Meeting.date) private var meetings: [Meeting]

    var body: some View {
        Button { router.sheet = .focus } label: {
            HStack(spacing: 10) {
                Image(systemName: focus.session.isIdle ? "timer" : focus.phase.symbol)
                    .foregroundStyle(Brand.gradient)
                    .symbolEffect(.pulse, isActive: focus.session.isRunning)
                if let end = focus.session.endDate {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(focus.session.taskTitle ?? focus.phase.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(focus.phase.title).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: 64, alignment: .trailing)
                } else if let next = meetings.first(where: { $0.date > .now }) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(next.date, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Start focus").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                } else {
                    Text("Start a focus session").font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
