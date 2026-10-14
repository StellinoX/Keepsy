#if DEBUG
import SwiftUI
import Combine

struct AdminArtworkReviewView: View {
    enum ReviewFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case allowed = "Allowed"
        case blocked = "Blocked"

        var id: Self { self }
    }

    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var artworks: [NetworkArtwork] = []
    @State private var selectedMuseumId = "all"
    @State private var reviewFilter: ReviewFilter = .all
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reviewRevision = 0
    @State private var updatingArtworkId: String? = nil
    @State private var isResequencing = false

    private var reviewedArtworks: [NetworkArtwork] {
        artworks.filter { artwork in
            let matchesMuseum = selectedMuseumId == "all" || artwork.museumId == selectedMuseumId
            let isAllowed = ArtworkSafetyPolicy.allows(
                internalName: artwork.internalName,
                remoteApproval: artwork.isAppStoreAllowed
            )
            let matchesStatus = switch reviewFilter {
            case .all: true
            case .allowed: isAllowed
            case .blocked: !isAllowed
            }
            let matchesSearch = searchText.isEmpty
                || artwork.title.localizedCaseInsensitiveContains(searchText)
                || artwork.artist?.localizedCaseInsensitiveContains(searchText) == true
            return matchesMuseum && matchesStatus && matchesSearch
        }
    }

    private var allowedCount: Int {
        artworks.count { artwork in
            ArtworkSafetyPolicy.allows(
                internalName: artwork.internalName,
                remoteApproval: artwork.isAppStoreAllowed
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading all artworks…")
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn’t Load Artworks",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    artworkList
                }
            }
            .navigationTitle("Artwork Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        ArtworkSafetyPolicy.clearLocalOverrides()
                        reviewRevision += 1
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button {
                            Task { await resequenceSelectedMuseum() }
                        } label: {
                            Label("Re-sequence Current Museum", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(selectedMuseumId == "all" || isResequencing)

                        Button {
                            Task { await resequenceAll() }
                        } label: {
                            Label("Re-sequence All Museums (1..N)", systemImage: "sparkles")
                        }
                        .disabled(isResequencing)
                    } label: {
                        if isResequencing {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Title or artist")
            .task {
                await loadArtworks()
            }
            .onReceive(NotificationCenter.default.publisher(for: .artworkDatabaseUpdated)) { _ in
                Task {
                    await loadArtworks()
                    reviewRevision += 1
                }
            }
        }
    }

    private var artworkList: some View {
        List {
            Section {
                Picker("Museum", selection: $selectedMuseumId) {
                    Text("All Museums").tag("all")
                    ForEach(MuseumConfig.shared.museums) { museum in
                        Text(museum.name).tag(museum.id)
                    }
                }

                Picker("Status", selection: $reviewFilter) {
                    ForEach(ReviewFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("\(artworks.count) total · \(allowedCount) allowed · \(artworks.count - allowedCount) blocked")
                    .id(reviewRevision)
            }

            Section("Showing \(reviewedArtworks.count)") {
                ForEach(reviewedArtworks) { artwork in
                    artworkRow(artwork)
                }
            }
        }
        .contentMargins(.bottom, 64, for: .scrollContent)
        .id(reviewRevision)
    }

    private func artworkRow(_ artwork: NetworkArtwork) -> some View {
        let isAllowed = ArtworkSafetyPolicy.allows(
            internalName: artwork.internalName,
            remoteApproval: artwork.isAppStoreAllowed
        )

        return HStack(spacing: 12) {
            AsyncImage(url: URL(string: artwork.imageUrl)) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                        .overlay { Image(systemName: "photo") }
                }
            }
            .frame(width: 72, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(artwork.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let number = artwork.cardNumber {
                        Text(String(format: "#%02d", number))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                    }
                }
                if let artist = artwork.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(ArtworkSafetyPolicy.reviewReason(
                    internalName: artwork.internalName,
                    remoteApproval: artwork.isAppStoreAllowed
                ))
                .font(.caption)
                .foregroundStyle(isAllowed ? .green : .red)
            }

            Spacer(minLength: 8)

            Button {
                Task {
                    await toggleArtwork(artwork)
                }
            } label: {
                if updatingArtworkId == artwork.id {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: isAllowed ? "checkmark.circle.fill" : "nosign")
                        .font(.title2)
                        .foregroundStyle(isAllowed ? .green : .red)
                }
            }
            .buttonStyle(.plain)
            .disabled(updatingArtworkId != nil || isResequencing)
            .accessibilityLabel(isAllowed ? "Mark blocked" : "Mark allowed")
        }
        .padding(.vertical, 4)
    }

    private func toggleArtwork(_ artwork: NetworkArtwork) async {
        guard let museumId = artwork.museumId else { return }
        let isCurrentlyAllowed = ArtworkSafetyPolicy.allows(
            internalName: artwork.internalName,
            remoteApproval: artwork.isAppStoreAllowed
        )
        let newStatus = !isCurrentlyAllowed
        updatingArtworkId = artwork.id

        do {
            try await NetworkService.shared.setArtworkAllowed(
                artworkId: artwork.id,
                museumId: museumId,
                isAllowed: newStatus
            )
            ArtworkSafetyPolicy.setLocalOverride(newStatus, for: artwork.internalName)
            await loadArtworks()
            reviewRevision += 1
        } catch {
            errorMessage = "Failed to update Firestore: \(error.localizedDescription)"
        }
        updatingArtworkId = nil
    }

    private func resequenceSelectedMuseum() async {
        guard selectedMuseumId != "all" else { return }
        isResequencing = true
        do {
            try await NetworkService.shared.resequenceMuseum(museumId: selectedMuseumId)
            await CardDatabase.syncWithCloud(force: true)
            await loadArtworks()
            reviewRevision += 1
        } catch {
            errorMessage = "Failed to resequence museum: \(error.localizedDescription)"
        }
        isResequencing = false
    }

    private func resequenceAll() async {
        isResequencing = true
        do {
            try await NetworkService.shared.resequenceAllMuseums()
            await loadArtworks()
            reviewRevision += 1
        } catch {
            errorMessage = "Failed to resequence all: \(error.localizedDescription)"
        }
        isResequencing = false
    }

    private func loadArtworks() async {
        do {
            var loaded: [NetworkArtwork] = []
            for museum in MuseumConfig.shared.museums {
                let museumArtworks = try await NetworkService.shared.fetchArtworks(
                    for: museum.id,
                    includeBlocked: true
                )
                loaded.append(contentsOf: museumArtworks)
            }
            artworks = loaded.sorted {
                if $0.museumId == $1.museumId {
                    return ($0.cardNumber ?? Int.max) < ($1.cardNumber ?? Int.max)
                }
                return ($0.museumId ?? "") < ($1.museumId ?? "")
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
#endif
