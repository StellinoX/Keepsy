import SwiftUI

struct CitySelectorView: View {
    @Binding var selectedMuseumId: String
    @Environment(\.dismiss) private var dismiss
    
    // Struct representing a museum in the selector list
    struct CityItem: Identifiable {
        let id = UUID()
        let name: String
        let cityFullName: String
        let museumId: String
        let packetImageName: String
    }
    
    private let cities = [
        CityItem(name: "Uffizi",       cityFullName: "Florence, Italy", museumId: "uffizi",      packetImageName: "uffizi_pacchetto"),
        CityItem(name: "Prado",        cityFullName: "Madrid, Spain",   museumId: "prado",       packetImageName: "prado_pacchetto"),
        CityItem(name: "Capodimonte",  cityFullName: "Naples, Italy",   museumId: "capodimonte", packetImageName: "capodimonte_pacchetto"),
        CityItem(name: "MoMA",         cityFullName: "New York, NY",    museumId: "moma",        packetImageName: "moma_pacchetto"),
    ]
    
    private func progressFor(_ museumId: String) -> Double {
        let artworks = CardDatabase.artworksFor(location: museumId)
        if artworks.isEmpty { return 0.0 }
        let revealed = CardDatabase.getRevealedCards()
        let found = artworks.filter { revealed.contains($0) }.count
        return Double(found) / Double(artworks.count)
    }
    
    var body: some View {
        ZStack {
            // Background gradient and Grid Background
            LinearGradient(
                colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            GridBackground()
            
            VStack(spacing: 0) {
                // Header (Close Button)
                HStack {
                    Button(action: {
                        HapticManager.shared.triggerImpact(style: .light)
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(hex: "383838")))
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 16)
                
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHERE SHOULD YOUR\nEXPERIENCE START?")
                        .font(.custom("Helvetica-BoldOblique", size: 26))
                        .italic()
                        .bold()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .lineSpacing(4)
                    
                    Text("Always updating...")
                        .font(.custom("Helvetica-Oblique", size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                // Museum Scroll List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(cities) { city in
                            let progress = progressFor(city.museumId)
                            let isSelected = selectedMuseumId == city.museumId
                            
                            MuseumCardView(
                                city: city,
                                progress: progress,
                                isSelected: isSelected
                            ) {
                                HapticManager.shared.triggerImpact(style: .medium)
                                selectedMuseumId = city.museumId
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Circular Progress Ring Component
struct MuseumProgressCircle: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            if progress >= 1.0 {
                Circle()
                    .fill(Color.green)
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 2)
                    )
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(progress))
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(round(progress * 100)))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Individual Card View Component
struct MuseumCardView: View {
    let city: CitySelectorView.CityItem
    let progress: Double
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Translucent Rounded Card Background
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "121214").opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: isSelected
                                        ? [Color(hex: "FF7A00"), Color(hex: "FFB800")]
                                        : [Color.white.opacity(0.15), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSelected ? 2.0 : 1.2
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
                
                // Decorative overlapping packets in background
                VStack {
                    Spacer()
                    HStack(spacing: -18) {
                        Image(city.packetImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 72)
                            .rotationEffect(.degrees(-12))
                            .offset(y: 10)
                        
                        Image(city.packetImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 55, height: 82)
                            .zIndex(1)
                        
                        Image(city.packetImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 72)
                            .rotationEffect(.degrees(12))
                            .offset(y: 10)
                    }
                    .opacity(0.70)
                    .padding(.bottom, -12)
                }
                .clipped()
                
                // Information Content Layout
                VStack(spacing: 0) {
                    HStack {
                        MuseumProgressCircle(progress: progress)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(city.name.uppercased())
                            .font(.custom("Helvetica-BoldOblique", size: 26))
                            .italic()
                            .bold()
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text(city.cityFullName)
                            .font(.custom("Helvetica-Oblique", size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.bottom, 22)
                }
            }
            .frame(height: 165)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
