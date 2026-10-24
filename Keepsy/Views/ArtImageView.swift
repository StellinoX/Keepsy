import SwiftUI

struct ArtImageView: View {
    let cardName: String
    var isRevealed: Bool
    
    @State private var localImage: UIImage?
    
    init(cardName: String, isRevealed: Bool = true) {
        self.cardName = cardName
        self.isRevealed = isRevealed
        if let cached = CardDatabase.imageCache.object(forKey: cardName as NSString) {
            self._localImage = State(initialValue: cached)
        } else if let bundleImg = UIImage(named: cardName) {
            CardDatabase.imageCache.setObject(bundleImg, forKey: cardName as NSString)
            self._localImage = State(initialValue: bundleImg)
        } else {
            self._localImage = State(initialValue: nil)
        }
    }
    
    var body: some View {
        Group {
            if let img = localImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(cardName == "vale" ? 1.66 : 1.0)
                    .clipped()
            } else if cardName.contains("_experience") || cardName == "vale" {
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: "1F1C18"), Color(hex: "0D0D0F"), Color(hex: "181510")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(spacing: 12) {
                        Image("LogoKeepsy")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 70, height: 70)
                            .shadow(color: Color(hex: "F1B40A").opacity(0.6), radius: 15, x: 0, y: 5)

                        Text(CardDatabase.cleanedArtworkName(cardName).uppercased())
                            .font(.custom("Helvetica-BoldOblique", size: 14))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "F5E480"), Color(hex: "F1B40A")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        Text("SPECIAL CARD")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            } else {
                ZStack {
                    CardDatabase.gradientFor(name: cardName)
                        .opacity(0.8)
                }
                .task(id: cardName, priority: .userInitiated) {
                    if let cached = CardDatabase.imageCache.object(forKey: cardName as NSString) {
                        self.localImage = cached
                        return
                    }
                    
                    if let img = await CardDatabase.localImageAsync(for: cardName) {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.localImage = img
                            }
                        }
                    } else {
                        // Se l'immagine manca in locale, proviamo a scaricarla al volo
                        if let art = CardDatabase.remoteArtworks[cardName] {
                            let urlString = art.imageUrl
                            if !urlString.isEmpty, let url = URL(string: urlString) {
                                do {
                                    let (data, _) = try await URLSession.shared.data(from: url)
                                    guard !Task.isCancelled else { return }
                                    
                                    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                                    let docDir = paths[0].appendingPathComponent("Artworks", isDirectory: true)
                                    if !FileManager.default.fileExists(atPath: docDir.path) {
                                        try? FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
                                    }
                                    let destinationURL = docDir.appendingPathComponent("\(cardName).jpg")
                                    try data.write(to: destinationURL, options: .atomic)
                                    
                                    if let finalImage = CardDatabase.loadLocalImageFromDisk(for: cardName) {
                                        CardDatabase.imageCache.setObject(finalImage, forKey: cardName as NSString)
                                        await MainActor.run {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                self.localImage = finalImage
                                            }
                                        }
                                    }
                                } catch {
                                    print("❌ Errore download dinamico per \(cardName): \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .artworkImageDownloaded)) { notification in
                    if let name = notification.userInfo?["internalName"] as? String, name == cardName {
                        Task(priority: .utility) {
                            if let img = await CardDatabase.localImageAsync(for: cardName) {
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        self.localImage = img
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .id(cardName)
    }
}

