import Charts
import SwiftData
import SwiftUI

/// A private work journal: what you did, the energy it took and the impact it had.
/// Meaning grows from noticing it. Any entry can become a LinkedIn post (500 characters max).
struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var editing: JournalEntry?
    @State private var sharing: JournalEntry?

    var body: some View {
        List {
            if !entries.isEmpty {
                Section { summary }
            }
            ForEach(entries) { entry in
                Button { editing = entry } label: { JournalRow(entry: entry) }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .leading) {
                        Button("Share on LinkedIn", systemImage: "square.and.arrow.up") { sharing = entry }.tint(Brand.blue)
                    }
                    .contextMenu {
                        Button("Share on LinkedIn", systemImage: "square.and.arrow.up") { sharing = entry }
                    }
            }
            .onDelete { offsets in offsets.map { entries[$0] }.forEach(context.delete) }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Your work journal", systemImage: "book.closed")
                } description: {
                    Text("A few lines a day about what you did and why it mattered. Only you can read it.")
                } actions: {
                    Button("Write today's entry") { editing = newEntry() }.buttonStyle(.gradientCapsule)
                }
            }
        }
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New entry", systemImage: "square.and.pencil") { editing = newEntry() }
            }
        }
        .sheet(item: $editing) { JournalEditorView(entry: $0) }
        .sheet(item: $sharing) { LinkedInComposerView(entry: $0) }
    }

    private func newEntry() -> JournalEntry {
        if let today = entries.first(where: { Calendar.current.isDateInToday($0.date) }) { return today }
        let entry = JournalEntry(text: "")
        context.insert(entry)
        return entry
    }

    private var streak: Int {
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: .now)
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private var summary: some View {
        let recent = entries.filter { $0.date > .now.addingTimeInterval(-86_400 * 30) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(streak)-day streak", systemImage: "flame.fill").foregroundStyle(.orange)
                Spacer()
                Text("Energy, last 30 days").font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            Chart(recent) { entry in
                LineMark(x: .value("Day", entry.date, unit: .day), y: .value("Energy", entry.energy))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Brand.violet)
                PointMark(x: .value("Day", entry.date, unit: .day), y: .value("Energy", entry.energy))
                    .foregroundStyle(Brand.violet)
            }
            .chartYScale(domain: 1...5)
            .chartYAxis { AxisMarks(values: [1, 3, 5]) }
            .frame(height: 90)
            .accessibilityLabel("Energy over the last 30 days")
        }
        .padding(.vertical, 4)
    }
}

struct JournalRow: View {
    var entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date, format: .dateTime.weekday(.wide).day().month())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                EnergyDots(value: entry.energy)
                if entry.sharedOnLinkedIn {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.blue).accessibilityLabel("Shared")
                }
            }
            Text(entry.text.isEmpty ? String(localized: "Empty entry") : entry.text)
                .font(.subheadline)
                .foregroundStyle(entry.text.isEmpty ? .tertiary : .primary)
                .lineLimit(3)
            if !entry.impact.isEmpty {
                Label(entry.impact, systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct EnergyDots: View {
    var value: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle().fill(i <= value ? AnyShapeStyle(Brand.violet) : AnyShapeStyle(.quaternary)).frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Energy \(value) out of 5")
    }
}

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var entry: JournalEntry
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you work on?") {
                    TextField("A few lines are enough", text: $entry.text, axis: .vertical)
                        .lineLimit(4...12)
                }
                Section {
                    TextField("Who did it help? What changed?", text: $entry.impact, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Why it mattered")
                } footer: {
                    Text("Writing down the impact of your work is one of the simplest ways to keep meaning in it.")
                }
                Section("Energy") {
                    Picker("Energy", selection: $entry.energy) {
                        ForEach(1...5, id: \.self) { level in
                            Image(systemName: ["battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent", "battery.100percent"][level - 1])
                                .accessibilityLabel("\(level) of 5")
                                .tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Turn into a LinkedIn post", systemImage: "square.and.arrow.up") { sharing = true }
                        .disabled(entry.text.isEmpty)
                }
            }
            .navigationTitle(Text(entry.date, format: .dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        if entry.text.isEmpty && entry.impact.isEmpty { context.delete(entry) }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $sharing) { LinkedInComposerView(entry: entry) }
        }
    }
}

/// Drafts a LinkedIn post (500 characters max) from a journal entry, with Apple Intelligence when available.
struct LinkedInComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var entry: JournalEntry
    @State private var text = ""
    @State private var hashtags = "freelance"
    @State private var isWriting = false

    private var tags: [String] { hashtags.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init).filter { !$0.isEmpty } }
    private var remaining: Int { SocialShare.linkedInLimit - text.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .onChange(of: text) { _, new in
                            if new.count > SocialShare.linkedInLimit { text = String(new.prefix(SocialShare.linkedInLimit)) }
                        }
                } header: {
                    Text("Post")
                } footer: {
                    HStack {
                        Text(WritingAssistant.isAvailable ? "Drafted on your device with Apple Intelligence. Nothing is sent until you post." : "Edit freely before posting.")
                        Spacer()
                        Text("\(remaining)")
                            .monospacedDigit()
                            .foregroundStyle(remaining < 30 ? Brand.warning : .secondary)
                            .accessibilityLabel("\(remaining) characters left")
                    }
                }
                Section("Hashtags") {
                    TextField("freelance, swiftui", text: $hashtags).textInputAutocapitalization(.never)
                }
                Section {
                    Button("Rewrite", systemImage: "sparkles") { Task { await draft() } }
                        .disabled(isWriting)
                    ShareLink(item: text) { Label("More options", systemImage: "square.and.arrow.up") }
                }
            }
            .overlay { if isWriting { ProgressView("Writing…").padding().glassEffect(in: .rect(cornerRadius: 16)) } }
            .navigationTitle("LinkedIn post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post", role: .confirm) {
                        UIPasteboard.general.string = text
                        if let url = SocialShare.linkedInComposeURL(text: text) { openURL(url) }
                        entry.sharedOnLinkedIn = true
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                }
            }
            .task { if text.isEmpty { await draft() } }
        }
    }

    private func draft() async {
        isWriting = true
        text = await WritingAssistant.linkedInPost(from: entry.text, impact: entry.impact, hashtags: tags)
        isWriting = false
    }
}
