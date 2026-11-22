import SwiftUI

// MARK: - Surfaces

/// Content card on the grouped background. Liquid Glass is reserved for controls/navigation (HIG).
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24, style: .continuous))
    }
}

/// Brand mesh gradient used for hero moments (score, motivation, onboarding).
struct BrandMesh: View {
    var animated = false

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                mesh(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            mesh(t: 0)
        }
    }

    private func mesh(t: Double) -> some View {
        let s = Float(sin(t * 0.4)) * 0.08
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + s, 0.5 - s], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                Brand.violet, Brand.blue, Brand.cyan,
                Brand.indigo, Brand.blue, Brand.blue,
                Brand.violet, Brand.indigo, Brand.blue,
            ]
        )
    }
}

// MARK: - Score

struct ScoreRing: View {
    var score: Int
    var lineWidth: CGFloat = 14
    var showsLabel = true
    var onBrand = false
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(onBrand ? .white.opacity(0.22) : Color.secondary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(onBrand ? AnyShapeStyle(.white) : AnyShapeStyle(Brand.angular),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsLabel {
                VStack(spacing: -2) {
                    Text(Int(animatedProgress * 100), format: .number)
                        .font(.system(size: 200, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.01)
                        .contentTransition(.numericText(value: animatedProgress))
                    Text("/ 100")
                        .font(.system(size: 60, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.01)
                        .foregroundStyle(onBrand ? .white.opacity(0.75) : .secondary)
                }
                .padding(lineWidth * 1.8)
                .foregroundStyle(onBrand ? .white : .primary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Freelancer score")
        .accessibilityValue("\(score) out of 100")
        .onAppear {
            withAnimation(.spring(duration: 1.2, bounce: 0.2).delay(0.15)) { animatedProgress = Double(score) / 100 }
        }
        .onChange(of: score) { _, new in
            withAnimation(.spring) { animatedProgress = Double(new) / 100 }
        }
    }
}

struct MetricBar: View {
    var title: LocalizedStringKey
    var symbol: String
    var value: Double
    var detail: String
    var tint: Color = Brand.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Gauge(value: value) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small pieces

struct SkillChip: View {
    var text: String
    var highlighted = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(highlighted ? .white : .primary)
            .background(highlighted ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.quaternary), in: .capsule)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: proposal, subviews: subviews) {
            for (index, x) in row.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var items: [(Int, CGFloat)] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > maxWidth, !rows[rows.count - 1].items.isEmpty {
                let y = rows[rows.count - 1].y + rows[rows.count - 1].height + spacing
                rows.append(Row(y: y))
            }
            var row = rows[rows.count - 1]
            row.items.append((index, row.width))
            row.width += size.width + spacing
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Generated avatar. Freelancers and employers never see each other's photo before contact is accepted.
struct AnonymousAvatar: View {
    var seed: String
    var symbol: String
    var size: CGFloat = 44

    private var hue: Double {
        Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                          Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.75)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct StarRating: View {
    var value: Double
    var size: Font = .caption

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5) { i in
                Image(systemName: Double(i) + 0.75 <= value ? "star.fill" : Double(i) + 0.25 <= value ? "star.leadinghalf.filled" : "star")
            }
        }
        .font(size)
        .foregroundStyle(.orange)
        .accessibilityElement()
        .accessibilityLabel(Text("\(value, format: .number.precision(.fractionLength(1))) out of 5 stars"))
    }
}

struct StatTile: View {
    var title: LocalizedStringKey
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: .circle)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader<Trailing: View>: View {
    var title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            trailing.font(.subheadline)
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

extension Color {
    static func named(_ name: String) -> Color {
        switch name {
        case "pink": .pink
        case "orange": .orange
        case "teal": .teal
        case "green": .green
        case "purple": Brand.violet
        case "indigo": Brand.indigo
        case "mint": .mint
        default: Brand.blue
        }
    }
}
