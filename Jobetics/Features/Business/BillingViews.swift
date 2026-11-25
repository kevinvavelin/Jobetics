import SwiftData
import SwiftUI

struct BillingListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings
    let kind: BillingKind
    @Query private var documents: [BillingDocument]
    @State private var editing: BillingDocument?
    @State private var filter: BillingStatus?

    init(kind: BillingKind) {
        self.kind = kind
        let raw = kind.rawValue
        // Credit notes are listed with the invoices they cancel.
        let companion = kind == .invoice ? BillingKind.creditNote.rawValue : raw
        _documents = Query(filter: #Predicate<BillingDocument> { $0.kindRaw == raw || $0.kindRaw == companion },
                           sort: \BillingDocument.issueDate, order: .reverse)
    }

    private var filtered: [BillingDocument] { documents.filter { filter == nil || $0.status == filter } }

    var body: some View {
        List {
            Section {
                summary.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                ForEach(filtered) { doc in
                    NavigationLink { BillingDetailView(document: doc) } label: { BillingRow(document: doc) }
                        .swipeActions {
                            // Issued invoices are legal records: only drafts and quotes can be deleted.
                            if doc.isDeletable {
                                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(doc) }
                            }
                        }
                }
            }
        }
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView("No \(kind.plural.lowercased()) yet", systemImage: kind.symbol)
            }
        }
        .navigationTitle(kind.plural)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Filter", systemImage: "line.3.horizontal.decrease") {
                    Picker("Status", selection: $filter) {
                        Text("All").tag(BillingStatus?.none)
                        ForEach(statuses) { Label($0.title, systemImage: $0.symbol).tag(BillingStatus?.some($0)) }
                    }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("New \(kind.title.lowercased())", systemImage: "plus") { editing = makeNew() }
            }
        }
        .sheet(item: $editing) { BillingEditorView(document: $0) }
    }

    private var statuses: [BillingStatus] {
        kind == .invoice ? [.draft, .sent, .paid, .overdue] : [.draft, .sent, .accepted, .declined]
    }

    private var summary: some View {
        let open = documents.filter { $0.status == .sent || $0.status == .overdue }
        let primary = kind == .invoice
            ? documents.filter { $0.status == .paid }.reduce(0) { $0 + $1.total.cents }
            : documents.filter { $0.status == .accepted }.reduce(0) { $0 + $1.total.cents }
        return HStack(spacing: 12) {
            StatTile(title: kind == .invoice ? "Paid" : "Accepted", value: Money(cents: primary).formatted,
                     symbol: "checkmark.circle.fill", tint: Brand.positive)
            StatTile(title: kind == .invoice ? "Awaiting payment" : "Awaiting answer",
                     value: Money(cents: open.reduce(0) { $0 + $1.total.cents }).formatted, symbol: "hourglass", tint: Brand.warning)
        }
    }

    private func makeNew() -> BillingDocument {
        // Quotes get their number right away. Invoices get the next legal number only when issued,
        // so abandoned drafts never leave a gap in the sequence.
        let number = kind == .quote ? settings.nextNumber(for: .quote) : ""
        let doc = BillingDocument(kind: kind, number: number, clientName: "", dueDate: .now.addingTimeInterval(86_400 * 30),
                                  taxRate: settings.settings.vatExempt ? 0 : settings.settings.defaultVATRate)
        context.insert(doc)
        return doc
    }
}

struct BillingRow: View {
    var document: BillingDocument

    var body: some View {
        let status = document.isOverdue ? .overdue : document.status
        HStack(spacing: 12) {
            Image(systemName: document.kind == .creditNote ? BillingKind.creditNote.symbol : status.symbol)
                .font(.title2)
                .foregroundStyle(document.kind == .creditNote ? Color.secondary : color(for: status))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.clientName.isEmpty ? String(localized: "New client") : document.clientName).font(.headline)
                Text("\(document.displayNumber) · \(document.issueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(document.total.formatted).font(.headline.monospacedDigit())
                Text(document.kind == .creditNote ? document.kind.title : document.isCancelled ? String(localized: "Cancelled") : status.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(document.kind == .creditNote || document.isCancelled ? Color.secondary : color(for: status))
            }
        }
        .padding(.vertical, 2)
    }

