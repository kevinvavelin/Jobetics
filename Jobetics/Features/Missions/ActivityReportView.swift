import PencilKit
import SwiftData
import SwiftUI

/// Monthly activity report (CRA): days worked, signed by the client on the device, then locked
/// and turned into an invoice in one tap.
struct ActivityReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings
    var mission: Mission
    @State var month: Date
    @State private var signing = false
    @State private var pdfURL: URL?
    @State private var invoice: BillingDocument?

    private var report: ActivityReport? { mission.activityReport(for: month) }
    private var record: ActivityReportRecord? {
        (mission.reports ?? []).first { Calendar.current.isDate($0.month, equalTo: month, toGranularity: .month) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthPicker
                ActivityReportPaper(mission: mission, report: report, record: record, business: settings.settings)
                    .background(.white, in: .rect(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                    .frame(maxWidth: 595)
                    .environment(\.colorScheme, .light)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Activity report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let pdfURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: pdfURL, subject: Text("Activity report \(mission.title)")) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .sheet(isPresented: $signing) { SignatureSheet(defaultName: mission.client?.contactName ?? "") { name, data in sign(name: name, signature: data) } }
        .navigationDestination(item: $invoice) { BillingDetailView(document: $0) }
        .task(id: "\(month)-\(record?.signedAt?.timeIntervalSince1970 ?? 0)-\(report?.totalDays ?? 0)") { renderPDF() }
    }

    private var monthPicker: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") { shift(-1) }.labelStyle(.iconOnly)
            Spacer()
            Text(month, format: .dateTime.month(.wide).year()).font(.headline)
            Spacer()
            Button("Next month", systemImage: "chevron.right") { shift(1) }.labelStyle(.iconOnly)
                .disabled(Calendar.current.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .buttonStyle(.glass)
        .frame(maxWidth: 595)
    }

    @ViewBuilder private var actions: some View {
        GlassEffectContainer {
            HStack {
                if record?.isSigned == true {
                    if record?.invoiceNumber == nil {
                        Button("Create invoice", systemImage: "doc.badge.plus") { createInvoice() }.buttonStyle(.gradientCapsule)
                    } else {
                        Label("Invoiced", systemImage: "checkmark.seal.fill").padding().glassEffect()
                    }
                } else {
                    Button("Have it signed", systemImage: "signature") { signing = true }
                        .buttonStyle(.gradientCapsule)
                        .disabled((report?.totalDays ?? 0) == 0)
                }
            }
            .controlSize(.large)
        }
        .padding()
    }

    private func shift(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    private func sign(name: String, signature: Data) {
        guard let report else { return }
        let record = self.record ?? {
            let r = ActivityReportRecord(month: report.month.start, totalDays: report.totalDays, onSiteDays: report.onSiteDays)
            r.mission = mission
            context.insert(r)
            return r
        }()
        record.totalDays = report.totalDays
        record.onSiteDays = report.onSiteDays
        record.signerName = name
        record.signature = signature
        record.signedAt = .now
        // A signed report freezes the days it contains.
        for log in mission.logs ?? [] where report.month.contains(log.date) { log.isLocked = true }
    }

    private func createInvoice() {
        guard let record else { return }
        // Days are locked by the signature: unlock them just for the invoice builder, which re-locks them.
        for log in mission.logs ?? [] where Calendar.current.isDate(log.date, equalTo: month, toGranularity: .month) { log.isLocked = false }
        invoice = MissionInvoicing.createInvoice(for: mission, month: month, settings: settings, in: context)
        record.invoiceNumber = invoice?.displayNumber
    }

    private func renderPDF() {
        let url = URL.temporaryDirectory.appending(path: "CRA-\(mission.title)-\(month.formatted(.iso8601.year().month())).pdf")
        let renderer = ImageRenderer(content: ActivityReportPaper(mission: mission, report: report, record: record, business: settings.settings)
            .frame(width: 595).environment(\.colorScheme, .light))
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
        pdfURL = ok ? url : nil
    }
}

struct ActivityReportPaper: View {
    var mission: Mission
    var report: ActivityReport?
    var record: ActivityReportRecord?
    var business: BusinessSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(business.displayName).font(.headline)
                    if !business.siret.isEmpty { Text("SIRET \(business.siret)").font(.caption2) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("ACTIVITY REPORT").font(.headline.weight(.heavy)).foregroundStyle(Brand.indigo)
                    Text(report?.month.start ?? .now, format: .dateTime.month(.wide).year()).font(.caption)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Client").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(mission.clientName).font(.subheadline.weight(.semibold))
                Text(mission.title).font(.caption)
                if !mission.purchaseOrder.isEmpty { Text("PO \(mission.purchaseOrder)").font(.caption) }
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Place").frame(width: 80, alignment: .leading)
                    Text("Days").frame(width: 50, alignment: .trailing)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.vertical, 6)
                Divider()
                ForEach(report?.entries ?? [], id: \.date) { entry in
                    HStack {
                        Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month()).frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.onSite ? "On site" : "Remote").frame(width: 80, alignment: .leading)
                        Text(entry.days.formatted()).frame(width: 50, alignment: .trailing)
                    }
                    .font(.caption).padding(.vertical, 4)
                    Divider()
                }
            }
            HStack {
                Spacer()
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text("On site").foregroundStyle(.secondary); Text((report?.onSiteDays ?? 0).formatted()) }
                    GridRow { Text("Remote").foregroundStyle(.secondary); Text((report?.remoteDays ?? 0).formatted()) }
                    GridRow { Text("Total days").bold(); Text((report?.totalDays ?? 0).formatted()).bold() }
                }
                .font(.caption)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Client approval").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let data = record?.signature, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 60)
                        Text("\(record?.signerName ?? "") · \(record?.signedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")").font(.caption2)
                    } else {
                        RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .frame(width: 200, height: 60)
                    }
                }
                Spacer()
            }
        }
        .padding(32)
        .foregroundStyle(.black)
    }
}

/// Signature pad with PencilKit: works with a finger or Apple Pencil.
struct SignatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    var defaultName: String
    var onSign: (String, Data) -> Void
    @State private var name = ""
    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Signer's name", text: $name)
                    .textContentType(.name)
                    .padding(12)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                SignatureCanvas(drawing: $drawing)
                    .frame(height: 220)
                    .background(.white, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator))
                    .overlay(alignment: .bottomLeading) {
                        Text("Sign here").font(.caption).foregroundStyle(.secondary).padding(12).allowsHitTesting(false)
                    }
                Text("By signing, the client approves the days listed in this report.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", systemImage: "eraser") { drawing = PKDrawing() }.disabled(drawing.strokes.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign", role: .confirm) {
                        let image = drawing.image(from: drawing.bounds.insetBy(dx: -10, dy: -10), scale: 2)
                        if let data = image.pngData() { onSign(name, data) }
                        dismiss()
                    }
                    .disabled(drawing.strokes.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = defaultName }
        }
        .interactiveDismissDisabled(!drawing.strokes.isEmpty)
    }
}

struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        canvas.accessibilityLabel = String(localized: "Signature area")
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing.wrappedValue = canvasView.drawing }
    }
}
