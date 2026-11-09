import Foundation
import SwiftUI
import UIKit
import CoreLocation

struct CitySelectorView: View {
    let locationManager: LocationManager
    @Binding var selectedMuseumId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(LocalizationManager.self) private var localization: LocalizationManager?

    var body: some View {
        KeyboardLockedHostingContainer(
            rootView: CitySelectorContentView(
                locationManager: locationManager,
                selectedMuseumId: $selectedMuseumId,
                onDismiss: { dismiss() }
            )
            .environment(localization ?? LocalizationManager.shared)
            .environment(\.locale, locale)
        )
        .ignoresSafeArea()
    }
}

private struct CitySelectorContentView: View {
    let locationManager: LocationManager
    @Binding var selectedMuseumId: String
    let onDismiss: () -> Void

    @State private var selectedCity: String = "Florence"
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
        CityItem(name: "Florence", flag: "🇮🇹", museumsCountText: "1 Museum", museumId: "uffizi"),
        CityItem(name: "Madrid",   flag: "🇪🇸", museumsCountText: "1 Museum", museumId: "prado"),
        CityItem(name: "New York", flag: "🇺🇸", museumsCountText: "1 Museum", museumId: "moma"),
    ]

    private var sortedCities: [CityItem] {
        guard let userLoc = locationManager.lastKnownLocation else { return cities }
        return cities.sorted { c1, c2 in
            guard let mId1 = c1.museumId, let m1 = MuseumConfig.shared.museums.first(where: { $0.id == mId1 }) else { return false }
            guard let mId2 = c2.museumId, let m2 = MuseumConfig.shared.museums.first(where: { $0.id == mId2 }) else { return true }
            let dist1 = userLoc.distance(from: CLLocation(latitude: m1.latitude, longitude: m1.longitude))
            let dist2 = userLoc.distance(from: CLLocation(latitude: m2.latitude, longitude: m2.longitude))
            return dist1 < dist2
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Background gradient and Grid Background
                LinearGradient(
                    colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                GridBackground()

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 143)

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
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                    // Search Bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.gray)
                            .font(.system(size: 18))

                        TextField("", text: $searchText, prompt: Text("Your city").foregroundStyle(.white.opacity(0.5)))
                            .foregroundStyle(.white)
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
                        let filteredCities = sortedCities.filter {
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
                                            .foregroundStyle(.white)

                                        Text(city.museumsCountText)
                                            .font(.custom("Helvetica-Oblique", size: 11))
                                            .foregroundStyle(.white.opacity(0.5))
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

                    Spacer(minLength: 0)

                    // Confirm Button
                    Button(action: {
                        HapticManager.shared.triggerImpact(style: .medium)
                        if let matched = cities.first(where: { $0.name == selectedCity }),
                           let museumId = matched.museumId {
                            selectedMuseumId = museumId
                            onDismiss()
                        }
                    }) {
                        Text("CONFIRM")
                            .font(.custom("Helvetica-BoldOblique", size: 18))
                            .foregroundStyle(.black)
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
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                // Independent from the searchable content so its position never changes.
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(hex: "383838")))
                }
                .padding(.leading, 24)
                .padding(.top, 64)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .onAppear {
            selectedCity = cities.first(where: { $0.museumId == selectedMuseumId })?.name ?? "Florence"
        }
    }
}

/// Hosts SwiftUI content with `safeAreaRegions = []` so UIKit/SwiftUI keyboard
/// avoidance inside `fullScreenCover` never shifts or resizes the root layout.
private struct KeyboardLockedHostingContainer<Content: View>: UIViewControllerRepresentable {
    let rootView: Content

    func makeUIViewController(context: Context) -> KeyboardLockedHostingController<Content> {
        KeyboardLockedHostingController(rootView: rootView)
    }

    func updateUIViewController(_ uiViewController: KeyboardLockedHostingController<Content>, context: Context) {
        uiViewController.update(rootView: rootView)
    }
}

@MainActor
private final class KeyboardLockedHostingController<Content: View>: UIViewController {
    private let hostingController: UIHostingController<Content>

    private final class PassthroughContainerView: UIView {
        override var center: CGPoint {
            didSet {
                if center != oldValue { setNeedsLayout() }
            }
        }

        override var bounds: CGRect {
            didSet {
                if bounds != oldValue { setNeedsLayout() }
            }
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if super.point(inside: point, with: event) { return true }
            return subviews.contains { subview in
                !subview.isHidden && subview.isUserInteractionEnabled && subview.alpha > 0.01
                    && subview.point(inside: convert(point, to: subview), with: event)
            }
        }
    }

    init(rootView: Content) {
        self.hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = PassthroughContainerView()
        container.backgroundColor = .clear
        container.clipsToBounds = false
        view = container

        hostingController.safeAreaRegions = []
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        container.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    func update(rootView: Content) {
        hostingController.rootView = rootView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let referenceView = parent?.view
        let targetSize = referenceView?.bounds.size
            ?? view.window?.windowScene?.screen.bounds.size
            ?? UIScreen.mainBounds.size
        let originInParent: CGPoint = referenceView.map { view.convert(CGPoint.zero, to: $0) } ?? .zero
        hostingController.view.frame = CGRect(
            x: -originInParent.x,
            y: -originInParent.y,
            width: targetSize.width,
            height: targetSize.height
        )
    }
}