    func color(for status: BillingStatus) -> Color {
        switch status {
        case .paid, .accepted: Brand.positive
        case .overdue, .declined: Brand.danger
        case .sent: Brand.blue
        case .draft: .secondary
        }
    }
}

struct BillingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(SettingsStore.self) private var settings
    @Bindable var document: BillingDocument
    @State private var editing = false
    @State private var pdfURL: URL?
    @State private var confirmsCancel = false
    @State private var isDraftingReminder = false

    var body: some View {
        ScrollView {
            BillingPaper(document: document, business: settings.settings)
                .background(.white, in: .rect(cornerRadius: 6))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                .frame(maxWidth: 595)
                .padding()
                .environment(\.colorScheme, .light)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(document.displayNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if document.isDeletable || document.kind == .quote {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if let pdfURL {
                    ShareLink(item: pdfURL, subject: Text("\(document.kind.title) \(document.number)"),
                              message: Text("Please find attached \(document.kind.title.lowercased()) \(document.number).")) {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .sheet(isPresented: $editing) { BillingEditorView(document: document) }
        .task(id: "\(document.total.cents)-\(document.number)-\(document.statusRaw)") { pdfURL = BillingPDF.render(document, settings: settings.settings) }
        .confirmationDialog("Cancel this invoice?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Issue a credit note", role: .destructive) { issueCreditNote() }
        } message: {
            Text("An issued invoice can't be deleted. A credit note with the opposite amount cancels it and keeps your numbering legal.")
        }
    }

    @ViewBuilder private var actions: some View {
        GlassEffectContainer {
            HStack {
                switch (document.kind, document.status) {
                case (.invoice, .sent), (.invoice, .overdue):
                    if !document.isCancelled {
                        if document.isOverdue {
                            Button("Remind", systemImage: "bell.badge") { Task { await sendReminder() } }
                                .buttonStyle(.glass)
                                .disabled(isDraftingReminder)
                        }
                        Menu("More", systemImage: "ellipsis") {
                            Button("Cancel with a credit note", systemImage: BillingKind.creditNote.symbol, role: .destructive) { confirmsCancel = true }
                        }
                        .buttonStyle(.glass)
                        Button("Mark as paid", systemImage: "checkmark.circle.fill") { markPaid() }.buttonStyle(.gradientCapsule)
                    }
                case (.quote, .sent):
                    Button("Declined", systemImage: "xmark") { document.status = .declined }.buttonStyle(.glass)
                    Button("Accepted", systemImage: "hand.thumbsup.fill") { document.status = .accepted }.buttonStyle(.gradientCapsule)
                case (.quote, .accepted):
                    Button("Convert to invoice", systemImage: "arrow.right.doc.on.clipboard") { convert() }.buttonStyle(.gradientCapsule)
                case (.invoice, .draft):
                    Button("Issue invoice", systemImage: "checkmark.seal.fill") { issue() }
                        .buttonStyle(.gradientCapsule)
                        .disabled(document.clientName.isEmpty || document.items.isEmpty)
                case (_, .draft):
                    Button("Mark as sent", systemImage: "paperplane.fill") {
                        document.status = .sent
                        document.sentAt = .now
                    }.buttonStyle(.gradientCapsule)
                default:
                    EmptyView()
                }
            }
            .controlSize(.large)
        }
        .padding()
    }

    /// Assigns the next legal number and freezes the invoice.
    private func issue() {
        if document.number.isEmpty { document.number = settings.nextNumber(for: .invoice) }
        document.issueDate = .now
        document.status = .sent
        document.sentAt = .now
    }

    private func markPaid() {
        document.status = .paid
        document.paidAt = .now
        context.insert(LedgerEntry(date: .now, amountCents: document.total.cents, kind: .income, category: "Client work",
                                   counterparty: document.clientName, invoiceNumber: document.number))
    }

    private func issueCreditNote() {
        let note = BillingDocument(kind: .creditNote, number: settings.nextNumber(for: .creditNote), clientName: document.clientName,
                                   clientEmail: document.clientEmail, dueDate: .now, status: .paid, taxRate: document.taxRate)
        note.clientAddress = document.clientAddress
        note.relatedNumber = document.number
        note.notes = String(localized: "Cancels invoice \(document.number).")
        context.insert(note)
        for item in document.items {
            let copy = LineItem(title: item.title, quantity: -item.quantity, unitPriceCents: item.unitPriceCents, order: item.order)
            copy.document = note
            context.insert(copy)
        }
        document.relatedNumber = note.number
    }

    private func sendReminder() async {
        isDraftingReminder = true
        defer { isDraftingReminder = false }
        let s = settings.settings
        let penalty = Money(cents: TaxMath.latePenalty(amountCents: document.total.cents, daysLate: document.daysLate,
                                                       yearlyRate: s.latePaymentRate)).formatted
        let body = await WritingAssistant.paymentReminder(client: document.clientName, number: document.number, amount: document.total.formatted,
                                                          daysLate: document.daysLate, reminderIndex: document.remindersSent,
                                                          penalty: penalty, sender: s.displayName)
        guard let url = SocialShare.mailURL(to: document.clientEmail, subject: String(localized: "Invoice \(document.number)"), body: body) else { return }
        document.remindersSent += 1
        document.status = .overdue
        openURL(url)
    }

    private func convert() {
        // The invoice starts as a draft: it gets its legal number when issued.
        let invoice = BillingDocument(kind: .invoice, number: "",
                                      clientName: document.clientName, clientEmail: document.clientEmail,
                                      dueDate: .now.addingTimeInterval(86_400 * 30), taxRate: document.taxRate)
        invoice.clientAddress = document.clientAddress
        invoice.missionTitle = document.missionTitle
        invoice.relatedNumber = nil
        invoice.notes = String(localized: "Quote \(document.number) accepted.")
        context.insert(invoice)
        for item in document.items {
            let copy = LineItem(title: item.title, quantity: item.quantity, unitPriceCents: item.unitPriceCents, order: item.order)
            copy.document = invoice
            context.insert(copy)
        }
        document.status = .paid // quote fulfilled → converted
    }
}

/// A4 document layout, used both on screen and for the PDF.
struct BillingPaper: View {
    var document: BillingDocument
    var business: BusinessSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(business.displayName).font(.title3.bold())
                    if !business.tradeName.isEmpty && business.tradeName != business.legalName {
                        Text(business.legalName).font(.caption)
                    }
                    Text(business.address).font(.caption)
                    Text([business.email, business.phone].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption)
                    if !business.siret.isEmpty { Text("SIRET \(business.siret)").font(.caption) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(document.kind.title.uppercased()).font(.title2.weight(.heavy)).foregroundStyle(Brand.indigo)
                    Text(document.displayNumber).font(.caption.monospaced())
                    if let related = document.relatedNumber, document.kind == .creditNote {
                        Text("Cancels \(related)").font(.caption2)
                    }
                    if !document.missionTitle.isEmpty { Text(document.missionTitle).font(.caption2) }
                }
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bill to").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(document.clientName).font(.subheadline.weight(.semibold))
                    Text(document.clientAddress).font(.caption)
                    Text(document.clientEmail).font(.caption)
                }
                Spacer()
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Issued").foregroundStyle(.secondary); Text(document.issueDate, format: .dateTime.day().month().year()) }
                    GridRow {
                        Text(document.kind == .invoice ? "Due" : "Valid until").foregroundStyle(.secondary)
                        Text(document.dueDate, format: .dateTime.day().month().year())
                    }
                }
                .font(.caption)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Qty").frame(width: 44, alignment: .trailing)
                    Text("Unit").frame(width: 80, alignment: .trailing)
                    Text("Total").frame(width: 90, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                Divider()
                ForEach(document.items) { item in
                    HStack(alignment: .top) {
                        Text(item.title).frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.quantity.formatted()).frame(width: 44, alignment: .trailing)
                        Text(Money(cents: item.unitPriceCents, currency: document.currency).formatted).frame(width: 80, alignment: .trailing)
                        Text(Money(cents: item.totalCents, currency: document.currency).formatted).frame(width: 90, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                    Divider()
                }
            }
            HStack {
                Spacer()
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("Subtotal").foregroundStyle(.secondary); Text(document.subtotal.formatted) }
                    if document.taxRate > 0 {
                        GridRow { Text("VAT \(document.taxRate.formatted())%").foregroundStyle(.secondary); Text(document.tax.formatted) }
                    }
                    GridRow { Text("Total").bold(); Text(document.total.formatted).font(.headline) }
                }
                .font(.caption)
            }
            if !document.notes.isEmpty {
                Text(document.notes).font(.caption).foregroundStyle(.secondary)
            }
            if document.kind != .quote {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(business.legalMentions, id: \.self) { Text($0) }
                }
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
            } else if !business.siret.isEmpty {
                Text(business.vatExempt ? "TVA non applicable, art. 293 B du CGI" : "").font(.system(size: 7)).foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .foregroundStyle(.black)
    }
}

