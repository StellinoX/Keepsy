import SwiftUI
import ARKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ArtworkEffect: CaseIterable {
    case pixelate, twirl, bump, hue
}

struct ARArtworkView: View {
    @State private var detectedArtwork: String = "Trova l'opera per sbloccarla!"
    @State private var isTargetUnlocked: Bool = false
    @State private var selectedEffect: ArtworkEffect = ArtworkEffect.allCases.randomElement() ?? .pixelate
    
    let targetArtworkName = "View of Campo Santi Giovanni e Paolo"
    let originalImage = UIImage(named: "TargetArtwork") ?? UIImage()
    
    var body: some View {
        ZStack {
            ARViewContainer(detectedArtwork: $detectedArtwork, isTargetUnlocked: $isTargetUnlocked, targetName: targetArtworkName)
                .edgesIgnoringSafeArea(.all)
            
            // Mostriamo solo il testo del riconoscimento
            VStack {
                Spacer()
                Text(detectedArtwork)
                    .font(.headline)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.bottom, 50)
            }
            
            /* 
            // CODICE EFFETTI E FOTO (COMMENTATO PER USO FUTURO)
            VStack {
                Text(isTargetUnlocked ? "✨ OPERA SBLOCCATA ✨" : "OBIETTIVO: Riconosci l'opera")
                    .font(.system(.title3, design: .monospaced))
                    .bold()
                    .padding()
                    .background(isTargetUnlocked ? Color.green.opacity(0.8) : Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.top, 60)
                
                Spacer()
                
                // Immagine con Effetto Casuale
                ZStack {
                    if isTargetUnlocked {
                        Image(uiImage: originalImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    } else {
                        DistortedImageView(image: originalImage, effect: selectedEffect)
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(isTargetUnlocked ? Color.green : Color.white, lineWidth: 5)
                )
                .shadow(color: .black.opacity(0.5), radius: 20)
                .animation(.easeInOut(duration: 0.8), value: isTargetUnlocked)
                
                Text(isTargetUnlocked ? "Hai trovato l'opera!" : "Effetto applicato: \(effectName)")
                    .font(.caption)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.top, 30)
                    .padding(.bottom, 60)
            }
            */
        }
    }
    
    var effectName: String {
        switch selectedEffect {
        case .pixelate: return "Mosaico (Pixel)"
        case .twirl: return "Vortice"
        case .bump: return "Distorsione"
        case .hue: return "Colori Alterati"
        }
    }
}

// MARK: - Gestore delle Distorsioni
struct DistortedImageView: View {
    var image: UIImage
    var effect: ArtworkEffect
    
    var body: some View {
        if let result = applyEffect(to: image) {
            Image(uiImage: result)
                .resizable()
                .interpolation(effect == .pixelate ? .none : .high) // Fondamentale per il pixelate
        } else {
            Image(uiImage: image)
                .resizable()
        }
    }
    
    func applyEffect(to input: UIImage) -> UIImage? {
        // Caso speciale per Pixelate: rimpiccioliamo e ingrandiamo
        if effect == .pixelate {
            return input.resize(to: CGSize(width: 20, height: 20))
        }
        
        // Altri effetti con Core Image
        let ciContext = CIContext()
        guard let ciImage = CIImage(image: input) else { return nil }
        var filter: CIFilter?
        
        switch effect {
        case .twirl:
            filter = CIFilter(name: "CITwirlDistortion")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: input.size.width / 2, y: input.size.height / 2), forKey: kCIInputCenterKey)
            filter?.setValue(min(input.size.width, input.size.height) / 2, forKey: kCIInputRadiusKey)
            filter?.setValue(3.0, forKey: kCIInputAngleKey)
            
        case .bump:
            filter = CIFilter(name: "CIBumpDistortion")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: input.size.width / 2, y: input.size.height / 2), forKey: kCIInputCenterKey)
            filter?.setValue(min(input.size.width, input.size.height) / 1.2, forKey: kCIInputRadiusKey)
            filter?.setValue(0.7, forKey: kCIInputScaleKey)
            
        case .hue:
            filter = CIFilter(name: "CIHueAdjust")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(2.5, forKey: kCIInputAngleKey)
            
        default: break
        }
        
        guard let output = filter?.outputImage,
              let cgImage = ciContext.createCGImage(output, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// Estensione per il ridimensionamento
extension UIImage {
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var detectedArtwork: String
    @Binding var isTargetUnlocked: Bool
    let targetName: String
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        let configuration = ARImageTrackingConfiguration()
        if let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
            configuration.trackingImages = referenceImages
            configuration.maximumNumberOfTrackedImages = 1
        }
        arView.session.run(configuration)
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewContainer
        init(parent: ARViewContainer) { self.parent = parent }
        
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let imageAnchor = anchor as? ARImageAnchor else { return }
            let rawName = imageAnchor.referenceImage.name ?? "Sconosciuta"
            
            // Il nome del database NON ha il suffisso "_0" o "_1"
            let dbName = rawName.replacingOccurrences(of: "_[0-9]+$", with: "", options: .regularExpression)
            
            let cleanedName = dbName
                .replacingOccurrences(of: "__detail_", with: "")
                .replacingOccurrences(of: "_detail_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespaces)
            
            DispatchQueue.main.async {
                if CardDatabase.getFoundCards().contains(dbName) {
                    CardDatabase.addRevealedCard(dbName)
                    self.parent.detectedArtwork = "Sbloccata: \(cleanedName)!"
                    self.parent.isTargetUnlocked = true
                }
            }
        }
    }
}
