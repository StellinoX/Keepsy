import SwiftUI

struct CitySelectorView: View {
    @Binding var selectedMuseumId: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCity: String = "Naples"
    @State private var searchText: String = ""
    
    // Struct representing a city in the selector list
    struct CityItem: Identifiable {
        let id = UUID()
        let name: String
        let flag: String
        let museumsCountText: String
        let museumId: String? // nil if coming soon
    }
    
    private let cities = [
        CityItem(name: "Naples",   flag: "🇮🇹", museumsCountText: "1 Museum", museumId: "capodimonte"),
        CityItem(name: "Florence", flag: "🇮🇹", museumsCountText: "1 Museum", museumId: "uffizi"),
        CityItem(name: "Madrid",   flag: "🇪🇸", museumsCountText: "1 Museum", museumId: "prado"),
        CityItem(name: "New York", flag: "🇺🇸", museumsCountText: "1 Museum", museumId: "moma"),
    ]
    
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
                .padding(.bottom, 35)

                
                // Title and Subtitle
                VStack(alignment: .leading, spacing: 8) {
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
                .padding(.bottom, 28)
                
                // Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .font(.system(size: 18))
                    
                    TextField("", text: $searchText, prompt: Text("Your city").foregroundColor(.white.opacity(0.5)))
                        .foregroundColor(.white)
                        .font(.custom("Helvetica", size: 16))
                }
                .padding(.horizontal, 16)
                .frame(width: 366, height: 55)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "B1B1B1"), Color(hex: "464646")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .padding(.bottom, 24)
                
                // City List Container Card
                VStack(spacing: 0) {
                    let filteredCities = cities.filter {
                        searchText.isEmpty || $0.name.lowercased().contains(searchText.lowercased())
                    }
                    
                    ForEach(Array(filteredCities.enumerated()), id: \.element.id) { idx, city in
                        Button(action: {
                            HapticManager.shared.triggerSelection()
                            selectedCity = city.name
                        }) {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(city.name) \(city.flag)")
                                        .font(.custom("Helvetica-Bold", size: 18))
                                        .foregroundColor(.white)
                                    
                                    Text(city.museumsCountText)
                                        .font(.custom("Helvetica-Oblique", size: 11))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                
                                Spacer()
                                
                                // Radio button ring/indicator
                                ZStack {
                                    Circle()
                                        .stroke(
                                            selectedCity == city.name ? Color(hex: "FF7A00") : Color.gray.opacity(0.5),
                                            lineWidth: 2
                                        )
                                        .frame(width: 22, height: 22)
                                    
                                    if selectedCity == city.name {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(hex: "FF7A00"), Color(hex: "464646")],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 12, height: 12)
                                    }
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 18)
                        }
                        
                        // Thin divider only after the first (localized) city item
                        if idx == 0 && filteredCities.count > 1 {
                            Divider()
                                .background(Color.white.opacity(0.12))
                                .padding(.horizontal, 18)
                        }
                    }
                }
                .frame(width: 366)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "121214").opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "B1B1B1"), Color(hex: "B1B1B1")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                
                Spacer()
                
                // Confirm Button
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .medium)
                    if let matched = cities.first(where: { $0.name == selectedCity }),
                       let museumId = matched.museumId {
                        selectedMuseumId = museumId
                        dismiss()
                    }
                }) {
                    Text("CONFIRM")
                        .font(.custom("Helvetica-BoldOblique", size: 18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 27)
                                .fill(Color(hex: "D8D8D8"))
                                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            selectedCity = cities.first(where: { $0.museumId == selectedMuseumId })?.name ?? "Naples"
        }
    }
}