enum BillingPDF {
    /// Renders the document to an A4 PDF in the temporary directory, ready to share.
    static func render(_ document: BillingDocument, settings: BusinessSettings) -> URL? {
        let url = URL.temporaryDirectory.appending(path: "\(document.number.isEmpty ? "draft" : document.number).pdf")
        let renderer = ImageRenderer(content:
            BillingPaper(document: document, business: settings)
                .frame(width: 595)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = .init(width: 595, height: nil)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 595, height: max(842, size.height))
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: box.height - size.height)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

struct BillingEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: BillingDocument

    var body: some View {
        NavigationStack {
            Form {
                Section("Client") {
                    TextField("Client name", text: $document.clientName)
                    TextField("E-mail", text: $document.clientEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Address", text: $document.clientAddress, axis: .vertical)
                }
                Section("Dates") {
                    DatePicker("Issued", selection: $document.issueDate, displayedComponents: .date)
                    DatePicker(document.kind == .invoice ? "Due" : "Valid until", selection: $document.dueDate, displayedComponents: .date)
                }
                Section("Items") {
                    ForEach(document.items) { item in LineItemEditor(item: item, currency: document.currency) }
                        .onDelete { offsets in offsets.map { document.items[$0] }.forEach(context.delete) }
                    Button("Add item", systemImage: "plus.circle.fill") {
                        let item = LineItem(title: "", quantity: 1, unitPriceCents: 0, order: Double(document.items.count))
                        item.document = document
                        context.insert(item)
                    }
                }
                Section {
                    Stepper("VAT \(document.taxRate.formatted())%", value: $document.taxRate, in: 0...30, step: 0.5)
                    LabeledContent("Total", value: document.total.formatted).font(.headline)
                }
                Section("Notes") {
                    TextField("Payment terms, bank details…", text: $document.notes, axis: .vertical)
                }
            }
            .navigationTitle(document.displayNumber)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm) { dismiss() } } }
        }
    }
}

struct LineItemEditor: View {
    @Bindable var item: LineItem
    var currency: String

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Description", text: $item.title)
            HStack {
                TextField("Qty", value: $item.quantity, format: .number).keyboardType(.decimalPad).frame(width: 60)
                TextField("Unit price", value: Binding(get: { Double(item.unitPriceCents) / 100 },
                                                       set: { item.unitPriceCents = Int(($0 * 100).rounded()) }),
                          format: .currency(code: currency))
                    .keyboardType(.decimalPad)
                Spacer()
                Text(Money(cents: item.totalCents, currency: currency).formatted).foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }
}
