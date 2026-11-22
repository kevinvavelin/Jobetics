import PhotosUI
import SwiftData
import SwiftUI

/// Portfolio stored with SwiftData (images & files as external storage) and synced through iCloud.
struct PortfolioView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PortfolioItem.createdAt, order: .reverse) private var items: [PortfolioItem]
    @State private var editing: PortfolioItem?
    @Namespace private var zoom

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    NavigationLink {
                        PortfolioDetailView(item: item)
                            .navigationTransition(.zoom(sourceID: item.persistentModelID, in: zoom))
                    } label: {
                        PortfolioTile(item: item)
                            .matchedTransitionSource(id: item.persistentModelID, in: zoom)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = item }
                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Show your best work", systemImage: "photo.on.rectangle.angled",
                                       description: Text("Add projects with images, files and links. Your portfolio syncs with iCloud."))
            }
        }
        .navigationTitle("Portfolio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add work", systemImage: "plus") {
                    let item = PortfolioItem(title: "", summary: "", discipline: .design)
                    context.insert(item)
                    editing = item
                }
            }
        }
        .sheet(item: $editing) { PortfolioEditor(item: $0) }
    }
}

struct PortfolioCover: View {
    var item: PortfolioItem

    var body: some View {
        if let data = item.coverImage, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            let seed = abs(item.title.hashValue % 3)
            ZStack {
                MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                             colors: [[Brand.cyan, Brand.blue, Brand.violet, Brand.indigo],
                                      [.pink, Brand.violet, .orange, Brand.indigo],
                                      [.teal, Brand.blue, .mint, Brand.indigo]][seed])
                Image(systemName: item.discipline.symbol)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 10)
            }
        }
    }
}

struct PortfolioTile: View {
    var item: PortfolioItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PortfolioCover(item: item)
                .frame(height: 170)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.headline)
                Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                FlowLayout { ForEach(item.tags, id: \.self) { SkillChip(text: $0) } }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }
}

struct PortfolioDetailView: View {
    @Environment(\.openURL) private var openURL
    var item: PortfolioItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PortfolioCover(item: item)
                    .frame(height: 320)
                    .clipped()
                    .backgroundExtensionEffect()
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title).font(.largeTitle.bold())
                    Text(item.summary).font(.body)
                    FlowLayout { ForEach(item.tags, id: \.self) { SkillChip(text: $0, highlighted: true) } }
                    if let link = item.link {
                        Button("Open project", systemImage: "safari") { openURL(link) }.buttonStyle(.glassProminent)
                    }
                    if let name = item.attachmentName {
                        Label(name, systemImage: "paperclip").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct PortfolioEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: PortfolioItem
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var link = ""
    @State private var tags = ""
    @State private var linkError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PortfolioCover(item: item).frame(height: 160).clipShape(.rect(cornerRadius: 16)).listRowInsets(EdgeInsets())
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose cover image", systemImage: "photo") }
                }
                Section("Project") {
                    TextField("Title", text: $item.title)
                    TextField("What did you do? What was the impact?", text: $item.summary, axis: .vertical).lineLimit(3...6)
                    TextField("Tags, comma separated", text: $tags)
                }
                Section {
                    TextField("https://", text: $link).keyboardType(.URL).textInputAutocapitalization(.never)
                    if let linkError { Text(linkError).font(.caption).foregroundStyle(Brand.danger) }
                    Button { importing = true } label: {
                        Label(item.attachmentName ?? String(localized: "Attach a file (PDF, image…)"), systemImage: "paperclip")
                    }
                } header: {
                    Text("Link & files")
                } footer: {
                    Text("Files sync across your devices with iCloud.")
                }
            }
            .navigationTitle("Portfolio item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm, action: save) } }
            .onAppear {
                link = item.link?.absoluteString ?? ""
                tags = item.tags.joined(separator: ", ")
            }
            .task(id: photo) {
                if let data = try? await photo?.loadTransferable(type: Data.self) { item.coverImage = data }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .movie, .zip]) { result in
                guard let url = try? result.get(), url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                item.attachment = try? Data(contentsOf: url)
                item.attachmentName = url.lastPathComponent
            }
        }
    }

    private func save() {
        item.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if link.isEmpty {
            item.link = nil
        } else {
            switch LinkGuard.validateProfileLink(link, kind: .website) {
            case .success(let url): item.link = url
            case .failure(let error):
                linkError = error.localizedDescription
                return
            }
        }
        dismiss()
    }
}
