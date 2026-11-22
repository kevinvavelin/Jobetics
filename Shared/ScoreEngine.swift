import Foundation

/// Raw, verifiable signals the freelancer score is derived from.
///
/// In production these are computed **server-side** (Cloud Functions) from message
/// timestamps, meeting check-ins and delivered milestones, and written with the Admin SDK.
/// Firestore rules forbid clients from writing them, so nobody can inflate their own score.
nonisolated struct ScoreSignals: Codable, Hashable, Sendable {
    var medianResponseMinutes: Double
    var meetingsAttended: Int
    var meetingsTotal: Int
    var deliveredOnTime: Int
    var deliveredTotal: Int
    /// 0...5
    var averageRating: Double
    var ratingCount: Int
    /// 0...1
    var profileCompleteness: Double

    static let newcomer = ScoreSignals(
        medianResponseMinutes: 60, meetingsAttended: 0, meetingsTotal: 0,
        deliveredOnTime: 0, deliveredTotal: 0, averageRating: 0, ratingCount: 0,
        profileCompleteness: 0.4
    )
}

nonisolated struct FreelancerScore: Codable, Hashable, Sendable {
    /// 0...100
    var overall: Int
    var responsiveness: Double
    var punctuality: Double
    var delivery: Double
    var satisfaction: Double
    var completeness: Double
    var tier: Tier

    enum Tier: String, Codable, Sendable, CaseIterable {
        case rising, established, trusted, topRated

        var title: String {
            switch self {
            case .rising: String(localized: "Rising")
            case .established: String(localized: "Established")
            case .trusted: String(localized: "Trusted")
            case .topRated: String(localized: "Top Rated")
            }
        }

        var symbol: String {
            switch self {
            case .rising: "leaf.fill"
            case .established: "checkmark.seal.fill"
            case .trusted: "shield.lefthalf.filled"
            case .topRated: "crown.fill"
            }
        }
    }
}

nonisolated enum ScoreEngine {
    struct Weights: Sendable {
        var responsiveness = 0.25
        var punctuality = 0.20
        var delivery = 0.25
        var satisfaction = 0.20
        var completeness = 0.10
    }

    /// Smoothed ratio so newcomers start from a fair prior instead of 0% or 100%.
    static func smoothed(_ successes: Int, of total: Int, prior: Double = 0.7, weight: Double = 3) -> Double {
        (Double(successes) + prior * weight) / (Double(total) + weight)
    }

    /// 1.0 when replying within 30 minutes, 0.5 at ~4h30, approaching 0 after days.
    static func responsiveness(medianMinutes: Double) -> Double {
        1 / (1 + max(0, medianMinutes - 30) / 240)
    }

    static func score(_ s: ScoreSignals, weights w: Weights = .init()) -> FreelancerScore {
        let responsiveness = responsiveness(medianMinutes: s.medianResponseMinutes)
        let punctuality = smoothed(s.meetingsAttended, of: s.meetingsTotal)
        let delivery = smoothed(s.deliveredOnTime, of: s.deliveredTotal)
        let rating = (s.averageRating * Double(s.ratingCount) + 3.5 * 3) / (Double(s.ratingCount) + 3)
        let satisfaction = min(1, max(0, rating / 5))
        let completeness = min(1, max(0, s.profileCompleteness))

        let raw = responsiveness * w.responsiveness + punctuality * w.punctuality
            + delivery * w.delivery + satisfaction * w.satisfaction + completeness * w.completeness
        let overall = Int((raw * 100).rounded())

        let tier: FreelancerScore.Tier = switch overall {
        // Higher tiers must be earned with real, reviewed deliveries.
        case 85... where s.ratingCount >= 5 && s.deliveredTotal >= 5: .topRated
        case 72... where s.deliveredTotal >= 3: .trusted
        case 58...: .established
        default: .rising
        }

        return FreelancerScore(
            overall: overall, responsiveness: responsiveness, punctuality: punctuality,
            delivery: delivery, satisfaction: satisfaction, completeness: completeness, tier: tier
        )
    }
}
