import CoreLocation
import MapKit

/// Commute estimates between the freelancer's home and a client site, using Apple Maps.
nonisolated struct CommuteEstimate: Hashable, Sendable {
    var distanceKm: Double
    var minutes: Double
    var destination: CLLocationCoordinate2D?

    static func == (a: CommuteEstimate, b: CommuteEstimate) -> Bool {
        a.distanceKm == b.distanceKm && a.minutes == b.minutes
    }
    func hash(into hasher: inout Hasher) { hasher.combine(distanceKm); hasher.combine(minutes) }
}

enum CommuteError: LocalizedError {
    case missingAddress, addressNotFound, noRoute

    var errorDescription: String? {
        switch self {
        case .missingAddress: String(localized: "Add your home address in Business settings and the client's address.")
        case .addressNotFound: String(localized: "Apple Maps couldn't find this address.")
        case .noRoute: String(localized: "No route found for this transport mode.")
        }
    }
}

enum CommuteService {
    static func mapItem(for address: String) async throws -> MKMapItem {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommuteError.missingAddress }
        guard let request = MKGeocodingRequest(addressString: trimmed),
              let item = try await request.mapItems.first else { throw CommuteError.addressNotFound }
        return item
    }

    /// Driving, walking and transit use Apple Maps routing. Bikes are estimated from the
    /// walking route at 15 km/h; trains from the transit ETA.
    static func estimate(from origin: String, to destination: String, mode: TransportMode) async throws -> CommuteEstimate {
        async let source = mapItem(for: origin)
        async let target = mapItem(for: destination)
        let (from, to) = try await (source, target)

        let request = MKDirections.Request()
        request.source = from
        request.destination = to
        switch mode {
        case .car: request.transportType = .automobile
        case .walk, .bike: request.transportType = .walking
        case .transit, .train: request.transportType = .transit
        }

        let coordinate = to.location.coordinate
        if request.transportType == .transit {
            let eta = try await MKDirections(request: request).calculateETA()
            return CommuteEstimate(distanceKm: eta.distance / 1000, minutes: eta.expectedTravelTime / 60, destination: coordinate)
        }
        guard let route = try await MKDirections(request: request).calculate().routes.first else { throw CommuteError.noRoute }
        let km = route.distance / 1000
        let minutes = mode == .bike ? km / 15 * 60 : route.expectedTravelTime / 60
        return CommuteEstimate(distanceKm: km, minutes: minutes, destination: coordinate)
    }

    /// Opens Apple Maps with directions to the client site.
    static func openDirections(to address: String, mode: TransportMode) async {
        guard let item = try? await mapItem(for: address) else { return }
        let directions: String = switch mode {
        case .car: MKLaunchOptionsDirectionsModeDriving
        case .walk: MKLaunchOptionsDirectionsModeWalking
        case .bike: MKLaunchOptionsDirectionsModeCycling
        case .transit, .train: MKLaunchOptionsDirectionsModeTransit
        }
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: directions])
    }

    /// Time to leave to arrive at `arrival`, with a safety margin.
    static func departureTime(arrival: Date, commuteMinutes: Double, marginMinutes: Double = 10) -> Date {
        arrival.addingTimeInterval(-(commuteMinutes + marginMinutes) * 60)
    }
}
