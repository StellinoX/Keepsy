import SwiftUI

struct CachedRemoteImage: View {
    let assetName: String

    private static let s3Base = "https://keepsy-art-images-rstudio.s3.us-east-2.amazonaws.com/artworks/"

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .task {
            uiImage = await load()
        }
    }

    private func load() async -> UIImage? {
        let key = "ui_\(assetName)" as NSString
        if let cached = CardDatabase.imageCache.object(forKey: key) { return cached }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UIAssets", isDirectory: true)
        let file = dir.appendingPathComponent("\(assetName).png")

        if let img = UIImage(contentsOfFile: file.path) {
            CardDatabase.imageCache.setObject(img, forKey: key)
            return img
        }

        guard let url = URL(string: "\(Self.s3Base)\(assetName).png"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }

        CardDatabase.imageCache.setObject(img, forKey: key)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file)
        return img
    }
}
