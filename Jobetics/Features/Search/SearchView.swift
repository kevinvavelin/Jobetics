import SwiftData
import SwiftUI

/// Quick search across jobs, conversations, projects, tasks, invoices and portfolio.
struct SearchView: View {
    var embedded = false
    @Environment(MarketplaceStore.self) private var store
    @Query private var tasks: [BoardTask]
    @Query private var documents: [BillingDocument]
    @Query private var portfolio: [PortfolioItem]
    @State private var query = ""

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        List {
            if query.isEmpty {
                Section("Suggestions") {
                    ForEach(store.profile?.skills.prefix(5) ?? [], id: \.self) { skill in
                        Button { query = skill } label: { Label(skill, systemImage: "magnifyingglass") }
                    }
                }
            } else {
                let jobs = store.openJobs.filter { $0.title.localizedStandardContains(query) || $0.skills.contains { $0.localizedStandardContains(query) } }
                if !jobs.isEmpty {
                    Section("Jobs") {
                        ForEach(jobs) { job in
                            NavigationLink { JobDetailView(job: job) } label: {
                                Label { Text(job.title) } icon: { Image(systemName: job.discipline.symbol).foregroundStyle(job.discipline.tint) }
                            }
                        }
                    }
                }
                let chats = store.conversations.filter { ($0.jobTitle ?? "").localizedStandardContains(query) || $0.lastMessage.localizedStandardContains(query) }
                if !chats.isEmpty {
                    Section("Messages") {
                        ForEach(chats) { c in NavigationLink { ChatView(conversation: c) } label: { Label(c.jobTitle ?? c.lastMessage, systemImage: "bubble.left.fill") } }
                    }
                }
                let matchingTasks = tasks.filter { $0.title.localizedStandardContains(query) }
                if !matchingTasks.isEmpty {
                    Section("Tasks") {
                        ForEach(matchingTasks) { t in
                            Label { VStack(alignment: .leading) { Text(t.title); Text(t.project?.name ?? "").font(.caption).foregroundStyle(.secondary) } }
                                icon: { Image(systemName: t.status.symbol) }
                        }
                    }
                }
                let docs = documents.filter { $0.clientName.localizedStandardContains(query) || $0.number.localizedStandardContains(query) }
                if !docs.isEmpty {
                    Section("Invoices & quotes") {
                        ForEach(docs) { d in NavigationLink { BillingDetailView(document: d) } label: { BillingRow(document: d) } }
                    }
                }
                let works = portfolio.filter { $0.title.localizedStandardContains(query) || $0.tags.contains { $0.localizedStandardContains(query) } }
                if !works.isEmpty {
                    Section("Portfolio") {
                        ForEach(works) { w in NavigationLink { PortfolioDetailView(item: w) } label: { Label(w.title, systemImage: "photo") } }
                    }
                }
                if jobs.isEmpty && chats.isEmpty && matchingTasks.isEmpty && docs.isEmpty && works.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, placement: embedded ? .automatic : .toolbar, prompt: "Jobs, clients, tasks, invoices…")
        .navigationTitle("Search")
    }
}
