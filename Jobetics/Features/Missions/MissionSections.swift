import MapKit
import SwiftUI

// MARK: - Travel mode

/// Commute, mileage and travel fees for on-site and hybrid missions.
struct TravelSection: View {
    @Environment(SettingsStore.self) private var settings
    @Bindable var mission: Mission
    @State private var isEstimating = false
    @State private var error: String?
    @State private var arrival = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = mission.siteLatitude, let lon = mission.siteLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        Section {
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_800, longitudinalMeters: 1_800)),
                    interactionModes: []) {
                    Marker(mission.clientName.isEmpty ? mission.title : mission.clientName, systemImage: "building.2.fill", coordinate: coordinate)
                        .tint(Color.named(mission.colorName))
                }
                .frame(height: 150)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .accessibilityLabel("Map of the client site")
            }

            Picker(selection: $mission.transport) {
                ForEach(TransportMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            } label: {
                Label("Transport", systemImage: mission.transport.symbol)
            }
            .onChange(of: mission.transport) { Task { await estimate() } }

            if mission.oneWayKm > 0 {
                LabeledContent {
                    Text("\(mission.oneWayKm.formatted(.number.precision(.fractionLength(0)))) km · \(Duration.seconds(mission.commuteMinutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                        .monospacedDigit()
                } label: {
                    Label("One way", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                DatePicker(selection: $arrival, displayedComponents: .hourAndMinute) {
                    Label("Arrive at", systemImage: "clock")
                }
                LabeledContent {
                    Text(CommuteService.departureTime(arrival: arrival, commuteMinutes: mission.commuteMinutes), format: .dateTime.hour().minute())
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                } label: {
                    Label("Leave by", systemImage: "figure.walk.departure")
                }
            }

            let onSite = mission.onSiteDaysLoggedThisMonth
            let fees = mission.travelFees(onSiteDays: onSite, ratePerKm: settings.settings.mileageRatePerKm)
            if mission.travelPolicy != .included && onSite > 0 {
                LabeledContent {
                    Text(Money(cents: fees.totalCents).formatted).fontWeight(.semibold)
                } label: {
                    Label {
                        Text("Travel fees this month")
                        Text(mission.transport.usesMileageAllowance
                             ? "\(fees.totalKm.formatted(.number.precision(.fractionLength(0)))) km × \(settings.settings.mileageRatePerKm.formatted(.currency(code: "EUR").precision(.fractionLength(3))))"
                             : "\(onSite.formatted()) round trips")
                    } icon: {
                        Image(systemName: "eurosign.circle")
                    }
                }
            }

            HStack {
                Button {
                    Task { await estimate() }
                } label: {
                    Label(mission.oneWayKm > 0 ? "Update estimate" : "Estimate commute", systemImage: "location.magnifyingglass")
                }
                .buttonStyle(.glass)
                .disabled(isEstimating || mission.siteAddress.isEmpty)
                Spacer()
                Button {
                    Task { await CommuteService.openDirections(to: mission.siteAddress, mode: mission.transport) }
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.gradientCapsule)
                .disabled(mission.siteAddress.isEmpty)
            }
            .controlSize(.small)
            .overlay { if isEstimating { ProgressView() } }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Brand.warning)
            }
        } header: {
            Text("Travel")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        switch mission.travelPolicy {
        case .included: String(localized: "Travel is included in your rate. Change it in Edit to bill it to the client.")
        case .flatPerDay: String(localized: "A flat fee per on-site day is added to the invoice.")
        case .actualCosts: mission.transport.usesMileageAllowance
            ? String(localized: "Mileage uses the official French scale for your \(settings.settings.vehicleHorsepower) CV vehicle.")
            : String(localized: "Your round-trip ticket price is added for each on-site day.")
        }
    }

    private func estimate() async {
        guard !mission.siteAddress.isEmpty else { return }
        isEstimating = true
        error = nil
        defer { isEstimating = false }
        do {
            let result = try await CommuteService.estimate(from: settings.settings.homeAddress, to: mission.siteAddress, mode: mission.transport)
            mission.oneWayKm = (result.distanceKm * 10).rounded() / 10
            mission.commuteMinutes = result.minutes.rounded()
            if let c = result.destination {
                mission.siteLatitude = c.latitude
                mission.siteLongitude = c.longitude
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Mission {
    var onSiteDaysLoggedThisMonth: Double {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return 0 }
        return (logs ?? []).filter { $0.onSite && month.contains($0.date) }.reduce(0) { $0 + $1.days }
    }
}

// MARK: - Client contact & sharing

struct ClientContactSection: View {
    @Environment(\.openURL) private var openURL
    var mission: Mission
    @State private var message = ""

    var body: some View {
        if let client = mission.client {
            Section {
                NavigationLink { ClientDetailView(client: client) } label: {
                    LabeledContent(client.name, value: client.contactName)
                }
                HStack(spacing: 10) {
                    if let phone = URL(string: "tel:\(client.phone.filter { $0.isNumber || $0 == "+" })"), !client.phone.isEmpty {
                        contactButton("Call", "phone.fill") { openURL(phone) }
                    }
                    if !client.phone.isEmpty, let sms = SocialShare.smsURL(phone: client.phone, text: update) {
                        contactButton("Message", "message.fill") { openURL(sms) }
                    }
                    if let whatsapp = SocialShare.whatsAppURL(text: update, phone: client.phone.isEmpty ? nil : client.phone) {
                        contactButton("WhatsApp", "bubble.left.and.text.bubble.right.fill") { openURL(whatsapp) }
                    }
                    if !client.email.isEmpty, let mail = SocialShare.mailURL(to: client.email, subject: mission.title, body: update) {
                        contactButton("Mail", "envelope.fill") { openURL(mail) }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Client")
            } footer: {
                Text("Messages, WhatsApp and Mail open with a progress update you can edit before sending.")
            }
        }
    }

    private var update: String {
        let contact = mission.client?.contactName.split(separator: " ").first.map(String.init) ?? ""
        return String(localized: "Hello \(contact), quick update on \(mission.title): \(mission.daysLogged.formatted()) days delivered so far. ")
    }

    private func contactButton(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
