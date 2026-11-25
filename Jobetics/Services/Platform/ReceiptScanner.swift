import Foundation
import Vision

/// On-device receipt reading with Vision: finds the total and a merchant name. Nothing leaves the device.
nonisolated struct ScannedReceipt: Hashable, Sendable {
    var merchant: String?
    var totalCents: Int?
    var vatCents: Int?
    var date: Date?
    var suggestedCategory: ExpenseCategory?
}

nonisolated enum ReceiptScanner {
    @concurrent
    static func scan(_ imageData: Data) async throws -> ScannedReceipt {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: imageData)
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return parse(lines: lines)
    }

    /// Text heuristics, separated from Vision so they can be unit tested.
    static func parse(lines: [String]) -> ScannedReceipt {
        var result = ScannedReceipt()
        result.merchant = lines.first { line in
            line.count >= 3 && line.rangeOfCharacter(from: .letters) != nil && amount(in: line) == nil
        }?.trimmingCharacters(in: .whitespaces)

        let totalKeywords = ["total ttc", "total", "montant", "à payer", "a payer", "amount due", "net à payer"]
        let vatKeywords = ["tva", "vat"]
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if result.totalCents == nil, totalKeywords.contains(where: lower.contains), !lower.contains("ht") || lower.contains("ttc") {
                result.totalCents = amount(in: line) ?? lines[safe: index + 1].flatMap(amount(in:))
            }
            if result.vatCents == nil, vatKeywords.contains(where: lower.contains) {
                result.vatCents = amount(in: line).flatMap { $0 < 100_000 ? $0 : nil }
            }
        }
        if result.totalCents == nil {
            result.totalCents = lines.compactMap(amount(in:)).max()
        }
        let joined = lines.joined(separator: " ").lowercased()
        result.suggestedCategory = category(for: joined)
        result.date = date(in: joined)
        return result
    }

    /// Finds the last money amount in a line: "12,50 €", "€12.50", "1 234,00".
    static func amount(in line: String) -> Int? {
        let pattern = /(\d{1,3}(?:[ \u{202F}\u{00A0}]?\d{3})*|\d+)[.,](\d{2})(?!\d)/
        guard let match = line.matches(of: pattern).last else { return nil }
        let euros = String(match.output.1).filter(\.isNumber)
        guard let e = Int(euros), let c = Int(match.output.2) else { return nil }
        return e * 100 + c
    }

    static func category(for text: String) -> ExpenseCategory? {
        let map: [(ExpenseCategory, [String])] = [
            (.transport, ["sncf", "tgv", "ouigo", "ratp", "uber", "taxi", "bolt", "train", "parking", "péage", "peage", "metro"]),
            (.mileage, ["total energies", "carburant", "gazole", "essence", "sp95", "sp98", "station"]),
            (.lodging, ["hotel", "hôtel", "airbnb", "ibis", "novotel", "booking"]),
            (.meals, ["restaurant", "café", "cafe", "brasserie", "boulangerie", "menu", "déjeuner", "dejeuner"]),
            (.coworking, ["coworking", "wework", "cordée", "cordee", "morning", "station f"]),
            (.software, ["apple.com", "figma", "github", "adobe", "notion", "subscription", "abonnement"]),
            (.equipment, ["fnac", "darty", "apple store", "boulanger", "ldlc"]),
        ]
        return map.first { _, words in words.contains(where: text.contains) }?.0
    }

    static func date(in text: String) -> Date? {
        guard let match = text.firstMatch(of: /(\d{2})[\/.-](\d{2})[\/.-](\d{2,4})/) else { return nil }
        var year = Int(match.output.3) ?? 0
        if year < 100 { year += 2000 }
        return DateComponents(calendar: .current, year: year, month: Int(match.output.2), day: Int(match.output.1)).date
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
