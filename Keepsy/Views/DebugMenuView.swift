import SwiftUI

#if INTERNAL_BUILD
struct DebugMenuView: View {
    let onDone: () -> Void

    @AppStorage("debugLocationEnabled") private var debugLocationEnabled = false
    @AppStorage("debugLocationMuseumID") private var debugLocationMuseumID =
        MuseumConfig.shared.museums.first?.id ?? "uffizi"

    @State private var collectionRevision = 0
    @State private var isSyncing = false
    @State private var isResequencing = false
    @State private var showResetCollectionConfirmation = false
    @State private var showResetOnboardingConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                locationSection
                collectionSection
                appSection
            }
            .navigationTitle("Debug Center")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private var locationSection: some View {
        Section {
            Toggle("Fake location", isOn: $debugLocationEnabled)

            Picker("Museum location", selection: $debugLocationMuseumID) {
                ForEach(MuseumConfig.shared.museums) { museum in
                    Text(museum.name).tag(museum.id)
                }
            }
            .disabled(!debugLocationEnabled)

            if debugLocationEnabled {
                let selectedMuseumName = MuseumConfig.shared.museums.first {
                    $0.id == debugLocationMuseumID
                }?.name ?? debugLocationMuseumID
                Label("Fake location: \(selectedMuseumName)", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Location Faker")
        } footer: {
            Text("Distance, sorting, and scanning use the selected museum as the current location.")
        }
    }

    private var collectionSection: some View {
        Section("Cards & Collection") {
            NavigationLink {
                AdminArtworkReviewView()
            } label: {
                Label("Artwork Review & Hiding", systemImage: "eye.slash.fill")
            }

            NavigationLink {
                DebugCardDatabaseView()
            } label: {
                Label("Card Database", systemImage: "rectangle.stack.fill")
            }

            Button {
                Task {
                    isResequencing = true
                    try? await NetworkService.shared.resequenceAllMuseums()
                    isResequencing = false
                    collectionRevision += 1
                }
            } label: {
                if isResequencing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Re-sequencing card numbers…")
                    }
                } else {
                    Label("Re-sequence Firestore card numbers (1..N)", systemImage: "number.square.fill")
                }
            }
            .disabled(isResequencing)

            Button {
                revealEveryCard()
            } label: {
                Label("Find and reveal every card", systemImage: "sparkles.rectangle.stack")
            }

            Button(role: .destructive) {
                showResetCollectionConfirmation = true
            } label: {
                Label("Reset collection and packs", systemImage: "trash")
            }
            .confirmationDialog(
                "Reset all collection progress?",
                isPresented: $showResetCollectionConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Collection", role: .destructive) {
                    resetCollection()
                }
            } message: {
                Text("Found cards, revealed cards, duplicates, and active packs will be removed.")
            }
        }
        .id(collectionRevision)
    }

    private var appSection: some View {
        Section("App") {
            Button {
                syncDatabase()
            } label: {
                if isSyncing {
                    HStack {
                        ProgressView()
                        Text("Syncing database…")
                    }
                } else {
                    Label("Force database sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)

            Button(role: .destructive) {
                showResetOnboardingConfirmation = true
            } label: {
                Label("Show onboarding again", systemImage: "person.crop.circle.badge.questionmark")
            }
            .confirmationDialog(
                "Show onboarding on the next launch?",
                isPresented: $showResetOnboardingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Onboarding", role: .destructive) {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                }
            }
        }
    }

    private func revealEveryCard() {
        let names = MuseumConfig.shared.museums.flatMap {
            CardDatabase.artworksFor(location: $0.id)
        }
        UserDefaults.standard.set(Array(Set(names)), forKey: "FoundCards")
        UserDefaults.standard.set(Array(Set(names)), forKey: "RevealedCards")
        collectionRevision += 1
        NotificationCenter.default.post(name: NSNotification.Name("KeepsyCardsDidChange"), object: nil)
    }

    private func resetCollection() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "FoundCards")
        defaults.removeObject(forKey: "RevealedCards")
        defaults.removeObject(forKey: "DuplicateCardCounts")
        defaults.removeObject(forKey: "activePackCards")
        defaults.removeObject(forKey: "activePackTearMask")
        defaults.removeObject(forKey: "activePackDuplicates")

        for museum in MuseumConfig.shared.museums {
            defaults.removeObject(forKey: "activePackCards_\(museum.id)")
            defaults.removeObject(forKey: "activePackTearMask_\(museum.id)")
            defaults.removeObject(forKey: "activePackDuplicates_\(museum.id)")
        }
        collectionRevision += 1
        NotificationCenter.default.post(name: NSNotification.Name("KeepsyCardsDidChange"), object: nil)
    }

    private func syncDatabase() {
        isSyncing = true
        Task {
            await CardDatabase.syncWithCloud(force: true)
            await MainActor.run {
                isSyncing = false
            }
        }
    }
}

private struct DebugCardDatabaseView: View {
    @State private var artworks: [NetworkArtwork] = []
    @State private var selectedMuseumID = "all"
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var revision = 0

