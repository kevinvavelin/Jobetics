import SwiftData
import SwiftUI

struct MissionEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Bindable var mission: Mission
    @Query(sort: \Client.name) private var clients: [Client]
    @State private var newClient: Client?
    @State private var sourceURL = ""

    private let colors = ["blue", "indigo", "purple", "pink", "orange", "teal", "green", "mint"]
    private let symbols = ["briefcase.fill", "building.columns.fill", "iphone", "paintbrush.pointed.fill", "chevron.left.forwardslash.chevron.right",
                           "accessibility", "person.2.wave.2.fill", "chart.line.uptrend.xyaxis", "applewatch", "cart.fill", "cross.case.fill", "graduationcap.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mission title", text: $mission.title)
                        .font(.headline)
                    Picker("Client", selection: $mission.client) {
                        Text("None").tag(Client?.none)
                        ForEach(clients) { Text($0.name).tag(Client?.some($0)) }
                    }
                    Button("New client", systemImage: "person.crop.circle.badge.plus") {
                        let client = Client(name: "")
                        context.insert(client)
                        newClient = client
                    }
                    Picker("Status", selection: $mission.status) {
                        ForEach(MissionStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }

                Section {
                    Picker("Billing", selection: $mission.billingMode) {
                        ForEach(BillingMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent(mission.billingMode == .fixed ? "Price (excl. VAT)" : "Rate (excl. VAT)") {
                        TextField("Amount", value: euros(\.rateCents), format: .currency(code: "EUR"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    let recommended = RateCalculator.recommend(settings.settings.rateInputs)
                    if mission.billingMode == .daily, recommended.dailyRateCents > 0, mission.rateCents < recommended.dailyRateCents {
                        Label("Below your target rate of \(Money(cents: recommended.dailyRateCents).formatted)/day.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Brand.warning)
                    }
                    Stepper(value: $mission.estimatedDays, in: 0...400, step: 0.5) {
                        LabeledContent(mission.billingMode == .fixed ? "Estimated days" : "Budgeted days", value: mission.estimatedDays.formatted())
                    }
                    DatePicker("Start", selection: $mission.startDate, displayedComponents: .date)
                    DatePicker("End", selection: $mission.endDate, in: mission.startDate..., displayedComponents: .date)
                } header: {
                    Text("Terms")
                }

                Section {
                    Picker("Location", selection: $mission.location) {
                        ForEach(WorkLocation.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if mission.needsTravel {
                        TextField("Client site address", text: $mission.siteAddress, axis: .vertical)
                            .textContentType(.fullStreetAddress)
                        if mission.location == .hybrid {
                            Stepper("On site \(mission.onSiteDaysPerWeek) days a week", value: $mission.onSiteDaysPerWeek, in: 0...5)
                        }
                        Picker("Travel costs", selection: $mission.travelPolicy) {
                            ForEach(TravelPolicy.allCases) { Text($0.title).tag($0) }
                        }
                        if mission.travelPolicy == .flatPerDay {
                            LabeledContent("Per on-site day") {
                                TextField("Amount", value: euros(\.flatTravelPerDayCents), format: .currency(code: "EUR"))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                        }
                        if mission.travelPolicy == .actualCosts && !mission.transport.usesMileageAllowance {
                            LabeledContent("Round-trip ticket") {
                                TextField("Amount", value: euros(\.ticketRoundTripCents), format: .currency(code: "EUR"))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                } header: {
                    Text("Where")
                } footer: {
                    if mission.needsTravel && settings.settings.homeAddress.isEmpty {
                        Text("Add your home address in Business settings to estimate the commute.")
                    }
                }

                Section("Found on") {
                    TextField("Source (Malt, LinkedIn, referral…)", text: $mission.source)
                    TextField("Listing URL", text: $sourceURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Purchase order number", text: $mission.purchaseOrder)
                }

                Section("Appearance") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(colors, id: \.self) { name in
                                Button {
                                    mission.colorName = name
                                } label: {
                                    Circle().fill(Color.named(name)).frame(width: 30, height: 30)
                                        .overlay { if mission.colorName == name { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(name)
                                .accessibilityAddTraits(mission.colorName == name ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button {
                                mission.symbol = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(mission.symbol == symbol ? .white : Color.named(mission.colorName))
                                    .background(mission.symbol == symbol ? Color.named(mission.colorName) : Color.named(mission.colorName).opacity(0.12),
                                                in: .rect(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                }
            }
            .navigationTitle(mission.title.isEmpty ? String(localized: "New mission") : mission.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        mission.sourceURL = sourceURL.isEmpty ? nil : LinkGuard.normalized(sourceURL)
                        if mission.title.isEmpty { mission.title = String(localized: "New mission") }
                        dismiss()
                    }
                }
            }
            .sheet(item: $newClient) { client in
                ClientEditorView(client: client) { mission.client = client }
            }
            .onAppear { sourceURL = mission.sourceURL?.absoluteString ?? "" }
        }
    }

    private func euros(_ keyPath: ReferenceWritableKeyPath<Mission, Int>) -> Binding<Double> {
        Binding(get: { Double(mission[keyPath: keyPath]) / 100 }, set: { mission[keyPath: keyPath] = Int(($0 * 100).rounded()) })
    }
}
