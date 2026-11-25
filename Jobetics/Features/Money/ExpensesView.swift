import PhotosUI
import SwiftData
import SwiftUI
import VisionKit

struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var editing: Expense?
    @State private var showsPendingOnly = false

    private var filtered: [Expense] { showsPendingOnly ? expenses.filter(\.isPendingRebill) : expenses }

    private var grouped: [(Date, [Expense])] {
        Dictionary(grouping: filtered) { Calendar.current.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        List {
            Section {
                let pending = expenses.filter(\.isPendingRebill).reduce(0) { $0 + $1.amountCents }
                let month = Calendar.current.dateInterval(of: .month, for: .now)
                let thisMonth = expenses.filter { month?.contains($0.date) == true }.reduce(0) { $0 + $1.amountCents }
                HStack(spacing: 12) {
                    StatTile(title: "This month", value: Money(cents: thisMonth).formatted, symbol: "creditcard.fill", tint: Brand.blue)
                    StatTile(title: "To rebill", value: Money(cents: pending).formatted, symbol: "arrow.uturn.forward.circle.fill", tint: Brand.warning)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            ForEach(grouped, id: \.0) { month, items in
                Section {
                    ForEach(items) { expense in
                        Button { editing = expense } label: { ExpenseRow(expense: expense) }
                            .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in offsets.map { items[$0] }.forEach(context.delete) }
                } header: {
                    HStack {
                        Text(month, format: .dateTime.month(.wide).year())
                        Spacer()
                        Text(Money(cents: items.reduce(0) { $0 + $1.amountCents }).formatted).monospacedDigit()
                    }
                }
            }
        }
        .overlay {
            if expenses.isEmpty {
                ContentUnavailableView("No expenses", systemImage: "receipt",
                                       description: Text("Scan a receipt: amount, VAT and category are read on your device."))
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showsPendingOnly) { Label("To rebill only", systemImage: "line.3.horizontal.decrease") }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("New expense", systemImage: "plus") {
                    let expense = Expense(date: .now, title: "", amountCents: 0, category: .other)
                    context.insert(expense)
                    editing = expense
                }
            }
        }
        .sheet(item: $editing) { ExpenseEditorView(expense: $0) }
    }
}

struct ExpenseRow: View {
    var expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.fill.tertiary, in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title.isEmpty ? expense.category.title : expense.title).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(expense.date, format: .dateTime.day().month(.abbreviated))
                    if let mission = expense.mission { Text("· \(mission.title)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.money.formatted).font(.subheadline.weight(.semibold).monospacedDigit())
                if expense.isPendingRebill {
                    Text("To rebill").font(.caption2.weight(.semibold)).foregroundStyle(Brand.warning)
                } else if expense.rebilledOn != nil {
                    Text("Rebilled").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if expense.receipt != nil {
                Image(systemName: "paperclip").font(.caption).foregroundStyle(.tertiary).accessibilityLabel("Receipt attached")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var expense: Expense
    @Query(filter: #Predicate<Mission> { $0.statusRaw == "active" }, sort: \Mission.title) private var missions: [Mission]
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var isReading = false
    @State private var readNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    receiptPreview
                    HStack {
                        if VNDocumentCameraViewController.isSupported {
                            Button("Scan receipt", systemImage: "doc.viewfinder") { scanning = true }
                                .buttonStyle(.glass)
                        }
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Photo", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity)
                    if isReading { ProgressView("Reading receipt…") }
                    if let readNote { Label(readNote, systemImage: "sparkles").font(.footnote).foregroundStyle(.secondary) }
                }

                Section {
                    TextField("Description", text: $expense.title)
                    LabeledContent("Amount incl. VAT") {
                        TextField("Amount", value: euros(\.amountCents), format: .currency(code: "EUR"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("of which VAT") {
                        TextField("VAT", value: euros(\.vatCents), format: .currency(code: "EUR"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $expense.date, displayedComponents: .date)
                    Picker("Category", selection: $expense.category) {
                        ForEach(ExpenseCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }

                Section {
                    Picker("Mission", selection: $expense.mission) {
                        Text("None").tag(Mission?.none)
                        ForEach(missions) { Text($0.title).tag(Mission?.some($0)) }
                    }
                    Toggle("Rebill to the client", isOn: $expense.isRebillable)
                        .disabled(expense.rebilledOn != nil)
                } footer: {
                    Text(expense.rebilledOn.map { String(localized: "Already rebilled on \($0).") }
                         ?? String(localized: "Rebillable expenses are suggested on the mission's next invoice."))
                }
            }
            .navigationTitle(expense.title.isEmpty ? String(localized: "New expense") : expense.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        if expense.title.isEmpty { expense.title = expense.category.title }
                        dismiss()
                    }
                }
            }
            .onChange(of: photo) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    await read(data)
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { data in Task { await read(data) } }.ignoresSafeArea()
            }
        }
    }

    @ViewBuilder private var receiptPreview: some View {
        if let data = expense.receipt, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityLabel("Receipt")
        }
    }

    private func read(_ data: Data) async {
        expense.receipt = UIImage(data: data)?.jpegData(compressionQuality: 0.7) ?? data
        isReading = true
        defer { isReading = false }
        guard let result = try? await ReceiptScanner.scan(data) else {
            readNote = String(localized: "Couldn't read this receipt. Enter the amount by hand.")
            return
        }
        if let total = result.totalCents { expense.amountCents = total }
        if let vat = result.vatCents { expense.vatCents = vat }
        if let category = result.suggestedCategory { expense.category = category }
        if let date = result.date, date <= .now { expense.date = date }
        if expense.title.isEmpty, let merchant = result.merchant { expense.title = merchant }
        readNote = String(localized: "Filled in from the receipt, on your device. Check the values.")
    }

    private func euros(_ keyPath: ReferenceWritableKeyPath<Expense, Int>) -> Binding<Double> {
        Binding(get: { Double(expense[keyPath: keyPath]) / 100 }, set: { expense[keyPath: keyPath] = Int(($0 * 100).rounded()) })
    }
}

/// VisionKit document camera: edge detection and perspective correction for paper receipts.
struct DocumentScanner: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onScan: (Data) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0, let data = scan.imageOfPage(at: 0).jpegData(compressionQuality: 0.8) { parent.onScan(data) }
            parent.dismiss()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}