    private var filteredArtworks: [NetworkArtwork] {
        artworks.filter { artwork in
            let matchesMuseum = selectedMuseumID == "all" || artwork.museumId == selectedMuseumID
            let matchesSearch = searchText.isEmpty
                || artwork.title.localizedCaseInsensitiveContains(searchText)
                || artwork.artist?.localizedCaseInsensitiveContains(searchText) == true
                || artwork.internalName.localizedCaseInsensitiveContains(searchText)
            return matchesMuseum && matchesSearch
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading all cards…")
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn’t Load Cards",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                List {
                    Section {
                        Picker("Museum", selection: $selectedMuseumID) {
                            Text("All Museums").tag("all")
                            ForEach(MuseumConfig.shared.museums) { museum in
                                Text(museum.name).tag(museum.id)
                            }
                        }
                    }

                    Section("Showing \(filteredArtworks.count) of \(artworks.count)") {
                        ForEach(filteredArtworks) { artwork in
                            DebugCardRow(artwork: artwork, revision: $revision)
                        }
                    }
                }
                .id(revision)
            }
        }
        .navigationTitle("Card Database")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Title, artist, or ID")
        .task {
            await loadArtworks()
        }
    }

    private func loadArtworks() async {
        do {
            var loaded: [NetworkArtwork] = []
            for museum in MuseumConfig.shared.museums {
                loaded.append(contentsOf: try await NetworkService.shared.fetchArtworks(
                    for: museum.id,
                    includeBlocked: true
                ))
            }
            artworks = loaded.sorted {
                if $0.museumId == $1.museumId {
                    return ($0.cardNumber ?? Int.max) < ($1.cardNumber ?? Int.max)
                }
                return ($0.museumId ?? "") < ($1.museumId ?? "")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct DebugCardRow: View {
    let artwork: NetworkArtwork
    @Binding var revision: Int

    private var isFound: Bool {
        CardDatabase.getFoundCards().contains(artwork.internalName)
    }

    private var isRevealed: Bool {
        CardDatabase.getRevealedCards().contains(artwork.internalName)
    }

    private var isAllowed: Bool {
        ArtworkSafetyPolicy.allows(
            internalName: artwork.internalName,
            remoteApproval: artwork.isAppStoreAllowed
        )
    }

    var body: some View {
        NavigationLink {
            DebugCardDetailView(artwork: artwork, revision: $revision)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: artwork.imageUrl)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.15)
                            .overlay { Image(systemName: "photo") }
                    }
                }
                .frame(width: 54, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 4) {
                    Text(artwork.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(artwork.internalName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        statusLabel("Found", active: isFound)
                        statusLabel("Revealed", active: isRevealed)
                        statusLabel("Allowed", active: isAllowed)
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func statusLabel(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(active ? .green : .secondary)
    }
}

private struct DebugCardDetailView: View {
    let artwork: NetworkArtwork
    @Binding var revision: Int

    private var foundBinding: Binding<Bool> {
        Binding(
            get: { CardDatabase.getFoundCards().contains(artwork.internalName) },
            set: { setFound($0) }
        )
    }

    private var revealedBinding: Binding<Bool> {
        Binding(
            get: { CardDatabase.getRevealedCards().contains(artwork.internalName) },
            set: { setRevealed($0) }
        )
    }

    private var allowedBinding: Binding<Bool> {
        Binding(
            get: {
                ArtworkSafetyPolicy.allows(
                    internalName: artwork.internalName,
                    remoteApproval: artwork.isAppStoreAllowed
                )
            },
            set: { newValue in
                ArtworkSafetyPolicy.setLocalOverride(newValue, for: artwork.internalName)
                if let museumId = artwork.museumId {
                    Task {
                        try? await NetworkService.shared.setArtworkAllowed(
                            artworkId: artwork.id,
                            museumId: museumId,
                            isAllowed: newValue
                        )
                    }
                }
                revision += 1
            }
        )
    }

    var body: some View {
        Form {
            Section {
                AsyncImage(url: URL(string: artwork.imageUrl)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        ContentUnavailableView("Image unavailable", systemImage: "photo")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Section("Debug State") {
                Toggle("Found", isOn: foundBinding)
                Toggle("Revealed", isOn: revealedBinding)
                Toggle("Allowed by safety filter", isOn: allowedBinding)
            }

            Section("Database Fields") {
                LabeledContent("Internal ID", value: artwork.internalName)
                LabeledContent("Document ID", value: artwork.id)
                LabeledContent("Museum", value: artwork.museumId ?? "—")
                let cardNum = CardDatabase.cardNumber(for: artwork.internalName) ?? artwork.cardNumber
                LabeledContent("Card number", value: cardNum.map { String(format: "#%02d", $0) } ?? "—")
                LabeledContent("Artist", value: artwork.artist ?? "—")
                LabeledContent("Date", value: artwork.date ?? "—")
                LabeledContent("Inventory", value: artwork.inventoryNumber ?? "—")
                LabeledContent("Technique", value: artwork.technique ?? "—")
                LabeledContent("Dimensions", value: artwork.dimensions ?? "—")
            }

            if let description = artwork.description, !description.isEmpty {
                Section("Description") {
                    Text(description)
                }
            }
        }
        .navigationTitle(artwork.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setFound(_ value: Bool) {
        var found = CardDatabase.getFoundCards()
        var revealed = CardDatabase.getRevealedCards()

        if value {
            found.insert(artwork.internalName)
            revealed.insert(artwork.internalName)
        } else {
            found.remove(artwork.internalName)
            revealed.remove(artwork.internalName)
        }

        UserDefaults.standard.set(Array(found), forKey: "FoundCards")
        UserDefaults.standard.set(Array(revealed), forKey: "RevealedCards")
        revision += 1
        NotificationCenter.default.post(name: NSNotification.Name("KeepsyCardsDidChange"), object: nil)
    }

    private func setRevealed(_ value: Bool) {
        var found = CardDatabase.getFoundCards()
        var revealed = CardDatabase.getRevealedCards()

        if value {
            found.insert(artwork.internalName)
            revealed.insert(artwork.internalName)
        } else {
            revealed.remove(artwork.internalName)
        }

        UserDefaults.standard.set(Array(found), forKey: "FoundCards")
        UserDefaults.standard.set(Array(revealed), forKey: "RevealedCards")
        revision += 1
        NotificationCenter.default.post(name: NSNotification.Name("KeepsyCardsDidChange"), object: nil)
    }
}
#endif
