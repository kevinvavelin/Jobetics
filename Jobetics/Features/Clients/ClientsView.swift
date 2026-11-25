import Contacts
import ContactsUI
import SwiftData
import SwiftUI

struct ClientsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.name) private var clients: [Client]
    @State private var editing: Client?
    @State private var picking = false
    @State private var query = ""

    private var filtered: [Client] {
        clients.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.contactName.localizedStandardContains(query) }
    }

    var body: some View {
        List {
            ForEach(filtered) { client in
                NavigationLink { ClientDetailView(client: client) } label: {
                    HStack(spacing: 12) {
                        ClientMonogram(name: client.name)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(client.name.isEmpty ? String(localized: "New client") : client.name).font(.headline)
                            if !client.contactName.isEmpty {
                                Text(client.contactName).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        let active = (client.missions ?? []).filter { $0.status == .active }.count
                        if active > 0 {
                            Text("\(active) active").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in offsets.map { filtered[$0] }.forEach(context.delete) }
        }
        .overlay {
            if clients.isEmpty {
                ContentUnavailableView {
                    Label("No clients yet", systemImage: "person.2")
                } description: {
                    Text("Import them from your contacts or add them by hand.")
                } actions: {
                    Button("Import from Contacts") { picking = true }.buttonStyle(.gradientCapsule)
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Add client", systemImage: "plus") {
                    Button("Import from Contacts", systemImage: "person.crop.circle.badge.plus") { picking = true }
                    Button("New client", systemImage: "square.and.pencil") {
                        let client = Client(name: "")
                        context.insert(client)
                        editing = client
                    }
                }
            }
        }
        .sheet(isPresented: $picking) {
            ContactPicker { contact in
                let client = Client.from(contact)
                context.insert(client)
                editing = client
            }
            .ignoresSafeArea()
        }
        .sheet(item: $editing) { ClientEditorView(client: $0) }
    }
}

struct ClientMonogram: View {
    var name: String
    var size: CGFloat = 40

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(initials.isEmpty ? "?" : initials.uppercased())
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.gray.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}

extension Client {
    /// Picking a contact needs no Contacts permission: the system picker only hands over what the user chose.
    static func from(_ contact: CNContact) -> Client {
        let person = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let client = Client(name: contact.organizationName.isEmpty ? person : contact.organizationName,
                            contactName: contact.organizationName.isEmpty ? "" : person,
                            email: (contact.emailAddresses.first?.value as String?) ?? "",
                            phone: contact.phoneNumbers.first?.value.stringValue ?? "")
        if let postal = contact.postalAddresses.first?.value {
            client.address = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
        }
        client.contactIdentifier = contact.identifier
        return client
    }
}

struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { onPick(contact) }
    }
}

struct ClientDetailView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var client: Client
    @State private var editing = false
    @Query private var invoices: [BillingDocument]

    init(client: Client) {
        self.client = client
        let name = client.name
        _invoices = Query(filter: #Predicate<BillingDocument> { $0.clientName == name && $0.kindRaw == "invoice" },
                          sort: \BillingDocument.issueDate, order: .reverse)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ClientMonogram(name: client.name, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name).font(.title3.bold())
                        if !client.contactName.isEmpty { Text(client.contactName).foregroundStyle(.secondary) }
                    }
                }
                HStack(spacing: 10) {
                    if !client.phone.isEmpty, let url = URL(string: "tel:\(client.phone.filter { $0.isNumber || $0 == "+" })") {
                        action("Call", "phone.fill") { openURL(url) }
                    }
                    if !client.phone.isEmpty, let url = SocialShare.smsURL(phone: client.phone, text: "") {
                        action("Message", "message.fill") { openURL(url) }
                    }
                    if !client.phone.isEmpty, let url = SocialShare.whatsAppURL(text: "", phone: client.phone) {
                        action("WhatsApp", "bubble.left.and.text.bubble.right.fill") { openURL(url) }
                    }
                    if !client.email.isEmpty, let url = SocialShare.mailURL(to: client.email, subject: "", body: "") {
                        action("Mail", "envelope.fill") { openURL(url) }
                    }
                }
                .buttonStyle(.borderless)
            }

            Section("Details") {
                if !client.email.isEmpty { LabeledContent("E-mail", value: client.email) }
                if !client.phone.isEmpty { LabeledContent("Phone", value: client.phone) }
                if !client.address.isEmpty { LabeledContent("Address", value: client.address) }
                if !client.siret.isEmpty { LabeledContent("SIRET", value: client.siret) }
                LabeledContent("Payment terms", value: String(localized: "\(client.paymentTermsDays) days"))
            }

            let missions = (client.missions ?? []).sorted { $0.startDate > $1.startDate }
            if !missions.isEmpty {
                Section("Missions") {
                    ForEach(missions) { mission in
                        NavigationLink { MissionDetailView(mission: mission) } label: { MissionRow(mission: mission) }
                    }
                }
            }

            if !invoices.isEmpty {
                let paid = invoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.total.cents }
                Section {
                    ForEach(invoices.prefix(5)) { doc in
                        NavigationLink { BillingDetailView(document: doc) } label: { BillingRow(document: doc) }
                    }
                } header: {
                    Text("Invoices")
                } footer: {
                    Text("Paid in total: \(Money(cents: paid).formatted)")
                }
            }
        }
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) { ClientEditorView(client: client) }
    }

    private func action(_ title: LocalizedStringKey, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12, style: .continuous))
        }
    }
}

struct ClientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var client: Client
    var onSave: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Company or client name", text: $client.name).textContentType(.organizationName)
                    TextField("Contact person", text: $client.contactName).textContentType(.name)
                    TextField("E-mail", text: $client.email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Phone", text: $client.phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                    TextField("Billing address", text: $client.address, axis: .vertical).textContentType(.fullStreetAddress)
                }
                Section("Legal") {
                    TextField("SIRET", text: $client.siret).keyboardType(.numberPad)
                    TextField("VAT number", text: $client.vatNumber).textInputAutocapitalization(.characters)
                    Stepper("Payment terms: \(client.paymentTermsDays) days", value: $client.paymentTermsDays, in: 0...60, step: 15)
                }
                Section("Notes") {
                    TextField("Notes", text: $client.notes, axis: .vertical)
                }
            }
            .navigationTitle(client.name.isEmpty ? String(localized: "New client") : client.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { onSave(); dismiss() }
                        .disabled(client.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
